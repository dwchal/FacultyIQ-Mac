import Charts
import SwiftUI

/// Column mark for charts whose x is an integer year. BarMark's
/// `width: .ratio` has no unit bandwidth on a continuous axis and silently
/// renders zero-width bars, so span an explicit x interval (70% of a year).
func yearColumn(year: Int, label: String, value: Double) -> some ChartContent {
    RectangleMark(
        xStart: .value("Year", Double(year) - 0.35),
        xEnd: .value("Year", Double(year) + 0.35),
        yStart: .value(label, 0.0),
        yEnd: .value(label, value)
    )
}

extension View {
    /// X axis for charts whose x is a Date at day granularity (the tracked-
    /// history charts): ticks on distinct days, thinned to a readable count
    /// and anchored so the most recent day is always labeled, formatted
    /// "Jul 16". The automatic axis shows times of day (12 AM, 6 AM, …) when
    /// readings span only a few days.
    func dayXAxis(dates: [Date]) -> some View {
        let calendar = Calendar.current
        let days = Array(Set(dates.map { calendar.startOfDay(for: $0) })).sorted()
        let step = max(1, Int((Double(days.count) / 6.0).rounded(.up)))
        let ticks = stride(from: days.count - 1, through: 0, by: -step).reversed().map { days[$0] }
        let last = dates.max() ?? Date()

        return self
            // Start the domain at the first tick so it isn't dropped for
            // sitting before the earliest reading's timestamp.
            .chartXScale(domain: (days.first ?? last)...last)
            .chartXAxis {
                AxisMarks(values: Array(ticks)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
    }

    /// X axis for charts whose x is an integer year: plain year labels (no
    /// thousands separators), whole-year ticks at a readable density anchored
    /// so the most recent year is always labeled, and domain padding so edge
    /// bars aren't clipped.
    func yearXAxis(years: [Int]) -> some View {
        let minYear = years.min() ?? MetricsEngine.currentYear
        let maxYear = years.max() ?? MetricsEngine.currentYear
        let step = max(1, Int((Double(maxYear - minYear) / 7.0).rounded(.up)))
        let ticks = Array(stride(from: maxYear, through: minYear, by: -step)).reversed()

        return self
            .chartXScale(domain: Double(minYear) - 0.6 ... Double(maxYear) + 0.6)
            .chartXAxis {
                AxisMarks(values: Array(ticks)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let year = value.as(Int.self) {
                            Text(String(year))
                                .fixedSize() // edge labels overflow instead of truncating to "2…"
                        }
                    }
                }
            }
    }
}
