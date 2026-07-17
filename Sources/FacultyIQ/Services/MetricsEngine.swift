import Foundation

/// Pure metric computation over fetched person data — the Swift counterpart of
/// utils_metrics.R and utils_prediction.R.
enum MetricsEngine {
    static var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    // MARK: Index metrics

    /// h papers cited at least h times.
    static func hIndex(citations: [Int]) -> Int {
        let sorted = citations.sorted(by: >)
        var h = 0
        for (i, c) in sorted.enumerated() where c >= i + 1 {
            h = i + 1
        }
        return h
    }

    static func i10Index(citations: [Int]) -> Int {
        citations.count { $0 >= 10 }
    }

    // The effective* helpers take the larger of the profile figure and the
    // one computed from the fetched works. The works list holds the top-cited
    // works, so the local computation is a hard lower bound on the truth —
    // if the profile reports less, OpenAlex handed back a degraded record
    // (observed 2026-07-16: zeroed summary_stats during a backend migration),
    // and trusting it would zero the dashboards, snapshots, and deltas.

    /// The larger of the profile's h-index and the locally computed one.
    static func effectiveHIndex(_ data: PersonData) -> Int {
        max(data.profile.hIndex ?? 0, hIndex(citations: data.works.map(\.citedByCount)))
    }

    /// The larger of the profile's citation total and the works-list sum.
    static func effectiveCitations(_ data: PersonData) -> Int {
        max(data.profile.citedByCount, data.works.map(\.citedByCount).reduce(0, +))
    }

    /// The larger of the profile's works count and the works-list length.
    static func effectiveWorksCount(_ data: PersonData) -> Int {
        max(data.profile.worksCount, data.works.count)
    }

    /// The larger of the profile's i10 and the locally computed one.
    static func effectiveI10(_ data: PersonData) -> Int {
        max(data.profile.i10Index ?? 0, i10Index(citations: data.works.map(\.citedByCount)))
    }

    // MARK: Refresh deltas

    /// What changed from `old` to `new`, folded into any accumulated delta so
    /// repeated checks keep reporting against the user's last-reviewed baseline.
    /// Work IDs that have since vanished from the record (merged or removed by
    /// OpenAlex) are dropped rather than reported as new.
    static func refreshDelta(old: PersonData, new: PersonData,
                             accumulating existing: RefreshDelta? = nil) -> RefreshDelta {
        let oldIDs = Set(old.works.map(\.id))
        let addedIDs = new.works.map(\.id).filter { !oldIDs.contains($0) }
        let currentIDs = Set(new.works.map(\.id))
        let carried = (existing?.newWorkIDs ?? []).filter {
            currentIDs.contains($0) && !addedIDs.contains($0)
        }
        return RefreshDelta(
            since: existing?.since ?? old.fetchedAt,
            checkedAt: new.fetchedAt,
            newWorkIDs: carried + addedIDs,
            worksDelta: (existing?.worksDelta ?? 0) + (effectiveWorksCount(new) - effectiveWorksCount(old)),
            citationsDelta: (existing?.citationsDelta ?? 0) + (effectiveCitations(new) - effectiveCitations(old)),
            hIndexDelta: (existing?.hIndexDelta ?? 0) + (effectiveHIndex(new) - effectiveHIndex(old))
        )
    }

    // MARK: Per-person metrics

