import XCTest
@testable import FacultyIQ

/// Serialization contract for the workspace archive, plus the work-level
/// funder rollup. These never touch Application Support — the archive tests
/// round-trip in memory, so a test run can't disturb a real workspace.
@MainActor
final class ArchiveAndFunderTests: XCTestCase {
    // MARK: Archive

    private func sampleState() -> AppStore.SavedState {
        var member = FacultyMember(name: "Ada Lovelace")
        member.rank = "Associate Professor"
        member.division = "Computing"
        member.notes = "Strong trajectory; revisit at midyear."
        member.lastReviewed = Date(timeIntervalSince1970: 1_750_000_000)
        let work = Work(id: "W1", title: "On the Analytical Engine", year: 1843, date: nil,
                        type: "article", citedByCount: 900, doi: nil, isOA: true,
                        oaStatus: "gold", venue: "Memoirs", venueISSN: "1111-1111")
        return AppStore.SavedState(
            roster: [member],
            resolutions: [member.id: Resolution(openalexID: "A1", displayName: "Ada Lovelace",
                                                method: .manual, affiliation: nil, orcid: nil)],
            personData: [member.id: PersonData(
                profile: AuthorProfile(openalexID: "A1", displayName: "Ada Lovelace",
                                       worksCount: 1, citedByCount: 900, hIndex: 1, i10Index: 1,
                                       affiliation: nil, countsByYear: []),
                works: [work], fetchedAt: Date(timeIntervalSince1970: 1_760_000_000))],
            enrichment: nil, deltas: nil, lastUpdateCheck: nil, excludedWorks: nil,
            openalexJournals: OpenAlexJournalData(
                byISSN: ["1111-1111": OpenAlexJournalMetrics(
                    issn: "1111-1111", sourceID: "S1", title: "Memoirs",
                    twoYearMeanCitedness: 4.5, hIndex: 12, worksCount: 300,
                    isOA: false, isInDOAJ: false)],
                fetchedAt: Date(timeIntervalSince1970: 1_760_000_000)))
    }

    private func archive(_ state: AppStore.SavedState) -> AppStore.WorkspaceArchive {
        AppStore.WorkspaceArchive(
            formatVersion: AppStore.WorkspaceArchive.currentFormatVersion,
            exportedAt: Date(timeIntervalSince1970: 1_760_000_000),
            appVersion: "1.3",
            state: state,
            snapshots: [MetricSnapshot(date: Date(timeIntervalSince1970: 1_759_000_000),
                                       openalexID: "A1", name: "Ada Lovelace",
                                       works: 1, citations: 900, hIndex: 1)])
    }

