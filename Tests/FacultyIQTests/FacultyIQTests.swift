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
