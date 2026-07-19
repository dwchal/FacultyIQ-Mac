import SwiftUI
import UniformTypeIdentifiers

/// "Year in review": per-member movement between two tracked-history dates —
/// works, citations, and h-index growth over an annual-review period — with a
/// one-page PDF export. Reads the same snapshots as the Tracked History
/// charts, so it only knows about dates the app actually fetched on.
struct SnapshotDiffView: View {
    @EnvironmentObject private var store: AppStore
    @State private var fromDate = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
    @State private var toDate = Date()

    private var trackedIDs: Set<String> {
        Set(store.filteredRoster.compactMap { store.resolutions[$0.id]?.openalexID })
    }

    private var snapshotSpan: ClosedRange<Date>? {
        let dates = store.snapshots.map(\.date)
        guard let first = dates.min(), let last = dates.max(), first < last else { return nil }
        return first...last
    }

    var body: some View {
        if let span = snapshotSpan {
            let diffs = MetricsEngine.snapshotDiff(
                snapshots: store.snapshots, authorIDs: trackedIDs,
                from: fromDate, to: toDate)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        DatePicker("From", selection: $fromDate,
                                   in: span, displayedComponents: .date)
                        DatePicker("To", selection: $toDate,
                                   in: max(fromDate, span.lowerBound)...span.upperBound,
                                   displayedComponents: .date)
                        Spacer()
                        savePDFButton(diffs)
                    }
                    .onAppear {
                        fromDate = max(fromDate, span.lowerBound)
                        toDate = min(max(toDate, fromDate), span.upperBound)
                    }
                    if diffs.isEmpty {
                        Text("No tracked readings in this window — history accumulates each time data is fetched.")
                            .foregroundStyle(.secondary)
                    } else {
                        totalsCard(diffs)
                        SnapshotDiffTable(diffs: diffs)
                            .padding(16)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(20)
            }
        } else {
            ContentUnavailableView(
                "Not Enough History Yet",
                systemImage: "calendar.badge.clock",
                description: Text("The diff needs tracked readings on at least two dates. History accumulates automatically each time data is fetched.")
            )
        }
    }

    private func totalsCard(_ diffs: [MetricsEngine.SnapshotDiffPair]) -> some View {
        let works = diffs.map(\.worksDelta).reduce(0, +)
        let citations = diffs.map(\.citationsDelta).reduce(0, +)
        let moved = diffs.count(where: \.hasChange)
        return HStack(spacing: 12) {
            diffTile("New works", "+\(works.formatted())")
            diffTile("Citations gained", "+\(citations.formatted())")
            diffTile("Members with movement", "\(moved)/\(diffs.count)")
        }
    }

    private func diffTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func savePDFButton(_ diffs: [MetricsEngine.SnapshotDiffPair]) -> some View {
        Button("Save as PDF…") {
            if case .failure(let error) = SavePanel.run(
                defaultName: "year_in_review.pdf", type: .pdf,
                write: { url in
                    try PDFComposer.write(
                        pages: SnapshotDiffPages.pages(
                            diffs: diffs, from: fromDate, to: toDate,
                            divisionName: store.divisionFilter),
                        to: url)
                }) {
                store.lastError = error.localizedDescription
            }
        }
        .disabled(diffs.isEmpty)
    }
}

/// The per-member delta grid, shared by the view and the PDF page.
struct SnapshotDiffTable: View {
    let diffs: [MetricsEngine.SnapshotDiffPair]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
            GridRow {
                Text("Member").font(.caption.weight(.semibold))
                Text("Works").font(.caption.weight(.semibold)).gridColumnAlignment(.trailing)
                Text("Citations").font(.caption.weight(.semibold)).gridColumnAlignment(.trailing)
                Text("h-index").font(.caption.weight(.semibold)).gridColumnAlignment(.trailing)
                Text("").frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(diffs) { diff in
                GridRow {
                    Text(diff.name).lineLimit(1)
                    deltaText(diff.worksDelta, total: diff.latest.works)
                    deltaText(diff.citationsDelta, total: diff.latest.citations)
                    deltaText(diff.hIndexDelta, total: diff.latest.hIndex)
                    Text(diff.newlyTracked ? "tracking started in this window" : "")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .font(.callout)
            }
        }
    }

    private func deltaText(_ delta: Int, total: Int) -> some View {
        Text(delta == 0 ? "\(total.formatted())" : "\(total.formatted()) (\(delta > 0 ? "+" : "")\(delta.formatted()))")
            .monospacedDigit()
            .foregroundStyle(delta > 0 ? ChartPalette.positive : Color.primary)
    }
}

/// One-page PDF of the between-dates review.
enum SnapshotDiffPages {
    static func pages(diffs: [MetricsEngine.SnapshotDiffPair],
                      from: Date, to: Date,
                      divisionName: String?) -> [AnyView] {
        let scope = divisionName ?? "All Divisions"
        let range = "\(from.formatted(date: .abbreviated, time: .omitted)) – \(to.formatted(date: .abbreviated, time: .omitted))"
        let works = diffs.map(\.worksDelta).reduce(0, +)
        let citations = diffs.map(\.citationsDelta).reduce(0, +)
        return [
            AnyView(
                ReportPage(footer: "\(scope) — Year in Review · \(ReportStyle.generatedLine)") {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Year in Review").font(.title.weight(.semibold))
                            Text("\(scope) · \(range)").foregroundStyle(.secondary)
                        }
                        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                            GridRow {
                                ReportTile(label: "New Works", value: "+\(works.formatted())")
                                ReportTile(label: "Citations Gained", value: "+\(citations.formatted())")
                                ReportTile(label: "Members Tracked", value: "\(diffs.count)")
                            }
                        }
                        SnapshotDiffTable(diffs: Array(diffs.prefix(28)))
                        if diffs.count > 28 {
                            Text("+ \(diffs.count - 28) more members without room on this page")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            ),
        ]
    }
}
