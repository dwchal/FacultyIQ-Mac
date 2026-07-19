import Foundation

/// Async client for the Elsevier Scopus APIs (https://api.elsevier.com) —
/// authoritative author metrics (the h-index promotion committees ask for),
/// journal quality metrics (CiteScore/SNIP/SJR), and the author's Scopus
/// document list for cross-checking OpenAlex coverage.
///
/// Requires a (free) Elsevier API key. Keys are IP-authorized to the
/// subscribing institution, so calls only succeed on the institutional
/// network or VPN unless Elsevier has issued an insttoken. Scopus JSON is
/// idiosyncratic — colon-namespaced keys, numbers as strings, single-element
/// arrays flattened to objects — so responses are parsed with lenient
/// JSONSerialization helpers instead of Codable.
actor ScopusClient {
    static let shared = ScopusClient()

    private let base = URL(string: "https://api.elsevier.com/content")!
    private let session = URLSession.shared
    private let cache = CacheStore.shared
    private var lastRequest = Date.distantPast

    /// Latest X-RateLimit-Remaining seen per endpoint family ("author",
    /// "serial", "search"), for the Settings quota readout.
    private(set) var quotaRemaining: [String: Int] = [:]

    func remainingQuota() -> [String: Int] { quotaRemaining }

    enum ClientError: LocalizedError {
        case missingKey
        case unauthorized
        case entitlement
        case quotaExceeded
        case badStatus(Int)
        case authorNotFound

        var errorDescription: String? {
            switch self {
            case .missingKey:
                "No Scopus API key set — add one in Settings (free from dev.elsevier.com)."
            case .unauthorized:
                "Scopus rejected the API key. Keys only work from the institution's network — connect to VPN, or request an insttoken from Elsevier and add it in Settings."
            case .entitlement:
                "This Scopus view needs a subscriber entitlement your key doesn't have from this network."
            case .quotaExceeded:
                "Scopus weekly API quota exhausted; it resets 7 days after first use."
            case .badStatus(let code):
                "Scopus returned HTTP \(code)."
            case .authorNotFound:
                "No Scopus author record found for that ID."
            }
        }
    }

    // MARK: Public API

    /// Author-level metrics for a Scopus author ID. ENHANCED view (h-index,
    /// affiliation) falls back to STANDARD when the entitlement is missing.
    func author(scopusID: String) async throws -> ScopusAuthorMetrics {
        let id = scopusID.filter(\.isNumber)
        guard !id.isEmpty else { throw ClientError.authorNotFound }
        let data: Data
        do {
            data = try await get("author/author_id/\(id)",
                                 query: [URLQueryItem(name: "view", value: "ENHANCED")],
                                 family: "author")
        } catch ClientError.entitlement {
            data = try await get("author/author_id/\(id)",
                                 query: [URLQueryItem(name: "view", value: "STANDARD")],
                                 family: "author")
        }
        guard let metrics = Self.parseAuthor(data, scopusID: id) else {
            throw ClientError.authorNotFound
        }
        return metrics
    }

    /// CiteScore/SNIP/SJR for a journal by ISSN; nil when Scopus doesn't
    /// index the venue. When the ENHANCED view lacks percentile data, a
    /// CITESCORE-view call fills it in (both responses cache for 7 days,
    /// and journals repeat across members, so live traffic stays small).
    func serialMetrics(issn: String) async throws -> ScopusJournalMetrics? {
        let clean = issn.replacingOccurrences(of: "-", with: "").uppercased()
        guard clean.count == 8 else { return nil }
        let data: Data
        do {
            data = try await get("serial/title/issn/\(clean)",
                                 query: [URLQueryItem(name: "view", value: "ENHANCED")],
                                 family: "serial")
        } catch ClientError.badStatus(404), ClientError.authorNotFound {
            return nil
        }
        guard var metrics = Self.parseSerial(data, issn: issn) else { return nil }
        if metrics.topPercentile == nil {
            if let extra = try? await get("serial/title/issn/\(clean)",
                                          query: [URLQueryItem(name: "view", value: "CITESCORE")],
                                          family: "serial"),
               let enriched = Self.parseSerial(extra, issn: issn),
               enriched.topPercentile != nil {
                metrics.topPercentile = enriched.topPercentile
            }
        }
        return metrics
    }

    /// Author candidates for a name — Scopus name search is fuzzy, so results
    /// are only ever attached after the user confirms one.
    func searchAuthors(lastName: String, firstName: String?) async throws -> [ScopusAuthorCandidate] {
        var query = "AUTHLASTNAME(\(lastName))"
        if let firstName, !firstName.isEmpty {
            query += " AND AUTHFIRST(\(firstName))"
        }
        let data = try await get("search/author",
                                 query: [URLQueryItem(name: "query", value: query),
                                         URLQueryItem(name: "count", value: "25")],
                                 family: "search")
        return Self.parseAuthorSearch(data)
    }

    /// Every document EID/DOI on the author's Scopus record, for the
    /// OpenAlex-coverage cross-check.
    func documents(scopusID: String) async throws -> [ScopusDocRef] {
        let id = scopusID.filter(\.isNumber)
        guard !id.isEmpty else { return [] }
        var docs: [ScopusDocRef] = []
        var start = 0
        let pageSize = 25
        while true {
            let data = try await get(
                "search/scopus",
                query: [URLQueryItem(name: "query", value: "AU-ID(\(id))"),
                        URLQueryItem(name: "field", value: "dc:identifier,prism:doi,eid,dc:title,prism:coverDate"),
                        URLQueryItem(name: "count", value: "\(pageSize)"),
                        URLQueryItem(name: "start", value: "\(start)")],
                family: "search")
            let page = Self.parseDocumentsPage(data)
            docs.append(contentsOf: page.docs)
            start += pageSize
            if start >= page.total || page.docs.isEmpty { break }
        }
        return docs
    }

    // MARK: Request plumbing

    private func get(_ path: String, query: [URLQueryItem], family: String) async throws -> Data {
        var components = URLComponents(
            url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        let url = components.url!

        // Credentials travel in headers, so the URL is a safe cache key that
        // survives key changes.
        if let cached = cache.data(forKey: url.absoluteString) {
            return cached
        }
        let data = try await fetchRaw(URLRequest(url: url), family: family)
        cache.store(data, forKey: url.absoluteString)
        return data
    }

    private func fetchRaw(_ request: URLRequest, family: String, attempt: Int = 1) async throws -> Data {
        let defaults = UserDefaults.standard
        guard let key = defaults.string(forKey: "scopusAPIKey")?
            .trimmingCharacters(in: .whitespaces), !key.isEmpty else {
            throw ClientError.missingKey
        }

        // Author Retrieval allows 3 req/s — the tightest Scopus throttle.
        let elapsed = Date().timeIntervalSince(lastRequest)
        if elapsed < 0.5 {
            try await Task.sleep(for: .seconds(0.5 - elapsed))
        }
        lastRequest = Date()

        var request = request
        request.setValue("FacultyIQ-Mac/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(key, forHTTPHeaderField: "X-ELS-APIKey")
        if let token = defaults.string(forKey: "scopusInsttoken")?
            .trimmingCharacters(in: .whitespaces), !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-ELS-Insttoken")
        }

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0

        if let remaining = http?.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap(Int.init) {
            quotaRemaining[family] = remaining
        }

        switch status {
        case 200: return data
        case 401: throw ClientError.unauthorized
        case 403: throw ClientError.entitlement
        case 429:
            if http?.value(forHTTPHeaderField: "X-ELS-Status")?
                .localizedCaseInsensitiveContains("QUOTA") == true {
                throw ClientError.quotaExceeded
            }
            fallthrough
        case 500...599:
            guard attempt < 3 else { throw ClientError.badStatus(status) }
            try await Task.sleep(for: .seconds(pow(2, Double(attempt))))
            return try await fetchRaw(request, family: family, attempt: attempt + 1)
        default:
            throw ClientError.badStatus(status)
        }
    }

    // MARK: Response parsing (static for fixture tests)

    static func parseAuthor(_ data: Data, scopusID: String) -> ScopusAuthorMetrics? {
        guard let root = jsonObject(data),
              let entry = objects(root["author-retrieval-response"]).first else { return nil }
        let coredata = object(entry["coredata"])
        let profile = object(entry["author-profile"])
        let affiliation = objects(object(profile?["affiliation-current"])?["affiliation"]).first
        let ipDoc = object(affiliation?["ip-doc"])
        let affiliationName = stringValue(ipDoc?["afdispname"])
            ?? stringValue(object(ipDoc?["preferred-name"])?["$"])
            ?? stringValue(affiliation?["affiliation-name"])
        return ScopusAuthorMetrics(
            scopusAuthorID: scopusID,
            documentCount: intValue(coredata?["document-count"]),
            citedByCount: intValue(coredata?["cited-by-count"]),
            citationCount: intValue(coredata?["citation-count"]),
            hIndex: intValue(entry["h-index"]),
            currentAffiliation: affiliationName)
    }

    static func parseSerial(_ data: Data, issn: String) -> ScopusJournalMetrics? {
        guard let root = jsonObject(data),
              let entry = objects(object(root["serial-metadata-response"])?["entry"]).first
        else { return nil }
        let citeScoreList = object(entry["citeScoreYearInfoList"])
        // Deepest percentile anywhere under the CiteScore info (the CITESCORE
        // view nests subject ranks several levels down); a journal's headline
        // percentile is its best subject-area percentile.
        let percentile = maxValue(forKey: "percentile", in: citeScoreList as Any?)
        return ScopusJournalMetrics(
            issn: issn,
            title: stringValue(entry["dc:title"]),
            citeScore: doubleValue(citeScoreList?["citeScoreCurrentMetric"]),
            citeScoreYear: intValue(citeScoreList?["citeScoreCurrentMetricYear"]),
            topPercentile: percentile,
            snip: latestListValue(entry["SNIPList"], itemKey: "SNIP"),
            sjr: latestListValue(entry["SJRList"], itemKey: "SJR"))
    }

    static func parseAuthorSearch(_ data: Data) -> [ScopusAuthorCandidate] {
        guard let root = jsonObject(data),
              let results = object(root["search-results"]) else { return [] }
        return objects(results["entry"]).compactMap { entry in
            guard let identifier = stringValue(entry["dc:identifier"]),
                  let id = identifier.split(separator: ":").last.map(String.init),
                  !id.isEmpty else { return nil }
            let name = object(entry["preferred-name"])
            let display = [stringValue(name?["given-name"]), stringValue(name?["surname"])]
                .compactMap(\.self).joined(separator: " ")
            let affiliation = object(entry["affiliation-current"])
            return ScopusAuthorCandidate(
                scopusID: id,
                name: display.isEmpty ? (stringValue(entry["dc:title"]) ?? id) : display,
                affiliation: stringValue(affiliation?["affiliation-name"]),
                city: stringValue(affiliation?["affiliation-city"]),
                documentCount: intValue(entry["document-count"]))
        }
    }

    static func parseDocumentsPage(_ data: Data) -> (docs: [ScopusDocRef], total: Int) {
        guard let root = jsonObject(data),
              let results = object(root["search-results"]) else { return ([], 0) }
        let docs = objects(results["entry"]).compactMap { entry -> ScopusDocRef? in
            guard let eid = stringValue(entry["eid"]) else { return nil }
            return ScopusDocRef(
                eid: eid,
                doi: stringValue(entry["prism:doi"]),
                title: stringValue(entry["dc:title"]),
                coverDate: stringValue(entry["prism:coverDate"]))
        }
        return (docs, intValue(results["opensearch:totalResults"]) ?? docs.count)
    }

    // MARK: Lenient JSON helpers

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func object(_ any: Any?) -> [String: Any]? {
        any as? [String: Any]
    }

    /// Scopus flattens single-element arrays to bare objects; normalize both.
    private static func objects(_ any: Any?) -> [[String: Any]] {
        if let list = any as? [[String: Any]] { return list }
        if let one = any as? [String: Any] { return [one] }
        return []
    }

    private static func stringValue(_ any: Any?) -> String? {
        if let s = any as? String { return s.isEmpty ? nil : s }
        if let n = any as? NSNumber { return n.stringValue }
        // Values sometimes arrive wrapped: {"$": "actual value"}
        if let wrapped = (any as? [String: Any])?["$"] { return stringValue(wrapped) }
        return nil
    }

    private static func intValue(_ any: Any?) -> Int? {
        stringValue(any).flatMap { Int($0) }
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        stringValue(any).flatMap { Double($0) }
    }

    /// Latest entry of a {"SNIPList": {"SNIP": [{"@year": "2024", "$": "1.2"}]}}
    /// style year list.
    private static func latestListValue(_ any: Any?, itemKey: String) -> Double? {
        let items = objects(object(any)?[itemKey])
        let dated = items.compactMap { item -> (year: Int, value: Double)? in
            guard let value = doubleValue(item) else { return nil }
            return (intValue(item["@year"]) ?? 0, value)
        }
        return dated.max { $0.year < $1.year }?.value
    }

    /// Largest numeric value under any occurrence of `key`, searching the
    /// whole subtree (subject ranks nest at varying depths per view).
    private static func maxValue(forKey key: String, in any: Any?) -> Double? {
        var best: Double?
        func walk(_ node: Any?) {
            if let dict = node as? [String: Any] {
                for (k, v) in dict {
                    if k == key, let value = doubleValue(v) {
                        best = max(best ?? -.infinity, value)
                    } else {
                        walk(v)
                    }
                }
            } else if let list = node as? [Any] {
                list.forEach(walk)
            }
        }
        walk(any)
        return best
    }
}
