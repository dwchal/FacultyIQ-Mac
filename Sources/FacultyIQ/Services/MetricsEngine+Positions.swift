import Foundation

/// Authorship-position analytics: lead-vs-contribute roles, the independence
/// (first→senior author) trajectory, the independent h-index, and
/// within-roster mentorship pairs. OpenAlex only knows byline order — co-first
/// and co-senior designations are invisible to it — so everything here is
/// approximate and should be presented that way.
extension MetricsEngine {
    // MARK: Role helpers

    /// The member's own authorship entry on a work.
    static func ownAuthorship(_ work: Work, authorID: String) -> WorkAuthor? {
        work.authors?.first { $0.openalexID == authorID }
    }

    /// First, last, or corresponding authorship — the roles that mark a work
    /// as part of the member's own research program rather than a
    /// contribution to someone else's.
    static func isLead(_ authorship: WorkAuthor) -> Bool {
        authorship.position == .first || authorship.position == .last
            || authorship.isCorresponding == true
    }

    // MARK: Independent h-index

    /// h-index over led works only (first/last/corresponding author) — the
    /// member's own program, stripped of middle authorships. Nil when no work
    /// carries position data for this author.
    static func independentHIndex(data: PersonData, authorID: String) -> Int? {
        var tracked = false
        var citations: [Int] = []
        for work in data.works {
            guard let own = ownAuthorship(work, authorID: authorID),
                  own.position != nil else { continue }
            tracked = true
            if isLead(own) { citations.append(work.citedByCount) }
        }
        return tracked ? hIndex(citations: citations) : nil
    }

    // MARK: Independence trajectory

    /// Senior-author (last position) share per year: percent of the member's
    /// positioned works each year where they are last author, over the
    /// trailing `span` years. Years with no positioned works are skipped.
    static func seniorShareByYear(data: PersonData, authorID: String,
                                  span: Int = 15) -> [(year: Int, share: Double, positioned: Int)] {
        let firstYear = currentYear - span + 1
        var positioned: [Int: Int] = [:]
        var senior: [Int: Int] = [:]
        for work in data.works {
            guard let year = work.year, year >= firstYear, year <= currentYear,
                  let position = ownAuthorship(work, authorID: authorID)?.position
            else { continue }
            positioned[year, default: 0] += 1
            if position == .last { senior[year, default: 0] += 1 }
        }
        return positioned.keys.sorted().map { year in
            (year: year,
             share: 100 * Double(senior[year] ?? 0) / Double(positioned[year]!),
             positioned: positioned[year]!)
        }
    }

    /// The first→senior crossover: the first year whose trailing 3-year
    /// window has at least two last-author works and at least as many
    /// last-author as first-author works. Nil when the member has never
    /// crossed — or has slipped back, i.e. the window at their most recent
    /// positioned year is first-author-dominant again. A merely quiet final
    /// window (career tapering off) doesn't invalidate the crossover, and
    /// anchoring at the last active year (not the calendar year) keeps it
    /// visible for emeritus members who stopped publishing.
    static func seniorTransitionYear(data: PersonData, authorID: String) -> Int? {
        var first: [Int: Int] = [:]
        var last: [Int: Int] = [:]
        for work in data.works {
            guard let year = work.year, year <= currentYear,
                  let position = ownAuthorship(work, authorID: authorID)?.position
            else { continue }
            if position == .first { first[year, default: 0] += 1 }
            if position == .last { last[year, default: 0] += 1 }
        }
        let years = Set(first.keys).union(last.keys)
        guard let earliest = years.min(), let anchor = years.max() else { return nil }
        func window(_ map: [Int: Int], _ year: Int) -> Int {
            ((year - 2)...year).reduce(0) { $0 + (map[$1] ?? 0) }
        }
        func crossed(_ year: Int) -> Bool {
            let seniors = window(last, year)
            return seniors >= 2 && seniors >= window(first, year)
        }
        guard window(first, anchor) <= window(last, anchor) else { return nil }
        return (earliest...anchor).first(where: crossed)
    }

    // MARK: Mentorship pairs

    /// Directed mentor→mentee signals within the roster: the mentor is last
    /// author on works where the mentee is first author. Weight is the number
    /// of distinct such works. Sorted heaviest first.
    static func mentorshipEdges(roster: [FacultyMember],
                                resolutions: [UUID: Resolution],
                                personData: [UUID: PersonData]) -> [MentorshipEdge] {
        let eligible = roster.filter { resolutions[$0.id] != nil && personData[$0.id] != nil }
        let authorToMember = Dictionary(
            eligible.map { (resolutions[$0.id]!.openalexID, $0.id) },
            uniquingKeysWith: { first, _ in first })

        // A shared work appears in every coauthor's works list, and copies
        // fetched before position tracking carry no positions — keep the
        // copy with the most position data so a stale copy can't mask a pair.
        var bylines: [String: [WorkAuthor]] = [:]
        for member in eligible {
            for work in personData[member.id]!.works {
                guard let authors = work.authors else { continue }
                let positioned = authors.count { $0.position != nil }
                if positioned > bylines[work.id]?.count(where: { $0.position != nil }) ?? -1 {
                    bylines[work.id] = authors
                }
            }
        }

        var counts: [String: (mentor: UUID, mentee: UUID, count: Int)] = [:]
        for authors in bylines.values {
            let firsts = authors.filter { $0.position == .first }
                .compactMap { authorToMember[$0.openalexID] }
            let lasts = authors.filter { $0.position == .last }
                .compactMap { authorToMember[$0.openalexID] }
            for mentor in lasts {
                for mentee in firsts where mentee != mentor {
                    let key = "\(mentor.uuidString)>\(mentee.uuidString)"
                    counts[key] = (mentor, mentee, (counts[key]?.count ?? 0) + 1)
                }
            }
        }
        return counts.values
            .map { MentorshipEdge(mentor: $0.mentor, mentee: $0.mentee, weight: $0.count) }
            .sorted { ($0.weight, $1.id) > ($1.weight, $0.id) }
    }

    static func mentorshipCSV(edges: [MentorshipEdge], roster: [FacultyMember]) -> String {
        let nameByID = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, $0.name) })
        var lines = ["Senior Author (mentor),First Author (mentee),Shared Works"]
        for edge in edges {
            lines.append([
                csvEscape(nameByID[edge.mentor] ?? ""),
                csvEscape(nameByID[edge.mentee] ?? ""),
                String(edge.weight),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
