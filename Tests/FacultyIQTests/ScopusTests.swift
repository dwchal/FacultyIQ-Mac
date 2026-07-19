import XCTest
@testable import FacultyIQ

/// Fixture tests for the Scopus response parsers — the API's JSON is
/// notorious for numbers-as-strings, colon-namespaced keys, and
/// single-element arrays flattened to objects, so each quirk is pinned here.
final class ScopusParsingTests: XCTestCase {
    func testParseAuthorWithStringNumbersAndWrappedEntry() throws {
        let json = Data("""
        {"author-retrieval-response":[
          {"coredata":{"document-count":"171","cited-by-count":"4321","citation-count":"5678"},
           "h-index":"27",
           "author-profile":{
             "affiliation-current":{"affiliation":{"ip-doc":{"afdispname":"Example Clinic"}}}}}
        ]}
        """.utf8)
        let author = try XCTUnwrap(ScopusClient.parseAuthor(json, scopusID: "7004212771"))
        XCTAssertEqual(author.scopusAuthorID, "7004212771")
        XCTAssertEqual(author.documentCount, 171)
        XCTAssertEqual(author.citedByCount, 4321)
        XCTAssertEqual(author.citationCount, 5678)
        XCTAssertEqual(author.hIndex, 27)
        XCTAssertEqual(author.currentAffiliation, "Example Clinic")
    }

    func testParseAuthorAffiliationArrayForm() throws {
        // affiliation-current.affiliation arrives as an array when the author
        // holds multiple current affiliations.
        let json = Data("""
        {"author-retrieval-response":[
          {"coredata":{"document-count":"12"},
           "author-profile":{"affiliation-current":{"affiliation":[
             {"ip-doc":{"preferred-name":{"$":"First University"}}},
             {"ip-doc":{"preferred-name":{"$":"Second Hospital"}}}]}}}
        ]}
        """.utf8)
        let author = try XCTUnwrap(ScopusClient.parseAuthor(json, scopusID: "1"))
        XCTAssertEqual(author.currentAffiliation, "First University")
        XCTAssertNil(author.hIndex, "STANDARD view has no h-index")
    }

    func testParseSerialMetricsWithYearListsAndPercentile() throws {
        let json = Data("""
        {"serial-metadata-response":{"entry":[
          {"dc:title":"Journal of Examples",
           "prism:issn":"1234-5678",
           "citeScoreYearInfoList":{
             "citeScoreCurrentMetric":"11.4",
             "citeScoreCurrentMetricYear":"2025",
             "citeScoreYearInfo":[{"citeScoreInformationList":[{"citeScoreInfo":[
               {"citeScoreSubjectRank":[
                 {"subjectCode":"2725","percentile":"93","rank":"12"},
                 {"subjectCode":"2726","percentile":"81","rank":"40"}]}]}]}]},
           "SNIPList":{"SNIP":[{"@year":"2023","$":"1.8"},{"@year":"2024","$":"2.1"}]},
           "SJRList":{"SJR":{"@year":"2024","$":"3.417"}}}
        ]}}
        """.utf8)
        let metrics = try XCTUnwrap(ScopusClient.parseSerial(json, issn: "1234-5678"))
        XCTAssertEqual(metrics.title, "Journal of Examples")
        XCTAssertEqual(metrics.citeScore, 11.4)
        XCTAssertEqual(metrics.citeScoreYear, 2025)
        XCTAssertEqual(metrics.topPercentile, 93, "best subject percentile wins")
        XCTAssertEqual(metrics.snip, 2.1, "latest SNIP year wins")
        XCTAssertEqual(metrics.sjr, 3.417, "object-form single-element list decodes")
        XCTAssertEqual(metrics.quartile, 1)
    }

    func testQuartileThresholds() {
        func metrics(_ percentile: Double?) -> ScopusJournalMetrics {
            ScopusJournalMetrics(issn: "x", topPercentile: percentile)
        }
        XCTAssertEqual(metrics(93).quartile, 1)
        XCTAssertEqual(metrics(75).quartile, 1)
        XCTAssertEqual(metrics(74.9).quartile, 2)
        XCTAssertEqual(metrics(50).quartile, 2)
        XCTAssertEqual(metrics(30).quartile, 3)
        XCTAssertEqual(metrics(2).quartile, 4)
        XCTAssertNil(metrics(nil).quartile)
    }

