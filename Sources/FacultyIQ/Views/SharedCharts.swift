import Charts
import SwiftUI

// Chart bodies shared between the on-screen dashboard/profile views and the
// PDF report pages, so both render identical configurations.

/// Publications per year as year columns.
struct WorksPerYearChart: View {
    let data: [(year: Int, count: Int)]

    var body: some View {
        Chart(data, id: \.year) { item in
            yearColumn(year: item.year, label: "Works", value: Double(item.count))
                .foregroundStyle(ChartPalette.series1)
                .cornerRadius(2)
        }
        .yearXAxis(years: data.map(\.year))
    }
}

/// Citations received per year as a line with point markers.
struct CitationsPerYearChart: View {
    let data: [(year: Int, count: Int)]

    var body: some View {
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

/// Open-access share of works per year, on a fixed 0–100 scale.
struct OAShareChart: View {
    let data: [(year: Int, percent: Double)]

    var body: some View {
        Chart(data, id: \.year) { item in
            yearColumn(year: item.year, label: "OA %", value: item.percent)
                .foregroundStyle(ChartPalette.series2)
                .cornerRadius(2)
        }
        .chartYScale(domain: 0...100)
        .yearXAxis(years: data.map(\.year))
    }
}

/// Horizontal bars of total citations for the most-cited faculty.
struct TopFacultyChart: View {
    let metrics: [PersonMetrics]     // already sorted and truncated by the caller

    var body: some View {
        Chart(metrics) { m in
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
