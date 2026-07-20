import XCTest
@testable import FacultyIQ

final class CSVParserTests: XCTestCase {
    func testSimpleRows() {
        let rows = CSVParser.parse("a,b,c\n1,2,3\n")
        XCTAssertEqual(rows, [["a", "b", "c"], ["1", "2", "3"]])
    }

    func testQuotedFieldsWithCommasAndQuotes() {
        let rows = CSVParser.parse("name,note\n\"Smith, Jane\",\"said \"\"hi\"\"\"\n")
        XCTAssertEqual(rows[1], ["Smith, Jane", "said \"hi\""])
    }

    func testNewlineInsideQuotes() {
        let rows = CSVParser.parse("a,b\n\"line1\nline2\",x\n")
        XCTAssertEqual(rows[1], ["line1\nline2", "x"])
    }

    func testCRLFAndTrailingEmptyLine() {
        let rows = CSVParser.parse("a,b\r\n1,2\r\n\r\n")
        XCTAssertEqual(rows.count, 2)
    }
}

final class RosterImporterTests: XCTestCase {
    func testSampleRosterImports() throws {
        let members = try RosterImporter.importRoster(fromText: sampleRosterCSV)
        XCTAssertEqual(members.count, 15)

        let chen = try XCTUnwrap(members.first { $0.name == "Sarah Chen" })
        XCTAssertEqual(chen.rank, "Associate Professor")
        XCTAssertEqual(chen.division, "Infectious Diseases")
        XCTAssertEqual(chen.orcid, "0000-0002-1825-0097")
        XCTAssertEqual(chen.scopusID, "7004567890123")
        XCTAssertEqual(chen.hireYear, 2014)
        XCTAssertEqual(chen.lastPromotionYear, 2021)
        XCTAssertEqual(chen.selfReportedPubs, 45)
    }

    func testNameColumnAvoidsUsername() {
        let header = ["Id", "What is your Google Scholar username?", "Name", "Email"]
        let mapping = RosterImporter.mapColumns(header)
        XCTAssertEqual(mapping[.name], 2)
        XCTAssertEqual(mapping[.scholarID], 1)
    }

    func testDivisionColumnMapping() {
        XCTAssertEqual(RosterImporter.mapColumns(["Name", "Division"])[.division], 1)
        XCTAssertEqual(RosterImporter.mapColumns(["Name", "Department"])[.division], 1)
        XCTAssertEqual(RosterImporter.mapColumns(["Name", "What section are you in?"])[.division], 1)
        XCTAssertNil(RosterImporter.mapColumns(["Name", "Email"])[.division])
    }

    func testStatusColumnAndParsing() throws {
        let csv = """
        Name,Rank,Status
        Alice,Full Professor,Emeritus Professor
        Bob,Assistant Professor,active
        Cara,Full Professor,Retired 2024
        Dan,Instructor,
        """
        let members = try RosterImporter.importRoster(fromText: csv)
        XCTAssertEqual(members.map(\.status), [.emeritus, .active, .retired, nil])
        XCTAssertEqual(members.map(\.isActive), [false, true, false, true])
    }

    func testCleanORCIDStripsURL() {
        XCTAssertEqual(RosterImporter.cleanORCID("https://orcid.org/0000-0001-2345-6789"),
                       "0000-0001-2345-6789")
        XCTAssertEqual(RosterImporter.cleanORCID("0000-0001-2345-6789"),
                       "0000-0001-2345-6789")
    }
}

final class MetricsEngineTests: XCTestCase {
    func testHIndex() {
        XCTAssertEqual(MetricsEngine.hIndex(citations: []), 0)
        XCTAssertEqual(MetricsEngine.hIndex(citations: [0, 0]), 0)
        XCTAssertEqual(MetricsEngine.hIndex(citations: [10, 8, 5, 4, 3]), 4)
        XCTAssertEqual(MetricsEngine.hIndex(citations: [25, 8, 5, 3, 3]), 3)
        XCTAssertEqual(MetricsEngine.hIndex(citations: [1, 1, 1]), 1)
    }

