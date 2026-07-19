import Charts
import SwiftUI

/// Builds the division/department summary PDF: KPI row plus the four
/// dashboard charts and the rank-benchmark table.
enum SummaryPages {
    static func pages(summary: DivisionSummary,
                      metrics: [PersonMetrics],
                      personData: [PersonData],
                      benchmarks: [RankBenchmark],
                      divisionName: String?,
                      scopusLine: String? = nil) -> [AnyView] {
        let scope = divisionName ?? "All Divisions"
        func footer(_ page: Int) -> String {
            "\(scope) — Faculty Report · page \(page)/2 · \(ReportStyle.generatedLine)"
        }
        return [
            AnyView(firstPage(summary: summary, personData: personData,
                              scope: scope, scopusLine: scopusLine, footer: footer(1))),
            AnyView(secondPage(metrics: metrics, personData: personData,
                               benchmarks: benchmarks, footer: footer(2))),
        ]
    }

    private static func firstPage(summary: DivisionSummary,
                                  personData: [PersonData],
                                  scope: String,
                                  scopusLine: String?,
                                  footer: String) -> some View {
        ReportPage(footer: footer) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Faculty Report").font(.title.weight(.semibold))
                    Text(scope).foregroundStyle(.secondary)
                }

                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        ReportTile(label: "Faculty", value: "\(summary.facultyCount)")
                        ReportTile(label: "Resolved", value: "\(summary.resolvedCount)")
                        ReportTile(label: "Total Works", value: summary.totalWorks.formatted())
                        ReportTile(label: "Total Citations", value: summary.totalCitations.formatted())
                        ReportTile(label: "Median h-index", value: String(format: "%.0f", summary.medianHIndex))
                        ReportTile(label: "Open Access",
                                   value: summary.oaPercent.map { String(format: "%.0f%%", $0) } ?? "—")
                    }
                }

                if let scopusLine {
                    Text(scopusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                chartSection("Publications per Year",
                             subtitle: "All indexed works across the cohort") {
                    WorksPerYearChart(data: MetricsEngine.worksPerYear(personData: personData))
                }
                chartSection("Citations Received per Year",
                             subtitle: "Last decade (OpenAlex counts)") {
                    CitationsPerYearChart(
                        data: MetricsEngine.citationsPerYear(personData: personData),
                        prorate: !MetricsEngine.staleCitationData(personData: personData))
                }
            }
        }
    }

    private static func secondPage(metrics: [PersonMetrics],
                                   personData: [PersonData],
                                   benchmarks: [RankBenchmark],
                                   footer: String) -> some View {
        ReportPage(footer: footer) {
            VStack(alignment: .leading, spacing: 18) {
                chartSection("Open Access Share",
                             subtitle: "% of works published open access, by year") {
                    OAShareChart(data: MetricsEngine.oaShareByYear(personData: personData))
                }
                chartSection("Most-Cited Faculty", subtitle: "Total citations, top 10") {
                    TopFacultyChart(metrics: Array(metrics.sorted { $0.citations > $1.citations }.prefix(10)))
                }
                if !benchmarks.isEmpty {
                    benchmarkSection(benchmarks)
                }
            }
        }
    }

    private static func chartSection(_ title: String, subtitle: String,
                                     @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content()
                .frame(height: 180)
        }
    }

    private static func benchmarkSection(_ benchmarks: [RankBenchmark]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rank Benchmarks").font(.headline)
                Text("Median within each rank; targets are the 25th percentile of current rank-holders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Rank").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Faculty").gridColumnAlignment(.trailing)
                    Text("Works").gridColumnAlignment(.trailing)
                    Text("Citations").gridColumnAlignment(.trailing)
                    Text("h-index").gridColumnAlignment(.trailing)
                    Text("Works / Year").gridColumnAlignment(.trailing)
                }
                .font(.caption.weight(.semibold))
                Rectangle().fill(ReportStyle.rowRule).frame(height: 0.5)
                    .gridCellColumns(6)
                ForEach(benchmarks) { bench in
                    GridRow {
                        Text(bench.rank.label)
                        Text("\(bench.count)")
                        benchmarkCell(median: bench.medianWorks, target: bench.targetWorks)
                        benchmarkCell(median: bench.medianCitations, target: bench.targetCitations)
                        benchmarkCell(median: bench.medianHIndex, target: bench.targetHIndex)
                        Text(String(format: "%.2f", bench.medianWorksPerYear))
                    }
                    .font(.footnote)
                }
            }
        }
    }

    private static func benchmarkCell(median: Double, target: Double) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(String(format: "%.0f", median))
            Text(String(format: "target %.0f", target))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
