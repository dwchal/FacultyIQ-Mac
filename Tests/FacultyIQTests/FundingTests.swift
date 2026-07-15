import XCTest
@testable import FacultyIQ

final class FundingTests: XCTestCase {
    private func grant(_ core: String, activity: String? = "R01", total: Int,
                       byFY: [Int: Int]? = nil, endDate: String? = "2030-06-30") -> Grant {
        Grant(coreProjectNum: core, latestProjectNum: "5\(core)-03", title: core,
              activityCode: activity, fiscalYears: byFY.map { $0.keys.sorted() } ?? [2024],
              totalAward: total, startDate: nil, endDate: endDate, orgName: nil,
              awardsByFiscalYear: byFY)
    }

    private func attach(_ grants: [Grant]) -> Enrichment {
        Enrichment(grants: GrantData(grants: grants, confirmedProfileID: 1,
                                     confirmedPIName: nil, fetchedAt: Date()))
    }

    func testDivisionFundingDedupesSharedProjects() throws {
        let alice = FacultyMember(name: "Alice")
        let bob = FacultyMember(name: "Bob")
        let shared = grant("R01AI000001", total: 900_000, byFY: [2023: 400_000, 2024: 500_000])
        let solo = grant("K08AI000002", activity: "K08", total: 300_000, byFY: [2024: 300_000])
        let enrichment = [alice.id: attach([shared, solo]),
                          bob.id: attach([shared])]

        let funding = try XCTUnwrap(
            MetricsEngine.divisionFunding(roster: [alice, bob], enrichment: enrichment))
        XCTAssertEqual(funding.projectCount, 2, "multi-PI project counts once")
        XCTAssertEqual(funding.totalAwarded, 1_200_000)
        XCTAssertEqual(funding.fundedMembers, 2)
        XCTAssertEqual(funding.r01EquivalentCount, 1)
        XCTAssertFalse(funding.missingFYBreakdown)

        XCTAssertEqual(funding.byFiscalYear.map(\.year), [2023, 2024])
        XCTAssertEqual(funding.byFiscalYear.map(\.amount), [400_000, 800_000])

        XCTAssertEqual(funding.byActivity.first?.code, "R01")
        XCTAssertEqual(funding.byActivity.first?.amount, 900_000)

        // Per-member sums keep each PI's full attachment.
        XCTAssertEqual(funding.topFunded.map(\.name), ["Alice", "Bob"])
        XCTAssertEqual(funding.topFunded[0].amount, 1_200_000)
        XCTAssertEqual(funding.topFunded[1].amount, 900_000)
    }

    func testDivisionFundingFlagsMissingBreakdown() throws {
        let alice = FacultyMember(name: "Alice")
        let old = grant("R01AI000003", total: 500_000, byFY: nil)  // pre-breakdown fetch
        let funding = try XCTUnwrap(
            MetricsEngine.divisionFunding(roster: [alice], enrichment: [alice.id: attach([old])]))
        XCTAssertTrue(funding.missingFYBreakdown)
        XCTAssertTrue(funding.byFiscalYear.isEmpty)
        XCTAssertEqual(funding.totalAwarded, 500_000, "totals never depend on the breakdown")
    }

    func testDivisionFundingNilWithoutGrants() {
        let alice = FacultyMember(name: "Alice")
        XCTAssertNil(MetricsEngine.divisionFunding(roster: [alice], enrichment: [:]))
        XCTAssertNil(MetricsEngine.divisionFunding(roster: [alice],
                                                   enrichment: [alice.id: attach([])]))
    }
}