    func testParseAuthorSearch() throws {
        let json = Data("""
        {"search-results":{"opensearch:totalResults":"2","entry":[
          {"dc:identifier":"AUTHOR_ID:7004212771",
           "preferred-name":{"surname":"Smith","given-name":"Jane Q."},
           "affiliation-current":{"affiliation-name":"Example Clinic","affiliation-city":"Rochester"},
           "document-count":"171"},
          {"dc:identifier":"AUTHOR_ID:57190000000",
           "preferred-name":{"surname":"Smith","given-name":"J."},
           "document-count":"3"}
        ]}}
        """.utf8)
        let candidates = ScopusClient.parseAuthorSearch(json)
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates[0].scopusID, "7004212771")
        XCTAssertEqual(candidates[0].name, "Jane Q. Smith")
        XCTAssertEqual(candidates[0].affiliation, "Example Clinic")
        XCTAssertEqual(candidates[0].city, "Rochester")
        XCTAssertEqual(candidates[0].documentCount, 171)
        XCTAssertNil(candidates[1].affiliation)
    }

    func testParseDocumentsPage() {
        let json = Data("""
        {"search-results":{"opensearch:totalResults":"57","entry":[
          {"eid":"2-s2.0-85141234567","prism:doi":"10.1000/EXAMPLE.1",
           "dc:title":"First Paper","prism:coverDate":"2024-06-01"},
          {"eid":"2-s2.0-85149999999","dc:title":"No-DOI Conference Item"}
        ]}}
        """.utf8)
        let page = ScopusClient.parseDocumentsPage(json)
        XCTAssertEqual(page.total, 57)
        XCTAssertEqual(page.docs.count, 2)
        XCTAssertEqual(page.docs[0].doi, "10.1000/EXAMPLE.1")
        XCTAssertNil(page.docs[1].doi)
    }
}

final class ScopusMetricsTests: XCTestCase {
    private func work(_ id: String, doi: String? = nil, issn: String? = nil) -> Work {
        Work(id: id, title: id, citedByCount: 0, doi: doi, venueISSN: issn)
    }

    func testJournalQualityAndQuartileDistribution() {
        let journals = [
            "0001": ScopusJournalMetrics(issn: "0001", citeScore: 12.0, topPercentile: 90),
            "0002": ScopusJournalMetrics(issn: "0002", citeScore: 2.0, topPercentile: 40),
        ]
        let works = [
            work("W1", issn: "0001"), work("W2", issn: "0001"),
            work("W3", issn: "0002"), work("W4", issn: "9999"), work("W5"),
        ]
        let quality = MetricsEngine.journalQuality(works: works, journals: journals)
        XCTAssertEqual(quality.ratedWorks, 3)
        XCTAssertEqual(quality.q1Works, 2)
        XCTAssertEqual(quality.q1Share.map { round($0 * 100) }, 67)
        XCTAssertEqual(quality.medianCiteScore, 12.0, "per-publication median: [12, 12, 2]")

        let data = PersonData(
            profile: AuthorProfile(openalexID: "A1", displayName: "x",
                                   worksCount: 5, citedByCount: 0, countsByYear: []),
            works: works, fetchedAt: Date())
        let distribution = MetricsEngine.quartileDistribution(personData: [data], journals: journals)
        XCTAssertEqual(distribution, [1: 2, 3: 1])
    }

    func testScopusCoverageDiffsByBareDOIBothDirections() {
        let works = [
            work("W1", doi: "https://doi.org/10.1/Both"),
            work("W2", doi: "https://doi.org/10.1/openalex.only"),
            work("W3"),
        ]
        let docs = [
            ScopusDocRef(eid: "e1", doi: "10.1/BOTH"),
            ScopusDocRef(eid: "e2", doi: "10.1/scopus.only"),
            ScopusDocRef(eid: "e3"),
        ]
        let coverage = MetricsEngine.scopusCoverage(works: works, documents: docs)
        XCTAssertEqual(coverage.matched, 1, "case- and prefix-insensitive DOI match")
        XCTAssertEqual(coverage.scopusOnly.map(\.eid), ["e2"])
        XCTAssertEqual(coverage.openalexOnly.map(\.id), ["W2"])
        XCTAssertEqual(coverage.scopusWithoutDOI, 1)
        XCTAssertEqual(coverage.openalexWithoutDOI, 1)
    }
}