    func testI10Index() {
        XCTAssertEqual(MetricsEngine.i10Index(citations: [12, 10, 9, 0]), 2)
    }

    func testMedian() {
        XCTAssertEqual([1.0, 3.0, 2.0].median, 2.0)
        XCTAssertEqual([1.0, 2.0, 3.0, 4.0].median, 2.5)
        XCTAssertEqual([Double]().median, 0)
    }

    func testPercentile() {
        XCTAssertEqual([1.0, 2.0, 3.0, 4.0, 5.0].percentile(0.25), 2.0)
        XCTAssertEqual([1.0, 2.0, 3.0, 4.0].percentile(0.25), 1.75)
        XCTAssertEqual([10.0].percentile(0.25), 10.0)
        XCTAssertEqual([1.0, 2.0].percentile(0), 1.0)
        XCTAssertEqual([1.0, 2.0].percentile(1), 2.0)
        XCTAssertEqual([Double]().percentile(0.25), 0)
        XCTAssertEqual([1.0, 2.0, 3.0].percentile(0.5), [1.0, 2.0, 3.0].median)
    }

    func testRankParsing() {
        XCTAssertEqual(AcademicRank.parse("Associate Professor"), .associate)
        XCTAssertEqual(AcademicRank.parse("assistant prof"), .assistant)
        XCTAssertEqual(AcademicRank.parse("Professor"), .full)
        XCTAssertEqual(AcademicRank.parse("Instructor"), .instructor)
        XCTAssertNil(AcademicRank.parse("Research Faculty"))
    }

    func testPromotionCandidates() {
        func metrics(_ name: String, rank: AcademicRank, works: Int, cites: Int, h: Int) -> PersonMetrics {
            PersonMetrics(
                memberID: UUID(), name: name, rank: rank, rawRank: rank.label,
                worksCount: works, citations: cites, hIndex: h, i10Index: 0,
                citationsPerWork: 0, worksPerYear: 0, oaPercent: nil,
                recentWorks5y: 0, firstPubYear: nil, careerYears: 1)
        }
        let all = [
            metrics("Strong Assoc", rank: .associate, works: 120, cites: 5000, h: 30),
            metrics("Typical Assoc", rank: .associate, works: 40, cites: 900, h: 12),
            metrics("Full A", rank: .full, works: 100, cites: 4000, h: 25),
            metrics("Full B", rank: .full, works: 140, cites: 6000, h: 35),
        ]
        let benchmarks = MetricsEngine.rankBenchmarks(metrics: all)
        let candidates = MetricsEngine.promotionCandidates(metrics: all, benchmarks: benchmarks)
        XCTAssertEqual(candidates.map(\.metrics.name), ["Strong Assoc"])
        XCTAssertEqual(candidates.first?.targetRank, .full)
    }

    func testPromotionCandidatesConfigurable() {
        func metrics(_ name: String, rank: AcademicRank, works: Int, cites: Int, h: Int) -> PersonMetrics {
            PersonMetrics(
                memberID: UUID(), name: name, rank: rank, rawRank: rank.label,
                worksCount: works, citations: cites, hIndex: h, i10Index: 0,
                citationsPerWork: 0, worksPerYear: 0, oaPercent: nil,
                recentWorks5y: 0, firstPubYear: nil, careerYears: 1)
        }
        // "Border" sits exactly at the .full cohort's median on all three
        // metrics — comfortably clears the default 25th-percentile/2-of-3
        // bar, but clears none of the three at the median/3-of-3 bar.
        let all = [
            metrics("Border", rank: .associate, works: 100, cites: 4000, h: 25),
            metrics("Full A", rank: .full, works: 80, cites: 3000, h: 20),
            metrics("Full B", rank: .full, works: 100, cites: 4000, h: 25),
            metrics("Full C", rank: .full, works: 120, cites: 5000, h: 30),
            metrics("Full D", rank: .full, works: 140, cites: 6000, h: 35),
        ]

        let defaultBenchmarks = MetricsEngine.rankBenchmarks(metrics: all)
        let defaultCandidates = MetricsEngine.promotionCandidates(metrics: all, benchmarks: defaultBenchmarks)
        XCTAssertEqual(defaultCandidates.map(\.metrics.name), ["Border"])

        let strictBenchmarks = MetricsEngine.rankBenchmarks(metrics: all, targetPercentile: 0.5)
        XCTAssertEqual(strictBenchmarks.first { $0.rank == .full }?.targetPercentile, 0.5)
        let strictCandidates = MetricsEngine.promotionCandidates(
            metrics: all, benchmarks: strictBenchmarks, requiredCount: 3)
        XCTAssertTrue(strictCandidates.isEmpty)
    }
}