    static func personMetrics(member: FacultyMember, data: PersonData) -> PersonMetrics {
        let works = data.works
        let totalCitations = effectiveCitations(data)
        let worksCount = effectiveWorksCount(data)

        let firstPubYear = works.compactMap(\.year).min()
        // Career span from hire year when known, else first publication.
        let startYear = member.hireYear ?? firstPubYear
        let careerYears = startYear.map { max(currentYear - $0 + 1, 1) } ?? 1

        let withOA = works.compactMap(\.isOA)
        let oaPercent: Double? = withOA.isEmpty
            ? nil
            : 100 * Double(withOA.count { $0 }) / Double(withOA.count)

        let recentCutoff = currentYear - 4
        let recentWorks = works.count { ($0.year ?? 0) >= recentCutoff }

        // Authorship-position metrics, from the member's own entry in each
        // work's byline (the profile ID is the resolved OpenAlex author).
        let authorID = data.profile.openalexID
        var firstAuthor = 0, seniorAuthor = 0, positioned = 0
        var recentPositioned = 0, recentSenior = 0
        for work in works {
            guard let position = ownAuthorship(work, authorID: authorID)?.position else { continue }
            positioned += 1
            if position == .first { firstAuthor += 1 }
            if position == .last { seniorAuthor += 1 }
            if (work.year ?? 0) >= recentCutoff {
                recentPositioned += 1
                if position == .last { recentSenior += 1 }
            }
        }

        return PersonMetrics(
            memberID: member.id,
            name: member.name,
            rank: AcademicRank.parse(member.rank),
            rawRank: member.rank,
            worksCount: worksCount,
            citations: totalCitations,
            hIndex: effectiveHIndex(data),
            i10Index: effectiveI10(data),
            citationsPerWork: worksCount > 0 ? Double(totalCitations) / Double(worksCount) : 0,
            worksPerYear: Double(worksCount) / Double(careerYears),
            oaPercent: oaPercent,
            recentWorks5y: recentWorks,
            firstPubYear: firstPubYear,
            careerYears: careerYears,
            firstAuthorWorks: firstAuthor,
            seniorAuthorWorks: seniorAuthor,
            positionTracked: positioned,
            independentHIndex: independentHIndex(data: data, authorID: authorID),
            seniorShare5y: recentPositioned > 0
                ? 100 * Double(recentSenior) / Double(recentPositioned) : nil
        )
    }

    static func allMetrics(roster: [FacultyMember], personData: [UUID: PersonData]) -> [PersonMetrics] {
        roster.compactMap { member in
            personData[member.id].map { personMetrics(member: member, data: $0) }
        }
    }

    // MARK: Division aggregates

    static func divisionSummary(roster: [FacultyMember],
                                resolvedCount: Int,
                                metrics: [PersonMetrics]) -> DivisionSummary {
        let oaValues = metrics.compactMap(\.oaPercent)
        return DivisionSummary(
            facultyCount: roster.count,
            resolvedCount: resolvedCount,
            totalWorks: metrics.map(\.worksCount).reduce(0, +),
            totalCitations: metrics.map(\.citations).reduce(0, +),
            medianHIndex: metrics.map { Double($0.hIndex) }.median,
            medianWorksPerYear: metrics.map(\.worksPerYear).median,
            oaPercent: oaValues.isEmpty ? nil : oaValues.median
        )
    }

    /// Publications per year across the division, from work records.
    static func worksPerYear(personData: [PersonData], fromYear: Int = 1990) -> [(year: Int, count: Int)] {
        var counts: [Int: Int] = [:]
        for data in personData {
            for work in data.works {
                if let y = work.year, y >= fromYear, y <= currentYear {
                    counts[y, default: 0] += 1
                }
            }
        }
        return counts.sorted { $0.key < $1.key }.map { (year: $0.key, count: $0.value) }
    }

    /// Citations received per year across the division — new citations dated
    /// by the citing paper's year, from per-work counts (roughly the last
    /// decade). Like the works chart, a coauthored work counts once per member.
    static func citationsPerYear(personData: [PersonData]) -> [(year: Int, count: Int)] {
        var counts: [Int: Int] = [:]
        for data in personData {
            for (year, count) in citationsByYear(data) where year <= currentYear {
                counts[year, default: 0] += count
            }
        }
        return counts.sorted { $0.key < $1.key }.map { (year: $0.key, count: $0.value) }
    }

    /// Total citations accrued to date by works published each year, distinct
    /// across the cohort (a coauthored work counts once) — the "vintage
    /// impact" companion to citationsPerYear. Recent years are always low:
    /// their papers are still accruing citations.
    static func citationsByPublicationYear(personData: [PersonData],
                                           fromYear: Int = 1990) -> [(year: Int, citations: Int)] {
        var seen = Set<String>()
        var totals: [Int: Int] = [:]
        for data in personData {
            for work in data.works {
                guard let year = work.year, year >= fromYear, year <= currentYear,
                      seen.insert(work.id).inserted else { continue }
                totals[year, default: 0] += work.citedByCount
            }
        }
        return totals.sorted { $0.key < $1.key }.map { (year: $0.key, citations: $0.value) }
    }

    /// OA share of division publications per year.
    static func oaShareByYear(personData: [PersonData], fromYear: Int = 2010) -> [(year: Int, percent: Double)] {
        var total: [Int: Int] = [:]
        var oa: [Int: Int] = [:]
        for data in personData {
            for work in data.works {
                guard let y = work.year, y >= fromYear, y <= currentYear,
                      let isOA = work.isOA else { continue }
                total[y, default: 0] += 1
                if isOA { oa[y, default: 0] += 1 }
            }
        }
        return total.sorted { $0.key < $1.key }.map {
            (year: $0.key, percent: 100 * Double(oa[$0.key] ?? 0) / Double($0.value))
        }
    }