final class ClinicalTrialsMatchingTests: XCTestCase {
    func testNameMatchesHandlesDegreesAndInitials() {
        XCTAssertTrue(ClinicalTrialsClient.nameMatches("Jane Q. Smith, MD", member: "Jane Smith"))
        XCTAssertTrue(ClinicalTrialsClient.nameMatches("J. Smith, MD, PhD", member: "Jane Smith"),
                      "matching first initial is enough")
        XCTAssertTrue(ClinicalTrialsClient.nameMatches("Smith, Jane", member: "Smith, Jane"))
        XCTAssertFalse(ClinicalTrialsClient.nameMatches("John Smith, MD", member: "Jane Smith"),
                       "same surname, different first name")
        XCTAssertFalse(ClinicalTrialsClient.nameMatches("Jane Jones", member: "Jane Smith"))
        XCTAssertFalse(ClinicalTrialsClient.nameMatches(nil, member: "Jane Smith"))
    }

    func testTrialsSummary() {
        let trials = [
            ClinicalTrial(nctID: "NCT1", title: "a", status: "RECRUITING",
                          role: "PRINCIPAL_INVESTIGATOR"),
            ClinicalTrial(nctID: "NCT2", title: "b", status: "COMPLETED",
                          role: "STUDY_CHAIR"),
            ClinicalTrial(nctID: "NCT3", title: "c", status: "ACTIVE_NOT_RECRUITING",
                          role: "PRINCIPAL_INVESTIGATOR"),
        ]
        let summary = MetricsEngine.trialsSummary(trials)
        XCTAssertEqual(summary.total, 3)
        XCTAssertEqual(summary.active, 2)
        XCTAssertEqual(summary.asPI, 2)
    }
}

final class DataHealthTests: XCTestCase {
    func testDataHealthFlagsMissingIDsAndUnjoinableWorks() {
        let complete = FacultyMember(name: "Complete Member", scopusID: "123",
                                     orcid: "0000-0001-0000-0001")
        let gappy = FacultyMember(name: "Gappy Member")
        let resolutions = [complete.id: Resolution(
            openalexID: "A1", displayName: "Complete Member", method: .orcid)]
        let data = PersonData(
            profile: AuthorProfile(openalexID: "A1", displayName: "x",
                                   worksCount: 2, citedByCount: 0, countsByYear: []),
            works: [
                Work(id: "W1", title: "has ids", citedByCount: 0, doi: "10.1/x", pmid: "1"),
                Work(id: "W2", title: "bare", citedByCount: 0),
            ],
            fetchedAt: Date())
        let health = MetricsEngine.dataHealth(
            roster: [complete, gappy],
            resolutions: resolutions,
            personData: [complete.id: data])
        XCTAssertEqual(health.gaps.map { $0.member.id }, [gappy.id])
        XCTAssertTrue(health.gaps[0].missingORCID)
        XCTAssertTrue(health.gaps[0].missingScopusID)
        XCTAssertTrue(health.gaps[0].unresolved)
        XCTAssertEqual(health.worksMissingDOI, 1)
        XCTAssertEqual(health.worksMissingPMID, 1)
        XCTAssertEqual(health.totalWorks, 2)
        XCTAssertFalse(health.isClean)
    }
}

final class SnapshotDiffTests: XCTestCase {
    private func snapshot(_ id: String, _ name: String, daysAgo: Int,
                          works: Int, citations: Int, h: Int) -> MetricSnapshot {
        MetricSnapshot(date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
                       openalexID: id, name: name, works: works, citations: citations, hIndex: h)
    }

    func testSnapshotDiffUsesWindowBaselines() {
        let snapshots = [
            snapshot("A1", "Grower", daysAgo: 400, works: 100, citations: 1000, h: 20),
            snapshot("A1", "Grower", daysAgo: 5, works: 110, citations: 1400, h: 22),
            snapshot("A2", "Newly Tracked", daysAgo: 30, works: 50, citations: 500, h: 10),
            snapshot("A2", "Newly Tracked", daysAgo: 5, works: 52, citations: 520, h: 10),
            snapshot("A3", "Off Roster", daysAgo: 5, works: 9, citations: 9, h: 1),
        ]
        let diffs = MetricsEngine.snapshotDiff(
            snapshots: snapshots, authorIDs: ["A1", "A2"],
            from: Calendar.current.date(byAdding: .day, value: -365, to: Date())!,
            to: Date())
        XCTAssertEqual(diffs.map(\.openalexID), ["A1", "A2"], "biggest citation mover first")

        let grower = diffs[0]
        XCTAssertEqual(grower.worksDelta, 10, "baseline = last reading before the window start")
        XCTAssertEqual(grower.citationsDelta, 400)
        XCTAssertEqual(grower.hIndexDelta, 2)
        XCTAssertFalse(grower.newlyTracked)

        let newcomer = diffs[1]
        XCTAssertEqual(newcomer.worksDelta, 2, "baseline = first reading inside the window")
        XCTAssertTrue(newcomer.newlyTracked)
    }
}
