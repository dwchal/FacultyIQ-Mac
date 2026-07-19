import Foundation

/// Publication-form aggregations over each work's OpenAlex metadata: work
/// types (article, review, …), venues, and open-access status detail.
extension MetricsEngine {
    // MARK: Types

    struct TypeCount: Identifiable {
        var name: String         // normalized work type, e.g. "article"
        var works: Int           // distinct works across the cohort
        var people: Int          // members with at least one work of the type

        var id: String { name }
    }

    /// Missing work types, shown as their own bucket rather than dropped.
    static let untypedLabel = "untyped"

    private static func normalizedType(_ raw: String?) -> String {
        let type = raw?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
        return type.isEmpty ? untypedLabel : type
    }

    /// Distinct works per work type across the cohort (a coauthored work
    /// counts once), with how many members publish each type.
    static func typeCounts(personData: [PersonData]) -> [TypeCount] {
        var worksByType: [String: Set<String>] = [:]
        var peopleByType: [String: Int] = [:]
        for data in personData {
            var personTypes = Set<String>()
            for work in data.works {
                let type = normalizedType(work.type)
                worksByType[type, default: []].insert(work.id)
                personTypes.insert(type)
            }
            for type in personTypes {
                peopleByType[type, default: 0] += 1
            }
        }
        return worksByType
            .map { type, ids in
                TypeCount(name: type, works: ids.count, people: peopleByType[type] ?? 0)
            }
            .sorted { ($0.works, $1.name) > ($1.works, $0.name) }
    }

    struct TypeYearCount: Identifiable {
        var type: String
        var year: Int
        var count: Int

        var id: String { "\(type)|\(year)" }
    }

    /// Distinct works per year for the given types over the trailing `span`
    /// years, zero-filled so trend lines have a point for every year.
    static func typeTrend(personData: [PersonData], types: [String],
                          span: Int = 10) -> [TypeYearCount] {
        let wanted = Set(types)
        let firstYear = currentYear - span + 1
        var perType: [String: [Int: Set<String>]] = [:]
        for data in personData {
            for work in data.works {
                let type = normalizedType(work.type)
                guard wanted.contains(type),
                      let year = work.year, year >= firstYear, year <= currentYear
                else { continue }
                perType[type, default: [:]][year, default: []].insert(work.id)
            }
        }
        return types.flatMap { type in
            (firstYear...currentYear).map { year in
                TypeYearCount(type: type, year: year,
                              count: perType[type]?[year]?.count ?? 0)
            }
        }
    }

    /// A person's most frequent work types.
    static func personTypeCounts(data: PersonData, limit: Int = 4) -> [(name: String, works: Int)] {
        var counts: [String: Int] = [:]
        for work in data.works {
            counts[normalizedType(work.type), default: 0] += 1
        }
        return counts
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(limit)
            .map { (name: $0.key, works: $0.value) }
    }

    // MARK: Venues

    struct VenueCount: Identifiable {
        var name: String
        var works: Int           // distinct works across the cohort
        var citations: Int       // summed once per distinct work
        var people: Int          // members with at least one work in the venue
        var issn: String? = nil  // most common linking ISSN among the venue's works
        var scopus: ScopusJournalMetrics? = nil
        var rating: JournalRating? = nil   // unified Scopus-or-OpenAlex quality

        var id: String { name }

        // Non-optional sort keys so the Table columns stay sortable.
        var citeScoreSort: Double { rating?.impact ?? scopus?.citeScore ?? -1 }
        var sjrSort: Double { rating?.sjr ?? scopus?.sjr ?? -1 }
        var quartileSort: Int { rating?.quartile ?? scopus?.quartile ?? 9 }
    }

