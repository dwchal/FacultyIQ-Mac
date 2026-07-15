import Foundation

/// Aggregations over the tracked metric snapshots — the app's own record of
/// how the cohort's totals moved across fetches, as opposed to the trends
/// inferred from OpenAlex counts_by_year.
extension MetricsEngine {
    struct HistoryPoint: Identifiable {
        var date: Date           // start of the snapshot day
        var works: Int
        var citations: Int
        var tracked: Int         // authors contributing to this point

        var id: Date { date }
    }

    /// Tracked totals per snapshot day for the given authors: each author
    /// contributes their most recent reading at or before that day (carried
    /// forward between fetches). Early points cover only the authors tracked
    /// by then — `tracked` says how many.
    static func divisionHistory(snapshots: [MetricSnapshot],
                                authorIDs: Set<String>) -> [HistoryPoint] {
        let calendar = Calendar.current
        let relevant = snapshots
            .filter { authorIDs.contains($0.openalexID) }
            .sorted { $0.date < $1.date }
        guard !relevant.isEmpty else { return [] }

        let days = Array(Set(relevant.map { calendar.startOfDay(for: $0.date) })).sorted()
        var latest: [String: MetricSnapshot] = [:]
        var index = 0
        return days.map { day in
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day)!
            while index < relevant.count, relevant[index].date < dayEnd {
                latest[relevant[index].openalexID] = relevant[index]
                index += 1
            }
            return HistoryPoint(
                date: day,
                works: latest.values.map(\.works).reduce(0, +),
                citations: latest.values.map(\.citations).reduce(0, +),
                tracked: latest.count)
        }
    }

    /// One author's snapshots, oldest first.
    static func personHistory(snapshots: [MetricSnapshot],
                              openalexID: String) -> [MetricSnapshot] {
        snapshots
            .filter { $0.openalexID == openalexID }
            .sorted { $0.date < $1.date }
    }
}
