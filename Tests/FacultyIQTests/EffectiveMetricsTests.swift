import XCTest
@testable import FacultyIQ

/// Degraded-response resilience: OpenAlex intermittently returns zeroed
/// author records (observed 2026-07-16 during a backend migration) while the
/// works list stays intact. The effective* helpers must fall back to the
/// works-derived lower bound so dashboards, snapshots, and What's New deltas
/// don't collapse to zero.
final class EffectiveMetricsTests: XCTestCase {
    /// Three works with 20/15/10 citations: local h = 3, i10 = 3, sum = 45.
    private let works = [("W1", 20), ("W2", 15), ("W3", 10)].map { id, cites in
        Work(id: id, title: id, year: 2020, date: nil, type: nil, citedByCount: cites,
             doi: nil, isOA: nil, oaStatus: nil, venue: nil, authors: nil)
    }

    private func personData(profileWorks: Int, profileCites: Int,
                            hIndex: Int?, i10: Int? = nil,
                            fetchedAt: Date = Date()) -> PersonData {
        PersonData(
            profile: AuthorProfile(openalexID: "A1", displayName: "Dr A",
                                   worksCount: profileWorks, citedByCount: profileCites,
                                   hIndex: hIndex, i10Index: i10, affiliation: nil,
                                   countsByYear: []),
            works: works, fetchedAt: fetchedAt)
    }

    func testDegradedProfileFallsBackToWorksDerivedMetrics() {
        let degraded = personData(profileWorks: 0, profileCites: 0, hIndex: 0, i10: 0)
        XCTAssertEqual(MetricsEngine.effectiveHIndex(degraded), 3)
        XCTAssertEqual(MetricsEngine.effectiveCitations(degraded), 45)
        XCTAssertEqual(MetricsEngine.effectiveWorksCount(degraded), 3)
        XCTAssertEqual(MetricsEngine.effectiveI10(degraded), 3)

        let m = MetricsEngine.personMetrics(member: FacultyMember(name: "A"), data: degraded)
        XCTAssertEqual(m.hIndex, 3)
        XCTAssertEqual(m.citations, 45)
        XCTAssertEqual(m.worksCount, 3)
    }

    func testHealthyProfileStillWins() {
        // The profile legitimately exceeds the works-derived bounds (works
        // list truncation, citations to unfetched works).
        let healthy = personData(profileWorks: 5, profileCites: 100, hIndex: 4, i10: 4)
        XCTAssertEqual(MetricsEngine.effectiveHIndex(healthy), 4)
        XCTAssertEqual(MetricsEngine.effectiveCitations(healthy), 100)
        XCTAssertEqual(MetricsEngine.effectiveWorksCount(healthy), 5)
        XCTAssertEqual(MetricsEngine.effectiveI10(healthy), 4)
    }

    func testOutageRoundTripDeltaNetsToZero() {
        // Healthy → degraded → healthy across three fetches, deltas
        // accumulated the whole way (the user never clicks Mark Reviewed):
        // the net delta must show no spurious movement.
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let t1 = t0.addingTimeInterval(86_400)
        let t2 = t1.addingTimeInterval(86_400)
        let healthy0 = personData(profileWorks: 5, profileCites: 100, hIndex: 4, fetchedAt: t0)
        let degraded = personData(profileWorks: 0, profileCites: 0, hIndex: 0, fetchedAt: t1)
        let healthy1 = personData(profileWorks: 5, profileCites: 100, hIndex: 4, fetchedAt: t2)

        let mid = MetricsEngine.refreshDelta(old: healthy0, new: degraded)
        // The degraded fetch can only sag to the works-derived floor, never to zero.
        XCTAssertEqual(mid.citationsDelta, 45 - 100)
        let final = MetricsEngine.refreshDelta(old: degraded, new: healthy1, accumulating: mid)
        XCTAssertEqual(final.worksDelta, 0)
        XCTAssertEqual(final.citationsDelta, 0)
        XCTAssertEqual(final.hIndexDelta, 0)
        XCTAssertEqual(final.since, t0)
    }
}
