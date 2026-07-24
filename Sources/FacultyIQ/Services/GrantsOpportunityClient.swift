import Foundation

/// Keyless search of the public Grants.gov opportunity catalog. The endpoint
/// returns posted and forecast opportunities and links users back to the full
/// announcement rather than duplicating application content locally.
actor GrantsOpportunityClient {
    static let shared = GrantsOpportunityClient()

    private let endpoint = URL(string: "https://api.grants.gov/v1/api/search2")!
    private let session = URLSession.shared
    private let cache = CacheStore.shared

    enum ClientError: LocalizedError {
        case badStatus(Int)
        case service(String)

        var errorDescription: String? {
            switch self {
            case .badStatus(let status): "Grants.gov returned HTTP \(status)."
            case .service(let message): "Grants.gov could not complete the search: \(message)"
            }
        }
    }

    func search(query: String, limit: Int = 50, bypassCache: Bool = false) async throws
        -> [FundingOpportunity] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let payload = SearchPayload(
            rows: min(max(limit, 1), 100),
            keyword: trimmed,
            oppStatuses: "forecasted|posted",
            startRecordNum: 0)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let body = try encoder.encode(payload)
        let key = "grants.gov:search2:" + String(decoding: body, as: UTF8.self)

        let data: Data
        if !bypassCache, let cached = cache.data(forKey: key) {
            data = cached
        } else {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("FacultyIQ-Mac/1.0", forHTTPHeaderField: "User-Agent")
            let (received, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw ClientError.badStatus(status) }
            data = received
            cache.store(received, forKey: key)
        }

        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        guard response.errorcode == 0 else { throw ClientError.service(response.msg) }
        let now = Date()
        return response.data.oppHits.map { hit in
            FundingOpportunity(
                id: hit.id,
                number: hit.number,
                title: hit.title,
                agencyCode: hit.agencyCode,
                agencyName: hit.agency,
                openDate: Self.date(hit.openDate),
                closeDate: Self.date(hit.closeDate),
                status: hit.oppStatus,
                assistanceListings: hit.cfdaList ?? [],
                matchedQuery: trimmed,
                fetchedAt: now)
        }
    }

    private static func date(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter.date(from: raw)
    }

    private struct SearchPayload: Encodable {
        var rows: Int
        var keyword: String
        var oppStatuses: String
        var startRecordNum: Int
    }

    private struct SearchResponse: Decodable {
        struct DataContainer: Decodable {
            var oppHits: [Hit]
        }
        struct Hit: Decodable {
            var id: String
            var number: String
            var title: String
            var agencyCode: String
            var agency: String
            var openDate: String?
            var closeDate: String?
            var oppStatus: String
            var cfdaList: [String]?
        }
        var errorcode: Int
        var msg: String
        var data: DataContainer
    }
}
