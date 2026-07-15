import XCTest
@testable import FacultyIQ

final class HistoryTests: XCTestCase {
    private func date(day: Int, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour))!
    }

    private func snap(_ author: String, day: Int, hour: Int = 12,
                      works: Int, citations: Int, h: Int = 5) -> MetricSnapshot {
        MetricSnapshot(date: date(day: day, hour: hour), openalexID: author, name: author,
                       works: works, citations: citations, hIndex: h)
    }

    func testDivisionHistoryCarriesForwardBetweenFetches() {
        let snapshots = [
            snap("A", day: 1, works: 10, citations: 100),
            snap("B", day: 1, works: 5, citations: 50),
            snap("A", day: 3, works: 12, citations: 110),
        ]
        let points = MetricsEngine.divisionHistory(snapshots: snapshots, authorIDs: ["A", "B"])

        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].works, 15)
        XCTAssertEqual(points[0].citations, 150)
        XCTAssertEqual(points[0].tracked, 2)
        // Day 3: A's new reading plus B carried forward from day 1.
        XCTAssertEqual(points[1].works, 17)
        XCTAssertEqual(points[1].citations, 160)
        XCTAssertEqual(points[1].tracked, 2)
    }

    func testDivisionHistoryRestrictsToGivenAuthors() {
        let snapshots = [
            snap("A", day: 1, works: 10, citations: 100),
            snap("X", day: 2, works: 99, citations: 999),  // not in the roster in view
        ]
        let points = MetricsEngine.divisionHistory(snapshots: snapshots, authorIDs: ["A"])
        XCTAssertEqual(points.count, 1, "days with only excluded authors don't appear")
        XCTAssertEqual(points[0].works, 10)
    }

    func testDivisionHistoryCollapsesSameDayToLatestReading() {
        let snapshots = [
            snap("A", day: 1, hour: 9, works: 10, citations: 100),
            snap("A", day: 1, hour: 17, works: 11, citations: 105),
        ]
        let points = MetricsEngine.divisionHistory(snapshots: snapshots, authorIDs: ["A"])
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].works, 11)
    }

    func testPersonHistorySortsOldestFirst() {
        let snapshots = [
            snap("A", day: 3, works: 12, citations: 110),
            snap("B", day: 2, works: 1, citations: 1),
            snap("A", day: 1, works: 10, citations: 100),
        ]
        let history = MetricsEngine.personHistory(snapshots: snapshots, openalexID: "A")
        XCTAssertEqual(history.map(\.works), [10, 12])
    }

    func testSnapshotsRoundTrip() throws {
        let snapshots = [snap("A", day: 1, works: 10, citations: 100)]
        let data = try JSONEncoder().encode(snapshots)
        let decoded = try JSONDecoder().decode([MetricSnapshot].self, from: data)
        XCTAssertEqual(decoded, snapshots)
    }
}
