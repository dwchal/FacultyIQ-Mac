import Foundation

/// Preprint handling: pairing a preprint with the journal version of the same
/// paper, so one piece of work isn't counted twice, and flagging preprints
/// that never reached a journal.
///
/// OpenAlex indexes the bioRxiv/medRxiv/arXiv posting and the eventual journal
/// article as separate works with separate DOIs. Both land in the author's
/// works list, which inflates works counts and puts a spurious extra point on
/// the publications-per-year chart, usually a year before the real one.
extension MetricsEngine {
    /// OpenAlex work types that represent a preprint posting rather than a
    /// published article. "posted-content" is the Crossref-derived spelling
    /// that predates OpenAlex's own "preprint" type.
    static let preprintTypes: Set<String> = ["preprint", "posted-content"]

    static func isPreprint(_ work: Work) -> Bool {
        preprintTypes.contains(work.type?.lowercased() ?? "")
    }

    /// Title key for matching a preprint to its published version: lowercased,
    /// diacritic-folded, punctuation stripped, whitespace collapsed. Titles are
    /// compared rather than DOIs because the two records carry different DOIs;
    /// journals do lightly reword titles between posting and publication, so
    /// this matches the common case and misses the reworded ones (never the
    /// reverse — a false pair would delete a real publication from the counts).
    static func titleKey(_ title: String) -> String {
        // A few OpenAlex titles carry un-decoded escape sequences ("EHR\n
        // System"), whose stray "n" would otherwise become its own token and
        // stop the record matching its clean twin.
        var normalized = title
        for escape in ["\\n", "\\t", "\\r"] {
            normalized = normalized.replacingOccurrences(of: escape, with: " ")
        }
        var tokens = normalized
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        // Some publishers (JMIR notably) title the posting "…(Preprint)" and
        // the article identically without it; drop the marker so the pair matches.
        if tokens.last == "preprint" { tokens.removeLast() }
        return tokens.joined(separator: " ")
    }

    /// One preprint and the published work it corresponds to, when there is one.
    struct PreprintPair: Identifiable {
        var preprint: Work
        var published: Work?     // nil = still only a preprint

        /// Months from the preprint's year to now, when unpublished.
        var id: String { preprint.id }
        var isPublished: Bool { published != nil }
    }

    /// Pair each preprint in `works` with a published work of the same title.
    /// Sorted newest preprint first.
    static func preprintPairs(works: [Work]) -> [PreprintPair] {
        let published = works.filter { !isPreprint($0) }
        var byTitle: [String: Work] = [:]
        for work in published {
            let key = titleKey(work.title)
            guard !key.isEmpty else { continue }
            // Prefer the earliest published version if a title somehow repeats.
            if let existing = byTitle[key], (existing.year ?? 0) <= (work.year ?? 0) { continue }
            byTitle[key] = work
        }
        return works.filter(isPreprint)
            .map { PreprintPair(preprint: $0, published: byTitle[titleKey($0.title)]) }
            .sorted { ($0.preprint.year ?? 0) > ($1.preprint.year ?? 0) }
    }

    /// The IDs of preprints that duplicate a published work in the same list —
    /// the ones metrics should drop.
    static func supersededPreprintIDs(works: [Work]) -> Set<String> {
        Set(preprintPairs(works: works).filter(\.isPublished).map(\.preprint.id))
    }

    /// Drop preprints whose journal version is already in the member's works,
    /// adjusting the headline counts the same way applyingExclusions does.
    /// Citations move with the dropped record: OpenAlex counts preprint and
    /// article citations separately, and the article's are the ones that count
    /// toward the published paper.
    static func collapsingPreprints(_ data: PersonData) -> PersonData {
        let superseded = supersededPreprintIDs(works: data.works)
        guard !superseded.isEmpty else { return data }
        var result = data
        let removed = data.works.filter { superseded.contains($0.id) }
        result.works = data.works.filter { !superseded.contains($0.id) }
        result.profile.worksCount = max(0, data.profile.worksCount - removed.count)
        result.profile.citedByCount = max(
            0, data.profile.citedByCount - removed.map(\.citedByCount).reduce(0, +))
        // Let the indexes recompute from the remaining works, as exclusions do.
        result.profile.hIndex = nil
        result.profile.i10Index = nil
        return result
    }

    // MARK: Division rollup

    struct PreprintSummary {
        var total: Int               // distinct preprints across the cohort
        var published: Int           // preprints matched to a journal version
        var unpublished: Int         // still preprint-only
        var stale: [StalePreprint]   // unpublished and older than the cutoff

        var publishedShare: Double? {
            total > 0 ? Double(published) / Double(total) : nil
        }
    }

    /// An unpublished preprint old enough to be worth chasing.
    struct StalePreprint: Identifiable {
        var memberName: String
        var work: Work
        var yearsOut: Int

        var id: String { "\(memberName)|\(work.id)" }
    }

    /// A preprint with no journal version after this many years is flagged.
    static let stalePreprintYears = 2

    /// Cohort preprint rollup. A preprint coauthored by two roster members
    /// counts once; the stale list names the first member it was found under.
    static func preprintSummary(roster: [FacultyMember],
                                personData: [UUID: PersonData]) -> PreprintSummary {
        var seen = Set<String>()
        var total = 0
        var published = 0
        var stale: [StalePreprint] = []
        for member in roster {
            guard let data = personData[member.id] else { continue }
            for pair in preprintPairs(works: data.works) {
                guard seen.insert(pair.preprint.id).inserted else { continue }
                total += 1
                if pair.isPublished {
                    published += 1
                } else if let year = pair.preprint.year,
                          currentYear - year >= stalePreprintYears {
                    stale.append(StalePreprint(memberName: member.name,
                                               work: pair.preprint,
                                               yearsOut: currentYear - year))
                }
            }
        }
        return PreprintSummary(
            total: total,
            published: published,
            unpublished: total - published,
            stale: stale.sorted { ($0.yearsOut, $1.memberName) > ($1.yearsOut, $0.memberName) })
    }
}