final class CoauthorNetworkTests: XCTestCase {
    private func member(_ name: String) -> FacultyMember {
        FacultyMember(name: name)
    }

    private func resolution(_ authorID: String) -> Resolution {
        Resolution(openalexID: authorID, displayName: authorID, method: .manual)
    }

    private func work(_ id: String, authors: [String]? = nil) -> Work {
        Work(id: id, title: id, year: 2020, date: nil, type: nil, citedByCount: 0,
             doi: nil, isOA: nil, oaStatus: nil, venue: nil,
             authors: authors.map { $0.map { WorkAuthor(openalexID: $0, displayName: $0) } })
    }

    private func personData(works: [Work]) -> PersonData {
        PersonData(
            profile: AuthorProfile(openalexID: "A0", displayName: "", worksCount: works.count,
                                   citedByCount: 0, hIndex: nil, i10Index: nil,
                                   affiliation: nil, countsByYear: []),
            works: works, fetchedAt: Date())
    }

    func testSharedWorkInBothListsCountsOnce() {
        let (a, b) = (member("Alice"), member("Bob"))
        let shared = work("W1", authors: ["A1", "A2"])
        let network = MetricsEngine.coauthorNetwork(
            roster: [a, b],
            resolutions: [a.id: resolution("A1"), b.id: resolution("A2")],
            personData: [a.id: personData(works: [shared, work("W2", authors: ["A1"])]),
                         b.id: personData(works: [shared])])
        XCTAssertEqual(network.edges.count, 1)
        XCTAssertEqual(network.edges.first?.weight, 1)
        XCTAssertFalse(network.staleAuthorData)
    }

    func testCanonicalPairOrdering() {
        let (a, b) = (member("Alice"), member("Bob"))
        let network = MetricsEngine.coauthorNetwork(
            roster: [b, a], // input order should not matter
            resolutions: [a.id: resolution("A1"), b.id: resolution("A2")],
            personData: [a.id: personData(works: [work("W1", authors: [])]),
                         b.id: personData(works: [work("W1", authors: [])])])
        let edge = try! XCTUnwrap(network.edges.first)
        XCTAssertLessThan(edge.memberA.uuidString, edge.memberB.uuidString)
    }

    func testAuthorlessWorksStillEdgeViaOwnershipUnion() {
        let (a, b) = (member("Alice"), member("Bob"))
        let network = MetricsEngine.coauthorNetwork(
            roster: [a, b],
            resolutions: [a.id: resolution("A1"), b.id: resolution("A2")],
            personData: [a.id: personData(works: [work("W1")]),
                         b.id: personData(works: [work("W1")])])
        XCTAssertEqual(network.edges.count, 1)
        XCTAssertTrue(network.staleAuthorData)
    }

    func testAuthorshipMatchRecoversWorkMissingFromOneList() {
        // W1 only appears in Alice's list (e.g. cut off by Bob's fetch limit),
        // but Bob's resolved ID is in its author list.
        let (a, b) = (member("Alice"), member("Bob"))
        let network = MetricsEngine.coauthorNetwork(
            roster: [a, b],
            resolutions: [a.id: resolution("A1"), b.id: resolution("A2")],
            personData: [a.id: personData(works: [work("W1", authors: ["A1", "A2"])]),
                         b.id: personData(works: [work("W9", authors: ["A2"])])])
        XCTAssertEqual(network.edges.count, 1)
    }

