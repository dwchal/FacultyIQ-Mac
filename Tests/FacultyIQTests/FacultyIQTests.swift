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
