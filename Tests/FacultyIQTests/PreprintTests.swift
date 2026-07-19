import XCTest
@testable import FacultyIQ

final class PreprintTests: XCTestCase {
    private func work(_ id: String, _ title: String, type: String?,
                      year: Int, citations: Int = 0) -> Work {
        Work(id: id, title: title, year: year, date: nil, type: type,
             citedByCount: citations, doi: nil, isOA: nil, oaStatus: nil, venue: nil)
    }

    private func data(_ works: [Work], profileWorks: Int? = nil,
                      profileCitations: Int? = nil) -> PersonData {
        PersonData(
            profile: AuthorProfile(
                openalexID: "A1", displayName: "Test Author",
                worksCount: profileWorks ?? works.count,
                citedByCount: profileCitations ?? works.map(\.citedByCount).reduce(0, +),
                hIndex: 5, i10Index: 3, affiliation: nil, countsByYear: []),
            works: works,
            fetchedAt: Date())
    }

    func testTitleKeyIgnoresPunctuationCaseAndDiacritics() {
        XCTAssertEqual(MetricsEngine.titleKey("Effets d'une Thérapie: A Trial!"),
                       MetricsEngine.titleKey("effets d une therapie a trial"))
    }

    func testTitleKeyIgnoresUndecodedEscapeSequences() {
        // Seen in real OpenAlex data: a literal backslash-n inside the title.
        XCTAssertEqual(MetricsEngine.titleKey("Notes from a Massive EHR\\n System Reveals"),
                       MetricsEngine.titleKey("Notes from a Massive EHR System Reveals"))
    }

    func testTitleKeyDropsTrailingPreprintMarker() {
        XCTAssertEqual(MetricsEngine.titleKey("Use of LLMs in Practice (Preprint)"),
                       MetricsEngine.titleKey("Use of LLMs in Practice"))
    }

    func testPairsPreprintWithPublishedVersion() {
        let works = [
            work("W1", "A Randomized Trial of Widgets", type: "preprint", year: 2023),
            work("W2", "A Randomized Trial of Widgets", type: "article", year: 2024),
            work("W3", "Something Else Entirely", type: "article", year: 2024),
        ]
        let pairs = MetricsEngine.preprintPairs(works: works)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs.first?.preprint.id, "W1")
        XCTAssertEqual(pairs.first?.published?.id, "W2")
        XCTAssertTrue(pairs.first?.isPublished ?? false)
    }

    func testUnmatchedPreprintHasNoPublishedVersion() {
        let works = [
            work("W1", "Never Published Findings", type: "preprint", year: 2020),
            work("W2", "An Unrelated Article", type: "article", year: 2024),
        ]
        let pairs = MetricsEngine.preprintPairs(works: works)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertNil(pairs.first?.published)
    }

    func testPostedContentCountsAsPreprint() {
        let works = [
            work("W1", "Shared Title", type: "posted-content", year: 2023),
            work("W2", "Shared Title", type: "article", year: 2024),
        ]
        XCTAssertEqual(MetricsEngine.supersededPreprintIDs(works: works), ["W1"])
    }

    func testCollapsingDropsSupersededPreprintAndAdjustsCounts() {
        let works = [
            work("W1", "Shared Title", type: "preprint", year: 2023, citations: 4),
            work("W2", "Shared Title", type: "article", year: 2024, citations: 30),
            work("W3", "Solo Article", type: "article", year: 2022, citations: 10),
        ]
        let collapsed = MetricsEngine.collapsingPreprints(data(works))
        XCTAssertEqual(collapsed.works.map(\.id), ["W2", "W3"])
        XCTAssertEqual(collapsed.profile.worksCount, 2)
        XCTAssertEqual(collapsed.profile.citedByCount, 40)
        // Indexes are cleared so they recompute from the remaining works.
        XCTAssertNil(collapsed.profile.hIndex)
    }

    func testCollapsingKeepsUnmatchedPreprints() {
        let works = [
            work("W1", "Only A Preprint", type: "preprint", year: 2023, citations: 2),
            work("W2", "A Real Article", type: "article", year: 2024, citations: 8),
        ]
        let collapsed = MetricsEngine.collapsingPreprints(data(works))
        XCTAssertEqual(collapsed.works.count, 2)
        // Untouched data is returned as-is, indexes intact.
        XCTAssertEqual(collapsed.profile.hIndex, 5)
    }

    func testSummaryCountsSharedPreprintOnce() {
        let shared = work("W1", "Coauthored Preprint", type: "preprint", year: 2019)
        let a = FacultyMember(name: "Alice")
        let b = FacultyMember(name: "Bob")
        let summary = MetricsEngine.preprintSummary(
            roster: [a, b],
            personData: [a.id: data([shared]), b.id: data([shared])])
        XCTAssertEqual(summary.total, 1)
        XCTAssertEqual(summary.unpublished, 1)
        XCTAssertEqual(summary.stale.count, 1, "a 2019 preprint is well past the stale cutoff")
    }

    func testRecentUnpublishedPreprintIsNotStale() {
        let member = FacultyMember(name: "Alice")
        let recent = work("W1", "Fresh Preprint", type: "preprint",
                          year: MetricsEngine.currentYear)
        let summary = MetricsEngine.preprintSummary(
            roster: [member], personData: [member.id: data([recent])])
        XCTAssertEqual(summary.unpublished, 1)
        XCTAssertTrue(summary.stale.isEmpty)
    }

    func testPublishedShare() {
        let member = FacultyMember(name: "Alice")
        let works = [
            work("W1", "One", type: "preprint", year: 2023),
            work("W2", "One", type: "article", year: 2024),
            work("W3", "Two", type: "preprint", year: 2023),
        ]
        let summary = MetricsEngine.preprintSummary(
            roster: [member], personData: [member.id: data(works)])
        XCTAssertEqual(summary.total, 2)
        XCTAssertEqual(summary.published, 1)
        XCTAssertEqual(summary.publishedShare ?? 0, 0.5, accuracy: 0.001)
    }
}
