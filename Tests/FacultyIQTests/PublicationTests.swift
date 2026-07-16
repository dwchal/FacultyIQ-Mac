import XCTest
@testable import FacultyIQ

final class PublicationTests: XCTestCase {
    private let year = MetricsEngine.currentYear

    private func work(_ id: String, year: Int? = nil, type: String? = "article",
                      venue: String? = nil, oaStatus: String? = nil,
                      citations: Int = 0) -> Work {
        Work(id: id, title: id, year: year ?? self.year, date: nil, type: type,
             citedByCount: citations, doi: nil, isOA: oaStatus == nil ? nil : oaStatus != "closed",
             oaStatus: oaStatus, venue: venue, authors: nil)
    }

    private func personData(works: [Work]) -> PersonData {
        PersonData(
            profile: AuthorProfile(openalexID: "A", displayName: "", worksCount: works.count,
                                   citedByCount: 0, hIndex: nil, i10Index: nil,
                                   affiliation: nil, countsByYear: []),
            works: works, fetchedAt: Date())
    }

    // MARK: Types

    func testTypeCountsDedupeSharedWorksAndCountPeople() {
        // W1 is coauthored: it must count once per type, but both people count.
        let a = personData(works: [work("W1"), work("W2"), work("W3", type: "review")])
        let b = personData(works: [work("W1")])
        let counts = MetricsEngine.typeCounts(personData: [a, b])

        XCTAssertEqual(counts.map(\.name), ["article", "review"])
        XCTAssertEqual(counts[0].works, 2)
        XCTAssertEqual(counts[0].people, 2)
        XCTAssertEqual(counts[1].people, 1)
    }

    func testTypeCountsNormalizeAndBucketUntyped() {
        let a = personData(works: [work("W1", type: "Article"), work("W2", type: nil),
                                   work("W3", type: "")])
        let counts = MetricsEngine.typeCounts(personData: [a])
        XCTAssertEqual(counts.map(\.name), [MetricsEngine.untypedLabel, "article"])
        XCTAssertEqual(counts[0].works, 2, "nil and empty types share the untyped bucket")
    }

    func testTypeTrendZeroFillsAndDedupes() {
        let a = personData(works: [work("W1", year: year), work("W2", year: year - 2)])
        let b = personData(works: [work("W1", year: year)])
        let trend = MetricsEngine.typeTrend(personData: [a, b], types: ["article"], span: 3)

        XCTAssertEqual(trend.count, 3, "one point per year in the span")
        XCTAssertEqual(trend.map(\.count), [1, 0, 1], "coauthored W1 counts once")
        XCTAssertEqual(trend.map(\.year), [year - 2, year - 1, year])
    }

    func testPersonTypeCountsOrderAndLimit() {
        let a = personData(works: [work("W1"), work("W2"), work("W3", type: "review"),
                                   work("W4", type: "letter"), work("W5", type: "editorial"),
                                   work("W6", type: "book-chapter")])
        let types = MetricsEngine.personTypeCounts(data: a, limit: 3)
        XCTAssertEqual(types.count, 3)
        XCTAssertEqual(types[0].name, "article")
        XCTAssertEqual(types[0].works, 2)
    }

    // MARK: Venues

    func testVenueCountsDedupeAndSumCitationsOnce() {
        let a = personData(works: [work("W1", venue: "JAMA", citations: 10),
                                   work("W2", venue: "JAMA", citations: 5),
                                   work("W3", venue: "Lancet", citations: 50),
                                   work("W4", venue: nil, citations: 99)])
        let b = personData(works: [work("W1", venue: "JAMA", citations: 10)])
        let counts = MetricsEngine.venueCounts(personData: [a, b])

        XCTAssertEqual(counts.map(\.name), ["JAMA", "Lancet"])
        let jama = counts[0]
        XCTAssertEqual(jama.works, 2, "coauthored W1 counts once")
        XCTAssertEqual(jama.citations, 15, "citations summed once per distinct work")
        XCTAssertEqual(jama.people, 2)
        XCTAssertEqual(counts[1].people, 1)
    }

    // MARK: Open-access status

    func testOAStatusCountsCanonicalOrderAndSkipUntagged() {
        let a = personData(works: [work("W1", oaStatus: "closed"), work("W2", oaStatus: "gold"),
                                   work("W3", oaStatus: "Gold"), work("W4", oaStatus: nil)])
        let counts = MetricsEngine.oaStatusCounts(personData: [a])
        XCTAssertEqual(counts.map(\.status), ["gold", "closed"],
                       "canonical open-to-closed order, case-normalized, untagged skipped")
        XCTAssertEqual(counts[0].count, 2)
    }

    func testOAStatusByYearSharesSumTo100() {
        let a = personData(works: [work("W1", year: year, oaStatus: "gold"),
                                   work("W2", year: year, oaStatus: "closed"),
                                   work("W3", year: year, oaStatus: "closed"),
                                   work("W4", year: year - 1, oaStatus: "green")])
        let b = personData(works: [work("W1", year: year, oaStatus: "gold")])
        let shares = MetricsEngine.oaStatusByYear(personData: [a, b])

        let thisYear = shares.filter { $0.year == year }
        XCTAssertEqual(thisYear.map(\.status), ["gold", "closed"])
        XCTAssertEqual(thisYear[0].percent, 100.0 / 3, accuracy: 0.001,
                       "coauthored W1 counts once")
        XCTAssertEqual(thisYear.map(\.percent).reduce(0, +), 100, accuracy: 0.001)

        let lastYear = shares.filter { $0.year == year - 1 }
        XCTAssertEqual(lastYear.map(\.percent), [100])
    }
}