    /// Distinct works and citations per venue across the cohort, with journal
    /// metrics joined by ISSN when available. Works without a venue are
    /// skipped.
    static func venueCounts(personData: [PersonData],
                            journals: [String: ScopusJournalMetrics] = [:],
                            ratings: [String: JournalRating] = [:]) -> [VenueCount] {
        var seenByVenue: [String: Set<String>] = [:]
        var citationsByVenue: [String: Int] = [:]
        var peopleByVenue: [String: Int] = [:]
        var issnVotes: [String: [String: Int]] = [:]
        for data in personData {
            var personVenues = Set<String>()
            for work in data.works {
                guard let venue = work.venue, !venue.isEmpty else { continue }
                personVenues.insert(venue)
                if seenByVenue[venue, default: []].insert(work.id).inserted {
                    citationsByVenue[venue, default: 0] += work.citedByCount
                }
                if let issn = work.venueISSN {
                    issnVotes[venue, default: [:]][issn, default: 0] += 1
                }
            }
            for venue in personVenues {
                peopleByVenue[venue, default: 0] += 1
            }
        }
        return seenByVenue
            .map { venue, ids in
                let issn = issnVotes[venue]?.max { $0.value < $1.value }?.key
                return VenueCount(name: venue, works: ids.count,
                                  citations: citationsByVenue[venue] ?? 0,
                                  people: peopleByVenue[venue] ?? 0,
                                  issn: issn,
                                  scopus: issn.flatMap { journals[$0] },
                                  rating: issn.flatMap { ratings[$0] })
            }
            .sorted { ($0.works, $0.citations, $1.name) > ($1.works, $1.citations, $0.name) }
    }

    // MARK: Unified journal ratings

    /// Where a venue's quality numbers came from. Scopus CiteScore quartiles
    /// are absolute (against every journal in the subject area); OpenAlex
    /// quartiles are relative to the venues this cohort actually publishes in,
    /// because OpenAlex publishes no quartile of its own.
    enum JournalRatingSource: String {
        case scopus = "Scopus"
        case openalex = "OpenAlex"

        var quartileCaption: String {
            switch self {
            case .scopus: "CiteScore quartile within the journal's subject area"
            case .openalex: "quartile among the venues this cohort publishes in"
            }
        }
    }

    /// One venue's quality numbers, from whichever source has them.
    struct JournalRating: Hashable {
        var issn: String
        var title: String?
        var source: JournalRatingSource
        /// CiteScore (Scopus) or 2-year mean citedness (OpenAlex) — both are
        /// "mean citations per recent paper", so they share a column.
        var impact: Double?
        var quartile: Int?
        var sjr: Double?         // Scopus only
        var hIndex: Int?         // OpenAlex only
    }

    /// Merge Scopus and OpenAlex journal metrics into one ISSN lookup. Scopus
    /// wins per journal wherever it has a CiteScore, since its quartiles are
    /// absolute; OpenAlex fills every remaining venue so the column is never
    /// empty for users without an Elsevier key.
    static func journalRatings(scopus: [String: ScopusJournalMetrics],
                               openalex: [String: OpenAlexJournalMetrics]) -> [String: JournalRating] {
        var ratings: [String: JournalRating] = [:]

        // OpenAlex quartiles are cohort-relative: rank the venues we have
        // citedness for, then split at the 75th/50th/25th percentiles.
        let citedness = openalex.values.compactMap(\.twoYearMeanCitedness).sorted()
        func openalexQuartile(_ value: Double?) -> Int? {
            guard let value, citedness.count >= 4 else { return nil }
            switch value {
            case citedness.percentile(0.75)...: return 1
            case citedness.percentile(0.50)...: return 2
            case citedness.percentile(0.25)...: return 3
            default: return 4
            }
        }
        for (issn, metrics) in openalex {
            ratings[issn] = JournalRating(
                issn: issn,
                title: metrics.title,
                source: .openalex,
                impact: metrics.twoYearMeanCitedness,
                quartile: openalexQuartile(metrics.twoYearMeanCitedness),
                sjr: nil,
                hIndex: metrics.hIndex)
        }
        for (issn, metrics) in scopus where metrics.citeScore != nil {
            ratings[issn] = JournalRating(
                issn: issn,
                title: metrics.title,
                source: .scopus,
                impact: metrics.citeScore,
                quartile: metrics.quartile,
                sjr: metrics.sjr,
                hIndex: ratings[issn]?.hIndex)
        }
        return ratings
    }

