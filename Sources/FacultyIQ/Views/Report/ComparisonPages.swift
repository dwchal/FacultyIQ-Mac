import SwiftUI

/// One member's column of the comparison sheet, precomputed so the on-screen
/// grid and the PDF page render the same numbers.
struct ComparisonColumn: Identifiable {
    var member: FacultyMember
    var metrics: PersonMetrics
    var meanRCR: Double?
    var scopus: ScopusAuthorMetrics?
    var quality: MetricsEngine.JournalQuality?
    var funding: MetricsEngine.FundingSummary?
    var trials: MetricsEngine.TrialsSummary?

    var id: UUID { member.id }

    @MainActor
    init(store: AppStore, member: FacultyMember) {
        let data = store.effectiveData(for: member.id)
            ?? PersonData(profile: AuthorProfile(openalexID: "", displayName: member.name,
                                                 worksCount: 0, citedByCount: 0, countsByYear: []),
                          works: [], fetchedAt: Date())
        let enrichment = store.enrichment[member.id]
        self.member = member
        self.metrics = MetricsEngine.personMetrics(member: member, data: data)
        self.meanRCR = MetricsEngine.meanRCR(works: data.works, icite: enrichment?.icite)
        self.scopus = enrichment?.scopus?.author
        self.quality = (enrichment?.scopus?.journalByISSN).flatMap { journals in
            journals.isEmpty ? nil : MetricsEngine.journalQuality(works: data.works, journals: journals)
        }
        self.funding = (enrichment?.grants?.grants).map { MetricsEngine.fundingSummary($0) }
        self.trials = (enrichment?.trials?.trials).map { MetricsEngine.trialsSummary($0) }
    }
}

/// The label/value grid itself; best value per row is bolded. Shared by
/// ComparisonView and the PDF page.
struct ComparisonGrid: View {
    let columns: [ComparisonColumn]
    let benchmarks: [RankBenchmark]

    private struct Row: Identifiable {
        var label: String
        var display: [String]
        var numeric: [Double?]   // for best-value bolding; nil = not comparable

        var id: String { label }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    ForEach(columns) { column in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(column.member.name).font(.headline)
                            Text(column.metrics.rawRank ?? "—")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(rows) { row in
                    GridRow {
                        Text(row.label)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.leading)
                        let best = bestValue(row.numeric)
                        ForEach(columns.indices, id: \.self) { i in
                            Text(row.display[i])
                                .font(.callout.weight(
                                    best != nil && row.numeric[i] == best ? .semibold : .regular))
                                .monospacedDigit()
                        }
                    }
                }
            }
            benchmarkFootnote
        }
    }

    /// Bold only when someone actually leads: a value that exists, is the
    /// maximum, and isn't shared by every column.
    private func bestValue(_ numeric: [Double?]) -> Double? {
        let present = numeric.compactMap(\.self)
        guard let max = present.max(), present.count > 1,
              !present.allSatisfy({ $0 == max }) else { return nil }
        return max
    }

    @ViewBuilder
    private var benchmarkFootnote: some View {
        let ranks = Array(Set(columns.compactMap(\.metrics.rank)))
        let relevant = benchmarks.filter { ranks.contains($0.rank) }
            .sorted { $0.rank.rawValue < $1.rank.rawValue }
        if !relevant.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(relevant) { benchmark in
                    Text("\(benchmark.rank.label) division median (n=\(benchmark.count)): \(Int(benchmark.medianWorks)) works · \(Int(benchmark.medianCitations)) citations · h-index \(Int(benchmark.medianHIndex))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var rows: [Row] {
        func row(_ label: String, _ value: (ComparisonColumn) -> Double?,
                 format: (Double) -> String) -> Row {
            let values = columns.map(value)
            return Row(label: label,
                       display: values.map { $0.map(format) ?? "—" },
                       numeric: values)
        }
        func intRow(_ label: String, _ value: @escaping (ComparisonColumn) -> Int?) -> Row {
            row(label, { value($0).map(Double.init) }, format: { Int($0).formatted() })
        }
        return [
            intRow("Works") { $0.metrics.worksCount },
            intRow("Citations") { $0.metrics.citations },
            intRow("h-index") { $0.metrics.hIndex },
            intRow("Scopus h-index") { $0.scopus?.hIndex },
            intRow("i10-index") { $0.metrics.i10Index },
            row("Citations / work", { $0.metrics.citationsPerWork },
                format: { String(format: "%.1f", $0) }),
            row("Works / year", { $0.metrics.worksPerYear },
                format: { String(format: "%.2f", $0) }),
            intRow("First-author works") {
                $0.metrics.positionTracked > 0 ? $0.metrics.firstAuthorWorks : nil
            },
            intRow("Senior-author works") {
                $0.metrics.positionTracked > 0 ? $0.metrics.seniorAuthorWorks : nil
            },
            row("Senior share, 5y", { $0.metrics.seniorShare5y.map { $0 / 100 } },
                format: { $0.formatted(.percent.precision(.fractionLength(0))) }),
            row("Open access", { $0.metrics.oaPercent.map { $0 / 100 } },
                format: { $0.formatted(.percent.precision(.fractionLength(0))) }),
            intRow("Works, last 5y") { $0.metrics.recentWorks5y },
            intRow("Career years") { $0.metrics.careerYears },
            row("Mean RCR", { $0.meanRCR }, format: { String(format: "%.2f", $0) }),
            row("Q1 journal share", { $0.quality?.q1Share },
                format: { $0.formatted(.percent.precision(.fractionLength(0))) }),
            intRow("NIH projects") { $0.funding?.grantCount },
            row("NIH funding", { $0.funding.map { Double($0.totalAwarded) } },
                format: { Int($0).formatted(.currency(code: "USD").precision(.fractionLength(0))) }),
            intRow("Clinical trials (as PI)") { $0.trials?.asPI },
        ]
    }
}

/// The comparison sheet as a one-page PDF.
enum ComparisonPages {
    static func pages(columns: [ComparisonColumn], benchmarks: [RankBenchmark]) -> [AnyView] {
        let footer = "Faculty Comparison · \(ReportStyle.generatedLine)"
        return [
            AnyView(
                ReportPage(footer: footer) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Faculty Comparison").font(.title.weight(.semibold))
                            Text(columns.map(\.member.name).joined(separator: " · "))
                                .foregroundStyle(.secondary)
                        }
                        ComparisonGrid(columns: columns, benchmarks: benchmarks)
                    }
                }
            ),
        ]
    }
}
