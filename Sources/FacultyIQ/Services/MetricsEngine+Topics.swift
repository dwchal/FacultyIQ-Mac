import Foundation

/// Research-topic aggregations over the OpenAlex primary topic of each work.
extension MetricsEngine {
    struct TopicCount: Identifiable {
        var name: String
        var field: String?       // the OpenAlex field most of the topic's works fall under
        var works: Int           // distinct works across the cohort
        var people: Int          // members with at least one work on the topic

        var id: String { name }
    }

    /// Distinct works per primary topic across the cohort (a coauthored work
    /// counts once), with how many members publish on each topic.
    static func topicCounts(personData: [PersonData]) -> [TopicCount] {
        var worksByTopic: [String: Set<String>] = [:]
        var peopleByTopic: [String: Int] = [:]
        var fieldVotes: [String: [String: Int]] = [:]
        for data in personData {
            var personTopics = Set<String>()
            for work in data.works {
                guard let topic = work.topicName else { continue }
                worksByTopic[topic, default: []].insert(work.id)
                personTopics.insert(topic)
                if let field = work.topicField {
                    fieldVotes[topic, default: [:]][field, default: 0] += 1
                }
            }
            for topic in personTopics {
                peopleByTopic[topic, default: 0] += 1
            }
        }
        return worksByTopic
            .map { topic, ids in
                TopicCount(
                    name: topic,
                    field: fieldVotes[topic]?.max { $0.value < $1.value }?.key,
                    works: ids.count,
                    people: peopleByTopic[topic] ?? 0)
            }
            .sorted { ($0.works, $1.name) > ($1.works, $0.name) }
    }

    struct TopicYearCount: Identifiable {
        var topic: String
        var year: Int
        var count: Int

        var id: String { "\(topic)|\(year)" }
    }

    /// Distinct works per year for the given topics over the trailing `span`
    /// years, zero-filled so trend lines have a point for every year.
    static func topicTrend(personData: [PersonData], topics: [String],
                           span: Int = 10) -> [TopicYearCount] {
        let wanted = Set(topics)
        let firstYear = currentYear - span + 1
        var perTopic: [String: [Int: Set<String>]] = [:]
        for data in personData {
            for work in data.works {
                guard let topic = work.topicName, wanted.contains(topic),
                      let year = work.year, year >= firstYear, year <= currentYear
                else { continue }
                perTopic[topic, default: [:]][year, default: []].insert(work.id)
            }
        }
        return topics.flatMap { topic in
            (firstYear...currentYear).map { year in
                TopicYearCount(topic: topic, year: year,
                               count: perTopic[topic]?[year]?.count ?? 0)
            }
        }
    }

    /// A person's most frequent primary topics.
    static func personTopics(data: PersonData, limit: Int = 3) -> [(name: String, works: Int)] {
        var counts: [String: Int] = [:]
        for work in data.works {
            if let topic = work.topicName { counts[topic, default: 0] += 1 }
        }
        return counts
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(limit)
            .map { (name: $0.key, works: $0.value) }
    }

    /// True when some member's works all predate topic tracking, so the
    /// topic charts undercount until a re-fetch.
    static func staleTopicData(personData: [PersonData]) -> Bool {
        personData.contains { data in
            !data.works.isEmpty && data.works.allSatisfy { $0.topicName == nil }
        }
    }
}
