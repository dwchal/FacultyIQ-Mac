import Charts
import SwiftUI

/// Division-level overview: KPI tiles, publication/citation trends, rank
/// medians, and the most-cited faculty.
struct DashboardView: View {
    @EnvironmentObject private var store: AppStore

    private var fetched: [PersonData] { store.filteredPersonData }

    var body: some View {
        if fetched.isEmpty {
            ContentUnavailableView(
                "No Data Fetched Yet",
                systemImage: "chart.bar.xaxis",
                description: Text("Resolve faculty on the Resolution tab, then click Fetch Metrics to populate the dashboard.")
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    kpiRow
                    HStack(alignment: .top, spacing: 20) {
                        worksChart
                        citationsChart
                    }
                    HStack(alignment: .top, spacing: 20) {
                        oaChart
                        topFacultyChart
                    }
                    HStack(alignment: .top, spacing: 20) {
                        vintageChart
                        if !topTranslational.isEmpty {
                            translationalChart
                        }
                    }
                    if history.count >= 2 {
                        historyRow
                    }
                }
                .padding(20)
            }
        }
    }

    // MARK: Tracked history

    /// The app's own record of the cohort's totals across fetches — actual
    /// observed movement, unlike the year charts inferred from OpenAlex data.
    private var history: [MetricsEngine.HistoryPoint] {
        let authorIDs = Set(store.filteredRoster.compactMap { store.resolutions[$0.id]?.openalexID })
        return MetricsEngine.divisionHistory(snapshots: store.snapshots, authorIDs: authorIDs)
    }

    private var historyRow: some View {
        let points = history
        let tracked = points.last?.tracked ?? 0
        // Two measures of different scale get two charts, never a second axis.
        return HStack(alignment: .top, spacing: 20) {
            chartCard("Tracked Works", subtitle: "Total works at each data fetch (\(tracked) tracked)") {
                historyChart(points, value: \.works, label: "Works")
            }
            chartCard("Tracked Citations", subtitle: "Total citations at each data fetch (\(tracked) tracked)") {
                historyChart(points, value: \.citations, label: "Citations")
            }
        }
    }

    private func historyChart(_ points: [MetricsEngine.HistoryPoint],
                              value: KeyPath<MetricsEngine.HistoryPoint, Int>,
                              label: String) -> some View {
        Chart(points) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value(label, point[keyPath: value])
            )
            .foregroundStyle(ChartPalette.series1)
            .lineStyle(StrokeStyle(lineWidth: 2))
            PointMark(
                x: .value("Date", point.date),
                y: .value(label, point[keyPath: value])
            )
            .foregroundStyle(ChartPalette.series1)
            .symbolSize(36)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .dayXAxis(dates: points.map(\.date))
    }

    // MARK: KPI tiles

    private var kpiRow: some View {
        let s = store.summary
        let medianRCR = MetricsEngine.medianRCR(
            roster: store.filteredRoster, personData: store.effectivePersonData, enrichment: store.enrichment)
        let medianAPT = MetricsEngine.medianAPT(
            roster: store.filteredRoster, personData: store.effectivePersonData, enrichment: store.enrichment)
        let columns = 6 + (medianRCR == nil ? 0 : 1) + (medianAPT == nil ? 0 : 1)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
            kpi("Faculty", "\(s.facultyCount)")
            kpi("Resolved", "\(s.resolvedCount)")
            kpi("Total Works", s.totalWorks.formatted())
            kpi("Total Citations", s.totalCitations.formatted())
            kpi("Median h-index", String(format: "%.0f", s.medianHIndex))
            kpi("Open Access", s.oaPercent.map { String(format: "%.0f%%", $0) } ?? "—")
            if let medianRCR {
                kpi("Median RCR", String(format: "%.2f", medianRCR))
                    .help("Median of each member's mean Relative Citation Ratio (NIH iCite)")
            }
            if let medianAPT {
                kpi("Median APT", String(format: "%.2f", medianAPT))
                    .help("Median of each member's mean Approximate Potential to Translate (NIH iCite), 0–1")
            }
        }
    }

    private func kpi(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 26, weight: .semibold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Charts

    private var worksChart: some View {
        let trend = MetricsEngine.divisionTrend(personData: fetched)
        return chartCard("Publications per Year", subtitle: "All indexed works across the division",
                         trend: trend, growth: trend.worksGrowth) {
            WorksPerYearChart(data: MetricsEngine.worksPerYear(personData: fetched))
        }
    }

    private var citationsChart: some View {
        let trend = MetricsEngine.divisionTrend(personData: fetched)
        return chartCard("Citations Received per Year",
                         subtitle: "New citations to the cohort's works, dated by the citing paper's year (last decade)",
                         trend: trend, growth: trend.citationsGrowth) {
            VStack(alignment: .leading, spacing: 4) {
                CitationsPerYearChart(data: MetricsEngine.citationsPerYear(personData: fetched))
                if MetricsEngine.staleCitationData(personData: fetched) {
                    Label("Some members' data predates per-work citation tracking — Refresh Data for accurate citation timing.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var vintageChart: some View {
        let series = MetricsEngine.citationsByPublicationYear(personData: fetched)
        return chartCard("Citations by Publication Year",
                         subtitle: "Citations accrued to date by each year's papers (coauthored works count once) — recent years are still accruing") {
            Chart(series, id: \.year) { item in
                yearColumn(year: item.year, label: "Citations", value: Double(item.citations))
                    .foregroundStyle(ChartPalette.series1Light)
                    .cornerRadius(2)
            }
            .yearXAxis(years: series.map(\.year))
        }
    }

    private var oaChart: some View {
        chartCard("Open Access Share", subtitle: "% of works published open access, by year") {
            OAShareChart(data: MetricsEngine.oaShareByYear(personData: fetched))
        }
    }

    private var topFacultyChart: some View {
        chartCard("Most-Cited Faculty", subtitle: "Total citations, top 10") {
            TopFacultyChart(metrics: Array(store.metrics.sorted { $0.citations > $1.citations }.prefix(10)))
        }
    }

    // Only rendered when iCite enrichment has produced APT scores.
    private var topTranslational: [MetricsEngine.TranslationalEntry] {
        MetricsEngine.topTranslational(
            roster: store.filteredRoster, personData: store.effectivePersonData, enrichment: store.enrichment)
    }

    private var translationalChart: some View {
        let top = Array(topTranslational.prefix(10))
        return chartCard("Most-Translational Faculty",
                         subtitle: "Mean Approximate Potential to Translate (NIH iCite), top 10") {
            Chart(top) { entry in
                BarMark(
                    x: .value("Mean APT", entry.meanAPT),
                    y: .value("Name", entry.name),
                    height: .ratio(0.7)
                )
                .foregroundStyle(ChartPalette.series2)
                .cornerRadius(2)
                .annotation(position: .trailing, spacing: 4) {
                    Text(String(format: "%.2f", entry.meanAPT))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXScale(domain: 0...1)
            .chartXAxis(.hidden)
        }
    }

    private func chartCard(_ title: String, subtitle: String,
                           trend: TrendMetrics? = nil, growth: Double? = nil,
                           @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let trend, let growth {
                    growthBadge(growth, trend: trend)
                }
            }
            content()
                .frame(height: 220)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Annualized 3y-vs-3y growth for the cohort in view, current year pro-rated.
    private func growthBadge(_ growth: Double, trend: TrendMetrics) -> some View {
        let color = growth >= 0 ? ChartPalette.positive : ChartPalette.critical
        return HStack(spacing: 4) {
            Image(systemName: growth >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.caption.weight(.bold))
            Text(String(format: "%+.0f%%/yr", growth))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
        .help(String(format: "Annualized rate, %d–%d vs %d–%d; %d counts as %.0f%% of a year",
                     trend.recentYears.lowerBound, trend.recentYears.upperBound,
                     trend.priorYears.lowerBound, trend.priorYears.upperBound,
                     MetricsEngine.currentYear, trend.currentYearFraction * 100))
    }
}
