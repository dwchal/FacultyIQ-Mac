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

    // MARK: Rank benchmarks & promotion insight

    static func rankBenchmarks(metrics: [PersonMetrics]) -> [RankBenchmark] {
        Dictionary(grouping: metrics.filter { $0.rank != nil }, by: { $0.rank! })
            .map { rank, group in
                RankBenchmark(
                    rank: rank,
                    count: group.count,
                    medianWorks: group.map { Double($0.worksCount) }.median,
                    medianCitations: group.map { Double($0.citations) }.median,
                    medianHIndex: group.map { Double($0.hIndex) }.median,
                    medianWorksPerYear: group.map(\.worksPerYear).median
                )
            }
            .sorted { $0.rank < $1.rank }
    }

    /// Faculty whose metrics meet or exceed the next rank's medians on at
    /// least two of three key metrics (works, citations, h-index) — the
    /// simplified counterpart of identify_promotion_candidates().
    static func promotionCandidates(metrics: [PersonMetrics],
                                    benchmarks: [RankBenchmark]) -> [PromotionCandidate] {
        let byRank = Dictionary(uniqueKeysWithValues: benchmarks.map { ($0.rank, $0) })
        return metrics.compactMap { m in
            guard let rank = m.rank, let next = rank.next,
                  let bench = byRank[next] else { return nil }
            var exceeded: [String] = []
            if Double(m.worksCount) >= bench.medianWorks { exceeded.append("Works") }
            if Double(m.citations) >= bench.medianCitations { exceeded.append("Citations") }
            if Double(m.hIndex) >= bench.medianHIndex { exceeded.append("h-index") }
            guard exceeded.count >= 2 else { return nil }
            return PromotionCandidate(
                metrics: m, currentRank: rank, targetRank: next, exceededMetrics: exceeded)
        }
        .sorted { $0.exceededMetrics.count > $1.exceededMetrics.count }
    }

    // MARK: Export

    static func metricsCSV(metrics: [PersonMetrics], roster: [FacultyMember]) -> String {
        let byID = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, $0) })
        var lines = ["Name,Rank,Works,Citations,h-index,i10-index,Citations/Work,Works/Year,OA %,Recent Works (5y),First Pub Year,Career Years,ORCID,Scopus ID"]
        for m in metrics.sorted(by: { $0.name < $1.name }) {
            let member = byID[m.memberID]
            let fields = [
                m.name,
                m.rawRank ?? "",
                String(m.worksCount),
                String(m.citations),
                String(m.hIndex),
                String(m.i10Index),
                String(format: "%.1f", m.citationsPerWork),
                String(format: "%.2f", m.worksPerYear),
                m.oaPercent.map { String(format: "%.0f", $0) } ?? "",
                String(m.recentWorks5y),
                m.firstPubYear.map(String.init) ?? "",
                String(m.careerYears),
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

    static func csvEscape(_ field: String) -> String {
        if field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
