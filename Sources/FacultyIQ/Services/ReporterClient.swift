import Foundation

/// Async client for NIH RePORTER (https://api.reporter.nih.gov) — grant
/// funding by principal investigator. No key required, but the API enforces
/// about one request per second, so the actor throttles live requests.
/// PI name search is fuzzy wildcard matching; grants are only attached after
/// the user (or an unambiguous single match) confirms a PI profile id.
actor ReporterClient {
    static let shared = ReporterClient()

    private let endpoint = URL(string: "https://api.reporter.nih.gov/v2/projects/search")!
    private let session = URLSession.shared
    private let cache = CacheStore.shared
    private let pageSize = 500
    private var lastRequest = Date.distantPast

    enum ClientError: LocalizedError {
        case badStatus(Int)

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): "NIH RePORTER returned HTTP \(code)."
            }
        }
    }

    // MARK: Public API

    /// PI candidates matching a name, grouped by RePORTER profile id.
    func searchPIs(name: String) async throws -> [PICandidate] {
        let rows = try await page(criteria: Criteria(piNames: [Self.piNameCriteria(from: name)]),
                                  offset: 0).results
        var byProfile: [Int: (name: String, org: String?, cores: Set<String>, latestFY: Int?)] = [:]
        for row in rows {
            guard let pi = (row.principalInvestigators ?? [])
                .first(where: { Self.rowNameMatches($0.fullName, query: name) }),
                  let profileID = pi.profileId else { continue }
            var entry = byProfile[profileID]
                ?? (name: pi.fullName ?? name, org: row.organization?.orgName, cores: [], latestFY: nil)
            if let num = row.projectNum { entry.cores.insert(Self.coreProjectNumber(num)) }
            entry.latestFY = max(entry.latestFY ?? 0, row.fiscalYear ?? 0)
            if entry.org == nil { entry.org = row.organization?.orgName }
            byProfile[profileID] = entry
        }
        return byProfile
            .map { PICandidate(profileID: $0.key, name: $0.value.name, orgName: $0.value.org,
                               projectCount: $0.value.cores.count,
                               latestFiscalYear: $0.value.latestFY == 0 ? nil : $0.value.latestFY) }
            .sorted { ($0.latestFiscalYear ?? 0, $0.projectCount) > (($1.latestFiscalYear ?? 0), $1.projectCount) }
    }

    /// All projects for a confirmed PI profile, grouped by core project number.
    func projects(profileID: Int) async throws -> [Grant] {
        var rows: [Response.Row] = []
        var offset = 0
        while true {
            let response = try await page(criteria: Criteria(piProfileIds: [profileID]), offset: offset)
            rows.append(contentsOf: response.results)
            offset += pageSize
            if rows.count >= (response.meta?.total ?? 0) || response.results.isEmpty { break }
        }
        return Self.groupIntoGrants(rows)
    }

    /// RePORTER's `any_name` matches single name fragments only, so multi-word
    /// queries ("Jane Smith", "Smith, Jane") are split into first/last name
    /// criteria; middle names are dropped.
    static func piNameCriteria(from query: String) -> Criteria.PIName {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if let comma = trimmed.firstIndex(of: ",") {
            let last = String(trimmed[..<comma]).trimmingCharacters(in: .whitespaces)
            let first = trimmed[trimmed.index(after: comma)...]
                .split(separator: " ").first.map(String.init)
            return Criteria.PIName(anyName: nil, firstName: first, lastName: last.nilIfEmpty)
        }
        let tokens = trimmed.split(separator: " ").map(String.init)
        if tokens.count >= 2 {
            return Criteria.PIName(anyName: nil, firstName: tokens.first, lastName: tokens.last)
        }
        return Criteria.PIName(anyName: trimmed, firstName: nil, lastName: nil)
    }

    // MARK: Grouping helpers (static for testability)

    /// "5U24HG007346-08" → "U24HG007346": drop the application-type digit and
    /// the support-year suffix, leaving the core project number.
    static func coreProjectNumber(_ projectNum: String) -> String {
        var core = projectNum.split(separator: "-").first.map(String.init) ?? projectNum
        if let first = core.first, first.isNumber { core.removeFirst() }
        return core
    }

    static func groupIntoGrants(_ rows: [Response.Row]) -> [Grant] {
        var byCore: [String: [Response.Row]] = [:]
        for row in rows {
            guard let num = row.projectNum else { continue }
            byCore[coreProjectNumber(num), default: []].append(row)
        }
        return byCore.map { core, group in
            let sorted = group.sorted { ($0.fiscalYear ?? 0) < ($1.fiscalYear ?? 0) }
            let latest = sorted.last!
            var byFY: [Int: Int] = [:]
            for row in group {
                if let fy = row.fiscalYear, let amount = row.awardAmount {
                    byFY[fy, default: 0] += amount
                }
            }
            return Grant(
                coreProjectNum: core,
                latestProjectNum: latest.projectNum ?? core,
                title: latest.projectTitle ?? "(untitled project)",
                activityCode: latest.activityCode,
                fiscalYears: sorted.compactMap(\.fiscalYear),
                totalAward: group.compactMap(\.awardAmount).reduce(0, +),
                startDate: sorted.compactMap(\.projectStartDate).first,
                endDate: sorted.compactMap(\.projectEndDate).last,
                orgName: latest.organization?.orgName,
                awardsByFiscalYear: byFY)
        }
        .sorted { ($0.fiscalYears.last ?? 0, $0.totalAward) > (($1.fiscalYears.last ?? 0), $1.totalAward) }
    }

    /// Loose surname check so a search for "Smith" doesn't credit rows where
    /// only a co-PI matched.
    static func rowNameMatches(_ fullName: String?, query: String) -> Bool {
        guard let fullName else { return false }
        let criteria = piNameCriteria(from: query)
        let nameTokens = Set(normalizedTokens(fullName))
        guard let surname = normalizedTokens(criteria.lastName ?? criteria.anyName ?? query).last else {
            return false
        }
        return nameTokens.contains(surname)
    }

    private static func normalizedTokens(_ s: String) -> [String] {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
    }

    // MARK: Request plumbing

    private func page(criteria: Criteria, offset: Int) async throws -> Response {
        let payload = Payload(criteria: criteria, offset: offset, limit: pageSize)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = .sortedKeys      // stable cache keys
        let body = try encoder.encode(payload)

        let key = "reporter:" + String(decoding: body, as: UTF8.self)
        let data: Data
        if let cached = cache.data(forKey: key) {
            data = cached
        } else {
            data = try await fetchRaw(body: body)
            cache.store(data, forKey: key)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Response.self, from: data)
    }

    private func fetchRaw(body: Data, attempt: Int = 1) async throws -> Data {
        // ≥1 s between live requests, or RePORTER blocks the IP.
        let elapsed = Date().timeIntervalSince(lastRequest)
        if elapsed < 1.1 {
            try await Task.sleep(for: .seconds(1.1 - elapsed))
        }
        lastRequest = Date()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("FacultyIQ-Mac/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        switch status {
        case 200: return data
        case 429, 500...599:
            guard attempt < 3 else { throw ClientError.badStatus(status) }
            try await Task.sleep(for: .seconds(pow(2, Double(attempt))))
            return try await fetchRaw(body: body, attempt: attempt + 1)
        default:
            throw ClientError.badStatus(status)
        }
    }

    // MARK: Payload / response shapes

    private struct Payload: Encodable {
        var criteria: Criteria
        var offset: Int
        var limit: Int
        var includeFields = [
            "FiscalYear", "ProjectNum", "ActivityCode", "AwardAmount", "ProjectTitle",
            "Organization", "PrincipalInvestigators", "ContactPiName",
            "ProjectStartDate", "ProjectEndDate",
        ]
    }

    struct Criteria: Encodable {
        struct PIName: Encodable, Equatable {
            var anyName: String?
            var firstName: String?
            var lastName: String?
        }
        var piNames: [PIName]?
        var piProfileIds: [Int]?
    }

    struct Response: Decodable {
        struct Meta: Decodable {
            var total: Int?
        }
        struct Row: Decodable {
            struct Org: Decodable {
                var orgName: String?
            }
            struct PI: Decodable {
                var profileId: Int?
                var fullName: String?
                var isContactPi: Bool?
            }
            var fiscalYear: Int?
            var projectNum: String?
            var activityCode: String?
            var awardAmount: Int?
            var projectTitle: String?
            var organization: Org?
            var principalInvestigators: [PI]?
            var contactPiName: String?
            var projectStartDate: String?
            var projectEndDate: String?
        }
        var meta: Meta?
        var results: [Row]
    }
}
