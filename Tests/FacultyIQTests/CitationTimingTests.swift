import XCTest
@testable import FacultyIQ

/// Citation-timing semantics: per-work counts_by_year is the trusted source
/// (OpenAlex's 2026-07 migration changed the author-level field to bucket
/// citations by the cited work's publication year), with the author-level
/// field as fallback for pre-tracking caches, and the vintage metric as its
/// own explicit series.
final class CitationTimingTests: XCTestCase {
    private func work(_ id: String, year: Int? = 2020, cites: Int = 0,
                      received: [(Int, Int)]? = nil) -> Work {
        Work(id: id, title: id, year: year, date: nil, type: nil, citedByCount: cites,
             doi: nil, isOA: nil, oaStatus: nil, venue: nil, authors: nil,
             citationsByYear: received.map { $0.map { WorkYearCites(year: $0.0, citedByCount: $0.1) } })
    }

    private func personData(_ works: [Work],
                            profileCounts: [YearCount] = []) -> PersonData {
        PersonData(
            profile: AuthorProfile(openalexID: "A1", displayName: "Dr A",
                                   worksCount: works.count,
                                   citedByCount: works.map(\.citedByCount).reduce(0, +),
                                   hIndex: nil, i10Index: nil, affiliation: nil,
                                   countsByYear: profileCounts),
            works: works, fetchedAt: Date())
    }

    func testCitationsByYearSumsWorkLevelCounts() {
        let data = personData(
            [work("W1", received: [(2023, 5), (2024, 7)]),
             work("W2", received: [(2024, 3), (2025, 2)]),
             work("W3", received: nil)],  // pre-tracking work: skipped, not a fallback trigger
            profileCounts: [YearCount(year: 2024, worksCount: 0, citedByCount: 999)])
        XCTAssertEqual(MetricsEngine.citationsByYear(data), [2023: 5, 2024: 10, 2025: 2])
    }

    func testCitationsByYearFallsBackToProfileWhenUntracked() {
        let data = personData(
            [work("W1"), work("W2")],
            profileCounts: [YearCount(year: 2024, worksCount: 3, citedByCount: 40)])
        XCTAssertEqual(MetricsEngine.citationsByYear(data), [2024: 40])
        XCTAssertTrue(MetricsEngine.staleCitationData(personData: [data]))
        let tracked = personData([work("W1", received: [(2024, 1)])])
        XCTAssertFalse(MetricsEngine.staleCitationData(personData: [tracked]))
    }

    func testCitationsByPublicationYearDedupesSharedWorks() {
        let shared = work("W1", year: 2020, cites: 100)
        let a = personData([shared, work("W2", year: 2021, cites: 30)])
        let b = personData([shared, work("W3", year: 2020, cites: 10)])
        let series = MetricsEngine.citationsByPublicationYear(personData: [a, b])
        XCTAssertEqual(series.map(\.year), [2020, 2021])
        XCTAssertEqual(series.map(\.citations), [110, 30])
    }

    func testDecodingOldStateWithoutWorkCountsYieldsNil() throws {
        let json = #"{"id":"W1","title":"t","citedByCount":5}"#
        let decoded = try JSONDecoder().decode(Work.self, from: Data(json.utf8))
        XCTAssertNil(decoded.citationsByYear)
    }
}
