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
                    nearCandidateSection
                }
                .padding(20)
            }
        }
    }

    private var benchmarkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rank Benchmarks").font(.headline)
            Text("Median within each rank, and the promotion target (25th percentile — the low end of the rank, since accumulated medians overstate the bar people cleared at promotion).")
                .font(.caption)
                .foregroundStyle(.secondary)
            Table(store.benchmarks.sorted(using: sortOrder), sortOrder: $sortOrder) {
                TableColumn("Rank", value: \.rank) { Text($0.rank.label) }
                TableColumn("Faculty", value: \.count) { Text("\($0.count)") }
                    .width(60)
                TableColumn("Works", value: \.medianWorks) {
                    benchmarkCell(median: $0.medianWorks, target: $0.targetWorks)
                }
                .width(90)
                TableColumn("Citations", value: \.medianCitations) {
                    benchmarkCell(median: $0.medianCitations, target: $0.targetCitations)
                }
                .width(100)
                TableColumn("h-index", value: \.medianHIndex) {
                    benchmarkCell(median: $0.medianHIndex, target: $0.targetHIndex)
                }
                .width(90)
                TableColumn("Works / Year", value: \.medianWorksPerYear) { Text(String(format: "%.2f", $0.medianWorksPerYear)) }
                    .width(90)
            }
            .frame(height: CGFloat(store.benchmarks.count) * 40 + 40)
        }
    }

    private func benchmarkCell(median: Double, target: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(String(format: "%.0f", median))
            Text(String(format: "target %.0f", target))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var nearCandidates: [PromotionProgress] {
        store.promotionProgress
            .filter { $0.metCount == 1 }
            .sorted { $0.closeness > $1.closeness }
    }

    @ViewBuilder
    private var candidateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Promotion Candidates").font(.headline)
            Text("Faculty meeting the next rank's promotion target on at least two of: works, citations, h-index.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if store.promotionCandidates.isEmpty {
                Text("No one currently meets two of the three next-rank targets.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(store.promotionCandidates) { candidate in
                    candidateCard(candidate)
                }
            }
        }
    }

    @ViewBuilder
    private var nearCandidateSection: some View {
        if !nearCandidates.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Close to Promotion").font(.headline)
                Text("Meeting one of the three targets — sorted by overall progress toward the next rank.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(nearCandidates) { progress in
                    nearCandidateCard(progress)
                }
            }
        }
    }

    private func nearCandidateCard(_ progress: PromotionProgress) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "clock.arrow.trianglehead.2.counterclockwise.rotate.90")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(progress.metrics.name).font(.body.weight(.semibold))
                Text("\(progress.currentRank.label) → \(progress.targetRank.label)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let pace = paceCaption(for: progress) {
                    Text(pace)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                predictionChip(for: progress)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(progress.checks) { check in
                    metricChip(check)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func meanRCR(for memberID: UUID) -> Double? {
        guard let data = store.personData[memberID] else { return nil }
        return MetricsEngine.meanRCR(works: data.works, icite: store.enrichment[memberID]?.icite)
    }

    /// Time-to-target estimate for the unmet checks, from the trailing
    /// five-year publication/citation pace.
    private func paceCaption(for progress: PromotionProgress) -> String? {
        guard let data = store.personData[progress.metrics.memberID] else { return nil }
        let projections = MetricsEngine.trajectoryProjections(data: data, promotion: progress)
        guard let longest = projections.map(\.yearsToTarget).max() else { return nil }
        if longest > 15 { return "At the current pace: 15+ years to the remaining targets" }
        let years = max(Int(longest.rounded(.up)), 1)
        return "At the current pace: ~\(years) \(years == 1 ? "year" : "years") to the remaining target\(projections.count == 1 ? "" : "s")"
    }

    /// Nearest-rank chip from the rank-distance model, shown when the profile
    /// resembles a different rank than the member currently holds.
    @ViewBuilder
    private func predictionChip(for progress: PromotionProgress) -> some View {
        if let prediction = MetricsEngine.rankPrediction(for: progress.metrics, cohort: store.metrics),
           prediction.rank != progress.currentRank {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                Text("Profile resembles: \(prediction.rank.label) (\(Int((prediction.confidence * 100).rounded()))%)")
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
            .help("Weighted distance from this member's works, citations, h-index, i10, career years, and works/year to each rank's median profile in view; the percentage is how decisively the nearest rank beats the runner-up.")
        }
    }

    private func metricChip(_ check: PromotionProgress.MetricCheck) -> some View {
        HStack(spacing: 4) {
            Image(systemName: check.met ? "checkmark.circle.fill" : "circle.dotted")
                .foregroundStyle(check.met ? ChartPalette.positive : Color.secondary)
            Text("\(check.label) \(check.value.formatted()) / \(Int(check.benchmark.rounded()))")
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
        .help(check.met
            ? "\(check.label): meets the next rank's promotion target"
            : "\(check.label): needs \(check.gap.formatted()) more to reach the target")
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
                if let progress = store.promotionProgress.first(where: { $0.id == candidate.id }) {
                    if let pace = paceCaption(for: progress) {
                        Text(pace)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    predictionChip(for: progress)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(candidate.metrics.worksCount) works · \(candidate.metrics.citations.formatted()) citations")
                Text("h-index \(candidate.metrics.hIndex)")
                if let rcr = meanRCR(for: candidate.metrics.memberID) {
                    Text(String(format: "mean RCR %.2f", rcr))
                        .help("Mean Relative Citation Ratio (NIH iCite): 1.0 is the field-normalized average")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
