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

/// Citations received per year as a line with point markers. The current
/// year is always partial, so its actual-to-date point is joined by an open
/// marker at the prorated full-year pace (dashed) — without it the last
/// point reads as a citation collapse every January through November.
struct CitationsPerYearChart: View {
    let data: [(year: Int, count: Int)]
    var prorate = true

    /// Prorated full-year value for the current year, once enough of the
    /// year has elapsed for the pace to mean anything (~Feb onward).
    private var pace: (projected: Int, through: Date)? {
        guard prorate,
              let last = data.last, last.year == MetricsEngine.currentYear,
              data.count >= 2 else { return nil }
        let calendar = Calendar.current
        let now = Date()
        guard let day = calendar.ordinality(of: .day, in: .year, for: now) else { return nil }
        let totalDays = calendar.dateInterval(of: .year, for: now).map {
            calendar.dateComponents([.day], from: $0.start, to: $0.end).day ?? 365
        } ?? 365
        let fraction = Double(day) / Double(totalDays)
        guard fraction >= 0.09, fraction <= 0.98 else { return nil }
        return (Int((Double(last.count) / fraction).rounded()), now)
    }

    var body: some View {
        // When the pace marker is shown, the solid line stops at the last
        // complete year — connecting it to the partial-year point draws the
        // very citation collapse the marker exists to prevent.
        let lineData = pace == nil ? data : Array(data.dropLast())
        VStack(alignment: .leading, spacing: 2) {
            Chart {
                ForEach(lineData, id: \.year) { item in
                    LineMark(
                        x: .value("Year", item.year),
                        y: .value("Citations", item.count),
                        series: .value("Series", "actual")
                    )
                    .foregroundStyle(ChartPalette.series1)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                ForEach(data, id: \.year) { item in
                    PointMark(
                        x: .value("Year", item.year),
                        y: .value("Citations", item.count)
                    )
                    .foregroundStyle(ChartPalette.series1)
                    .symbolSize(36)
                }
                if let pace, let previous = data.dropLast().last, let last = data.last {
                    LineMark(
                        x: .value("Year", previous.year),
                        y: .value("Citations", previous.count),
                        series: .value("Series", "pace")
                    )
                    .foregroundStyle(ChartPalette.series1.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    LineMark(
                        x: .value("Year", last.year),
                        y: .value("Citations", pace.projected),
                        series: .value("Series", "pace")
                    )
                    .foregroundStyle(ChartPalette.series1.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    PointMark(
                        x: .value("Year", last.year),
                        y: .value("Citations", pace.projected)
                    )
                    .foregroundStyle(.clear)
                    .symbolSize(48)
                    .annotation(position: .topTrailing, spacing: 2) {
                        Text("pace")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    PointMark(
                        x: .value("Year", last.year),
                        y: .value("Citations", pace.projected)
                    )
                    .symbol {
                        Circle()
                            .strokeBorder(ChartPalette.series1.opacity(0.7), lineWidth: 1.5)
                            .frame(width: 7, height: 7)
                    }
                }
            }
            .yearXAxis(years: data.map(\.year))
            if let pace, let last = data.last {
                Text("\(String(last.year)) shows \(last.count.formatted()) citations through \(pace.through.formatted(.dateTime.month(.abbreviated).day())); ○ marks the full-year pace (≈\(pace.projected.formatted())).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
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
