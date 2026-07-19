import Foundation
import SwiftUI

/// Unattended PDF generation. Rides the same hourly heartbeat as the automatic
/// update check: `run(store:)` decides for itself whether a report is due, so
/// the timer can call it freely.
///
/// Reports always cover the whole roster, not the division currently filtered
/// in the UI — a scheduled artifact shouldn't change shape because of what the
/// window happened to be showing when the timer fired.
@MainActor
enum ScheduledReport {
    enum Kind: String, CaseIterable {
        case divisionSummary
        case yearInReview

        var label: String {
            switch self {
            case .divisionSummary: "Division Summary"
            case .yearInReview: "Year in Review"
            }
        }

        var filenameStem: String {
            switch self {
            case .divisionSummary: "division_summary"
            case .yearInReview: "year_in_review"
            }
        }
    }

    private static let lastRunKey = "scheduledReportLastRun"

    static var lastRun: Date? {
        get { UserDefaults.standard.object(forKey: lastRunKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastRunKey) }
    }

    /// Write the configured report if it's due (or `force` is set). Silent on
    /// every "not yet" path — this runs unattended and must not nag.
    static func run(store: AppStore, force: Bool = false) async {
        let defaults = UserDefaults.standard
        guard force || defaults.bool(forKey: "scheduledReportEnabled") else { return }

        let folderPath = defaults.string(forKey: "scheduledReportFolder") ?? ""
        guard !folderPath.isEmpty else { return }
        guard !store.personData.isEmpty else { return }

        if !force {
            let days = max(defaults.integer(forKey: "scheduledReportIntervalDays"), 1)
            if let last = lastRun,
               Date().timeIntervalSince(last) < Double(days) * 86_400 {
                return
            }
        }

        let kind = Kind(rawValue: defaults.string(forKey: "scheduledReportKind") ?? "")
            ?? .divisionSummary
        let folder = URL(fileURLWithPath: folderPath, isDirectory: true)

        do {
            let pages = try pages(for: kind, store: store)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try PDFComposer.write(pages: pages, to: uniqueURL(in: folder, kind: kind))
            lastRun = Date()
        } catch {
            store.lastError = "Scheduled report failed: \(error.localizedDescription)"
        }
    }

    enum ReportError: LocalizedError {
        case noSnapshotWindow

        var errorDescription: String? {
            switch self {
            case .noSnapshotWindow:
                "not enough tracked history yet for a Year in Review — it needs readings from more than one date."
            }
        }
    }

    /// Whole-roster pages, deliberately ignoring the UI's division filter.
    private static func pages(for kind: Kind, store: AppStore) throws -> [AnyView] {
        let roster = store.roster
        let personData = roster.compactMap { store.effectivePersonData[$0.id] }
        let metrics = MetricsEngine.allMetrics(roster: roster,
                                               personData: store.effectivePersonData)
        let activeIDs = Set(roster.filter(\.isActive).map(\.id))
        let benchmarks = MetricsEngine.rankBenchmarks(
            metrics: metrics.filter { activeIDs.contains($0.memberID) })

        switch kind {
        case .divisionSummary:
            return SummaryPages.pages(
                summary: MetricsEngine.divisionSummary(
                    roster: roster,
                    resolvedCount: roster.count { store.resolutions[$0.id] != nil },
                    metrics: metrics),
                metrics: metrics,
                personData: personData,
                benchmarks: benchmarks,
                divisionName: nil,
                scopusLine: MetricsEngine.divisionScopusLine(
                    roster: roster, personData: store.personData,
                    enrichment: store.enrichment))
        case .yearInReview:
            let now = Date()
            guard let from = Calendar(identifier: .gregorian)
                .date(byAdding: .year, value: -1, to: now) else {
                throw ReportError.noSnapshotWindow
            }
            let authorIDs = Set(roster.compactMap { store.resolutions[$0.id]?.openalexID })
            let diffs = MetricsEngine.snapshotDiff(
                snapshots: store.snapshots, authorIDs: authorIDs, from: from, to: now)
            guard !diffs.isEmpty else { throw ReportError.noSnapshotWindow }
            return SnapshotDiffPages.pages(diffs: diffs, from: from, to: now, divisionName: nil)
        }
    }

    /// A dated filename that never collides: the plain date first, then
    /// -2, -3, … Overwriting a report someone may already have circulated
    /// would be the wrong default.
    private static func uniqueURL(in folder: URL, kind: Kind) -> URL {
        let stamp = Date().formatted(.iso8601.year().month().day())
        let base = "\(kind.filenameStem)_\(stamp)"
        var candidate = folder.appendingPathComponent("\(base).pdf")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base)-\(suffix).pdf")
            suffix += 1
        }
        return candidate
    }
}
