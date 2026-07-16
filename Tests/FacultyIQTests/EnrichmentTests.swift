import XCTest
@testable import FacultyIQ

final class EnrichmentDecodingTests: XCTestCase {
    func testICiteResponseDecodes() throws {
        let json = Data("""
        {"meta":{"limit":1000},"data":[
          {"pmid":23456789,"year":2013,"citation_count":42,"citations_per_year":3.5,
           "nih_percentile":78.2,"relative_citation_ratio":1.91,"apt":0.75},
          {"pmid":11111111,"year":2020,"citation_count":0,"citations_per_year":0.0,
           "nih_percentile":null,"relative_citation_ratio":null,"apt":0.05}
        ]}
        """.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(ICiteResponse.self, from: json)
        XCTAssertEqual(response.data.count, 2)

        let first = response.data[0].metrics
        XCTAssertEqual(first.pmid, "23456789")
        XCTAssertEqual(first.rcr, 1.91)
        XCTAssertEqual(first.nihPercentile, 78.2)
        XCTAssertNil(response.data[1].metrics.rcr, "null RCR should decode as nil")
    }

    func testReporterResponseDecodesAndGroups() throws {
        let json = Data("""
        {"meta":{"total":3,"offset":0,"limit":500},"results":[
          {"fiscal_year":2023,"project_num":"5U24HG007346-08","activity_code":"U24",
           "award_amount":1200000,"project_title":"A Resource",
           "organization":{"org_name":"Example University"},
           "principal_investigators":[{"profile_id":42,"full_name":"Jane Q Smith","is_contact_pi":true}],
           "contact_pi_name":"SMITH, JANE Q",
           "project_start_date":"2016-05-01T00:00:00","project_end_date":"2027-04-30T00:00:00"},
          {"fiscal_year":2024,"project_num":"5U24HG007346-09","activity_code":"U24",
           "award_amount":1300000,"project_title":"A Resource (renamed)",
           "organization":{"org_name":"Example University"},
           "principal_investigators":[{"profile_id":42,"full_name":"Jane Q Smith","is_contact_pi":true}],
           "project_start_date":"2016-05-01T00:00:00","project_end_date":"2027-04-30T00:00:00"},
          {"fiscal_year":2024,"project_num":"1R01AI123456-01A1","activity_code":"R01",
           "award_amount":650000,"project_title":"New R01",
           "organization":{"org_name":"Example University"},
           "principal_investigators":[{"profile_id":42,"full_name":"Jane Q Smith","is_contact_pi":true}]}
        ]}
        """.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(ReporterClient.Response.self, from: json)
        XCTAssertEqual(response.meta?.total, 3)

        let grants = ReporterClient.groupIntoGrants(response.results)
        XCTAssertEqual(grants.count, 2)

        let u24 = try XCTUnwrap(grants.first { $0.coreProjectNum == "U24HG007346" })
        XCTAssertEqual(u24.fiscalYears, [2023, 2024])
        XCTAssertEqual(u24.totalAward, 2_500_000)
        XCTAssertEqual(u24.latestProjectNum, "5U24HG007346-09")
        XCTAssertEqual(u24.title, "A Resource (renamed)")
        XCTAssertEqual(u24.awardsByFiscalYear, [2023: 1_200_000, 2024: 1_300_000])

        let r01 = try XCTUnwrap(grants.first { $0.coreProjectNum == "R01AI123456" })
        XCTAssertEqual(r01.totalAward, 650_000)
    }

    func testCoreProjectNumber() {
        XCTAssertEqual(ReporterClient.coreProjectNumber("5U24HG007346-08"), "U24HG007346")
        XCTAssertEqual(ReporterClient.coreProjectNumber("1R01AI123456-01A1"), "R01AI123456")
        XCTAssertEqual(ReporterClient.coreProjectNumber("R21AI000001"), "R21AI000001")
    }

    func testS2PaperDecodes() throws {
        let json = Data("""
        {"externalIds":{"DOI":"10.1093/CID/ciab001","PubMed":"33000000"},
         "influentialCitationCount":12,
         "authors":[{"authorId":"12345","name":"Sarah Chen"}]}
        """.utf8)
        let paper = try JSONDecoder().decode(S2Paper.self, from: json)
        XCTAssertEqual(paper.externalIds?.doi?.bareDOI, "10.1093/cid/ciab001")
        XCTAssertEqual(paper.influentialCitationCount, 12)
        XCTAssertEqual(paper.authors?.first?.authorId, "12345")
    }

    func testEnrichmentRoundTripsAndOldStateDecodes() throws {
        let enrichment = Enrichment(
            icite: ICiteData(byPMID: ["1": WorkCitationMetrics(pmid: "1", rcr: 2.0,
                                                               nihPercentile: 90, citationsPerYear: 5, apt: 0.9)],
                             fetchedAt: Date()),
            grants: GrantData(grants: [], confirmedProfileID: 42,
                              confirmedPIName: "Jane Q Smith", fetchedAt: Date()),
            semanticScholar: nil)
        let data = try JSONEncoder().encode(["k": enrichment])
        let decoded = try JSONDecoder().decode([String: Enrichment].self, from: data)
        XCTAssertEqual(decoded["k"], enrichment)

        // Pre-enrichment payloads (no `enrichment`, works without `pmid`) still decode.
        struct OldState: Codable { var enrichment: [String: Enrichment]? }
        XCTAssertNil(try JSONDecoder().decode(OldState.self, from: Data("{}".utf8)).enrichment)
        let oldWork = Data("""
        {"id":"W1","title":"T","citedByCount":3}
        """.utf8)
        XCTAssertNil(try JSONDecoder().decode(Work.self, from: oldWork).pmid)
    }
}

final class EnrichmentMatchingTests: XCTestCase {
    func testS2NameMatching() {
        XCTAssertTrue(SemanticScholarClient.nameMatches("Sarah Chen", "S. Chen"))
        XCTAssertTrue(SemanticScholarClient.nameMatches("sarah chen", "Sarah Chen"))
        XCTAssertTrue(SemanticScholarClient.nameMatches("José García", "Jose Garcia"))
        XCTAssertFalse(SemanticScholarClient.nameMatches("Sarah Chen", "Michael Chen"))
        XCTAssertFalse(SemanticScholarClient.nameMatches("Sarah Chen", "Sarah Cohen"))
    }

    func testReporterRowNameMatching() {
        XCTAssertTrue(ReporterClient.rowNameMatches("SMITH, JANE Q", query: "Jane Smith"))
        XCTAssertTrue(ReporterClient.rowNameMatches("SMITH, JANE Q", query: "Smith, Jane"))
        XCTAssertTrue(ReporterClient.rowNameMatches("Jane Q Smith", query: "Smith"))
        XCTAssertFalse(ReporterClient.rowNameMatches("Jane Q Jones", query: "Jane Smith"))
        XCTAssertFalse(ReporterClient.rowNameMatches(nil, query: "Smith"))
    }

    func testReporterPINameCriteria() {
        XCTAssertEqual(ReporterClient.piNameCriteria(from: "Smith, Jane Q"),
                       .init(anyName: nil, firstName: "Jane", lastName: "Smith"))
        XCTAssertEqual(ReporterClient.piNameCriteria(from: "Jane Q Smith"),
                       .init(anyName: nil, firstName: "Jane", lastName: "Smith"))
        XCTAssertEqual(ReporterClient.piNameCriteria(from: "Smith"),
                       .init(anyName: "Smith", firstName: nil, lastName: nil))
    }
}

final class EnrichmentMetricsTests: XCTestCase {
    private func work(_ id: String, pmid: String?, doi: String? = nil) -> Work {
        Work(id: id, title: id, year: 2020, date: nil, type: nil, citedByCount: 0,
             doi: doi, pmid: pmid, isOA: nil, oaStatus: nil, venue: nil, authors: nil)
    }

    func testMeanRCR() {
        let icite = ICiteData(byPMID: [
            "1": WorkCitationMetrics(pmid: "1", rcr: 1.0, nihPercentile: nil, citationsPerYear: nil, apt: nil),
            "2": WorkCitationMetrics(pmid: "2", rcr: 3.0, nihPercentile: nil, citationsPerYear: nil, apt: nil),
            "3": WorkCitationMetrics(pmid: "3", rcr: nil, nihPercentile: nil, citationsPerYear: nil, apt: nil),
        ], fetchedAt: Date())
        let works = [work("W1", pmid: "1"), work("W2", pmid: "2"),
                     work("W3", pmid: "3"), work("W4", pmid: nil)]
        XCTAssertEqual(MetricsEngine.meanRCR(works: works, icite: icite), 2.0)
        XCTAssertNil(MetricsEngine.meanRCR(works: works, icite: nil))
        XCTAssertNil(MetricsEngine.meanRCR(works: [work("W4", pmid: nil)], icite: icite))
    }

    func testMeanAPTAndNilGating() {
        let icite = ICiteData(byPMID: [
            "1": WorkCitationMetrics(pmid: "1", rcr: nil, nihPercentile: nil, citationsPerYear: nil, apt: 0.95),
            "2": WorkCitationMetrics(pmid: "2", rcr: nil, nihPercentile: nil, citationsPerYear: nil, apt: 0.05),
            "3": WorkCitationMetrics(pmid: "3", rcr: 2.0, nihPercentile: nil, citationsPerYear: nil, apt: nil),
        ], fetchedAt: Date())
        let works = [work("W1", pmid: "1"), work("W2", pmid: "2"),
                     work("W3", pmid: "3"), work("W4", pmid: nil)]
        XCTAssertEqual(MetricsEngine.meanAPT(works: works, icite: icite)!, 0.5, accuracy: 0.001)
        XCTAssertNil(MetricsEngine.meanAPT(works: works, icite: nil))
        XCTAssertNil(MetricsEngine.meanAPT(works: [work("W3", pmid: "3")], icite: icite),
                     "RCR without APT must not produce an APT")
    }

    func testTopTranslationalRanksAndGates() {
        let alice = FacultyMember(name: "Alice")
        let bob = FacultyMember(name: "Bob")
        let carol = FacultyMember(name: "Carol")   // no iCite data
        func data(_ works: [Work]) -> PersonData {
            PersonData(profile: AuthorProfile(openalexID: "A", displayName: "", worksCount: 0,
                                              citedByCount: 0, hIndex: nil, i10Index: nil,
                                              affiliation: nil, countsByYear: []),
                       works: works, fetchedAt: Date())
        }
        func icite(_ apts: [String: Double]) -> ICiteData {
            ICiteData(byPMID: apts.mapValues {
                WorkCitationMetrics(pmid: "", rcr: nil, nihPercentile: nil,
                                    citationsPerYear: nil, apt: $0)
            }, fetchedAt: Date())
        }
        let personData = [alice.id: data([work("W1", pmid: "1"), work("W2", pmid: "2")]),
                          bob.id: data([work("W3", pmid: "3")]),
                          carol.id: data([work("W4", pmid: "4")])]
        let enrichment = [alice.id: Enrichment(icite: icite(["1": 0.9, "2": 0.5])),
                          bob.id: Enrichment(icite: icite(["3": 0.95]))]

        let top = MetricsEngine.topTranslational(roster: [alice, bob, carol],
                                                 personData: personData,
                                                 enrichment: enrichment)
        XCTAssertEqual(top.map(\.name), ["Bob", "Alice"], "ranked by mean APT")
        XCTAssertEqual(top[1].meanAPT, 0.7, accuracy: 0.001)
        XCTAssertEqual(top[1].highAPTWorks, 1, "only the 0.9 work clears 0.75")
        XCTAssertEqual(top[1].scoredWorks, 2)

        XCTAssertTrue(MetricsEngine.topTranslational(roster: [carol], personData: personData,
                                                     enrichment: [:]).isEmpty,
                      "no iCite data anywhere → empty, so views can gate on isEmpty")
        XCTAssertNil(MetricsEngine.medianAPT(roster: [carol], personData: personData,
                                             enrichment: [:]))
    }

    func testFundingSummary() {
        let year = MetricsEngine.currentYear
        let grants = [
            Grant(coreProjectNum: "R01A", latestProjectNum: "5R01A-04", title: "Active R01",
                  activityCode: "R01", fiscalYears: [year - 2, year - 1, year],
                  totalAward: 1_500_000, startDate: nil, endDate: "\(year + 2)-06-30", orgName: nil),
            Grant(coreProjectNum: "K08B", latestProjectNum: "5K08B-05", title: "Ended K",
                  activityCode: "K08", fiscalYears: [year - 6, year - 5],
                  totalAward: 400_000, startDate: nil, endDate: "\(year - 4)-06-30", orgName: nil),
        ]
        let summary = MetricsEngine.fundingSummary(grants)
        XCTAssertEqual(summary.totalAwarded, 1_900_000)
        XCTAssertEqual(summary.grantCount, 2)
        XCTAssertEqual(summary.activeCount, 1)
        XCTAssertEqual(summary.r01EquivalentCount, 1)
    }

    func testGrantsCSV() {
        let member = FacultyMember(name: "Smith, \"Jane\"")
        let enrichment = [member.id: Enrichment(
            icite: nil,
            grants: GrantData(grants: [
                Grant(coreProjectNum: "R01A", latestProjectNum: "5R01A-04", title: "Study, with comma",
                      activityCode: "R01", fiscalYears: [2022, 2023], totalAward: 900_000,
                      startDate: nil, endDate: nil, orgName: "Example U"),
            ], confirmedProfileID: 1, confirmedPIName: nil, fetchedAt: Date()),
            semanticScholar: nil)]
        let csv = MetricsEngine.grantsCSV(roster: [member], enrichment: enrichment)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains("\"Study, with comma\""))
        XCTAssertTrue(lines[1].contains("900000"))
    }
}

/// Live enrichment API tests — network-dependent, keyless public endpoints.
final class EnrichmentIntegrationTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FACULTYIQ_LIVE"] == "1",
                          "Set FACULTYIQ_LIVE=1 to run live API tests")
    }

    func testICiteLive() async throws {
        let metrics = try await ICiteClient.shared.metrics(pmids: ["23456789"])
        let pub = try XCTUnwrap(metrics.first)
        XCTAssertEqual(pub.pmid, "23456789")
        XCTAssertNotNil(pub.rcr)
    }

    func testReporterLive() async throws {
        let candidates = try await ReporterClient.shared.searchPIs(name: "Collins, Francis")
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.contains { $0.projectCount > 0 })
    }

    func testSemanticScholarLive() async throws {
        do {
            var member = FacultyMember(name: "Carberry")
            member.semanticScholarID = "2262347271"
            let s2 = try await SemanticScholarClient.shared.enrich(
                member: member, resolvedName: "Josiah Carberry", works: [])
            XCTAssertEqual(s2.authorID, "2262347271")
        } catch SemanticScholarClient.ClientError.rateLimited {
            throw XCTSkip("Semantic Scholar shared pool is throttled right now")
        }
    }
}
