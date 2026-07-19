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

    // MARK: Work-level funders (any agency)

    /// Funders credited across the cohort's publications, most-credited first.
    /// This sees every agency and foundation — not just NIH and NSF — because
    /// the credit is recorded on the paper rather than matched by PI name.
    /// A coauthored work counts once.
    static func funderCredits(roster: [FacultyMember],
                              personData: [UUID: PersonData]) -> [FunderCredit] {
        var name: [String: String] = [:]
        var workIDs: [String: Set<String>] = [:]
        var awardIDs: [String: Set<String>] = [:]
        var peopleCount: [String: Int] = [:]
        for member in roster {
            guard let data = personData[member.id] else { continue }
            var personFunders = Set<String>()
            for work in data.works {
                for grant in work.grants ?? [] {
                    name[grant.funderID] = grant.funderName
                    workIDs[grant.funderID, default: []].insert(work.id)
                    if let awardID = grant.awardID {
                        awardIDs[grant.funderID, default: []].insert(awardID)
                    }
                    personFunders.insert(grant.funderID)
                }
            }
            for funder in personFunders {
                peopleCount[funder, default: 0] += 1
            }
        }
        return workIDs
            .map { funderID, works in
                FunderCredit(
                    funderID: funderID,
                    name: name[funderID] ?? funderID,
                    works: works.count,
                    people: peopleCount[funderID] ?? 0,
                    awardCount: awardIDs[funderID]?.count ?? 0)
            }
            .sorted { ($0.works, $0.people, $1.name) > ($1.works, $1.people, $0.name) }
    }

    /// True when nobody's works carry funder data yet — the cohort predates
    /// funder tracking and needs a refetch, which the view says out loud
    /// rather than showing an empty chart.
    static func funderDataMissing(roster: [FacultyMember],
                                  personData: [UUID: PersonData]) -> Bool {
        let fetched = roster.compactMap { personData[$0.id] }.filter { !$0.works.isEmpty }
        guard !fetched.isEmpty else { return false }
        return fetched.allSatisfy { data in data.works.allSatisfy { $0.grants == nil } }
    }

    // MARK: NSF awards

    /// Cohort NSF rollup: awards shared by two roster members count once.
    struct NSFSummary {
        var totalAwarded: Int
        var awardCount: Int
        var activeCount: Int
        var fundedMembers: Int
        var asPI: Int
    }

    static func nsfSummary(roster: [FacultyMember],
                           enrichment: [UUID: Enrichment],
                           asOf now: Date = Date()) -> NSFSummary? {
        var distinct: [String: NSFAward] = [:]
        var funded = 0
        for member in roster {
            let awards = enrichment[member.id]?.nsf?.awards ?? []
            guard !awards.isEmpty else { continue }
            funded += 1
            for award in awards where distinct[award.awardID] == nil {
                distinct[award.awardID] = award
            }
        }
        guard !distinct.isEmpty else { return nil }
        let awards = Array(distinct.values)
        return NSFSummary(
            totalAwarded: awards.map(\.totalAward).reduce(0, +),
            awardCount: awards.count,
            activeCount: awards.count { ($0.endDate ?? .distantPast) >= now },
            fundedMembers: funded,
            asPI: awards.count(where: \.isPI))
    }

    // MARK: Funding cliffs

    /// A member whose funding is running out: their last grant ends within the
    /// lookahead window and nothing else on their record runs past it.
    ///
    /// "Successor" is deliberately loose — any other attached grant that runs
    /// beyond the ending one counts, whether it's a renewal of the same core
    /// project or unrelated support, since either keeps the salary line whole.
    struct FundingCliff: Identifiable {
        var memberID: UUID
        var memberName: String
        var projectNumber: String    // NIH core project number or NSF award ID
        var title: String
        var source: String           // "NIH" or "NSF"
        var endDate: Date
        var approximate: Bool        // the end date came from fiscal years
        var remainingGrants: Int     // other awards still running at endDate
        var totalAtRisk: Int         // award dollars on the ending project

        var id: UUID { memberID }

        /// Whole months from `now` until the grant ends (0 when it ends today).
        func monthsOut(from now: Date = Date()) -> Int {
            max(0, Calendar(identifier: .gregorian)
                .dateComponents([.month], from: now, to: endDate).month ?? 0)
        }
    }

    /// How far ahead a funding cliff is called.
    static let fundingCliffMonths = 12

    /// Members whose last running grant ends within `months` and who have no
    /// other grant covering the gap. Soonest cliff first.
    ///
    /// Only members with attached grants are considered — an unfunded member
    /// has no cliff to fall off, and flagging them would bury the real signal.
    static func fundingCliffs(roster: [FacultyMember],
                              enrichment: [UUID: Enrichment],
                              asOf now: Date = Date(),
                              months: Int = fundingCliffMonths) -> [FundingCliff] {
        let calendar = Calendar(identifier: .gregorian)
        guard let horizon = calendar.date(byAdding: .month, value: months, to: now) else { return [] }

        /// Every award a member holds, from both funders, reduced to the
        /// fields the cliff calculation needs.
        struct Award {
            var number: String
            var title: String
            var source: String
            var end: Date
            var approximate: Bool
            var amount: Int
        }

        return roster.compactMap { member -> FundingCliff? in
            var awards: [Award] = []
            for grant in enrichment[member.id]?.grants?.grants ?? [] {
                // RePORTER sometimes omits project dates; fall back to the
                // end of the last fiscal year it reported, and say so.
                var approximate = false
                var end = parseGrantDate(grant.endDate)
                if end == nil, let lastFY = grant.fiscalYears.last {
                    approximate = true
                    end = calendar.date(from: DateComponents(year: lastFY, month: 12, day: 31))
                }
                guard let end else { continue }
                awards.append(Award(number: grant.coreProjectNum, title: grant.title,
                                    source: "NIH", end: end, approximate: approximate,
                                    amount: grant.totalAward))
            }
            for award in enrichment[member.id]?.nsf?.awards ?? [] {
                guard let end = award.endDate else { continue }
                awards.append(Award(number: award.awardID, title: award.title,
                                    source: "NSF", end: end, approximate: false,
                                    amount: award.totalAward))
            }
            guard !awards.isEmpty else { return nil }

            // The furthest-out award is what defines the cliff: if it reaches
            // past the horizon the member is covered, whatever else ends.
            guard let last = awards.max(by: { $0.end < $1.end }),
                  last.end > now, last.end <= horizon else { return nil }

            return FundingCliff(
                memberID: member.id,
                memberName: member.name,
                projectNumber: last.number,
                title: last.title,
                source: last.source,
                endDate: last.end,
                approximate: last.approximate,
                remainingGrants: awards.count { $0.end > last.end },
                totalAtRisk: last.amount)
        }
        .sorted { ($0.endDate, $0.memberName) < ($1.endDate, $1.memberName) }
    }

    static func fundingCliffsCSV(_ cliffs: [FundingCliff]) -> String {
        var lines = ["Name,Source,Project,Title,Ends,Months Out,Approximate End,Awards Running Past,Amount At Risk"]
        for cliff in cliffs {
            lines.append([
                cliff.memberName,
                cliff.source,
                cliff.projectNumber,
                cliff.title,
                cliff.endDate.formatted(.iso8601.year().month().day()),
                String(cliff.monthsOut()),
                cliff.approximate ? "yes" : "no",
                String(cliff.remainingGrants),
                String(cliff.totalAtRisk),
            ].map(csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func fundersCSV(_ funders: [FunderCredit]) -> String {
        var lines = ["Funder,OpenAlex Funder ID,Works,Faculty,Named Awards"]
        for funder in funders {
            lines.append([
                funder.name,
                funder.funderID,
                String(funder.works),
                String(funder.people),
                String(funder.awardCount),
            ].map(csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func nsfAwardsCSV(roster: [FacultyMember],
                             enrichment: [UUID: Enrichment]) -> String {
        var lines = ["Name,Award ID,Title,Role,Program,Organization,Start,End,Total Award"]
        let isoDay = { (date: Date?) in
            date.map { $0.formatted(.iso8601.year().month().day()) } ?? ""
        }
        for member in roster.sorted(by: { $0.name < $1.name }) {
            for award in enrichment[member.id]?.nsf?.awards ?? [] {
                lines.append([
                    member.name,
                    award.awardID,
                    award.title,
                    award.isPI ? "PI" : "co-PI",
                    award.program ?? "",
                    award.organization ?? "",
                    isoDay(award.startDate),
                    isoDay(award.endDate),
                    String(award.totalAward),
                ].map(csvEscape).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
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

    // MARK: Scopus journal quality

    struct JournalQuality {
        var ratedWorks: Int          // works whose venue has CiteScore data
        var q1Works: Int
        var medianCiteScore: Double? // across rated publications (not distinct journals)

        var q1Share: Double? {
            ratedWorks > 0 ? Double(q1Works) / Double(ratedWorks) : nil
        }
    }

    /// Journal-quality rollup for a set of works against Scopus serial
    /// metrics. Median CiteScore is per publication, so journals someone
    /// publishes in repeatedly weigh accordingly.
    static func journalQuality(works: [Work],
                               journals: [String: ScopusJournalMetrics]) -> JournalQuality {
        var rated = 0
        var q1 = 0
        var scores: [Double] = []
        for work in works {
            guard let issn = work.venueISSN, let metrics = journals[issn] else { continue }
            if let quartile = metrics.quartile {
                rated += 1
                if quartile == 1 { q1 += 1 }
            }
            if let score = metrics.citeScore { scores.append(score) }
        }
        return JournalQuality(
            ratedWorks: rated,
            q1Works: q1,
            medianCiteScore: scores.isEmpty ? nil : scores.median)
    }

    /// Every member's Scopus journal metrics merged into one ISSN lookup
    /// (identical journals repeat across members, so collisions are benign).
    static func mergedJournals(enrichment: [UUID: Enrichment]) -> [String: ScopusJournalMetrics] {
        var merged: [String: ScopusJournalMetrics] = [:]
        for entry in enrichment.values {
            merged.merge(entry.scopus?.journalByISSN ?? [:]) { first, _ in first }
        }
        return merged
    }

    // MARK: Clinical trials

    struct TrialsSummary {
        var total: Int
        var active: Int
        var asPI: Int
    }

    static let activeTrialStatuses: Set<String> = [
        "RECRUITING", "ACTIVE_NOT_RECRUITING", "ENROLLING_BY_INVITATION", "NOT_YET_RECRUITING",
    ]

    /// One-line division Scopus rollup for the summary report — median Scopus
    /// h-index across enriched members plus the cohort Q1 share.
    static func divisionScopusLine(roster: [FacultyMember],
                                   personData: [UUID: PersonData],
                                   enrichment: [UUID: Enrichment]) -> String? {
        let hIndexes = roster.compactMap { enrichment[$0.id]?.scopus?.author?.hIndex }
            .map(Double.init)
        let journals = mergedJournals(enrichment: enrichment)
        var parts: [String] = []
        if !hIndexes.isEmpty {
            parts.append("median h-index \(Int(hIndexes.median.rounded())) (\(hIndexes.count) enriched members)")
        }
        if !journals.isEmpty {
            let distribution = quartileDistribution(
                personData: roster.compactMap { personData[$0.id] }, journals: journals)
            let rated = distribution.values.reduce(0, +)
            if rated > 0 {
                let share = Double(distribution[1] ?? 0) / Double(rated)
                parts.append("\(share.formatted(.percent.precision(.fractionLength(0)))) of \(rated) rated publications in Q1 journals")
            }
        }
        return parts.isEmpty ? nil : "Scopus: " + parts.joined(separator: " · ")
    }

    static func trialsSummary(_ trials: [ClinicalTrial]) -> TrialsSummary {
        TrialsSummary(
            total: trials.count,
            active: trials.count { activeTrialStatuses.contains($0.status ?? "") },
            asPI: trials.count { $0.role == "PRINCIPAL_INVESTIGATOR" })
    }
}