    func testThreeMembersOnOneWorkMakeThreeEdges() {
        let (a, b, c) = (member("Alice"), member("Bob"), member("Cara"))
        let shared = work("W1", authors: ["A1", "A2", "A3"])
        let network = MetricsEngine.coauthorNetwork(
            roster: [a, b, c],
            resolutions: [a.id: resolution("A1"), b.id: resolution("A2"), c.id: resolution("A3")],
            personData: [a.id: personData(works: [shared]),
                         b.id: personData(works: [shared]),
                         c.id: personData(works: [shared])])
        XCTAssertEqual(network.edges.count, 3)
        XCTAssertEqual(network.nodes.map(\.degree), [2, 2, 2])
        XCTAssertEqual(network.nodes.map(\.sharedWorks), [2, 2, 2])
    }

    func testUnresolvedOrUnfetchedMembersExcluded() {
        let (a, b, c) = (member("Alice"), member("NoData"), member("NoResolution"))
        let network = MetricsEngine.coauthorNetwork(
            roster: [a, b, c],
            resolutions: [a.id: resolution("A1"), b.id: resolution("A2")],
            personData: [a.id: personData(works: [work("W1", authors: ["A1", "A2", "A3"])]),
                         c.id: personData(works: [work("W1")])])
        XCTAssertEqual(network.nodes.map(\.name), ["Alice"])
        XCTAssertTrue(network.edges.isEmpty)
    }

    func testNodesCarryParsedRank() {
        var a = member("Alice")
        a.rank = "Associate Professor"
        var b = member("Bob")
        b.rank = "Adjunct Wizard"
        let network = MetricsEngine.coauthorNetwork(
            roster: [a, b],
            resolutions: [a.id: resolution("A1"), b.id: resolution("A2")],
            personData: [a.id: personData(works: []), b.id: personData(works: [])])
        XCTAssertEqual(network.nodes.first { $0.name == "Alice" }?.rank, .associate)
        XCTAssertNil(network.nodes.first { $0.name == "Bob" }?.rank ?? nil)
    }

    func testWeightsAccumulateAcrossWorks() {
        let (a, b) = (member("Alice"), member("Bob"))
        let works = [work("W1", authors: ["A1", "A2"]), work("W2", authors: ["A1", "A2"])]
        let network = MetricsEngine.coauthorNetwork(
            roster: [a, b],
            resolutions: [a.id: resolution("A1"), b.id: resolution("A2")],
            personData: [a.id: personData(works: works), b.id: personData(works: works)])
        XCTAssertEqual(network.edges.first?.weight, 2)
    }

    func testCoauthorshipCSV() {
        let (a, b) = (member("Smith, Jane"), member("Bob"))
        let network = MetricsEngine.coauthorNetwork(
            roster: [a, b],
            resolutions: [a.id: resolution("A1"), b.id: resolution("A2")],
            personData: [a.id: personData(works: [work("W1", authors: [])]),
                         b.id: personData(works: [work("W1", authors: [])])])
        let csv = MetricsEngine.coauthorshipCSV(network: network)
        XCTAssertTrue(csv.hasPrefix("Member A,Member B,Shared Works\n"))
        XCTAssertTrue(csv.contains("\"Smith, Jane\""))
        XCTAssertTrue(csv.contains(",1\n"))
    }
}

final class ExternalCollaboratorTests: XCTestCase {
    private func member(_ name: String, division: String? = nil) -> FacultyMember {
        FacultyMember(name: name, division: division)
    }

    private func resolution(_ authorID: String, name: String = "") -> Resolution {
        Resolution(openalexID: authorID, displayName: name.isEmpty ? authorID : name, method: .manual)
    }

    private func work(_ id: String, year: Int = 2020, authors: [(String, String)]) -> Work {
        Work(id: id, title: id, year: year, date: nil, type: nil, citedByCount: 0,
             doi: nil, isOA: nil, oaStatus: nil, venue: nil,
             authors: authors.map { WorkAuthor(openalexID: $0.0, displayName: $0.1) })
    }

    private func personData(works: [Work]) -> PersonData {
        PersonData(
            profile: AuthorProfile(openalexID: "A0", displayName: "", worksCount: works.count,
                                   citedByCount: 0, hIndex: nil, i10Index: nil,
                                   affiliation: nil, countsByYear: []),
            works: works, fetchedAt: Date())
    }

