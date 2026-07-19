import Foundation

/// Async client for the NSF Awards API (https://api.nsf.gov/services/v1) —
/// grant funding for members whose work NIH RePORTER never sees. Free and
/// keyless.
///
/// Unlike RePORTER there are no investigator profile IDs, so awards are
/// matched on the PI name string alone; the server-side query is re-verified
/// client-side the same way the trials client does it, and the results still
/// go through a confirmation step before they're attached.
actor NSFClient {
    static let shared = NSFClient()

    private let base = URL(string: "https://api.nsf.gov/services/v1")!
    private let session = URLSession.shared
    private let cache = CacheStore.shared
    /// The API caps rpp at 25 and pages with a 1-based offset.
    private let pageSize = 25
    private let maxPages = 8
    private var lastRequest = Date.distantPast

    enum ClientError: LocalizedError {
        case badStatus(Int)

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): "NSF Awards API returned HTTP \(code)."
            }
        }
    }

    // MARK: Public API

    /// Awards where the named person is the PI or a co-PI. `pdPIName` searches
    /// the principal-investigator name; co-PI hits come back through the same
    /// query, so each award is re-checked against both fields.
    func awards(piName: String) async throws -> [NSFAward] {
        let criteria = ReporterClient.piNameCriteria(from: piName)
        let surname = criteria.lastName ?? criteria.anyName ?? piName
        let query = [criteria.firstName, surname].compactMap(\.self).joined(separator: " ")

        var rows: [Row] = []
        for page in 0..<maxPages {
            let response: Response = try await get(query: [
                // Unquoted: pdPIName is a substring match over the whole PI
                // name, and quoting the phrase makes it match nothing.
                // `offset` is a 1-based record index, not a page number.
                URLQueryItem(name: "pdPIName", value: query),
                URLQueryItem(name: "printFields", value: Self.fields),
                URLQueryItem(name: "rpp", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(page * pageSize + 1)),
            ])
            let batch = response.response?.award ?? []
            rows.append(contentsOf: batch)
            if batch.count < pageSize { break }
        }

        return rows
            .filter { row in
                Self.nameMatches(row.pdPIName, member: piName)
                    || (row.coPDPI ?? []).contains { Self.nameMatches($0, member: piName) }
            }
            .compactMap { $0.award(matchedAsPI: Self.nameMatches($0.pdPIName, member: piName)) }
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    private static let fields = [
        "id", "title", "agency", "awardeeName", "pdPIName", "coPDPI",
        "startDate", "expDate", "estimatedTotalAmt", "fundsObligatedAmt",
        "fundProgramName", "primaryProgram",
    ].joined(separator: ",")

    /// The co-PI field arrives as "Andrew Kitchen andrew-kitchen@uiowa.edu",
    /// so the trials client's token matcher (which already strips degrees and
    /// tolerates initials) does the verification.
    static func nameMatches(_ candidate: String?, member: String) -> Bool {
        ClinicalTrialsClient.nameMatches(candidate, member: member)
    }

    /// NSF dates are US-format "MM/DD/YYYY".
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter
    }()

    static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return dateFormatter.date(from: raw)
    }

    // MARK: Request plumbing

    private func get<T: Decodable>(query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(
            url: base.appendingPathComponent("awards.json"), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        let url = components.url!

        let data: Data
        if let cached = cache.data(forKey: url.absoluteString) {
            data = cached
        } else {
            data = try await fetchRaw(url)
            cache.store(data, forKey: url.absoluteString)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func fetchRaw(_ url: URL, attempt: Int = 1) async throws -> Data {
        // Be a good citizen on a keyless public API, as with RePORTER.
        let elapsed = Date().timeIntervalSince(lastRequest)
        if elapsed < 1.0 {
            try await Task.sleep(for: .seconds(1.0 - elapsed))
        }
        lastRequest = Date()

        var request = URLRequest(url: url)
        request.setValue("FacultyIQ-Mac/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        switch status {
        case 200: return data
        case 429, 500...599:
            guard attempt < 3 else { throw ClientError.badStatus(status) }
            try await Task.sleep(for: .seconds(pow(2, Double(attempt))))
            return try await fetchRaw(url, attempt: attempt + 1)
        default:
            throw ClientError.badStatus(status)
        }
    }

    // MARK: Response shapes

    private struct Response: Decodable {
        struct Inner: Decodable {
            var award: [Row]?
        }
        var response: Inner?
    }

    /// NSF returns every amount as a string, and `coPDPI` only when present.
    struct Row: Decodable {
        var id: String?
        var title: String?
        var agency: String?
        var awardeeName: String?
        var pdPIName: String?
        var coPDPI: [String]?
        var startDate: String?
        var expDate: String?
        var estimatedTotalAmt: String?
        var fundsObligatedAmt: String?
        var fundProgramName: String?

        func award(matchedAsPI: Bool) -> NSFAward? {
            guard let id else { return nil }
            return NSFAward(
                awardID: id,
                title: title ?? "(untitled award)",
                agency: agency ?? "NSF",
                program: fundProgramName,
                organization: awardeeName,
                piName: pdPIName,
                isPI: matchedAsPI,
                startDate: NSFClient.parseDate(startDate),
                endDate: NSFClient.parseDate(expDate),
                totalAward: Int(estimatedTotalAmt ?? "") ?? Int(fundsObligatedAmt ?? "") ?? 0)
        }
    }
}
