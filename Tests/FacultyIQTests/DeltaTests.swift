import XCTest
@testable import FacultyIQ

final class DeltaTests: XCTestCase {
    private func work(_ id: String, citations: Int = 0) -> Work {
        Work(id: id, title: id, year: 2024, date: nil, type: nil,
             citedByCount: citations, doi: nil, isOA: nil, oaStatus: nil, venue: nil, authors: nil)
    }

    private func personData(works: [Work], citations: Int = 0, hIndex: Int? = nil,
                            fetchedAt: Date) -> PersonData {
        PersonData(
            profile: AuthorProfile(openalexID: "A1", displayName: "Dr A",
                                   worksCount: works.count, citedByCount: citations,
                                   hIndex: hIndex, i10Index: nil, affiliation: nil,
                                   countsByYear: []),
            works: works, fetchedAt: fetchedAt)
    }

    private let t0 = Date(timeIntervalSinceReferenceDate: 0)
    private let t1 = Date(timeIntervalSinceReferenceDate: 86_400)
    private let t2 = Date(timeIntervalSinceReferenceDate: 2 * 86_400)

    func testDeltaDetectsNewWorksAndMetricChanges() {
        let old = personData(works: [work("W1")], citations: 10, hIndex: 2, fetchedAt: t0)
        let new = personData(works: [work("W1"), work("W2")], citations: 25, hIndex: 3, fetchedAt: t1)
        let delta = MetricsEngine.refreshDelta(old: old, new: new)
        XCTAssertEqual(delta.newWorkIDs, ["W2"])
        XCTAssertEqual(delta.worksDelta, 1)
        XCTAssertEqual(delta.citationsDelta, 15)
        XCTAssertEqual(delta.hIndexDelta, 1)
        XCTAssertEqual(delta.since, t0)
        XCTAssertEqual(delta.checkedAt, t1)
        XCTAssertTrue(delta.hasChanges)
    }

    func testDeltaAccumulatesAcrossChecksKeepingBaseline() {
        let existing = RefreshDelta(since: t0, checkedAt: t1, newWorkIDs: ["W2"],
                                    worksDelta: 1, citationsDelta: 15, hIndexDelta: 1)
        let old = personData(works: [work("W1"), work("W2")], citations: 25, hIndex: 3, fetchedAt: t1)
        let new = personData(works: [work("W1"), work("W2"), work("W3")],
                             citations: 30, hIndex: 3, fetchedAt: t2)
        let delta = MetricsEngine.refreshDelta(old: old, new: new, accumulating: existing)
        XCTAssertEqual(delta.newWorkIDs, ["W2", "W3"], "earlier finds carry through later checks")
        XCTAssertEqual(delta.since, t0, "baseline stays at the first diff")
        XCTAssertEqual(delta.checkedAt, t2)
        XCTAssertEqual(delta.worksDelta, 2)
        XCTAssertEqual(delta.citationsDelta, 20)
        XCTAssertEqual(delta.hIndexDelta, 1)
    }

    func testDeltaDropsWorksThatVanishedFromTheRecord() {
        // W9 was reported new earlier but OpenAlex has since merged/removed it.
        let existing = RefreshDelta(since: t0, checkedAt: t1, newWorkIDs: ["W9"],
                                    worksDelta: 1, citationsDelta: 0, hIndexDelta: 0)
        let old = personData(works: [work("W1"), work("W9")], fetchedAt: t1)
        let new = personData(works: [work("W1"), work("W2")], fetchedAt: t2)
        let delta = MetricsEngine.refreshDelta(old: old, new: new, accumulating: existing)
        XCTAssertEqual(delta.newWorkIDs, ["W2"])
    }

    func testIdenticalFetchHasNoChanges() {
        let old = personData(works: [work("W1", citations: 5)], citations: 5, hIndex: 1, fetchedAt: t0)
        let new = personData(works: [work("W1", citations: 5)], citations: 5, hIndex: 1, fetchedAt: t1)
        XCTAssertFalse(MetricsEngine.refreshDelta(old: old, new: new).hasChanges)
    }

    func testHIndexDeltaFallsBackToLocalComputation() {
        // No profile h-index: computed from work citations (h=1 → h=2).
        let old = personData(works: [work("W1", citations: 10)], fetchedAt: t0)
        let new = personData(works: [work("W1", citations: 12), work("W2", citations: 3)],
                             fetchedAt: t1)
        XCTAssertEqual(MetricsEngine.refreshDelta(old: old, new: new).hIndexDelta, 1)
    }
}