    func testAggregatesAcrossMembersAndDedupesSharedWorks() {
        let (a, b) = (member("Alice"), member("Bob"))
        // X1 appears on a shared work in both members' lists: counts once.
        let shared = work("W1", year: 2021, authors: [("A1", "Alice"), ("A2", "Bob"), ("X1", "Xena Ruiz")])
        let solo = work("W2", year: 2023, authors: [("A2", "Bob"), ("X1", "Xena Ruiz")])
        let externals = MetricsEngine.externalCollaborators(
            roster: [a, b],
            resolutions: [a.id: resolution("A1"), b.id: resolution("A2")],
            personData: [a.id: personData(works: [shared]),
                         b.id: personData(works: [shared, solo])])
        XCTAssertEqual(externals.count, 1)
        let x = externals[0]
        XCTAssertEqual(x.openalexID, "X1")
        XCTAssertEqual(x.sharedWorks, 2)
        XCTAssertEqual(x.partnerCount, 2)
        XCTAssertEqual(x.lastSharedYear, 2023)
        XCTAssertEqual(x.partners.first?.name, "Bob")
        XCTAssertEqual(x.partners.first?.weight, 2)
    }

    func testResolvedRosterMembersNeverExternal() {
        let (a, b) = (member("Alice", division: "Cardiology"), member("Bob", division: "GIM"))
        let externals = MetricsEngine.externalCollaborators(
            roster: [a],                       // division-filtered to Alice only
            fullRoster: [a, b],
            resolutions: [a.id: resolution("A1"), b.id: resolution("A2")],
            personData: [a.id: personData(works: [work("W1", authors: [("A1", "Alice"), ("A2", "Bob")])])])
        XCTAssertTrue(externals.isEmpty)
    }

    func testUnresolvedRosterMemberExcludedByNameMatch() {
        let (a, b) = (member("Alice"), member("Doe, John"))
        let externals = MetricsEngine.externalCollaborators(
            roster: [a, b],
            resolutions: [a.id: resolution("A1")],  // John never resolved
            personData: [a.id: personData(works: [
                work("W1", authors: [("A1", "Alice"), ("A9", "John A. Doe"), ("X1", "Xena Ruiz")])
            ])])
        XCTAssertEqual(externals.map(\.openalexID), ["X1"])
    }

    func testKeepsLongestNameVariant() {
        let a = member("Alice")
        let externals = MetricsEngine.externalCollaborators(
            roster: [a],
            resolutions: [a.id: resolution("A1")],
            personData: [a.id: personData(works: [
                work("W1", authors: [("A1", "Alice"), ("X1", "X. Ruiz")]),
                work("W2", authors: [("A1", "Alice"), ("X1", "Xena B. Ruiz")]),
            ])])
        XCTAssertEqual(externals.first?.displayName, "Xena B. Ruiz")
    }

    func testNameKeyNormalization() {
        XCTAssertEqual(MetricsEngine.nameKey("Doe, John A."), MetricsEngine.nameKey("John Doe"))
        XCTAssertEqual(MetricsEngine.nameKey("José García"), MetricsEngine.nameKey("Jose Garcia"))
        XCTAssertNotEqual(MetricsEngine.nameKey("John Doe"), MetricsEngine.nameKey("Jane Doe"))
    }

    func testCSV() {
        let a = member("Alice")
        let externals = MetricsEngine.externalCollaborators(
            roster: [a],
            resolutions: [a.id: resolution("A1")],
            personData: [a.id: personData(works: [
                work("W1", year: 2022, authors: [("A1", "Alice"), ("X1", "Ruiz, Xena")])
            ])])
        let csv = MetricsEngine.externalCollaboratorsCSV(externals)
        XCTAssertTrue(csv.hasPrefix("Name,OpenAlex ID,Shared Works,Roster Partners,Partner Names,Last Shared Year\n"))
        XCTAssertTrue(csv.contains("\"Ruiz, Xena\",X1,1,1,Alice (1),2022\n"))
    }
}