    /// Quartile distribution over the unified ratings, Q1…Q4.
    static func quartileDistribution(personData: [PersonData],
                                     ratings: [String: JournalRating]) -> [Int: Int] {
        var seen = Set<String>()
        var counts: [Int: Int] = [:]
        for data in personData {
            for work in data.works {
                guard seen.insert(work.id).inserted,
                      let issn = work.venueISSN,
                      let quartile = ratings[issn]?.quartile else { continue }
                counts[quartile, default: 0] += 1
            }
        }
        return counts
    }

    /// Quartile distribution of the cohort's rated publications (distinct
    /// works whose venue has Scopus CiteScore data), Q1…Q4.
    static func quartileDistribution(personData: [PersonData],
                                     journals: [String: ScopusJournalMetrics]) -> [Int: Int] {
        var seen = Set<String>()
        var counts: [Int: Int] = [:]
        for data in personData {
            for work in data.works {
                guard seen.insert(work.id).inserted,
                      let issn = work.venueISSN,
                      let quartile = journals[issn]?.quartile else { continue }
                counts[quartile, default: 0] += 1
            }
        }
        return counts
    }

    // MARK: Open-access status

    /// Canonical display order, most to least open. Statuses outside this
    /// list (OpenAlex adds them occasionally) sort after, alphabetically.
    static let oaStatusOrder = ["diamond", "gold", "hybrid", "green", "bronze", "closed"]

    private static func oaStatusRank(_ status: String) -> Int {
        oaStatusOrder.firstIndex(of: status) ?? oaStatusOrder.count
    }

    /// Distinct works per OA status across the cohort, in canonical order.
    /// Works with no oa_status are skipped.
    static func oaStatusCounts(personData: [PersonData]) -> [(status: String, count: Int)] {
        var seenByStatus: [String: Set<String>] = [:]
        for data in personData {
            for work in data.works {
                guard let status = work.oaStatus?.lowercased(), !status.isEmpty else { continue }
                seenByStatus[status, default: []].insert(work.id)
            }
        }
        return seenByStatus
            .map { (status: $0.key, count: $0.value.count) }
            .sorted { (oaStatusRank($0.status), $0.status) < (oaStatusRank($1.status), $1.status) }
    }

    struct OAStatusYearShare: Identifiable {
        var status: String
        var year: Int
        var percent: Double      // share of that year's status-tagged works

        var id: String { "\(status)|\(year)" }
    }

    /// Per-year OA-status composition of division publications, as percent of
    /// each year's status-tagged works (columns stack to 100).
    static func oaStatusByYear(personData: [PersonData],
                               fromYear: Int = 2010) -> [OAStatusYearShare] {
        var seen = Set<String>()
        var byYearStatus: [Int: [String: Int]] = [:]
        var totalByYear: [Int: Int] = [:]
        for data in personData {
            for work in data.works {
                guard let year = work.year, year >= fromYear, year <= currentYear,
                      let status = work.oaStatus?.lowercased(), !status.isEmpty,
                      seen.insert(work.id).inserted
                else { continue }
                byYearStatus[year, default: [:]][status, default: 0] += 1
                totalByYear[year, default: 0] += 1
            }
        }
        return byYearStatus
            .flatMap { year, statuses in
                statuses.map { status, count in
                    OAStatusYearShare(
                        status: status, year: year,
                        percent: 100 * Double(count) / Double(totalByYear[year] ?? 1))
                }
            }
            .sorted {
                ($0.year, oaStatusRank($0.status), $0.status)
                    < ($1.year, oaStatusRank($1.status), $1.status)
            }
    }
}
