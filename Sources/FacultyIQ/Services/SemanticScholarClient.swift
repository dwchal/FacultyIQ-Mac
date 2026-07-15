import Foundation

/// Async client for the Semantic Scholar Graph API
/// (https://api.semanticscholar.org/graph/v1) — influential-citation counts
/// per paper plus author-level stats. No key required, but unauthenticated
/// requests share a global rate pool, so 429s are expected and surfaced as a
/// friendly per-member error. The Graph API has no ORCID author lookup: the
/// author id comes from the member's Semantic Scholar ID field when set,
/// otherwise from name-matching the authors of the member's top-cited DOIs.
actor SemanticScholarClient {
    static let shared = SemanticScholarClient()

    private let base = URL(string: "https://api.semanticscholar.org/graph/v1")!
    private let session = URLSession.shared
    private let cache = CacheStore.shared
    private let batchLimit = 500

    enum ClientError: LocalizedError {
        case badStatus(Int)
        case rateLimited
        case authorNotFound

        var errorDescription: String? {
            switch self {
            case .badStatus(let code):
                "Semantic Scholar returned HTTP \(code)."
            case .rateLimited:
                "Semantic Scholar rate limit hit (the keyless pool is shared); try again in a few minutes."
            case .authorNotFound:
                "Could not identify a Semantic Scholar author — set the member's Semantic Scholar ID in the roster editor."
            }
        }
    }

    // MARK: Public API

    func enrich(member: FacultyMember, resolvedName: String, works: [Work]) async throws -> S2Data {
        let authorID = try await resolveAuthorID(
            member: member, resolvedName: resolvedName, works: works)

        let author: S2Author = try await get(
            "author/\(authorID)", query: [URLQueryItem(name: "fields", value: "hIndex,paperCount,citationCount")])

        let dois = works
            .sorted { $0.citedByCount > $1.citedByCount }
            .compactMap(\.doi)
            .map(\.bareDOI)
            .prefix(batchLimit)
        var influential: [String: Int] = [:]
        if !dois.isEmpty {
            let papers = try await paperBatch(ids: dois.map { "DOI:\($0)" })
            for paper in papers.compactMap(\.self) {
                guard let doi = paper.externalIds?.doi?.bareDOI,
                      let count = paper.influentialCitationCount else { continue }
                influential[doi] = count
            }
        }
        return S2Data(
            authorID: authorID,
            hIndex: author.hIndex,
            paperCount: author.paperCount,
            citationCount: author.citationCount,
            influentialByDOI: influential,
            fetchedAt: Date())
    }

    /// Surname + first-initial match, diacritic- and case-insensitive.
    static func nameMatches(_ a: String, _ b: String) -> Bool {
        func key(_ s: String) -> (surname: String, initial: Character?) {
            let tokens = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .lowercased()
                .components(separatedBy: CharacterSet.letters.inverted)
                .filter { !$0.isEmpty }
            return (tokens.last ?? "", tokens.first?.first)
        }
        let ka = key(a), kb = key(b)
        guard !ka.surname.isEmpty, ka.surname == kb.surname else { return false }
        guard let ia = ka.initial, let ib = kb.initial else { return true }
        return ia == ib
    }

    // MARK: Author resolution

    private func resolveAuthorID(member: FacultyMember,
                                 resolvedName: String,
                                 works: [Work]) async throws -> String {
        if let id = member.semanticScholarID?.trimmingCharacters(in: .whitespaces), !id.isEmpty {
            return id
        }
        // Look the member up via the author lists of their top-cited DOIs.
        let candidates = works
            .filter { $0.doi != nil }
            .sorted { $0.citedByCount > $1.citedByCount }
            .prefix(3)
        for work in candidates {
            let paper: S2Paper = try await get(
                "paper/DOI:\(work.doi!.bareDOI)",
                query: [URLQueryItem(name: "fields", value: "authors")],
                tolerate404: true)
            let matches = (paper.authors ?? []).filter {
                guard let name = $0.name else { return false }
                return Self.nameMatches(name, resolvedName)
            }
            if matches.count == 1, let id = matches[0].authorId {
                return id
            }
        }
        throw ClientError.authorNotFound
    }

    // MARK: Request plumbing

    private func get<T: Decodable>(_ path: String,
                                   query: [URLQueryItem],
                                   tolerate404: Bool = false) async throws -> T {
        var components = URLComponents(
            url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        let url = components.url!

        let data: Data
        if let cached = cache.data(forKey: url.absoluteString) {
            data = cached
        } else {
            do {
                data = try await fetchRaw(URLRequest(url: url))
            } catch ClientError.badStatus(404) where tolerate404 {
                // A DOI Semantic Scholar doesn't know is normal; treat as empty.
                data = Data("{}".utf8)
            }
            cache.store(data, forKey: url.absoluteString)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func paperBatch(ids: [String]) async throws -> [S2Paper?] {
        let fields = "externalIds,influentialCitationCount"
        var components = URLComponents(
            url: base.appendingPathComponent("paper/batch"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "fields", value: fields)]
        let body = try JSONEncoder().encode(["ids": ids])

        let key = "s2:paper/batch:\(fields):" + ids.joined(separator: ",")
        let data: Data
        if let cached = cache.data(forKey: key) {
            data = cached
        } else {
            var request = URLRequest(url: components.url!)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            data = try await fetchRaw(request)
            cache.store(data, forKey: key)
        }
        return try JSONDecoder().decode([S2Paper?].self, from: data)
    }

    private func fetchRaw(_ request: URLRequest, attempt: Int = 1) async throws -> Data {
        var request = request
        request.setValue("FacultyIQ-Mac/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0

        switch status {
        case 200: return data
        case 429, 500...599:
            guard attempt < 3 else {
                throw status == 429 ? ClientError.rateLimited : ClientError.badStatus(status)
            }
            let retryAfter = http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            try await Task.sleep(for: .seconds(retryAfter ?? pow(2, Double(attempt + 1))))
            return try await fetchRaw(request, attempt: attempt + 1)
        default:
            throw ClientError.badStatus(status)
        }
    }
}

// MARK: - Semantic Scholar response shapes

struct S2Author: Decodable {
    var authorId: String?
    var hIndex: Int?
    var paperCount: Int?
    var citationCount: Int?
}

struct S2Paper: Decodable {
    struct ExternalIds: Decodable {
        var doi: String?

        enum CodingKeys: String, CodingKey {
            case doi = "DOI"
        }
    }
    struct Author: Decodable {
        var authorId: String?
        var name: String?
    }
    var externalIds: ExternalIds?
    var influentialCitationCount: Int?
    var authors: [Author]?
}
