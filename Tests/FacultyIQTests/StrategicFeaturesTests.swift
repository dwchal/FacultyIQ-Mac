import XCTest
@testable import FacultyIQ

final class PublicationReferenceImporterTests: XCTestCase {
    private let memberID = UUID()

    func testBibTeXImportHandlesBracedTitleDOIAndYear() throws {
        let text = """
        @article{sample,
          title = {Cancer {Data} Science in Practice},
          year = {2025},
          doi = {https://doi.org/10.1000/ABC.1}
        }
        """
        let records = try PublicationReferenceImporter.importText(
            text, format: .bibtex, memberID: memberID)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].title, "Cancer Data Science in Practice")
        XCTAssertEqual(records[0].doi, "10.1000/abc.1")
        XCTAssertEqual(records[0].year, 2025)
    }

    func testRISImportReadsMultipleRecords() throws {
        let text = """
        TY  - JOUR
        TI  - First Work
        DO  - 10.1/first
        PY  - 2024
        ER  -
        TY  - JOUR
        T1  - Second Work
        Y1  - 2023/01/01
        ER  -
        """
        let records = try PublicationReferenceImporter.importText(
            text, format: .ris, memberID: memberID)
        XCTAssertEqual(records.map(\.title), ["First Work", "Second Work"])
        XCTAssertEqual(records.map(\.year), [2024, 2023])
    }

    func testCSVImportUsesTitleDOIAndYearColumns() throws {
        let text = """
        Publication Title,DOI,Publication Year
        "A Work, With a Comma",10.2/work,2022
        """
        let records = try PublicationReferenceImporter.importText(
            text, format: .csv, memberID: memberID)
        XCTAssertEqual(records.first?.title, "A Work, With a Comma")
        XCTAssertEqual(records.first?.doi, "10.2/work")
        XCTAssertEqual(records.first?.year, 2022)
    }
}

final class StrategicMetricsTests: XCTestCase {
    private func work(_ id: String, title: String, doi: String? = nil,
                      topic: String? = nil, authorID: String = "A1") -> Work {
        Work(
            id: id, title: title, year: 2025, date: nil, type: "article",
            citedByCount: 10, doi: doi, pmid: "1", isOA: true, oaStatus: "gold",
            venue: "Journal", venueISSN: "1111-1111",
            authors: [WorkAuthor(openalexID: authorID, displayName: "Person",
                                 position: .last, isCorresponding: true)],
            topicName: topic, topicField: "Medicine")
    }

    private func data(_ works: [Work], authorID: String = "A1",
                      fetchedAt: Date = Date()) -> PersonData {
        PersonData(
            profile: AuthorProfile(
                openalexID: authorID, displayName: "Person",
                worksCount: works.count, citedByCount: works.map(\.citedByCount).reduce(0, +),
                hIndex: works.isEmpty ? 0 : 1, i10Index: works.count,
                affiliation: "University", countsByYear: []),
            works: works, fetchedAt: fetchedAt)
    }

    func testReconciliationPrefersDOIThenTitleAndFlagsMissing() {
        let memberID = UUID()
        let works = [
            work("W1", title: "Exact DOI Work", doi: "https://doi.org/10.1/one"),
            work("W2", title: "A Punctuated: Title!", doi: nil),
        ]
        let imported = [
            ImportedPublication(memberID: memberID, title: "Different title",
                                doi: "10.1/ONE", sourceFormat: .bibtex),
            ImportedPublication(memberID: memberID, title: "A punctuated title",
                                doi: nil, sourceFormat: .ris),
            ImportedPublication(memberID: memberID, title: "Absent Work",
                                doi: "10.1/missing", sourceFormat: .csv),
        ]
        let matches = MetricsEngine.reconciliationMatches(imported: imported, works: works)
        XCTAssertEqual(matches.count { $0.kind == .doi }, 1)
        XCTAssertEqual(matches.count { $0.kind == .title }, 1)
        XCTAssertEqual(matches.count { $0.kind == .missing }, 1)
    }

    func testConfidencePenalizesStaleWeakIdentityAndMissingCoverage() {
        let member = FacultyMember(name: "Person")
        let oldData = data(
            [Work(id: "W1", title: "Old", year: 2020, date: nil, type: nil,
                  citedByCount: 0, doi: nil, isOA: nil, oaStatus: nil, venue: nil)],
            fetchedAt: Date(timeIntervalSinceNow: -45 * 86_400))
        let report = MetricsEngine.dataConfidence(
            member: member,
            resolution: Resolution(openalexID: "A1", displayName: "Person",
                                   method: .manual, affiliation: nil, orcid: nil),
            data: oldData, enrichment: nil)
        XCTAssertLessThan(report.score, 60)
        XCTAssertTrue(report.warnings.contains { $0.contains("30 days") })
        XCTAssertTrue(report.warnings.contains { $0.contains("DOI") })
    }

    func testOpportunityMatchingUsesTopicsAndAgencyFunding() {
        var alice = FacultyMember(name: "Alice")
        alice.rank = "Associate Professor"
        let aliceData = data([
            work("W1", title: "Cancer AI", topic: "Cancer Informatics"),
            work("W2", title: "Cancer Data", topic: "Cancer Informatics"),
        ])
        let opportunity = FundingOpportunity(
            id: "1", number: "RFA-1", title: "Informatics Technologies for Cancer",
            agencyCode: "HHS-NIH11", agencyName: "National Institutes of Health",
            openDate: nil, closeDate: nil, status: "posted",
            assistanceListings: [], matchedQuery: "cancer informatics", fetchedAt: Date())
        let matches = MetricsEngine.opportunityFacultyMatches(
            opportunity: opportunity,
            roster: [alice],
            personData: [alice.id: aliceData],
            enrichment: [:])
        XCTAssertEqual(matches.first?.member.id, alice.id)
        XCTAssertTrue(matches.first?.matchedTopics.contains("Cancer Informatics") == true)
        XCTAssertGreaterThan(matches.first?.score ?? 0, 0)
    }

    func testCohortSnapshotRestrictsMembers() {
        let alice = FacultyMember(name: "Alice")
        let bob = FacultyMember(name: "Bob")
        let cohort = SavedCohort(name: "Selected", memberIDs: [alice.id])
        let snapshot = MetricsEngine.cohortSnapshot(
            cohort,
            roster: [alice, bob],
            resolutions: [alice.id: Resolution(openalexID: "A1", displayName: "Alice",
                                               method: .orcid, affiliation: nil, orcid: "x")],
            personData: [
                alice.id: data([work("W1", title: "One", topic: "Topic A")]),
                bob.id: data([work("W2", title: "Two", topic: "Topic B")]),
            ])
        XCTAssertEqual(snapshot.memberCount, 1)
        XCTAssertEqual(snapshot.resolvedCount, 1)
        XCTAssertEqual(snapshot.totalWorks, 1)
        XCTAssertEqual(snapshot.topTopics, ["Topic A"])
    }
}

final class OpportunityIntegrationTests: XCTestCase {
    func testGrantsGovSearch() async throws {
        guard ProcessInfo.processInfo.environment["FACULTYIQ_LIVE"] == "1" else {
            throw XCTSkip("Set FACULTYIQ_LIVE=1 to run live API tests")
        }
        let results = try await GrantsOpportunityClient.shared.search(
            query: "cancer informatics", limit: 5, bypassCache: true)
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { !$0.id.isEmpty && !$0.title.isEmpty })
        XCTAssertTrue(results.allSatisfy { $0.detailsURL != nil })
    }
}
