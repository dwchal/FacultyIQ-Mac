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
                }
                .padding(20)
            }
        }
    }

    // MARK: KPI tiles

    private var kpiRow: some View {
        let s = store.summary
        let medianRCR = MetricsEngine.medianRCR(
            roster: store.filteredRoster, personData: store.personData, enrichment: store.enrichment)
        let columns = medianRCR == nil ? 6 : 7
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
        return chartCard("Citations Received per Year", subtitle: "Last decade (OpenAlex counts)",
                         trend: trend, growth: trend.citationsGrowth) {
            CitationsPerYearChart(data: MetricsEngine.citationsPerYear(personData: fetched))
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
