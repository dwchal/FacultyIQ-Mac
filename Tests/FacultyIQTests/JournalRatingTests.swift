import XCTest
@testable import FacultyIQ

final class JournalRatingTests: XCTestCase {
    private func openalex(_ issn: String, citedness: Double?) -> OpenAlexJournalMetrics {
        OpenAlexJournalMetrics(issn: issn, sourceID: "S\(issn)", title: "Journal \(issn)",
                               twoYearMeanCitedness: citedness, hIndex: 40,
                               worksCount: 1000, isOA: false, isInDOAJ: false)
    }

    private func scopus(_ issn: String, citeScore: Double?, percentile: Double?) -> ScopusJournalMetrics {
        ScopusJournalMetrics(issn: issn, title: "Journal \(issn)", citeScore: citeScore,
                             citeScoreYear: 2025, topPercentile: percentile, snip: nil, sjr: 2.5)
    }

    private func work(_ id: String, issn: String?) -> Work {
        Work(id: id, title: "Work \(id)", year: 2024, date: nil, type: "article",
             citedByCount: 1, doi: nil, isOA: nil, oaStatus: nil, venue: "Venue",
             venueISSN: issn)
    }

    private func data(_ works: [Work]) -> PersonData {
        PersonData(
            profile: AuthorProfile(openalexID: "A1", displayName: "A", worksCount: works.count,
                                   citedByCount: 0, hIndex: 1, i10Index: 0,
                                   affiliation: nil, countsByYear: []),
            works: works, fetchedAt: Date())
    }

    func testOpenAlexFillsEveryVenueWhenScopusIsAbsent() {
        let ratings = MetricsEngine.journalRatings(
            scopus: [:],
            openalex: ["1111-1111": openalex("1111-1111", citedness: 5)])
        XCTAssertEqual(ratings["1111-1111"]?.source, .openalex)
        XCTAssertEqual(ratings["1111-1111"]?.impact, 5)
    }

    func testScopusWinsWhereItHasACiteScore() {
        let ratings = MetricsEngine.journalRatings(
            scopus: ["1111-1111": scopus("1111-1111", citeScore: 12, percentile: 90)],
            openalex: ["1111-1111": openalex("1111-1111", citedness: 5)])
        XCTAssertEqual(ratings["1111-1111"]?.source, .scopus)
        XCTAssertEqual(ratings["1111-1111"]?.impact, 12)
        XCTAssertEqual(ratings["1111-1111"]?.quartile, 1)
        XCTAssertEqual(ratings["1111-1111"]?.sjr, 2.5)
    }

    func testScopusWithoutCiteScoreDoesNotDisplaceOpenAlex() {
        let ratings = MetricsEngine.journalRatings(
            scopus: ["1111-1111": scopus("1111-1111", citeScore: nil, percentile: nil)],
            openalex: ["1111-1111": openalex("1111-1111", citedness: 5)])
        XCTAssertEqual(ratings["1111-1111"]?.source, .openalex,
                       "an empty Scopus record must not blank out usable OpenAlex data")
    }

    func testMixedSourcesCoexist() {
        let ratings = MetricsEngine.journalRatings(
            scopus: ["1111-1111": scopus("1111-1111", citeScore: 12, percentile: 90)],
            openalex: ["1111-1111": openalex("1111-1111", citedness: 5),
                       "2222-2222": openalex("2222-2222", citedness: 3)])
        XCTAssertEqual(ratings["1111-1111"]?.source, .scopus)
        XCTAssertEqual(ratings["2222-2222"]?.source, .openalex)
    }

    func testOpenAlexQuartilesAreCohortRelative() {
        // Four venues spanning a wide range: the top should land in Q1 and the
        // bottom in Q4, since quartiles are cut within this set.
        let openalex = [
            "1111-1111": openalex("1111-1111", citedness: 40),
            "2222-2222": openalex("2222-2222", citedness: 20),
            "3333-3333": openalex("3333-3333", citedness: 10),
            "4444-4444": openalex("4444-4444", citedness: 1),
        ]
        let ratings = MetricsEngine.journalRatings(scopus: [:], openalex: openalex)
        XCTAssertEqual(ratings["1111-1111"]?.quartile, 1)
        XCTAssertEqual(ratings["4444-4444"]?.quartile, 4)
    }

    func testTooFewVenuesForARelativeQuartile() {
        let ratings = MetricsEngine.journalRatings(
            scopus: [:],
            openalex: ["1111-1111": openalex("1111-1111", citedness: 40),
                       "2222-2222": openalex("2222-2222", citedness: 1)])
        XCTAssertNil(ratings["1111-1111"]?.quartile,
                     "two venues can't support a meaningful quartile split")
    }

    func testQuartileDistributionCountsDistinctWorks() {
        let ratings = MetricsEngine.journalRatings(
            scopus: ["1111-1111": scopus("1111-1111", citeScore: 12, percentile: 90)],
            openalex: [:])
        let shared = work("W1", issn: "1111-1111")
        let distribution = MetricsEngine.quartileDistribution(
            personData: [data([shared]), data([shared])], ratings: ratings)
        XCTAssertEqual(distribution[1], 1, "a coauthored work counts once")
    }

    func testWorksWithoutISSNAreUnrated() {
        let ratings = MetricsEngine.journalRatings(
            scopus: [:], openalex: ["1111-1111": openalex("1111-1111", citedness: 5)])
        let distribution = MetricsEngine.quartileDistribution(
            personData: [data([work("W1", issn: nil)])], ratings: ratings)
        XCTAssertTrue(distribution.isEmpty)
    }

    func testVenueCountsCarryTheUnifiedRating() {
        let ratings = MetricsEngine.journalRatings(
            scopus: ["1111-1111": scopus("1111-1111", citeScore: 12, percentile: 90)],
            openalex: [:])
        let venues = MetricsEngine.venueCounts(
            personData: [data([work("W1", issn: "1111-1111")])], ratings: ratings)
        XCTAssertEqual(venues.first?.rating?.impact, 12)
        XCTAssertEqual(venues.first?.quartileSort, 1)
    }
}
