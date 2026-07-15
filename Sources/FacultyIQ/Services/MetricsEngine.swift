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

    // MARK: Per-person metrics

    static func personMetrics(member: FacultyMember, data: PersonData) -> PersonMetrics {
        let works = data.works
        let citations = works.map(\.citedByCount)
        let totalCitations = data.profile.citedByCount
        let worksCount = max(data.profile.worksCount, works.count)

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

        return PersonMetrics(
            memberID: member.id,
            name: member.name,
            rank: AcademicRank.parse(member.rank),
            rawRank: member.rank,
            worksCount: worksCount,
            citations: totalCitations,
            hIndex: data.profile.hIndex ?? hIndex(citations: citations),
            i10Index: data.profile.i10Index ?? i10Index(citations: citations),
            citationsPerWork: worksCount > 0 ? Double(totalCitations) / Double(worksCount) : 0,
            worksPerYear: Double(worksCount) / Double(careerYears),
            oaPercent: oaPercent,
            recentWorks5y: recentWorks,
            firstPubYear: firstPubYear,
            careerYears: careerYears
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

    /// Citations received per year across the division (OpenAlex counts_by_year,
    /// which covers roughly the last decade).
    static func citationsPerYear(personData: [PersonData]) -> [(year: Int, count: Int)] {
        var counts: [Int: Int] = [:]
        for data in personData {
            for yc in data.profile.countsByYear where yc.year <= currentYear {
                counts[yc.year, default: 0] += yc.citedByCount
            }
        }
        return counts.sorted { $0.key < $1.key }.map { (year: $0.key, count: $0.value) }
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
        var lines = ["Name,Rank,Division,Works,Citations,h-index,i10-index,Citations/Work,Works/Year,OA %,Recent Works (5y),First Pub Year,Career Years,Mean RCR,NIH Grants,Total NIH Funding,ORCID,Scopus ID"]
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
                String(m.worksCount),
                String(m.citations),
                String(m.hIndex),
                String(m.i10Index),
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
            let citesByYear = Dictionary(uniqueKeysWithValues: data.profile.countsByYear.map { ($0.year, $0.citedByCount) })
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

    static func csvEscape(_ field: String) -> String {
        if field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
