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

    // MARK: Between-dates diff ("year in review")

    /// One member's movement between two dates, from tracked snapshots.
    struct SnapshotDiffPair: Identifiable {
        var openalexID: String
        var name: String
        var baseline: MetricSnapshot   // latest reading at or before `from`
                                       // (or the first inside the window for authors tracked later)
        var latest: MetricSnapshot     // latest reading at or before `to`
        var newlyTracked: Bool         // baseline fell inside the window

        var id: String { openalexID }
        var worksDelta: Int { latest.works - baseline.works }
        var citationsDelta: Int { latest.citations - baseline.citations }
        var hIndexDelta: Int { latest.hIndex - baseline.hIndex }
        var hasChange: Bool { worksDelta != 0 || citationsDelta != 0 || hIndexDelta != 0 }
    }

    /// Per-author deltas between two dates: each author's last reading at or
    /// before `from` (falling back to their first reading inside the window)
    /// against their last reading at or before `to`. Biggest citation movers
    /// first.
    static func snapshotDiff(snapshots: [MetricSnapshot],
                             authorIDs: Set<String>,
                             from: Date, to: Date) -> [SnapshotDiffPair] {
        let calendar = Calendar.current
        let fromEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: from))!
        let toEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: to))!
        var byAuthor: [String: [MetricSnapshot]] = [:]
        for snapshot in snapshots where authorIDs.contains(snapshot.openalexID) {
            byAuthor[snapshot.openalexID, default: []].append(snapshot)
        }
        return byAuthor.compactMap { id, readings -> SnapshotDiffPair? in
            let sorted = readings.sorted { $0.date < $1.date }
            guard let latest = sorted.last(where: { $0.date < toEnd }) else { return nil }
            let baseline = sorted.last(where: { $0.date < fromEnd })
                ?? sorted.first(where: { $0.date < toEnd })!
            return SnapshotDiffPair(openalexID: id, name: latest.name,
                                    baseline: baseline, latest: latest,
                                    newlyTracked: baseline.date >= fromEnd)
        }
        .sorted { ($0.citationsDelta, $0.worksDelta) > ($1.citationsDelta, $1.worksDelta) }
    }
}
