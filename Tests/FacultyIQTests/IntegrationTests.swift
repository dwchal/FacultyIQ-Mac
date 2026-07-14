import XCTest
@testable import FacultyIQ

/// Live OpenAlex tests — network-dependent, so they only run when
/// FACULTYIQ_LIVE=1 is set (e.g. `FACULTYIQ_LIVE=1 swift test`).
final class OpenAlexIntegrationTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FACULTYIQ_LIVE"] == "1",
                          "Set FACULTYIQ_LIVE=1 to run live API tests")
    }

    func testSearchAuthors() async throws {
        let results = try await OpenAlexClient.shared.searchAuthors(name: "John Ioannidis")
        XCTAssertFalse(results.isEmpty)
        let top = try XCTUnwrap(results.first)
        XCTAssertTrue(top.displayName.localizedCaseInsensitiveContains("Ioannidis"))
        XCTAssertGreaterThan(top.worksCount, 100)
        XCTAssertNotNil(top.hIndex)
    }

    func testResolveByORCIDAndFetchWorks() async throws {
        // Josiah Carberry: ORCID's fictional test researcher, stable in OpenAlex.
        let candidate = try await OpenAlexClient.shared.authorByORCID("0000-0002-1825-0097")
        let resolved = try XCTUnwrap(candidate)

        let profile = try await OpenAlexClient.shared.author(id: resolved.openalexID)
        XCTAssertEqual(profile.openalexID, resolved.openalexID)

        let works = try await OpenAlexClient.shared.works(authorID: resolved.openalexID)
        XCTAssertFalse(works.isEmpty)
        XCTAssertNotNil(works.first?.title)
    }

    func testUnknownORCIDReturnsNil() async throws {
        // Checksum-invalid, guaranteed 404. (Note: 0000-0000-0000-0000 actually
        // matches a real record in OpenAlex — junk data on their side.)
        let candidate = try await OpenAlexClient.shared.authorByORCID("9999-9999-9999-9999")
        XCTAssertNil(candidate)
    }
}