    static func topWorks(personData: [PersonData], n: Int = 20) -> [Work] {
        var seen = Set<String>()
        var all: [Work] = []
        for data in personData {
            for work in data.works where seen.insert(work.id).inserted {
                all.append(work)
            }
        }
        return Array(all.sorted { $0.citedByCount > $1.citedByCount }.prefix(n))
    }

    // MARK: Coauthorship network

    /// Pairwise coauthorship between resolved roster members. A shared work is
    /// detected two ways: it appears in both members' works lists (which also
    /// covers data fetched before authorships were tracked), or a member's
    /// resolved OpenAlex ID appears in another member's work.authors (which
    /// recovers works cut off by the per-author fetch limit).
    static func coauthorNetwork(roster: [FacultyMember],
                                resolutions: [UUID: Resolution],
                                personData: [UUID: PersonData]) -> CoauthorNetwork {
        let eligible = roster.filter { resolutions[$0.id] != nil && personData[$0.id] != nil }
        let authorToMember = Dictionary(
            eligible.map { (resolutions[$0.id]!.openalexID, $0.id) },
            uniquingKeysWith: { first, _ in first })

        var membersPerWork: [String: Set<UUID>] = [:]
        var staleAuthorData = false
        for member in eligible {
            let works = personData[member.id]!.works
            if !works.isEmpty, works.allSatisfy({ $0.authors == nil }) {
                staleAuthorData = true
            }
            for work in works {
                membersPerWork[work.id, default: []].insert(member.id)
                for author in work.authors ?? [] {
                    if let coauthor = authorToMember[author.openalexID] {
                        membersPerWork[work.id, default: []].insert(coauthor)
                    }
                }
            }
        }

        var pairCounts: [String: (a: UUID, b: UUID, count: Int)] = [:]
        for members in membersPerWork.values where members.count >= 2 {
            let sorted = members.sorted { $0.uuidString < $1.uuidString }
            for i in sorted.indices {
                for j in sorted.indices where j > i {
                    let key = "\(sorted[i].uuidString)|\(sorted[j].uuidString)"
                    let existing = pairCounts[key]?.count ?? 0
                    pairCounts[key] = (sorted[i], sorted[j], existing + 1)
                }
            }
        }
        let edges = pairCounts.values
            .map { CoauthorEdge(memberA: $0.a, memberB: $0.b, weight: $0.count) }
            .sorted { ($0.weight, $1.id) > ($1.weight, $0.id) }

        var degree: [UUID: Int] = [:]
        var sharedWorks: [UUID: Int] = [:]
        for edge in edges {
            for member in [edge.memberA, edge.memberB] {
                degree[member, default: 0] += 1
                sharedWorks[member, default: 0] += edge.weight
            }
        }
        let nodes = eligible
            .map { member in
                CoauthorNode(
                    memberID: member.id,
                    name: member.name,
                    rank: AcademicRank.parse(member.rank),
                    worksCount: personData[member.id]!.works.count,
                    degree: degree[member.id] ?? 0,
                    sharedWorks: sharedWorks[member.id] ?? 0)
            }
            .sorted { $0.name < $1.name }

        return CoauthorNetwork(nodes: nodes, edges: edges, staleAuthorData: staleAuthorData)
    }

    // MARK: External collaborators

