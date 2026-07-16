import XCTest
@testable import FacultyIQ

final class GrantTimelineTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Fixed "today" so active/expiring classifications are deterministic.
    private var now: Date { date(2026, 7, 15) }

    private func grant(_ core: String, start: String?, end: String?,
                       fiscalYears: [Int] = [2024]) -> Grant {
        Grant(coreProjectNum: core, latestProjectNum: "5\(core)-03", title: core,
              activityCode: "R01", fiscalYears: fiscalYears, totalAward: 100,
              startDate: start, endDate: end, orgName: nil)
    }

    private func attach(_ grants: [Grant]) -> Enrichment {
        Enrichment(grants: GrantData(grants: grants, confirmedProfileID: 1,
                                     confirmedPIName: nil, fetchedAt: Date()))
    }

    // MARK: Date parsing

    func testParseGrantDateHandlesBothReporterFormats() {
        XCTAssertEqual(MetricsEngine.parseGrantDate("2016-05-01T00:00:00"), date(2016, 5, 1),
                       "live RePORTER format: no timezone designator")
        XCTAssertEqual(MetricsEngine.parseGrantDate("2030-06-30"), date(2030, 6, 30))
        XCTAssertNil(MetricsEngine.parseGrantDate(nil))
        XCTAssertNil(MetricsEngine.parseGrantDate(""))
        XCTAssertNil(MetricsEngine.parseGrantDate("not a date"))
    }

    // MARK: Timeline

    func testActiveAndExpiringClassification() {
        let alice = FacultyMember(name: "Alice")
        let active = grant("R01AA000001", start: "2022-04-01T00:00:00", end: "2029-03-31T00:00:00")
        // Ends exactly 12 months out: still counts as expiring soon.
        let boundary = grant("R01BB000002", start: "2021-07-16T00:00:00", end: "2027-07-15T00:00:00")
        let future = grant("R01CC000003", start: "2027-01-01T00:00:00", end: "2032-12-31T00:00:00")
        let enrichment = [alice.id: attach([active, boundary, future])]

        let bars = MetricsEngine.grantTimeline(roster: [alice], enrichment: enrichment, asOf: now)
        XCTAssertEqual(bars.count, 3)

        let byCore = Dictionary(uniqueKeysWithValues: bars.map { ($0.grant.coreProjectNum, $0) })
        XCTAssertTrue(byCore["R01AA000001"]!.isActive)
        XCTAssertFalse(byCore["R01AA000001"]!.expiresSoon)
        XCTAssertTrue(byCore["R01BB000002"]!.expiresSoon)
        XCTAssertFalse(byCore["R01CC000003"]!.isActive, "not started yet")
        XCTAssertFalse(byCore["R01CC000003"]!.expiresSoon)
    }

    func testCompletedGrantsHiddenByDefault() {
        let alice = FacultyMember(name: "Alice")
        let recentEnded = grant("K08AA000001", start: "2018-07-01T00:00:00", end: "2023-06-30T00:00:00")
        let ancient = grant("R01BB000002", start: "2005-07-01T00:00:00", end: "2010-06-30T00:00:00")
        let active = grant("R01CC000003", start: "2024-01-01T00:00:00", end: "2029-12-31T00:00:00")
        let enrichment = [alice.id: attach([recentEnded, ancient, active])]

        let defaults = MetricsEngine.grantTimeline(roster: [alice], enrichment: enrichment, asOf: now)
        XCTAssertEqual(defaults.map(\.grant.coreProjectNum), ["R01CC000003"])

        let withCompleted = MetricsEngine.grantTimeline(
            roster: [alice], enrichment: enrichment, asOf: now, includeCompleted: true)
        XCTAssertEqual(Set(withCompleted.map(\.grant.coreProjectNum)),
                       ["K08AA000001", "R01CC000003"],
                       "completed within 5 years appears; older stays hidden")
        XCTAssertFalse(withCompleted.first { $0.grant.coreProjectNum == "K08AA000001" }!.isActive)
    }

    func testFiscalYearFallbackIsFlaggedApproximate() {
        let alice = FacultyMember(name: "Alice")
        let noDates = grant("U01AA000001", start: nil, end: nil, fiscalYears: [2023, 2026])
        let noneAtAll = grant("U01BB000002", start: nil, end: nil, fiscalYears: [])
        let enrichment = [alice.id: attach([noDates, noneAtAll])]

        let bars = MetricsEngine.grantTimeline(roster: [alice], enrichment: enrichment, asOf: now)
        XCTAssertEqual(bars.count, 1, "grants with neither dates nor fiscal years are skipped")
        let bar = bars[0]
        XCTAssertTrue(bar.approximate)
        XCTAssertEqual(bar.start, date(2023, 1, 1))
        XCTAssertEqual(bar.end, date(2026, 12, 31))
        XCTAssertTrue(bar.isActive)
    }

    func testMultiPIGrantsAppearOnEachRow() {
        let alice = FacultyMember(name: "Alice")
        let bob = FacultyMember(name: "Bob")
        let shared = grant("R01AA000001", start: "2024-04-01T00:00:00", end: "2029-03-31T00:00:00")
        let enrichment = [alice.id: attach([shared]), bob.id: attach([shared])]

        let bars = MetricsEngine.grantTimeline(roster: [bob, alice], enrichment: enrichment, asOf: now)
        XCTAssertEqual(bars.map(\.memberName), ["Alice", "Bob"],
                       "one row per PI, sorted by name — never deduplicated")
    }
}
