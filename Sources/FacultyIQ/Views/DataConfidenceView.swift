import SwiftUI

/// Explains where each displayed metric came from, when it was fetched, and
/// where cross-source disagreement or incomplete metadata deserves review.
struct DataConfidenceView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection: UUID?

    private var reports: [MetricsEngine.DataConfidenceReport] {
        store.filteredRoster.map { member in
            MetricsEngine.dataConfidence(
                member: member,
                resolution: store.resolutions[member.id],
                data: store.effectivePersonData[member.id],
                enrichment: store.enrichment[member.id])
        }
        .sorted { ($0.score, $1.member.name) < ($1.score, $0.member.name) }
    }

    private var selectedReport: MetricsEngine.DataConfidenceReport? {
        reports.first { $0.id == selection }
    }

    var body: some View {
        if store.roster.isEmpty {
            ContentUnavailableView(
                "No Roster Loaded",
                systemImage: "checkmark.shield",
                description: Text("Load and resolve a roster to inspect metric provenance."))
        } else {
            HSplitView {
                reportList
                    .frame(minWidth: 260, idealWidth: 310, maxWidth: 380)
                detail
                    .frame(minWidth: 580)
            }
            .onAppear {
                if selection == nil { selection = reports.first?.id }
            }
            .onChange(of: store.scopeName) {
                if let selection, !reports.contains(where: { $0.id == selection }) {
                    self.selection = reports.first?.id
                }
            }
        }
    }

    private var reportList: some View {
        List(reports, selection: $selection) { report in
            HStack(spacing: 10) {
                scoreBadge(report.score)
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.member.name).lineLimit(1)
                    Text(report.grade)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !report.warnings.isEmpty {
                    Text(report.warnings.count.formatted())
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.16), in: Capsule())
                }
            }
            .tag(report.id)
        }
        .safeAreaInset(edge: .top) {
            let reviewed = reports.count { $0.score >= 75 }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Data Confidence").font(.headline)
                    Text("\(reviewed) of \(reports.count) good or better")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(.bar)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let report = selectedReport {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 16) {
                        scoreBadge(report.score, large: true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(report.member.name).font(.title2.weight(.semibold))
                            Text("\(report.grade) confidence · \(report.score)/100")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open Profile") {
                            store.profileFocusID = report.member.id
                            store.pendingSidebarTarget = .profiles
                        }
                    }
                    if !report.warnings.isEmpty {
                        warningsCard(report.warnings)
                    }
                    provenanceCard(report.entries)
                    methodologyCard
                }
                .padding(20)
            }
        } else {
            ContentUnavailableView(
                "Select a Faculty Member",
                systemImage: "checkmark.shield",
                description: Text("Choose a person to inspect sources, freshness, and coverage."))
        }
    }

    private func warningsCard(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Review Recommended", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            ForEach(warnings, id: \.self) { warning in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "circle.fill").font(.system(size: 5))
                    Text(warning)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private func provenanceCard(_ entries: [MetricsEngine.ProvenanceEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Metric Provenance").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    Text("Metric")
                    Text("Source")
                    Text("Value")
                    Text("Retrieved")
                    Text("Notes")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                Divider()
                ForEach(entries) { entry in
                    GridRow {
                        Text(entry.metric)
                        Text(entry.source)
                        Text(entry.value).monospacedDigit()
                        Text(entry.fetchedAt?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                            .foregroundStyle(.secondary)
                        Text(entry.note ?? "—").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var methodologyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How the score works").font(.headline)
            Text("The score begins at 100 and flags stale data, weak identity anchors, incomplete DOI/authorship/topic coverage, and material disagreement between OpenAlex and Scopus. It measures data readiness—not research quality or faculty performance.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func scoreBadge(_ score: Int, large: Bool = false) -> some View {
        Text(score.formatted())
            .font(large ? .title2.weight(.bold).monospacedDigit()
                        : .callout.weight(.semibold).monospacedDigit())
            .foregroundStyle(scoreColor(score))
            .frame(width: large ? 66 : 42, height: large ? 66 : 34)
            .background(scoreColor(score).opacity(0.13), in: Circle())
            .accessibilityLabel("Confidence score \(score) out of 100")
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 90...: ChartPalette.positive
        case 75..<90: .blue
        case 55..<75: .orange
        default: .red
        }
    }
}
