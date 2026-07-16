import Foundation

/// Metrics over the enrichment sources (iCite RCR, NIH funding).
extension MetricsEngine {
    // MARK: iCite

    /// Mean Relative Citation Ratio across the works iCite scored; nil when
    /// no works carry RCR data.
    static func meanRCR(works: [Work], icite: ICiteData?) -> Double? {
        guard let icite else { return nil }
        let values = works.compactMap { work in
            work.pmid.flatMap { icite.byPMID[$0]?.rcr }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Median of the per-person mean RCRs in view; nil when no one has data.
    static func medianRCR(roster: [FacultyMember],
                          personData: [UUID: PersonData],
                          enrichment: [UUID: Enrichment]) -> Double? {
        let means = roster.compactMap { member in
            personData[member.id].flatMap {
                meanRCR(works: $0.works, icite: enrichment[member.id]?.icite)
            }
        }
        return means.isEmpty ? nil : means.median
    }

    /// Mean Approximate Potential to Translate (0…1) across the works iCite
    /// scored; nil when no works carry APT data.
    static func meanAPT(works: [Work], icite: ICiteData?) -> Double? {
        guard let icite else { return nil }
        let values = works.compactMap { work in
            work.pmid.flatMap { icite.byPMID[$0]?.apt }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Median of the per-person mean APTs in view; nil when no one has data.
    static func medianAPT(roster: [FacultyMember],
                          personData: [UUID: PersonData],
                          enrichment: [UUID: Enrichment]) -> Double? {
        let means = roster.compactMap { member in
            personData[member.id].flatMap {
                meanAPT(works: $0.works, icite: enrichment[member.id]?.icite)
            }
        }
        return means.isEmpty ? nil : means.median
    }

    /// iCite's "likely to translate" bucket: works with APT at or above this
    /// are more likely than not to be cited by a clinical article.
    static let highAPTThreshold = 0.75

    struct TranslationalEntry: Identifiable {
        var memberID: UUID
        var name: String
        var meanAPT: Double
        var highAPTWorks: Int    // works with apt >= highAPTThreshold
        var scoredWorks: Int     // works iCite returned an APT for

        var id: UUID { memberID }
    }

    /// Members ranked by mean APT; empty when no one has iCite data, so
    /// views gate on isEmpty.
    static func topTranslational(roster: [FacultyMember],
                                 personData: [UUID: PersonData],
                                 enrichment: [UUID: Enrichment]) -> [TranslationalEntry] {
        roster.compactMap { member -> TranslationalEntry? in
            guard let data = personData[member.id],
                  let icite = enrichment[member.id]?.icite else { return nil }
            let values = data.works.compactMap { work in
                work.pmid.flatMap { icite.byPMID[$0]?.apt }
            }
            guard !values.isEmpty else { return nil }
            return TranslationalEntry(
                memberID: member.id,
                name: member.name,
                meanAPT: values.reduce(0, +) / Double(values.count),
                highAPTWorks: values.count { $0 >= highAPTThreshold },
                scoredWorks: values.count)
        }
        .sorted { ($0.meanAPT, $1.name) > ($1.meanAPT, $0.name) }
    }

    // MARK: NIH funding

    /// NIH "R01-equivalent" research activity codes.
    static let r01EquivalentCodes: Set<String> = [
        "R01", "R23", "R29", "R37", "R56", "RF1", "RL1", "U01", "DP1", "DP2", "DP5",
    ]

    struct FundingSummary {
        var totalAwarded: Int
        var grantCount: Int
        var activeCount: Int
        var r01EquivalentCount: Int
    }

    static func fundingSummary(_ grants: [Grant]) -> FundingSummary {
        let active = grants.count { grant in
            if let endYear = grant.endDate?.extractedYear {
                endYear >= currentYear
            } else {
                (grant.fiscalYears.last ?? 0) >= currentYear - 1
            }
        }
        return FundingSummary(
            totalAwarded: grants.map(\.totalAward).reduce(0, +),
            grantCount: grants.count,
            activeCount: active,
            r01EquivalentCount: grants.count {
                $0.activityCode.map(r01EquivalentCodes.contains) ?? false
            })
    }

    /// Cohort-level NIH funding rollup. Grants shared by two roster members
    /// (multi-PI projects) are deduplicated by core project number for the
    /// totals and charts; per-member sums keep each PI's full attachment.
    struct DivisionFunding {
        var totalAwarded: Int
        var fundedMembers: Int       // members with ≥1 attached grant
        var projectCount: Int        // distinct core projects
        var activeCount: Int
        var r01EquivalentCount: Int
        var byFiscalYear: [(year: Int, amount: Int)]      // ascending
        var missingFYBreakdown: Bool // some grants predate the per-FY breakdown
        var byActivity: [(code: String, amount: Int, count: Int)]  // amount desc
        var topFunded: [(name: String, amount: Int)]      // per member, desc
    }

    static func divisionFunding(roster: [FacultyMember],
                                enrichment: [UUID: Enrichment]) -> DivisionFunding? {
        var distinct: [String: Grant] = [:]
        var funded = 0
        var topFunded: [(name: String, amount: Int)] = []
        for member in roster {
            let grants = enrichment[member.id]?.grants?.grants ?? []
            guard !grants.isEmpty else { continue }
            funded += 1
            topFunded.append((name: member.name, amount: grants.map(\.totalAward).reduce(0, +)))
            for grant in grants where distinct[grant.coreProjectNum] == nil {
                distinct[grant.coreProjectNum] = grant
            }
        }
        guard !distinct.isEmpty else { return nil }
        let grants = Array(distinct.values)

        var byFY: [Int: Int] = [:]
        for grant in grants {
            for (fy, amount) in grant.awardsByFiscalYear ?? [:] {
                byFY[fy, default: 0] += amount
            }
        }
        var byActivity: [String: (amount: Int, count: Int)] = [:]
        for grant in grants {
            let code = grant.activityCode ?? "—"
            let entry = byActivity[code] ?? (0, 0)
            byActivity[code] = (entry.amount + grant.totalAward, entry.count + 1)
        }
        let summary = fundingSummary(grants)
        return DivisionFunding(
            totalAwarded: summary.totalAwarded,
            fundedMembers: funded,
            projectCount: grants.count,
            activeCount: summary.activeCount,
            r01EquivalentCount: summary.r01EquivalentCount,
            byFiscalYear: byFY.sorted { $0.key < $1.key }.map { (year: $0.key, amount: $0.value) },
            missingFYBreakdown: grants.contains { $0.awardsByFiscalYear == nil && $0.totalAward > 0 },
            byActivity: byActivity
                .map { (code: $0.key, amount: $0.value.amount, count: $0.value.count) }
                .sorted { ($0.amount, $1.code) > ($1.amount, $0.code) },
            topFunded: topFunded.sorted { ($0.amount, $1.name) > ($1.amount, $0.name) }
        )
    }

    // MARK: Grant timeline

    /// RePORTER project dates arrive as "2016-05-01T00:00:00" (no timezone
    /// designator, so ISO8601DateFormatter rejects them) or occasionally as
    /// bare "2016-05-01"; parse the date part alone.
    private static let grantDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter
    }()

    static func parseGrantDate(_ raw: String?) -> Date? {
        guard let raw, raw.count >= 10 else { return nil }
        return grantDateFormatter.date(from: String(raw.prefix(10)))
    }

    /// One grant period on one member's timeline row. Multi-PI grants are
    /// deliberately not deduplicated — each PI legitimately shows the shared
    /// award on their own row (unlike the deduplicated division totals).
    struct GrantBar: Identifiable {
        var memberName: String
        var grant: Grant
        var start: Date
        var end: Date
        var approximate: Bool    // a bound was derived from fiscal years alone
        var isActive: Bool       // start <= asOf <= end
        var expiresSoon: Bool    // isActive && end within 12 months of asOf

        var id: String { "\(memberName)|\(grant.coreProjectNum)" }
    }

    /// Timeline bars for every attached grant with a resolvable period,
    /// sorted by member name then start date. When project dates are missing,
    /// the period is approximated from the fiscal-year span (Jan 1 of the
    /// first FY through Dec 31 of the last) and flagged. By default only
    /// grants still running at `asOf` are returned; `includeCompleted` adds
    /// grants that ended within the trailing five years.
    static func grantTimeline(roster: [FacultyMember],
                              enrichment: [UUID: Enrichment],
                              asOf now: Date = Date(),
                              includeCompleted: Bool = false) -> [GrantBar] {
        let calendar = Calendar(identifier: .gregorian)
        let soonCutoff = calendar.date(byAdding: .month, value: 12, to: now) ?? now
        let completedFloor = calendar.date(byAdding: .year, value: -5, to: now) ?? now

        var bars: [GrantBar] = []
        for member in roster {
            for grant in enrichment[member.id]?.grants?.grants ?? [] {
                var start = parseGrantDate(grant.startDate)
                var end = parseGrantDate(grant.endDate)
                var approximate = false
                if start == nil || end == nil {
                    guard let firstFY = grant.fiscalYears.first,
                          let lastFY = grant.fiscalYears.last else { continue }
                    approximate = true
                    start = start ?? calendar.date(from: DateComponents(year: firstFY, month: 1, day: 1))
                    end = end ?? calendar.date(from: DateComponents(year: lastFY, month: 12, day: 31))
                }
                guard let start, let end, start <= end else { continue }
                guard includeCompleted ? end >= completedFloor : end >= now else { continue }
                let isActive = start <= now && now <= end
                bars.append(GrantBar(
                    memberName: member.name,
                    grant: grant,
                    start: start,
                    end: end,
                    approximate: approximate,
                    isActive: isActive,
                    expiresSoon: isActive && end <= soonCutoff))
            }
        }
        return bars.sorted { ($0.memberName, $0.start) < ($1.memberName, $1.start) }
    }

    static func grantsCSV(roster: [FacultyMember],
                          enrichment: [UUID: Enrichment]) -> String {
        var lines = ["Name,Core Project,Activity,Title,Organization,First FY,Latest FY,Total Award"]
        for member in roster.sorted(by: { $0.name < $1.name }) {
            for grant in enrichment[member.id]?.grants?.grants ?? [] {
                lines.append([
                    member.name,
                    grant.coreProjectNum,
                    grant.activityCode ?? "",
                    grant.title,
                    grant.orgName ?? "",
                    grant.fiscalYears.first.map(String.init) ?? "",
                    grant.fiscalYears.last.map(String.init) ?? "",
                    String(grant.totalAward),
                ].map(csvEscape).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