    private func roundTrip(_ archive: AppStore.WorkspaceArchive) throws -> AppStore.WorkspaceArchive {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppStore.WorkspaceArchive.self,
                                  from: try encoder.encode(archive))
    }

    func testArchiveRoundTripPreservesRosterAndNotes() throws {
        let restored = try roundTrip(archive(sampleState()))
        let member = try XCTUnwrap(restored.state.roster.first)
        XCTAssertEqual(member.name, "Ada Lovelace")
        XCTAssertEqual(member.notes, "Strong trajectory; revisit at midyear.")
        XCTAssertEqual(member.lastReviewed?.timeIntervalSince1970, 1_750_000_000)
    }

    func testArchiveRoundTripPreservesWorksResolutionsAndSnapshots() throws {
        let restored = try roundTrip(archive(sampleState()))
        XCTAssertEqual(restored.state.resolutions.values.first?.openalexID, "A1")
        XCTAssertEqual(restored.state.personData.values.first?.works.first?.title,
                       "On the Analytical Engine")
        XCTAssertEqual(restored.snapshots.count, 1)
        XCTAssertEqual(restored.snapshots.first?.citations, 900)
    }

    func testArchiveRoundTripPreservesJournalMetrics() throws {
        let restored = try roundTrip(archive(sampleState()))
        let journals = try XCTUnwrap(restored.state.openalexJournals)
        XCTAssertEqual(journals.byISSN["1111-1111"]?.twoYearMeanCitedness, 4.5)
    }

    func testArchiveCarriesItsFormatVersion() throws {
        let restored = try roundTrip(archive(sampleState()))
        XCTAssertEqual(restored.formatVersion, AppStore.WorkspaceArchive.currentFormatVersion)
        XCTAssertEqual(restored.appVersion, "1.3")
    }

    func testArchivePreservesStrategicWorkflowState() throws {
        var state = sampleState()
        let memberID = try XCTUnwrap(state.roster.first?.id)
        state.cohorts = [SavedCohort(name: "Review Group", memberIDs: [memberID])]
        state.opportunities = [FundingOpportunity(
            id: "123", number: "RFA-TEST", title: "Test Opportunity",
            agencyCode: "HHS-NIH11", agencyName: "NIH",
            openDate: nil, closeDate: Date(timeIntervalSince1970: 1_800_000_000),
            status: "posted", assistanceListings: ["93.000"],
            matchedQuery: "test", fetchedAt: Date(timeIntervalSince1970: 1_700_000_000))]
        state.importedPublications = [ImportedPublication(
            memberID: memberID, title: "Imported Work", doi: "10.1/test",
            year: 2025, sourceFormat: .bibtex)]
        let restored = try roundTrip(archive(state))
        XCTAssertEqual(restored.state.cohorts?.first?.name, "Review Group")
        XCTAssertEqual(restored.state.opportunities?.first?.number, "RFA-TEST")
        XCTAssertEqual(restored.state.importedPublications?.first?.title, "Imported Work")
    }

    func testStateFromABareRosterStillDecodes() throws {
        // A pre-notes, pre-journals state file: every added field is optional,
        // so old archives and old state.json files must still load.
        let json = """
        {"roster":[{"id":"\(UUID().uuidString)","name":"Old Member"}],
         "resolutions":[],"personData":[]}
        """
        let state = try JSONDecoder().decode(AppStore.SavedState.self,
                                             from: Data(json.utf8))
        XCTAssertEqual(state.roster.first?.name, "Old Member")
        XCTAssertNil(state.roster.first?.notes)
        XCTAssertNil(state.openalexJournals)
    }

    // MARK: Funder credits

    private func work(_ id: String, funders: [WorkGrant]?) -> Work {
        Work(id: id, title: "Work \(id)", year: 2024, date: nil, type: "article",
             citedByCount: 0, doi: nil, isOA: nil, oaStatus: nil, venue: nil,
             grants: funders)
    }

    private func data(_ works: [Work]) -> PersonData {
        PersonData(
            profile: AuthorProfile(openalexID: "A1", displayName: "A", worksCount: works.count,
                                   citedByCount: 0, hIndex: 0, i10Index: 0,
                                   affiliation: nil, countsByYear: []),
            works: works, fetchedAt: Date())
    }

    private let nih = WorkGrant(funderID: "F1", funderName: "NIH", awardID: "R01AA")
    private let nsf = WorkGrant(funderID: "F2", funderName: "NSF", awardID: "1234")

    func testFunderCreditsCountWorksAndPeople() {
        let alice = FacultyMember(name: "Alice")
        let bob = FacultyMember(name: "Bob")
        let credits = MetricsEngine.funderCredits(
            roster: [alice, bob],
            personData: [alice.id: data([work("W1", funders: [nih]),
                                         work("W2", funders: [nih, nsf])]),
                         bob.id: data([work("W3", funders: [nih])])])
        let nihCredit = try! XCTUnwrap(credits.first { $0.funderID == "F1" })
        XCTAssertEqual(nihCredit.works, 3)
        XCTAssertEqual(nihCredit.people, 2)
        let nsfCredit = try! XCTUnwrap(credits.first { $0.funderID == "F2" })
        XCTAssertEqual(nsfCredit.works, 1)
        XCTAssertEqual(nsfCredit.people, 1)
    }

    func testSharedWorkCountsOncePerFunder() {
        let alice = FacultyMember(name: "Alice")
        let bob = FacultyMember(name: "Bob")
        let shared = work("W1", funders: [nih])
        let credits = MetricsEngine.funderCredits(
            roster: [alice, bob],
            personData: [alice.id: data([shared]), bob.id: data([shared])])
        XCTAssertEqual(credits.first?.works, 1, "one paper is one work, not one per author")
        XCTAssertEqual(credits.first?.people, 2)
    }

    func testDistinctAwardIDsAreCounted() {
        let alice = FacultyMember(name: "Alice")
        let credits = MetricsEngine.funderCredits(
            roster: [alice],
            personData: [alice.id: data([
                work("W1", funders: [nih]),
                work("W2", funders: [WorkGrant(funderID: "F1", funderName: "NIH", awardID: "R01BB")]),
                work("W3", funders: [WorkGrant(funderID: "F1", funderName: "NIH", awardID: nil)]),
            ])])
        XCTAssertEqual(credits.first?.awardCount, 2, "two named awards; the nil one doesn't count")
        XCTAssertEqual(credits.first?.works, 3)
    }

    func testMissingFunderDataIsDetected() {
        let alice = FacultyMember(name: "Alice")
        // nil grants = fetched before funders were tracked.
        XCTAssertTrue(MetricsEngine.funderDataMissing(
            roster: [alice], personData: [alice.id: data([work("W1", funders: nil)])]))
        // An empty array is a real answer: this work has no funders.
        XCTAssertFalse(MetricsEngine.funderDataMissing(
            roster: [alice], personData: [alice.id: data([work("W1", funders: [])])]))
    }

    func testNoFetchedWorksIsNotMissingData() {
        let alice = FacultyMember(name: "Alice")
        XCTAssertFalse(MetricsEngine.funderDataMissing(
            roster: [alice], personData: [alice.id: data([])]),
            "an empty roster shouldn't nag about refreshing")
    }
}
