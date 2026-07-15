import Charts
import SwiftUI
import XCTest
@testable import FacultyIQ

/// Renders the profile-list works sparkline plus a projection-style chart to a
/// PNG for visual inspection.
/// Opt-in: RENDER_OUT=/path/to/out.png swift test --filter SparklineRenderTest
final class SparklineRenderTest: XCTestCase {
    @MainActor
    func testRenderSparklineAndProjection() throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_OUT"] else {
            throw XCTSkip("Set RENDER_OUT=<path.png> to render")
        }
        let year = MetricsEngine.currentYear
        let sparkline = ((year - 9)...year).map { (year: $0, count: ($0 % 4) + ($0 > year - 3 ? 3 : 0)) }
        let history = (0..<10).map { (x: Double(year - 9 + $0), y: Double(20 + $0 * 4)) }
        let projected = [(x: Double(year), y: 56.0), (x: Double(year + 3), y: 71.0)]

        let content = VStack(alignment: .leading, spacing: 20) {
            Chart(sparkline, id: \.year) { point in
                LineMark(x: .value("Year", point.year), y: .value("Works", point.count))
                    .foregroundStyle(ChartPalette.series1)
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
            }
            .chartXScale(domain: (year - 9)...year)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(width: 56, height: 16)

            Chart {
                ForEach(history, id: \.x) { point in
                    LineMark(x: .value("Year", point.x), y: .value("Cumulative Works", point.y),
                             series: .value("Series", "History"))
                        .foregroundStyle(ChartPalette.series1)
                }
                ForEach(projected, id: \.x) { point in
                    LineMark(x: .value("Year", point.x), y: .value("Cumulative Works", point.y),
                             series: .value("Series", "Projected"))
                        .foregroundStyle(ChartPalette.series1Light)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
                RuleMark(y: .value("Target", 68.0))
                    .foregroundStyle(ChartPalette.series3)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("works target ≈ \(String(year + 3))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            .yearXAxis(years: history.map { Int($0.x) } + [year + 3])
            .frame(width: 480, height: 180)
        }
        .padding(20)
        .background(Color.white)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: out))
    }
}
