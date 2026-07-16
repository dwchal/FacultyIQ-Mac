import Foundation

/// Data-quality and authorship analytics: misattribution candidates,
/// retractions, author-position breakdowns, collaboration-gap suggestions,
/// and the institution rollup for external collaborators.
extension MetricsEngine {
    // MARK: Misattribution heuristic

    /// Works in fields the member has barely ever touched (≤ max(1, 2%) of
    /// their tagged works) — the isolated-excursion pattern misattributed
    /// papers follow. Candidates for the "not my paper" review, not verdicts:
    /// legitimately interdisciplinary one-offs land here too, which is why
    /// this only flags and never excludes.
    ///
    /// When `authorID` is given, byline position tempers the flag: a work the
    /// member led (first/last/corresponding) is much more likely a genuine
    /// excursion than an incidental middle authorship, so led works are only
    /// flagged when their field is a single-work excursion.
    static func suspectWorkIDs(works: [Work], authorID: String? = nil) -> Set<String> {
        let tagged = works.compactMap { work in work.topicField.map { (work: work, field: $0) } }
        guard tagged.count >= 10 else { return [] }
        let counts = Dictionary(grouping: tagged, by: \.field).mapValues(\.count)
        let threshold = max(1, Int((0.02 * Double(tagged.count)).rounded()))
        return Set(tagged.filter { entry in
            let fieldCount = counts[entry.field]!
            guard fieldCount <= threshold else { return false }
            if let authorID, let own = ownAuthorship(entry.work, authorID: authorID),
               own.position != nil, isLead(own) {
                return fieldCount == 1
            }
            return true
        }.map(\.work.id))
    }

    /// The member's data with excluded works removed and headline counts
    /// adjusted; the OpenAlex-level indexes are dropped so they recompute
    /// from the remaining works' citation counts.
    static func applyingExclusions(_ data: PersonData, excluded: Set<String>) -> PersonData {
        guard !excluded.isEmpty else { return data }
        var result = data
        let removed = data.works.filter { excluded.contains($0.id) }
        guard !removed.isEmpty else { return data }
        result.works = data.works.filter { !excluded.contains($0.id) }
        result.profile.worksCount = max(0, data.profile.worksCount - removed.count)
        result.profile.citedByCount = max(
            0, data.profile.citedByCount - removed.map(\.citedByCount).reduce(0, +))
        result.profile.hIndex = nil
        result.profile.i10Index = nil
        return result
    }

    // MARK: Retractions

    /// Retracted works across the cohort, with the members they're attributed
    /// to (a shared retracted work lists every affected member).
    static func retractedWorks(roster: [FacultyMember],
                               personData: [UUID: PersonData]) -> [(memberName: String, work: Work)] {
        roster.flatMap { member -> [(String, Work)] in
            (personData[member.id]?.works ?? [])
                .filter { $0.isRetracted == true }
                .map { (member.name, $0) }
        }
        .sorted { ($0.1.year ?? 0, $0.0) > (($1.1.year ?? 0), $1.0) }
    }

    // MARK: Authorship positions

    struct AuthorshipSummary {
        var tracked: Int         // works carrying position data for this author
        var first: Int
        var middle: Int
        var last: Int
        var corresponding: Int
    }

    /// Where the member sits on their own works, from OpenAlex authorship
    /// positions. `tracked` < works.count means some works predate position
    /// tracking and need a refresh.
    static func authorshipSummary(data: PersonData, authorID: String) -> AuthorshipSummary {
        var summary = AuthorshipSummary(tracked: 0, first: 0, middle: 0, last: 0, corresponding: 0)
        for work in data.works {
            guard let own = work.authors?.first(where: { $0.openalexID == authorID }),
                  let position = own.position else { continue }
            summary.tracked += 1
            switch position {
            case .first: summary.first += 1
            case .middle: summary.middle += 1
            case .last: summary.last += 1
            }
            if own.isCorresponding == true { summary.corresponding += 1 }
        }
        return summary
    }

    struct AuthorshipYearCount: Identifiable {
        var year: Int
        var position: AuthorPosition
        var count: Int

        var id: String { "\(year)|\(position.rawValue)" }
    }

    /// Position counts per year over the trailing `span` years, zero-filled
    /// so stacked bars have a slot for every year. Empty when nothing in the
    /// window carries position data.
    static func authorshipByYear(data: PersonData, authorID: String,
                                 span: Int = 15) -> [AuthorshipYearCount] {
        let firstYear = currentYear - span + 1
        var counts: [Int: [AuthorPosition: Int]] = [:]
        for work in data.works {
            guard let year = work.year, year >= firstYear, year <= currentYear,
                  let own = work.authors?.first(where: { $0.openalexID == authorID }),
                  let position = own.position else { continue }
            counts[year, default: [:]][position, default: 0] += 1
        }
        guard !counts.isEmpty else { return [] }
        let years = counts.keys.min()!...currentYear
        return years.flatMap { year in
            [AuthorPosition.first, .middle, .last].map { position in
                AuthorshipYearCount(year: year, position: position,
                                    count: counts[year]?[position] ?? 0)
            }
        }
    }

