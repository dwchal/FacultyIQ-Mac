import XCTest
@testable import FacultyIQ

/// Live checks for the sources added alongside preprints and funding cliffs.
/// Opt in with FACULTYIQ_LIVE=1, like the other live suites — these hit the
/// real APIs and are the only way to catch a schema change.
final class NewSourceLiveTests: XCTestCase {
    private func requireLive() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FACULTYIQ_LIVE"] == "1",
                          "set FACULTYIQ_LIVE=1 to run live API tests")
    }

    func testOpenAlexSourcesReturnsJournalMetrics() async throws {
        try requireLive()
        // NEJM's linking ISSN plus its alternate, which must resolve to the
        // same source record.
        let metrics = try await OpenAlexClient.shared.sources(issns: ["0028-4793", "1533-4406"])
        XCTAssertFalse(metrics.isEmpty)
        let nejm = try XCTUnwrap(metrics.first { $0.issn == "0028-4793" })
        XCTAssertEqual(nejm.title, "New England Journal of Medicine")
        let citedness = try XCTUnwrap(nejm.twoYearMeanCitedness)
        XCTAssertGreaterThan(citedness, 1, "a top journal should have real citedness")
        XCTAssertGreaterThan(nejm.hIndex ?? 0, 0)
    }

    func testOpenAlexSourcesSkipsUnknownISSN() async throws {
        try requireLive()
        let metrics = try await OpenAlexClient.shared.sources(issns: ["0000-0000"])
        XCTAssertTrue(metrics.isEmpty, "an unmatched ISSN should drop out, not throw")
    }

    func testOpenAlexWorksCarryFunderCredits() async throws {
        try requireLive()
        // Francis Collins — heavily NIH-funded, so some work must credit a funder.
        let author = try await OpenAlexClient.shared.authorByORCID("0000-0002-1023-7410")
        let id = try XCTUnwrap(author?.openalexID)
        let works = try await OpenAlexClient.shared.works(authorID: id, limit: 200)
        XCTAssertFalse(works.isEmpty)
        XCTAssertTrue(works.contains { !($0.grants ?? []).isEmpty },
                      "at least one work should carry funder credits")
    }

    func testNSFAwardsForAKnownInvestigator() async throws {
        try requireLive()
        let awards = try await NSFClient.shared.awards(piName: "John Logsdon")
        XCTAssertFalse(awards.isEmpty)
        let award = try XCTUnwrap(awards.first)
        XCTAssertFalse(award.title.isEmpty)
        XCTAssertFalse(award.awardID.isEmpty)
    }

    func testNSFAwardsForANonsenseNameIsEmpty() async throws {
        try requireLive()
        let awards = try await NSFClient.shared.awards(piName: "Zzzqqx Vvbbnn")
        XCTAssertTrue(awards.isEmpty)
    }

    func testNSFDateParsing() {
        // Not a live test, but it guards the format the live rows arrive in.
        let date = NSFClient.parseDate("11/30/2029")
        let components = Calendar(identifier: .gregorian)
            .dateComponents([.year, .month, .day], from: try! XCTUnwrap(date))
        XCTAssertEqual(components.year, 2029)
        XCTAssertEqual(components.month, 11)
        XCTAssertEqual(components.day, 30)
        XCTAssertNil(NSFClient.parseDate(nil))
        XCTAssertNil(NSFClient.parseDate(""))
    }
}