final class AuditTests: XCTestCase {
    private func work(_ id: String, year: Int = 2020, cites: Int = 0, field: String? = nil,
                      retracted: Bool? = nil, authors: [WorkAuthor]? = nil) -> Work {
        Work(id: id, title: id, year: year, date: nil, type: nil, citedByCount: cites,
             doi: nil, isOA: nil, oaStatus: nil, venue: nil, authors: authors,
             topicField: field, isRetracted: retracted)
    }

    private func personData(works: [Work], profileWorks: Int? = nil,
                            profileCites: Int? = nil, hIndex: Int? = nil) -> PersonData {
        PersonData(
            profile: AuthorProfile(openalexID: "A1", displayName: "", worksCount: profileWorks ?? works.count,
                                   citedByCount: profileCites ?? works.map(\.citedByCount).reduce(0, +),
                                   hIndex: hIndex, i10Index: nil, affiliation: nil, countsByYear: []),
            works: works, fetchedAt: Date())
    }

    // MARK: Exclusions

    func testApplyingExclusionsAdjustsCountsAndRecomputesIndexes() {
        let data = personData(
            works: [work("W1", cites: 100), work("W2", cites: 10), work("W3", cites: 1)],
            profileWorks: 3, profileCites: 111, hIndex: 3)
        let result = MetricsEngine.applyingExclusions(data, excluded: ["W1"])
        XCTAssertEqual(result.works.map(\.id), ["W2", "W3"])
        XCTAssertEqual(result.profile.worksCount, 2)
        XCTAssertEqual(result.profile.citedByCount, 11)
        XCTAssertNil(result.profile.hIndex)  // forces local recomputation
        XCTAssertEqual(MetricsEngine.effectiveHIndex(result), 1)  // h of [10, 1]
    }

    func testApplyingExclusionsNoOpWhenEmpty() {
        let data = personData(works: [work("W1", cites: 5)], hIndex: 1)
        let result = MetricsEngine.applyingExclusions(data, excluded: [])
        XCTAssertEqual(result.profile.hIndex, 1)
        XCTAssertEqual(result.works.count, 1)
    }

    // MARK: Misattribution heuristic

    func testSuspectWorksFlagRareFields() {
        // 12 medicine + 1 economics: the isolated excursion is flagged.
        let works = (1...12).map { work("M\($0)", field: "Medicine") }
            + [work("E1", field: "Economics")]
        XCTAssertEqual(MetricsEngine.suspectWorkIDs(works: works), ["E1"])
        // A field with real presence (3 of 15) is not rare, so not flagged.
        let mixed = (1...12).map { work("M\($0)", field: "Medicine") }
            + (1...3).map { work("I\($0)", field: "Immunology and Microbiology") }
        XCTAssertTrue(MetricsEngine.suspectWorkIDs(works: mixed).isEmpty)
        // Fewer than 10 tagged works: too little signal.
        XCTAssertTrue(MetricsEngine.suspectWorkIDs(works: Array(works.prefix(9))).isEmpty)
    }

    // MARK: Retractions

    func testRetractedWorks() {
        let member = FacultyMember(name: "Alice")
        let data = personData(works: [work("W1", retracted: true), work("W2", retracted: false), work("W3")])
        let found = MetricsEngine.retractedWorks(roster: [member], personData: [member.id: data])
        XCTAssertEqual(found.map(\.work.id), ["W1"])
        XCTAssertEqual(found.first?.memberName, "Alice")
    }

    // MARK: Authorship positions