    /// Authors on roster members' works who are not themselves on the roster.
    /// Exclusion is by resolved OpenAlex ID across `fullRoster` (not just the
    /// division-filtered `roster`, so members of other divisions never appear
    /// as "external"), plus a normalized-name match so unresolved roster
    /// members don't list themselves.
    static func externalCollaborators(roster: [FacultyMember],
                                      fullRoster: [FacultyMember]? = nil,
                                      resolutions: [UUID: Resolution],
                                      personData: [UUID: PersonData]) -> [ExternalCollaborator] {
        let eligible = roster.filter { resolutions[$0.id] != nil && personData[$0.id] != nil }
        let everyone = fullRoster ?? roster
        let rosterAuthorIDs = Set(everyone.compactMap { resolutions[$0.id]?.openalexID })
        let rosterNameKeys = Set(
            everyone.map { nameKey($0.name) } +
            everyone.compactMap { resolutions[$0.id].map { nameKey($0.displayName) } }
        ).subtracting([""])

        var displayName: [String: String] = [:]
        var workIDs: [String: Set<String>] = [:]
        var partnerWorkIDs: [String: [UUID: Set<String>]] = [:]
        var lastYear: [String: Int] = [:]
        for member in eligible {
            for work in personData[member.id]!.works {
                for author in work.authors ?? [] {
                    guard !rosterAuthorIDs.contains(author.openalexID),
                          !rosterNameKeys.contains(nameKey(author.displayName)) else { continue }
                    let id = author.openalexID
                    // Keep the longest name variant seen (most complete form).
                    if author.displayName.count > (displayName[id]?.count ?? 0) {
                        displayName[id] = author.displayName
                    }
                    workIDs[id, default: []].insert(work.id)
                    partnerWorkIDs[id, default: [:]][member.id, default: []].insert(work.id)
                    if let year = work.year {
                        lastYear[id] = max(lastYear[id] ?? year, year)
                    }
                }
            }
        }

        let memberName = Dictionary(uniqueKeysWithValues: eligible.map { ($0.id, $0.name) })
        return workIDs
            .map { id, works in
                let partners = (partnerWorkIDs[id] ?? [:])
                    .map { memberID, shared in
                        ExternalCollaborator.Partner(
                            memberID: memberID,
                            name: memberName[memberID] ?? "—",
                            weight: shared.count)
                    }
                    .sorted { ($0.weight, $1.name) > ($1.weight, $0.name) }
                return ExternalCollaborator(
                    openalexID: id,
                    displayName: displayName[id] ?? id,
                    sharedWorks: works.count,
                    partners: partners,
                    lastSharedYear: lastYear[id])
            }
            .sorted { ($0.sharedWorks, $0.partnerCount, $1.displayName)
                    > ($1.sharedWorks, $1.partnerCount, $0.displayName) }
    }

