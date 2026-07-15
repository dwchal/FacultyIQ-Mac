import SwiftUI

/// Rank benchmarks and promotion candidates — the simplified counterpart of
/// the Shiny app's prediction module.
struct PromotionView: View {
    @EnvironmentObject private var store: AppStore
    @State private var sortOrder: [KeyPathComparator<RankBenchmark>] = [] // empty = rank order

    var body: some View {
        if store.metrics.isEmpty {
            ContentUnavailableView(
                "No Metrics Available",
                systemImage: "arrow.up.right.circle",
                description: Text("Fetch metrics first; promotion insights compare each member against the next rank's medians.")
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    benchmarkSection
                    candidateSection
                }
                .padding(20)
            }
        }
    }

    private var benchmarkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rank Benchmarks (Medians)").font(.headline)
            Text("Median metrics within each academic rank in this roster.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Table(store.benchmarks.sorted(using: sortOrder), sortOrder: $sortOrder) {
                TableColumn("Rank", value: \.rank) { Text($0.rank.label) }
                TableColumn("Faculty", value: \.count) { Text("\($0.count)") }
                    .width(60)
                TableColumn("Works", value: \.medianWorks) { Text(String(format: "%.0f", $0.medianWorks)) }
                    .width(70)
                TableColumn("Citations", value: \.medianCitations) { Text(String(format: "%.0f", $0.medianCitations)) }
                    .width(80)
                TableColumn("h-index", value: \.medianHIndex) { Text(String(format: "%.0f", $0.medianHIndex)) }
                    .width(70)
                TableColumn("Works / Year", value: \.medianWorksPerYear) { Text(String(format: "%.2f", $0.medianWorksPerYear)) }
                    .width(90)
            }
            .frame(height: CGFloat(store.benchmarks.count) * 28 + 40)
        }
    }

    @ViewBuilder
    private var candidateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Promotion Candidates").font(.headline)
            Text("Faculty meeting or exceeding the next rank's median on at least two of: works, citations, h-index.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if store.promotionCandidates.isEmpty {
                Text("No candidates identified with the current data.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(store.promotionCandidates) { candidate in
                    candidateCard(candidate)
                }
            }
        }
    }

    private func candidateCard(_ candidate: PromotionCandidate) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "arrow.up.right.circle.fill")
                .font(.title2)
                .foregroundStyle(ChartPalette.positive)
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.metrics.name).font(.body.weight(.semibold))
                Text("\(candidate.currentRank.label) → \(candidate.targetRank.label)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(candidate.exceededMetrics, id: \.self) { metric in
                        Text(metric)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(candidate.metrics.worksCount) works · \(candidate.metrics.citations.formatted()) citations")
                Text("h-index \(candidate.metrics.hIndex)")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