    func testAuthorshipSummaryAndSeries() {
        let mine = { (position: AuthorPosition, corresponding: Bool) in
            WorkAuthor(openalexID: "A1", displayName: "Me", position: position,
                       isCorresponding: corresponding)
        }
        let data = personData(works: [
            work("W1", year: 2023, authors: [mine(.first, true)]),
            work("W2", year: 2024, authors: [mine(.last, false)]),
            work("W3", year: 2024, authors: [mine(.last, true)]),
            work("W4", year: 2024, authors: [WorkAuthor(openalexID: "A1", displayName: "Me")]), // untracked
        ])
        let summary = MetricsEngine.authorshipSummary(data: data, authorID: "A1")
        XCTAssertEqual(summary.tracked, 3)
        XCTAssertEqual(summary.first, 1)
        XCTAssertEqual(summary.last, 2)
        XCTAssertEqual(summary.corresponding, 2)

        let series = MetricsEngine.authorshipByYear(data: data, authorID: "A1")
        XCTAssertEqual(series.first { $0.year == 2024 && $0.position == .last }?.count, 2)
        XCTAssertEqual(series.first { $0.year == 2023 && $0.position == .first }?.count, 1)
    }

    // MARK: Percentile rank

    func testPercentileRank() {
        XCTAssertEqual(MetricsEngine.percentileRank(of: 5, in: [1, 2, 3, 4]), 100)
        XCTAssertEqual(MetricsEngine.percentileRank(of: 0, in: [1, 2, 3, 4]), 0)
        XCTAssertEqual(MetricsEngine.percentileRank(of: 3, in: [1, 2, 3, 4]), 62.5) // 2 below + half a tie
        XCTAssertEqual(MetricsEngine.percentileRank(of: 1, in: []), 0)
    }

    // MARK: Collaboration suggestions

    func testCollaborationSuggestionsSkipConnectedPairs() {
        let (a, b, c) = (FacultyMember(name: "Alice"), FacultyMember(name: "Bob"), FacultyMember(name: "Cara"))
        func topical(_ prefix: String, _ topic: String, _ n: Int) -> [Work] {
            (1...n).map { i in
                Work(id: "\(prefix)\(i)", title: "", year: 2020, date: nil, type: nil,
                     citedByCount: 0, doi: nil, isOA: nil, oaStatus: nil, venue: nil,
                     topicName: topic)
            }
        }
        let personData = [
            a.id: self.personData(works: topical("A", "Endocarditis", 3)),
            b.id: self.personData(works: topical("B", "Endocarditis", 4)),
            c.id: self.personData(works: topical("C", "Endocarditis", 5)),
        ]
        // Alice–Bob already co-publish; only pairs with Cara are suggested.
        let sorted = [a.id, b.id].sorted { $0.uuidString < $1.uuidString }
        let network = CoauthorNetwork(
            nodes: [], edges: [CoauthorEdge(memberA: sorted[0], memberB: sorted[1], weight: 2)],
            staleAuthorData: false)
        let suggestions = MetricsEngine.collaborationSuggestions(
            roster: [a, b, c], personData: personData, network: network)
        XCTAssertEqual(suggestions.count, 2)
        XCTAssertTrue(suggestions.allSatisfy { $0.nameA == "Cara" || $0.nameB == "Cara" })
        XCTAssertEqual(suggestions.first?.sharedTopics, ["Endocarditis"])
        XCTAssertEqual(suggestions.map(\.score).max(), 4)  // Bob(4) vs Cara(5) → min 4
    }

    // MARK: Institution rollup

    func testInstitutionRollupGroupsByFetchedAffiliation() {
        let externals = [
            ExternalCollaborator(openalexID: "X1", displayName: "Xena", sharedWorks: 5, partners: []),
            ExternalCollaborator(openalexID: "X2", displayName: "Yuri", sharedWorks: 3, partners: []),
            ExternalCollaborator(openalexID: "X3", displayName: "Zoe", sharedWorks: 9, partners: []),
        ]
        let details = [
            "X1": AuthorCandidate(openalexID: "X1", displayName: "Xena", worksCount: 0,
                                  citedByCount: 0, affiliation: "Duke University"),
            "X2": AuthorCandidate(openalexID: "X2", displayName: "Yuri", worksCount: 0,
                                  citedByCount: 0, affiliation: "Duke University"),
            // X3 has no fetched details → left out.
        ]
        let rollup = MetricsEngine.institutionRollup(collaborators: externals, details: details)
        XCTAssertEqual(rollup.count, 1)
        XCTAssertEqual(rollup.first?.name, "Duke University")
        XCTAssertEqual(rollup.first?.collaborators, 2)
        XCTAssertEqual(rollup.first?.sharedWorks, 8)
        XCTAssertEqual(rollup.first?.topNames, ["Xena", "Yuri"])
        let csv = MetricsEngine.institutionRollupCSV(rollup)
        XCTAssertTrue(csv.contains("Duke University,2,8,Xena; Yuri\n"))
    }

