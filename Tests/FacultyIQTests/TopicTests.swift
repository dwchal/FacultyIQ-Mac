import XCTest
@testable import FacultyIQ

final class TopicTests: XCTestCase {
    private let year = MetricsEngine.currentYear

    private func work(_ id: String, year: Int? = nil,
                      topic: String?, field: String? = "Medicine") -> Work {
        Work(id: id, title: id, year: year ?? self.year, date: nil, type: nil,
             citedByCount: 0, doi: nil, isOA: nil, oaStatus: nil, venue: nil,
             authors: nil, topicName: topic, topicField: topic == nil ? nil : field)
    }

    private func personData(works: [Work]) -> PersonData {
        PersonData(
            profile: AuthorProfile(openalexID: "A", displayName: "", worksCount: works.count,
                                   citedByCount: 0, hIndex: nil, i10Index: nil,
                                   affiliation: nil, countsByYear: []),
            works: works, fetchedAt: Date())
    }

    func testTopicCountsDedupeSharedWorksAndCountPeople() {
        // W1 is coauthored: it must count once for the topic, but both people count.
        let a = personData(works: [work("W1", topic: "Sepsis"), work("W2", topic: "Sepsis"),
                                   work("W3", topic: "Antibiotics")])
        let b = personData(works: [work("W1", topic: "Sepsis")])
        let counts = MetricsEngine.topicCounts(personData: [a, b])

        XCTAssertEqual(counts.map(\.name), ["Sepsis", "Antibiotics"])
        let sepsis = counts[0]
        XCTAssertEqual(sepsis.works, 2)
        XCTAssertEqual(sepsis.people, 2)
        XCTAssertEqual(sepsis.field, "Medicine")
        XCTAssertEqual(counts[1].people, 1)
    }

    func testTopicCountsIgnoreUntaggedWorks() {
        let a = personData(works: [work("W1", topic: nil), work("W2", topic: "Sepsis")])
        let counts = MetricsEngine.topicCounts(personData: [a])
        XCTAssertEqual(counts.count, 1)
        XCTAssertEqual(counts[0].works, 1)
    }

    func testTopicTrendZeroFillsAndDedupes() {
        let a = personData(works: [work("W1", year: year, topic: "Sepsis"),
                                   work("W2", year: year - 2, topic: "Sepsis")])
        let b = personData(works: [work("W1", year: year, topic: "Sepsis")])
        let trend = MetricsEngine.topicTrend(personData: [a, b], topics: ["Sepsis"], span: 3)

        XCTAssertEqual(trend.count, 3, "one point per year in the span")
        XCTAssertEqual(trend.map(\.count), [1, 0, 1], "coauthored W1 counts once")
        XCTAssertEqual(trend.map(\.year), [year - 2, year - 1, year])
    }

    func testPersonTopicsOrderAndLimit() {
        let a = personData(works: [work("W1", topic: "Sepsis"), work("W2", topic: "Sepsis"),
                                   work("W3", topic: "Antibiotics"), work("W4", topic: "Fungi"),
                                   work("W5", topic: "Malaria")])
        let topics = MetricsEngine.personTopics(data: a, limit: 3)
        XCTAssertEqual(topics.count, 3)
        XCTAssertEqual(topics[0].name, "Sepsis")
        XCTAssertEqual(topics[0].works, 2)
    }

    func testStaleTopicData() {
        let untagged = personData(works: [work("W1", topic: nil)])
        let tagged = personData(works: [work("W2", topic: "Sepsis")])
        let empty = personData(works: [])
        XCTAssertTrue(MetricsEngine.staleTopicData(personData: [untagged, tagged]))
        XCTAssertFalse(MetricsEngine.staleTopicData(personData: [tagged]))
        XCTAssertFalse(MetricsEngine.staleTopicData(personData: [empty]),
                       "no works isn't staleness")
    }
}
