import Foundation

/// Async client for the ClinicalTrials.gov API v2
/// (https://clinicaltrials.gov/api/v2) — registered trials where a member is
/// an overall official (PI, study chair, or study director). Free and
/// keyless. The registry has no investigator IDs, so the server-side name
/// query is re-verified client-side with normalized token matching before a
/// trial is attached.
actor ClinicalTrialsClient {
    static let shared = ClinicalTrialsClient()

    private let base = URL(string: "https://clinicaltrials.gov/api/v2")!
    private let session = URLSession.shared
    private let cache = CacheStore.shared
    private let pageSize = 200

    enum ClientError: LocalizedError {
        case badStatus(Int)

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): "ClinicalTrials.gov returned HTTP \(code)."
            }
        }
    }

    // MARK: Public API

    func trials(officialName: String) async throws -> [ClinicalTrial] {
        let criteria = ReporterClient.piNameCriteria(from: officialName)
        let surname = criteria.lastName ?? criteria.anyName ?? officialName
        var term = "\"\(surname)\""
        if let first = criteria.firstName {
            term = "(\"\(first)\" AND \"\(surname)\")"
        }

        var studies: [Study] = []
        var pageToken: String?
        repeat {
            var query = [
                URLQueryItem(name: "query.term", value: "AREA[OverallOfficialName]\(term)"),
                URLQueryItem(name: "fields", value: "NCTId,BriefTitle,OverallStatus,Phase,LeadSponsorName,OverallOfficialName,OverallOfficialRole,OverallOfficialAffiliation,StartDate,PrimaryCompletionDate,EnrollmentCount"),
                URLQueryItem(name: "pageSize", value: "\(pageSize)"),
            ]
            if let pageToken {
                query.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            let page: Response = try await get("studies", query: query)
            studies.append(contentsOf: page.studies ?? [])
            pageToken = page.nextPageToken
        } while pageToken != nil

        return studies.compactMap { study -> ClinicalTrial? in
            let section = study.protocolSection
            guard let nct = section?.identificationModule?.nctId else { return nil }
            let officials = section?.contactsLocationsModule?.overallOfficials ?? []
            guard let match = officials.first(where: {
                Self.nameMatches($0.name, member: officialName)
            }) else { return nil }
            return ClinicalTrial(
                nctID: nct,
                title: section?.identificationModule?.briefTitle ?? "(untitled trial)",
                status: section?.statusModule?.overallStatus,
                phase: section?.designModule?.phases?.joined(separator: "/"),
                role: match.role,
                sponsor: section?.sponsorCollaboratorsModule?.leadSponsor?.name,
                startDate: section?.statusModule?.startDateStruct?.date,
                completionDate: section?.statusModule?.primaryCompletionDateStruct?.date,
                enrollment: section?.designModule?.enrollmentInfo?.count)
        }
        .sorted { ($0.startDate ?? "") > ($1.startDate ?? "") }
    }

    /// Registry names carry degrees and middle initials ("Jane Q. Smith, MD"),
    /// so require the member's surname plus a first-name token or matching
    /// initial among the official's name tokens.
    static func nameMatches(_ officialName: String?, member: String) -> Bool {
        guard let officialName else { return false }
        func tokens(_ s: String) -> [String] {
            s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .lowercased()
                .components(separatedBy: CharacterSet.letters.inverted)
                .filter { !$0.isEmpty && !["md", "phd", "do", "mph", "ms", "mbbs", "dr"].contains($0) }
        }
        let criteria = ReporterClient.piNameCriteria(from: member)
        guard let surname = tokens(criteria.lastName ?? criteria.anyName ?? member).last else {
            return false
        }
        let official = tokens(officialName)
        guard official.contains(surname) else { return false }
        guard let first = criteria.firstName.flatMap({ tokens($0).first }) else { return true }
        return official.contains(first)
            || official.contains { $0.count == 1 && $0.first == first.first }
    }

    // MARK: Request plumbing

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(
            url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        let url = components.url!

        let data: Data
        if let cached = cache.data(forKey: url.absoluteString) {
            data = cached
        } else {
            data = try await fetchRaw(URLRequest(url: url))
            cache.store(data, forKey: url.absoluteString)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func fetchRaw(_ request: URLRequest, attempt: Int = 1) async throws -> Data {
        var request = request
        request.setValue("FacultyIQ-Mac/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        switch status {
        case 200: return data
        case 429, 500...599:
            guard attempt < 3 else { throw ClientError.badStatus(status) }
            try await Task.sleep(for: .seconds(pow(2, Double(attempt))))
            return try await fetchRaw(request, attempt: attempt + 1)
        default:
            throw ClientError.badStatus(status)
        }
    }

    // MARK: Response shapes

    private struct Response: Decodable {
        var studies: [Study]?
        var nextPageToken: String?
    }

    private struct Study: Decodable {
        struct ProtocolSection: Decodable {
            struct Identification: Decodable {
                var nctId: String?
                var briefTitle: String?
            }
            struct Status: Decodable {
                struct DateStruct: Decodable {
                    var date: String?
                }
                var overallStatus: String?
                var startDateStruct: DateStruct?
                var primaryCompletionDateStruct: DateStruct?
            }
            struct Design: Decodable {
                struct Enrollment: Decodable {
                    var count: Int?
                }
                var phases: [String]?
                var enrollmentInfo: Enrollment?
            }
            struct Sponsors: Decodable {
                struct Sponsor: Decodable {
                    var name: String?
                }
                var leadSponsor: Sponsor?
            }
            struct ContactsLocations: Decodable {
                struct Official: Decodable {
                    var name: String?
                    var affiliation: String?
                    var role: String?
                }
                var overallOfficials: [Official]?
            }
            var identificationModule: Identification?
            var statusModule: Status?
            var designModule: Design?
            var sponsorCollaboratorsModule: Sponsors?
            var contactsLocationsModule: ContactsLocations?
        }
        var protocolSection: ProtocolSection?
    }
}
