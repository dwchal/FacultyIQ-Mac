import XCTest
@testable import FacultyIQ

final class FundingCliffTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)   // 2025-10-09

    private func day(_ iso: String) -> String { "\(iso)T00:00:00" }

    private func grant(_ core: String, end: String?, fiscalYears: [Int] = [],
                       award: Int = 500_000) -> Grant {
        Grant(coreProjectNum: core, latestProjectNum: core, title: "Project \(core)",
              activityCode: "R01", fiscalYears: fiscalYears, totalAward: award,
              startDate: day("2020-01-01"), endDate: end.map(day), orgName: nil)
    }

    private func enrichment(_ member: FacultyMember,
                            grants: [Grant] = [],
                            nsf: [NSFAward] = []) -> [UUID: Enrichment] {
        var entry = Enrichment()
        if !grants.isEmpty {
            entry.grants = GrantData(grants: grants, confirmedProfileID: 1,
                                     confirmedPIName: member.name, fetchedAt: Date())
        }
        if !nsf.isEmpty {
            entry.nsf = NSFData(awards: nsf, confirmedPIName: member.name, fetchedAt: Date())
        }
        return [member.id: entry]
    }

    func testFlagsGrantEndingInsideTheWindow() {
        let member = FacultyMember(name: "Alice")
        let cliffs = MetricsEngine.fundingCliffs(
            roster: [member],
            enrichment: enrichment(member, grants: [grant("R01AA", end: "2026-03-31")]),
            asOf: now)
        XCTAssertEqual(cliffs.count, 1)
        XCTAssertEqual(cliffs.first?.projectNumber, "R01AA")
        XCTAssertEqual(cliffs.first?.source, "NIH")
        XCTAssertFalse(cliffs.first?.approximate ?? true)
    }

    func testIgnoresGrantRunningPastTheWindow() {
        let member = FacultyMember(name: "Alice")
        let cliffs = MetricsEngine.fundingCliffs(
            roster: [member],
            enrichment: enrichment(member, grants: [grant("R01AA", end: "2028-03-31")]),
            asOf: now)
        XCTAssertTrue(cliffs.isEmpty)
    }

    func testIgnoresAlreadyExpiredGrant() {
        let member = FacultyMember(name: "Alice")
        let cliffs = MetricsEngine.fundingCliffs(
            roster: [member],
            enrichment: enrichment(member, grants: [grant("R01AA", end: "2024-03-31")]),
            asOf: now)
        XCTAssertTrue(cliffs.isEmpty, "a grant that already ended is not an upcoming cliff")
    }

    func testSuccessorGrantCoversTheCliff() {
        let member = FacultyMember(name: "Alice")
        let cliffs = MetricsEngine.fundingCliffs(
            roster: [member],
            enrichment: enrichment(member, grants: [
                grant("R01AA", end: "2026-03-31"),
                grant("R01BB", end: "2029-06-30"),
            ]),
            asOf: now)
        XCTAssertTrue(cliffs.isEmpty, "a grant running past the horizon means no cliff")
    }

    func testNSFAwardCoversAnEndingNIHGrant() {
        let member = FacultyMember(name: "Alice")
        let nsf = NSFAward(awardID: "2548111", title: "NSF Project", agency: "NSF",
                           program: nil, organization: nil, piName: "Alice", isPI: true,
                           startDate: now, endDate: Date(timeIntervalSince1970: 1_890_000_000),
                           totalAward: 400_000)
        let cliffs = MetricsEngine.fundingCliffs(
            roster: [member],
            enrichment: enrichment(member, grants: [grant("R01AA", end: "2026-03-31")], nsf: [nsf]),
            asOf: now)
        XCTAssertTrue(cliffs.isEmpty, "NSF support past the horizon covers the NIH gap")
    }

    func testNSFAwardCanItselfBeTheCliff() {
        let member = FacultyMember(name: "Alice")
        // Ends 2026-01-27, inside the 12-month window from 2025-10-09.
        let nsf = NSFAward(awardID: "2548111", title: "NSF Project", agency: "NSF",
                           program: nil, organization: nil, piName: "Alice", isPI: true,
                           startDate: nil, endDate: Date(timeIntervalSince1970: 1_769_500_000),
                           totalAward: 400_000)
        let cliffs = MetricsEngine.fundingCliffs(
            roster: [member], enrichment: enrichment(member, nsf: [nsf]), asOf: now)
        XCTAssertEqual(cliffs.count, 1)
        XCTAssertEqual(cliffs.first?.source, "NSF")
        XCTAssertEqual(cliffs.first?.projectNumber, "2548111")
    }

    func testUnfundedMemberIsNotACliff() {
        let member = FacultyMember(name: "Alice")
        let cliffs = MetricsEngine.fundingCliffs(
            roster: [member], enrichment: [:], asOf: now)
        XCTAssertTrue(cliffs.isEmpty)
    }

    func testFallsBackToFiscalYearsAndFlagsApproximate() {
        let member = FacultyMember(name: "Alice")
        // No end date; last FY 2025 → approximated to 2025-12-31.
        let undated = grant("R01AA", end: nil, fiscalYears: [2023, 2024, 2025])
        let cliffs = MetricsEngine.fundingCliffs(
            roster: [member], enrichment: enrichment(member, grants: [undated]), asOf: now)
        XCTAssertEqual(cliffs.count, 1)
        XCTAssertTrue(cliffs.first?.approximate ?? false)
    }

    func testSortedBySoonestFirst() {
        let alice = FacultyMember(name: "Alice")
        let bob = FacultyMember(name: "Bob")
        var enrichment = self.enrichment(alice, grants: [grant("R01AA", end: "2026-08-31")])
        enrichment.merge(self.enrichment(bob, grants: [grant("R01BB", end: "2025-12-31")])) { a, _ in a }
        let cliffs = MetricsEngine.fundingCliffs(
            roster: [alice, bob], enrichment: enrichment, asOf: now)
        XCTAssertEqual(cliffs.map(\.memberName), ["Bob", "Alice"])
    }

    func testMonthsOutIsMeasuredFromTheGivenDate() {
        let member = FacultyMember(name: "Alice")
        let cliffs = MetricsEngine.fundingCliffs(
            roster: [member],
            enrichment: enrichment(member, grants: [grant("R01AA", end: "2026-03-31")]),
            asOf: now)
        XCTAssertEqual(cliffs.first?.monthsOut(from: now), 5)
    }

    func testCSVIncludesEveryCliff() {
        let member = FacultyMember(name: "Alice")
        let cliffs = MetricsEngine.fundingCliffs(
            roster: [member],
            enrichment: enrichment(member, grants: [grant("R01AA", end: "2026-03-31")]),
            asOf: now)
        let csv = MetricsEngine.fundingCliffsCSV(cliffs)
        XCTAssertTrue(csv.contains("Alice"))
        XCTAssertTrue(csv.contains("R01AA"))
        XCTAssertEqual(csv.split(separator: "\n").count, 2, "header plus one row")
    }
}
