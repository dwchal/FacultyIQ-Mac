import Foundation

/// Async client for NIH iCite (https://icite.od.nih.gov/api) — field-
/// normalized citation metrics (Relative Citation Ratio, NIH percentile) for
/// PubMed-indexed works. No key required. The documented POST route rejects
/// unauthenticated calls, so PMIDs go in GET query strings, chunked to stay
/// well under URL length limits; `fl` is always sent because the default
/// payload includes full citation graphs.
actor ICiteClient {
    static let shared = ICiteClient()

    private let base = URL(string: "https://icite.od.nih.gov/api/pubs")!
    private let session = URLSession.shared
    private let cache = CacheStore.shared
    private let chunkSize = 100
    private let fields = "pmid,year,relative_citation_ratio,nih_percentile,citation_count,citations_per_year,apt"

    enum ClientError: LocalizedError {
        case badStatus(Int)

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): "iCite returned HTTP \(code)."
            }
        }
    }

    func metrics(pmids: [String]) async throws -> [WorkCitationMetrics] {
        var all: [WorkCitationMetrics] = []
        for start in stride(from: 0, to: pmids.count, by: chunkSize) {
            let chunk = pmids[start..<min(start + chunkSize, pmids.count)]
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "pmids", value: chunk.joined(separator: ",")),
                URLQueryItem(name: "fl", value: fields),
            ]
            let url = components.url!

            let data: Data
            if let cached = cache.data(forKey: url.absoluteString) {
                data = cached
            } else {
                data = try await fetchRaw(url)
                cache.store(data, forKey: url.absoluteString)
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(ICiteResponse.self, from: data)
            all.append(contentsOf: response.data.map(\.metrics))
        }
        return all
    }

    private func fetchRaw(_ url: URL, attempt: Int = 1) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("FacultyIQ-Mac/1.0", forHTTPHeaderField: "User-Agent")
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
}

// MARK: - iCite response shapes

struct ICiteResponse: Decodable {
    struct Pub: Decodable {
        var pmid: Int
        var relativeCitationRatio: Double?
        var nihPercentile: Double?
        var citationsPerYear: Double?
        var apt: Double?

        var metrics: WorkCitationMetrics {
            WorkCitationMetrics(
                pmid: String(pmid),
                rcr: relativeCitationRatio,
                nihPercentile: nihPercentile,
                citationsPerYear: citationsPerYear,
                apt: apt)
        }
    }
    var data: [Pub]
}