    // MARK: New Work fields survive old state files

    func testDecodingOldStateWithoutNewFieldsYieldsNil() throws {
        let json = #"{"id":"W1","title":"T","citedByCount":3,"authors":[{"openalexID":"A1","displayName":"X"}]}"#
        let decoded = try JSONDecoder().decode(Work.self, from: Data(json.utf8))
        XCTAssertNil(decoded.isRetracted)
        XCTAssertNil(decoded.authors?.first?.position)
        XCTAssertNil(decoded.authors?.first?.isCorresponding)
    }
}

final class NetworkLayoutTests: XCTestCase {
    private func ids(_ n: Int) -> [UUID] { (0..<n).map { _ in UUID() } }

    func testDeterministic() {
        let nodes = ids(6)
        let edges = [
            CoauthorEdge(memberA: nodes[0], memberB: nodes[1], weight: 3),
            CoauthorEdge(memberA: nodes[1], memberB: nodes[2], weight: 1),
            CoauthorEdge(memberA: nodes[3], memberB: nodes[4], weight: 2),
        ]
        XCTAssertEqual(NetworkLayout.layout(nodeIDs: nodes, edges: edges),
                       NetworkLayout.layout(nodeIDs: nodes, edges: edges))
    }

    func testBoundsAndTrivialCases() {
        XCTAssertTrue(NetworkLayout.layout(nodeIDs: [], edges: []).isEmpty)

        let single = UUID()
        XCTAssertEqual(NetworkLayout.layout(nodeIDs: [single], edges: []),
                       [single: NetworkLayout.Point(x: 0.5, y: 0.5)])

        let nodes = ids(10)
        for point in NetworkLayout.layout(nodeIDs: nodes, edges: []).values {
            XCTAssertTrue((0...1).contains(point.x) && (0...1).contains(point.y))
        }
    }

    func testClustersEndUpCloserThanNonClusters() {
        let nodes = ids(6)
        var edges: [CoauthorEdge] = []
        for group in [[0, 1, 2], [3, 4, 5]] {
            for i in group {
                for j in group where j > i {
                    edges.append(CoauthorEdge(memberA: nodes[i], memberB: nodes[j], weight: 5))
                }
            }
        }
        let pos = NetworkLayout.layout(nodeIDs: nodes, edges: edges)

        func distance(_ i: Int, _ j: Int) -> Double {
            let (a, b) = (pos[nodes[i]]!, pos[nodes[j]]!)
            return ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
        }
        let intra = (distance(0, 1) + distance(1, 2) + distance(3, 4) + distance(4, 5)) / 4
        let inter = (distance(0, 3) + distance(1, 4) + distance(2, 5)) / 3
        XCTAssertLessThan(intra, inter)
    }

    func testRingPlacesAllNodes() {
        let nodes = ids(5)
        let pos = NetworkLayout.ring(nodeIDs: nodes)
        XCTAssertEqual(pos.count, 5)
    }
}

final class WorkCodableTests: XCTestCase {
    func testDecodingOldStateWithoutAuthorsYieldsNil() throws {
        let json = """
        {"id": "W1", "title": "Old work", "citedByCount": 4}
        """.data(using: .utf8)!
        let work = try JSONDecoder().decode(Work.self, from: json)
        XCTAssertNil(work.authors)
    }

    func testAuthorsRoundTrip() throws {
        let work = Work(id: "W1", title: "T", year: 2024, date: nil, type: nil,
                        citedByCount: 0, doi: nil, isOA: nil, oaStatus: nil, venue: nil,
                        authors: [WorkAuthor(openalexID: "A1", displayName: "Alice")])
        let decoded = try JSONDecoder().decode(Work.self, from: JSONEncoder().encode(work))
        XCTAssertEqual(decoded, work)
    }
}
