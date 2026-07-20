import Foundation

/// Async client for the OpenAlex REST API (https://docs.openalex.org).
/// All responses are cached on disk; requests retry with exponential backoff
/// on rate limits and server errors (mirrors the R app's api_retry()).
actor OpenAlexClient {
    static let shared = OpenAlexClient()

    private let base = URL(string: "https://api.openalex.org")!
    private let session = URLSession.shared
    private let cache = CacheStore.shared

    enum ClientError: LocalizedError {
        case badStatus(Int)
        case rateLimited

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): "OpenAlex returned HTTP \(code)."
            case .rateLimited: "OpenAlex rate limit hit; try again in a minute (set your email in Settings for the polite pool)."
            }
        }
    }

    // MARK: Public API

    func searchAuthors(name: String, limit: Int = 10) async throws -> [AuthorCandidate] {
        let url = endpoint("authors", query: [
            URLQueryItem(name: "search", value: name),
            URLQueryItem(name: "per-page", value: String(limit)),
        ])
        let list: OAList<OAAuthor> = try await fetch(url)
        return list.results.map { $0.candidate }
    }

    /// Look up an author by Scopus author ID (external-ID filter).
    func authorByScopus(_ scopusID: String) async throws -> AuthorCandidate? {
        let cleaned = scopusID.filter(\.isNumber)
        guard !cleaned.isEmpty else { return nil }
        let url = endpoint("authors", query: [
            URLQueryItem(name: "filter", value: "scopus:\(cleaned)"),
        ])
        let list: OAList<OAAuthor> = try await fetch(url)
        return list.results.first?.candidate
    }

    /// Look up an author by ORCID (canonical external-ID route).
    func authorByORCID(_ orcid: String) async throws -> AuthorCandidate? {
        let cleaned = RosterImporter.cleanORCID(orcid)
        guard !cleaned.isEmpty else { return nil }
        let url = endpoint("authors/orcid:\(cleaned)", query: [])
        do {
            let author: OAAuthor = try await fetch(url)
            return author.candidate
        } catch ClientError.badStatus(404) {
            return nil
        }
    }

    /// Batch-fetch author records by short OpenAlex ID. OpenAlex allows up to
    /// 50 OR-ed values per filter, so requests go out in chunks of 50. The
    /// authors list endpoint sometimes returns empty results (observed during
    /// OpenAlex backend migrations), so IDs the batch misses are retried
    /// individually via the single-author route; unresolvable IDs are skipped.
    func authors(ids: [String]) async throws -> [AuthorCandidate] {
        var found: [String: AuthorCandidate] = [:]
        for start in stride(from: 0, to: ids.count, by: 50) {
            let chunk = ids[start..<min(start + 50, ids.count)]
            let url = endpoint("authors", query: [
                URLQueryItem(name: "filter", value: "ids.openalex:" + chunk.joined(separator: "|")),
                URLQueryItem(name: "per-page", value: String(chunk.count)),
            ])
            if let list: OAList<OAAuthor> = try? await fetch(url) {
                for author in list.results {
                    found[author.id.shortOpenAlexID] = author.candidate
                }
            }
        }
        for id in ids where found[id] == nil {
            let url = endpoint("authors/\(id.shortOpenAlexID)", query: [])
            if let author: OAAuthor = try? await fetch(url) {
                found[id] = author.candidate
            }
        }
        return ids.compactMap { found[$0] }
    }

    func author(id openalexID: String, bypassCache: Bool = false) async throws -> AuthorProfile {
        let url = endpoint("authors/\(openalexID.shortOpenAlexID)", query: [])
        let author: OAAuthor = try await fetch(url, bypassCache: bypassCache)
        return author.profile
    }

    /// Resolve a topic name to its OpenAlex topic ID via search.
    func topic(named name: String) async throws -> (id: String, name: String)? {
        let url = endpoint("topics", query: [
            URLQueryItem(name: "search", value: name),
            URLQueryItem(name: "per-page", value: "1"),
        ])
        let list: OAList<OATopic> = try await fetch(url)
        return list.results.first.map { ($0.id.shortOpenAlexID, $0.displayName) }
    }

    /// A random sample of authors active on a topic (≥10 works), for peer
    /// percentile benchmarks. The seed keeps the sample reproducible so the
    /// response cache stays useful. When `institutionIDs` is non-empty, the
    /// sample is restricted to authors last known at one of those
    /// institutions (OR-ed) — for named peer-institution benchmarking rather
    /// than a field-wide draw.
    func authorSample(topicID: String, institutionIDs: [String] = [],
                      size: Int = 200) async throws -> [AuthorCandidate] {
        var filter = "topics.id:\(topicID),works_count:>9"
        if !institutionIDs.isEmpty {
            filter += ",last_known_institutions.id:" + institutionIDs.joined(separator: "|")
        }
        let url = endpoint("authors", query: [
            URLQueryItem(name: "filter", value: filter),
            URLQueryItem(name: "sample", value: String(size)),
            URLQueryItem(name: "seed", value: "42"),
            URLQueryItem(name: "per-page", value: String(min(size, 200))),
        ])
        let list: OAList<OAAuthor> = try await fetch(url)
        return list.results.map { $0.candidate }
    }

    /// Search OpenAlex institutions by name, for the user-curated peer
    /// benchmark list — ambiguous names (e.g. "Washington University" vs
    /// "University of Washington") need a picker, not a first-result guess.
    func searchInstitutions(name: String, limit: Int = 10) async throws -> [InstitutionCandidate] {
        let url = endpoint("institutions", query: [
            URLQueryItem(name: "search", value: name),
            URLQueryItem(name: "per-page", value: String(limit)),
        ])
        let list: OAList<OAInstitution> = try await fetch(url)
        return list.results.map {
            InstitutionCandidate(id: $0.id.shortOpenAlexID, displayName: $0.displayName,
                                 countryCode: $0.countryCode, type: $0.type)
        }
    }

    /// Journal metrics for a batch of linking ISSNs, from the OpenAlex sources
    /// index — the keyless stand-in for Scopus CiteScore. OpenAlex allows 50
    /// OR-ed filter values per request, so ISSNs go out in chunks of 50.
    func sources(issns: [String]) async throws -> [OpenAlexJournalMetrics] {
        var found: [String: OpenAlexJournalMetrics] = [:]
        let select = "id,display_name,issn_l,works_count,cited_by_count,is_oa,is_in_doaj,summary_stats"
        for start in stride(from: 0, to: issns.count, by: 50) {
            let chunk = issns[start..<min(start + 50, issns.count)]
            let url = endpoint("sources", query: [
                URLQueryItem(name: "filter", value: "issn:" + chunk.joined(separator: "|")),
                URLQueryItem(name: "select", value: select),
                URLQueryItem(name: "per-page", value: String(chunk.count)),
            ])
            guard let list: OAList<OASource> = try? await fetch(url) else { continue }
            for source in list.results {
                // A source can carry several ISSNs; key it by the linking ISSN
                // it reports, and by whichever requested ISSN pulled it in.
                let metrics = source.metrics
                if let issnL = source.issnL { found[issnL] = metrics }
                for issn in chunk where found[issn] == nil && source.matches(issn) {
                    found[issn] = metrics
                }
            }
        }
        return issns.compactMap { found[$0] }
    }

    /// All works for an author, cursor-paginated, most-cited first.
    func works(authorID: String, limit: Int = 2000, bypassCache: Bool = false) async throws -> [Work] {
        var works: [Work] = []
        var cursor: String? = "*"
        let select = "id,display_name,publication_year,publication_date,type,cited_by_count,doi,ids,open_access,primary_location,authorships,primary_topic,is_retracted,counts_by_year,awards,funders"

        while let c = cursor, works.count < limit {
            let url = endpoint("works", query: [
                URLQueryItem(name: "filter", value: "author.id:\(authorID.shortOpenAlexID)"),
                URLQueryItem(name: "per-page", value: "200"),
                URLQueryItem(name: "select", value: select),
                URLQueryItem(name: "sort", value: "cited_by_count:desc"),
                URLQueryItem(name: "cursor", value: c),
            ])
            let page: OAList<OAWork> = try await fetch(url, bypassCache: bypassCache)
            works.append(contentsOf: page.results.map { $0.work })
            cursor = page.results.isEmpty ? nil : page.meta?.nextCursor
        }
        return works
    }

    // MARK: Request plumbing

    private func endpoint(_ path: String, query: [URLQueryItem]) -> URL {
        var components = URLComponents(
            url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var items = query
        // Polite-pool email speeds up rate limits; never send anything else.
        if let email = UserDefaults.standard.string(forKey: "openalexEmail"),
           !email.isEmpty {
            items.append(URLQueryItem(name: "mailto", value: email))
        }
        if !items.isEmpty { components.queryItems = items }
        return components.url!
    }

    private func fetch<T: Decodable>(_ url: URL, bypassCache: Bool = false) async throws -> T {
        // Cache key excludes the mailto param so changing email keeps the cache.
        var keyComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        keyComponents.queryItems = keyComponents.queryItems?.filter { $0.name != "mailto" }
        let key = keyComponents.url!.absoluteString

        let data: Data
        if !bypassCache, let cached = cache.data(forKey: key) {
            data = cached
        } else {
            data = try await fetchRaw(url)
            cache.store(data, forKey: key)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    private func fetchRaw(_ url: URL, attempt: Int = 1) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("FacultyIQ-Mac/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        switch status {
        case 200: return data
        case 429, 500...599:
            guard attempt < 3 else {
                throw status == 429 ? ClientError.rateLimited : ClientError.badStatus(status)
            }
            try await Task.sleep(for: .seconds(pow(2, Double(attempt))))
            return try await fetchRaw(url, attempt: attempt + 1)
        default:
            throw ClientError.badStatus(status)
        }
    }
}

// MARK: - OpenAlex response shapes

private struct OAList<T: Decodable>: Decodable {
    struct Meta: Decodable {
        var nextCursor: String?
    }
    var meta: Meta?
    var results: [T]
}

private struct OAAuthor: Decodable {
    struct SummaryStats: Decodable {
        var hIndex: Int?
        var i10Index: Int?
    }
    struct Institution: Decodable {
        var displayName: String?
    }
    struct CountsByYear: Decodable {
        var year: Int
        var worksCount: Int?
        var citedByCount: Int?
    }

    var id: String
    var displayName: String
    var orcid: String?
    var worksCount: Int?
    var citedByCount: Int?
    var summaryStats: SummaryStats?
    var lastKnownInstitutions: [Institution]?
    var countsByYear: [CountsByYear]?

    var candidate: AuthorCandidate {
        AuthorCandidate(
            openalexID: id.shortOpenAlexID,
            displayName: displayName,
            worksCount: worksCount ?? 0,
            citedByCount: citedByCount ?? 0,
            hIndex: summaryStats?.hIndex,
            i10Index: summaryStats?.i10Index,
            affiliation: lastKnownInstitutions?.first?.displayName,
            orcid: orcid
        )
    }

    var profile: AuthorProfile {
        AuthorProfile(
            openalexID: id.shortOpenAlexID,
            displayName: displayName,
            worksCount: worksCount ?? 0,
            citedByCount: citedByCount ?? 0,
            hIndex: summaryStats?.hIndex,
            i10Index: summaryStats?.i10Index,
            affiliation: lastKnownInstitutions?.first?.displayName,
            countsByYear: (countsByYear ?? []).map {
                YearCount(year: $0.year, worksCount: $0.worksCount ?? 0, citedByCount: $0.citedByCount ?? 0)
            }.sorted { $0.year < $1.year }
        )
    }
}

private struct OATopic: Decodable {
    var id: String
    var displayName: String
}

private struct OAInstitution: Decodable {
    var id: String
    var displayName: String
    var countryCode: String?
    var type: String?
}

/// A candidate from an institution-name search — for adding to the
/// user-curated peer-institution benchmark list.
struct InstitutionCandidate: Identifiable, Hashable {
    var id: String
    var displayName: String
    var countryCode: String?
    var type: String?
}

private struct OASource: Decodable {
    struct SummaryStats: Decodable {
        var twoYrMeanCitedness: Double?
        var hIndex: Int?
        var i10Index: Int?

        // OpenAlex spells this "2yr_mean_citedness"; convertFromSnakeCase
        // turns a leading digit into "2yrMeanCitedness", which isn't a legal
        // Swift identifier, so the key is mapped by hand.
        enum CodingKeys: String, CodingKey {
            case twoYrMeanCitedness = "2yrMeanCitedness"
            case hIndex, i10Index
        }
    }

    var id: String
    var displayName: String?
    var issnL: String?
    var issn: [String]?
    var worksCount: Int?
    var citedByCount: Int?
    var isOa: Bool?
    var isInDoaj: Bool?
    var summaryStats: SummaryStats?

    func matches(_ issn: String) -> Bool {
        issnL == issn || (self.issn ?? []).contains(issn)
    }

    var metrics: OpenAlexJournalMetrics {
        OpenAlexJournalMetrics(
            issn: issnL ?? issn?.first ?? id.shortOpenAlexID,
            sourceID: id.shortOpenAlexID,
            title: displayName,
            twoYearMeanCitedness: summaryStats?.twoYrMeanCitedness,
            hIndex: summaryStats?.hIndex,
            worksCount: worksCount,
            isOA: isOa,
            isInDOAJ: isInDoaj)
    }
}

private struct OAWork: Decodable {
    struct OpenAccess: Decodable {
        var isOa: Bool?
        var oaStatus: String?
    }
    struct Location: Decodable {
        struct Source: Decodable {
            var displayName: String?
            var issnL: String?
        }
        var source: Source?
    }
    struct Authorship: Decodable {
        struct Author: Decodable {
            var id: String?
            var displayName: String?
        }
        var author: Author?
        var authorPosition: String?  // "first" | "middle" | "last"
        var isCorresponding: Bool?
    }
    struct Ids: Decodable {
        var pmid: String?        // URL form: https://pubmed.ncbi.nlm.nih.gov/123456
    }
    struct PrimaryTopic: Decodable {
        struct Field: Decodable {
            var displayName: String?
        }
        var displayName: String?
        var field: Field?
    }
    struct CountsByYear: Decodable {
        var year: Int
        var citedByCount: Int?
    }
    /// The richer per-award record: names the funder and its award number.
    struct Award: Decodable {
        var funderId: String?
        var funderDisplayName: String?
        var funderAwardId: String?
    }
    /// The plainer funder credit, present on works that name a funder but no
    /// specific award.
    struct Funder: Decodable {
        var id: String?
        var displayName: String?
    }

    var id: String
    var displayName: String?
    var publicationYear: Int?
    var publicationDate: String?
    var type: String?
    var citedByCount: Int?
    var doi: String?
    var ids: Ids?
    var openAccess: OpenAccess?
    var primaryLocation: Location?
    var authorships: [Authorship]?
    var primaryTopic: PrimaryTopic?
    var isRetracted: Bool?
    var countsByYear: [CountsByYear]?
    var awards: [Award]?
    var funders: [Funder]?

    /// Funder credits, preferring the `awards` entries (which carry award
    /// numbers) and filling in from `funders` for funders they don't mention.
    /// nil only when OpenAlex returned neither field, so "no funders recorded"
    /// stays distinguishable from "fetched before funders were tracked".
    var funderCredits: [WorkGrant]? {
        guard awards != nil || funders != nil else { return nil }
        var credits: [WorkGrant] = []
        var seen = Set<String>()
        for award in awards ?? [] {
            guard let funderID = award.funderId?.shortOpenAlexID else { continue }
            credits.append(WorkGrant(
                funderID: funderID,
                funderName: award.funderDisplayName ?? funderID,
                awardID: award.funderAwardId))
            seen.insert(funderID)
        }
        for funder in funders ?? [] {
            guard let funderID = funder.id?.shortOpenAlexID,
                  seen.insert(funderID).inserted else { continue }
            credits.append(WorkGrant(
                funderID: funderID,
                funderName: funder.displayName ?? funderID,
                awardID: nil))
        }
        return credits
    }

    var work: Work {
        Work(
            id: id.shortOpenAlexID,
            title: displayName ?? "(untitled)",
            year: publicationYear,
            date: publicationDate,
            type: type,
            citedByCount: citedByCount ?? 0,
            doi: doi,
            pmid: ids?.pmid.map { $0.replacingOccurrences(of: "https://pubmed.ncbi.nlm.nih.gov/", with: "") },
            isOA: openAccess?.isOa,
            oaStatus: openAccess?.oaStatus,
            venue: primaryLocation?.source?.displayName,
            venueISSN: primaryLocation?.source?.issnL,
            authors: authorships.map { list in
                list.compactMap { entry in
                    guard let authorID = entry.author?.id else { return nil }
                    return WorkAuthor(
                        openalexID: authorID.shortOpenAlexID,
                        displayName: entry.author?.displayName ?? "",
                        position: entry.authorPosition.flatMap(AuthorPosition.init),
                        isCorresponding: entry.isCorresponding)
                }
            },
            topicName: primaryTopic?.displayName,
            topicField: primaryTopic?.field?.displayName,
            isRetracted: isRetracted,
            citationsByYear: countsByYear.map { list in
                list.map { WorkYearCites(year: $0.year, citedByCount: $0.citedByCount ?? 0) }
            },
            grants: funderCredits
        )
    }
}