    // MARK: Collaboration gap suggestions

    /// A pair of members who publish on the same topics but have never
    /// co-published — an internal collaboration worth brokering.
    struct CollaborationSuggestion: Identifiable {
        var memberA: UUID
        var nameA: String
        var memberB: UUID
        var nameB: String
        var sharedTopics: [String]   // strongest first
        var score: Int               // Σ min(worksA, worksB) over shared topics

        var id: String { "\(memberA.uuidString)|\(memberB.uuidString)" }
    }

    /// Rank never-co-published pairs by topic overlap. Score sums, per shared
    /// topic, the smaller of the two members' work counts — both need real
    /// activity on a topic for it to count.
    static func collaborationSuggestions(roster: [FacultyMember],
                                         personData: [UUID: PersonData],
                                         network: CoauthorNetwork,
                                         limit: Int = 10) -> [CollaborationSuggestion] {
        let members = roster.filter { personData[$0.id] != nil }
        let topicCounts: [UUID: [String: Int]] = Dictionary(uniqueKeysWithValues: members.map { member in
            var counts: [String: Int] = [:]
            for work in personData[member.id]!.works {
                if let topic = work.topicName { counts[topic, default: 0] += 1 }
            }
            return (member.id, counts)
        })
        let connected = Set(network.edges.map(\.id))

        var suggestions: [CollaborationSuggestion] = []
        for i in members.indices {
            for j in members.indices where j > i {
                let (a, b) = (members[i], members[j])
                let sorted = [a, b].sorted { $0.id.uuidString < $1.id.uuidString }
                guard !connected.contains("\(sorted[0].id.uuidString)|\(sorted[1].id.uuidString)")
                else { continue }
                let shared = topicCounts[a.id]!.compactMap { topic, countA -> (String, Int)? in
                    guard let countB = topicCounts[b.id]![topic] else { return nil }
                    return (topic, min(countA, countB))
                }
                let score = shared.map(\.1).reduce(0, +)
                guard score >= 2 else { continue }
                suggestions.append(CollaborationSuggestion(
                    memberA: a.id, nameA: a.name,
                    memberB: b.id, nameB: b.name,
                    sharedTopics: shared.sorted { ($0.1, $1.0) > ($1.1, $0.0) }.prefix(3).map(\.0),
                    score: score))
            }
        }
        return Array(suggestions.sorted { ($0.score, $1.id) > ($1.score, $0.id) }.prefix(limit))
    }

    // MARK: Percentile rank

    /// Percent of cohort values below `value`, counting ties at half weight.
    static func percentileRank(of value: Int, in cohort: [Int]) -> Double {
        guard !cohort.isEmpty else { return 0 }
        let below = cohort.count { $0 < value }
        let equal = cohort.count { $0 == value }
        return 100 * (Double(below) + Double(equal) / 2) / Double(cohort.count)
    }

    // MARK: Institution rollup

    struct InstitutionRollup: Identifiable {
        var name: String
        var collaborators: Int       // externals whose last known institution this is
        var sharedWorks: Int         // their shared roster works, summed
        var topNames: [String]       // heaviest collaborators there

        var id: String { name }
    }

    /// External collaborators grouped by fetched affiliation. Externals whose
    /// details haven't been fetched (or have no institution) are left out —
    /// the view reports the coverage.
    static func institutionRollup(collaborators: [ExternalCollaborator],
                                  details: [String: AuthorCandidate]) -> [InstitutionRollup] {
        var grouped: [String: [ExternalCollaborator]] = [:]
        for collaborator in collaborators {
            guard let affiliation = details[collaborator.openalexID]?.affiliation,
                  !affiliation.isEmpty else { continue }
            grouped[affiliation, default: []].append(collaborator)
        }
        return grouped
            .map { name, members in
                InstitutionRollup(
                    name: name,
                    collaborators: members.count,
                    sharedWorks: members.map(\.sharedWorks).reduce(0, +),
                    topNames: members.sorted { $0.sharedWorks > $1.sharedWorks }
                        .prefix(3).map(\.displayName))
            }
            .sorted { ($0.sharedWorks, $1.name) > ($1.sharedWorks, $0.name) }
    }

    static func institutionRollupCSV(_ rollup: [InstitutionRollup]) -> String {
        var lines = ["Institution,External Collaborators,Shared Works,Top Collaborators"]
        for row in rollup {
            lines.append([
                csvEscape(row.name),
                String(row.collaborators),
                String(row.sharedWorks),
                csvEscape(row.topNames.joined(separator: "; ")),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
