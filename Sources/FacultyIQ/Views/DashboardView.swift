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
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
            kpi("Faculty", "\(s.facultyCount)")
            kpi("Resolved", "\(s.resolvedCount)")
            kpi("Total Works", s.totalWorks.formatted())
            kpi("Total Citations", s.totalCitations.formatted())
            kpi("Median h-index", String(format: "%.0f", s.medianHIndex))
            kpi("Open Access", s.oaPercent.map { String(format: "%.0f%%", $0) } ?? "—")
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
        let data = MetricsEngine.worksPerYear(personData: fetched)
        return chartCard("Publications per Year", subtitle: "All indexed works across the division") {
            Chart(data, id: \.year) { item in
                yearColumn(year: item.year, label: "Works", value: Double(item.count))
                    .foregroundStyle(ChartPalette.series1)
                    .cornerRadius(2)
            }
            .yearXAxis(years: data.map(\.year))
        }
    }

    private var citationsChart: some View {
        let data = MetricsEngine.citationsPerYear(personData: fetched)
        return chartCard("Citations Received per Year", subtitle: "Last decade (OpenAlex counts)") {
            Chart(data, id: \.year) { item in
                LineMark(
                    x: .value("Year", item.year),
                    y: .value("Citations", item.count)
                )
                .foregroundStyle(ChartPalette.series1)
                .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(
                    x: .value("Year", item.year),
                    y: .value("Citations", item.count)
                )
                .foregroundStyle(ChartPalette.series1)
                .symbolSize(36)
            }
            .yearXAxis(years: data.map(\.year))
        }
    }

    private var oaChart: some View {
        let data = MetricsEngine.oaShareByYear(personData: fetched)
        return chartCard("Open Access Share", subtitle: "% of works published open access, by year") {
            Chart(data, id: \.year) { item in
                yearColumn(year: item.year, label: "OA %", value: item.percent)
                    .foregroundStyle(ChartPalette.series2)
                    .cornerRadius(2)
            }
            .chartYScale(domain: 0...100)
            .yearXAxis(years: data.map(\.year))
        }
    }

    private var topFacultyChart: some View {
        let top = store.metrics.sorted { $0.citations > $1.citations }.prefix(10)
        return chartCard("Most-Cited Faculty", subtitle: "Total citations, top 10") {
            Chart(Array(top)) { m in
                BarMark(
                    x: .value("Citations", m.citations),
                    y: .value("Name", m.name),
                    height: .ratio(0.7)
                )
                .foregroundStyle(ChartPalette.series1)
                .cornerRadius(2)
                .annotation(position: .trailing, spacing: 4) {
                    Text(m.citations.formatted())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
        }
    }

    private func chartCard(_ title: String, subtitle: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content()
                .frame(height: 220)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