    /// Order-insensitive name key: lowercased, diacritic-folded word tokens,
    /// single-letter initials dropped, sorted. "Doe, John A." == "John Doe".
    static func nameKey(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count > 1 }
            .sorted()
            .joined(separator: " ")
    }

    // MARK: Rank benchmarks & promotion insight

    static func rankBenchmarks(metrics: [PersonMetrics]) -> [RankBenchmark] {
        Dictionary(grouping: metrics.filter { $0.rank != nil }, by: { $0.rank! })
            .map { rank, group in
                let works = group.map { Double($0.worksCount) }
                let citations = group.map { Double($0.citations) }
                let hIndexes = group.map { Double($0.hIndex) }
                return RankBenchmark(
                    rank: rank,
                    count: group.count,
                    medianWorks: works.median,
                    medianCitations: citations.median,
                    medianHIndex: hIndexes.median,
                    medianWorksPerYear: group.map(\.worksPerYear).median,
                    targetWorks: works.percentile(0.25),
                    targetCitations: citations.percentile(0.25),
                    targetHIndex: hIndexes.percentile(0.25)
                )
            }
            .sorted { $0.rank < $1.rank }
    }

    /// Every member's standing against the next rank's promotion targets
    /// (25th percentile of current rank-holders) on the three key metrics.
    static func promotionProgress(metrics: [PersonMetrics],
                                  benchmarks: [RankBenchmark]) -> [PromotionProgress] {
        let byRank = Dictionary(uniqueKeysWithValues: benchmarks.map { ($0.rank, $0) })
        return metrics.compactMap { m in
            guard let rank = m.rank, let next = rank.next,
                  let bench = byRank[next] else { return nil }
            return PromotionProgress(
                metrics: m, currentRank: rank, targetRank: next,
                checks: [
                    .init(label: "Works", value: m.worksCount, benchmark: bench.targetWorks),
                    .init(label: "Citations", value: m.citations, benchmark: bench.targetCitations),
                    .init(label: "h-index", value: m.hIndex, benchmark: bench.targetHIndex),
                ])
        }
    }

    /// Faculty whose metrics meet or exceed the next rank's medians on at
    /// least two of three key metrics — the simplified counterpart of
    /// identify_promotion_candidates().
    static func promotionCandidates(metrics: [PersonMetrics],
                                    benchmarks: [RankBenchmark]) -> [PromotionCandidate] {
        promotionProgress(metrics: metrics, benchmarks: benchmarks)
            .filter { $0.metCount >= 2 }
            .map {
                PromotionCandidate(
                    metrics: $0.metrics, currentRank: $0.currentRank,
                    targetRank: $0.targetRank,
                    exceededMetrics: $0.checks.filter(\.met).map(\.label))
            }
            .sorted { $0.exceededMetrics.count > $1.exceededMetrics.count }
    }

    // MARK: Export

    static func metricsCSV(metrics: [PersonMetrics],
                           roster: [FacultyMember],
                           personData: [UUID: PersonData] = [:],
                           enrichment: [UUID: Enrichment] = [:]) -> String {
        let byID = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, $0) })
        var lines = ["Name,Rank,Division,Status,Works,Citations,h-index,i10-index,Independent h-index,First Author Works,Senior Author Works,Senior Share 5y %,Citations/Work,Works/Year,OA %,Recent Works (5y),First Pub Year,Career Years,Mean RCR,NIH Grants,Total NIH Funding,ORCID,Scopus ID"]
        for m in metrics.sorted(by: { $0.name < $1.name }) {
            let member = byID[m.memberID]
            let rcr: Double? = personData[m.memberID].flatMap {
                meanRCR(works: $0.works, icite: enrichment[m.memberID]?.icite)
            }
            let grants: [Grant]? = enrichment[m.memberID]?.grants?.grants
            let totalFunding: Int? = grants.map { $0.map(\.totalAward).reduce(0, +) }
            var fields: [String] = [
                m.name,
                m.rawRank ?? "",
                member?.division ?? "",
                (member?.status ?? .active).label,
                String(m.worksCount),
                String(m.citations),
                String(m.hIndex),
                String(m.i10Index),
                m.independentHIndex.map(String.init) ?? "",
                m.positionTracked > 0 ? String(m.firstAuthorWorks) : "",
                m.positionTracked > 0 ? String(m.seniorAuthorWorks) : "",
                m.seniorShare5y.map { String(format: "%.0f", $0) } ?? "",
                String(format: "%.1f", m.citationsPerWork),
                String(format: "%.2f", m.worksPerYear),
            ]
            fields += [
                m.oaPercent.map { String(format: "%.0f", $0) } ?? "",
                String(m.recentWorks5y),
                m.firstPubYear.map(String.init) ?? "",
                String(m.careerYears),
                rcr.map { String(format: "%.2f", $0) } ?? "",
                grants.map { String($0.count) } ?? "",
                totalFunding.map(String.init) ?? "",
                member?.orcid ?? "",
                member?.scopusID ?? "",
            ]
            lines.append(fields.map(csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func yearlyCSV(roster: [FacultyMember], personData: [UUID: PersonData]) -> String {
        var lines = ["Name,Year,Works,Citations Received"]
        for member in roster.sorted(by: { $0.name < $1.name }) {
            guard let data = personData[member.id] else { continue }
            var worksByYear: [Int: Int] = [:]
            for work in data.works {
                if let y = work.year { worksByYear[y, default: 0] += 1 }
            }
            let citesByYear = citationsByYear(data)
            for year in Set(worksByYear.keys).union(citesByYear.keys).sorted() {
                lines.append([
                    csvEscape(member.name),
                    String(year),
                    String(worksByYear[year] ?? 0),
                    String(citesByYear[year] ?? 0),
                ].joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func coauthorshipCSV(network: CoauthorNetwork) -> String {
        let nameByID = Dictionary(uniqueKeysWithValues: network.nodes.map { ($0.memberID, $0.name) })
        var lines = ["Member A,Member B,Shared Works"]
        for edge in network.edges {
            lines.append([
                csvEscape(nameByID[edge.memberA] ?? ""),
                csvEscape(nameByID[edge.memberB] ?? ""),
                String(edge.weight),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func externalCollaboratorsCSV(_ collaborators: [ExternalCollaborator]) -> String {
        var lines = ["Name,OpenAlex ID,Shared Works,Roster Partners,Partner Names,Last Shared Year"]
        for c in collaborators {
            lines.append([
                csvEscape(c.displayName),
                c.openalexID,
                String(c.sharedWorks),
                String(c.partnerCount),
                csvEscape(c.partners.map { "\($0.name) (\($0.weight))" }.joined(separator: "; ")),
                c.lastSharedYear.map(String.init) ?? "",
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func csvEscape(_ field: String) -> String {
        if field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
