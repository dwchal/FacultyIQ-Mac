import Charts
import SwiftUI
import XCTest
@testable import FacultyIQ

/// Renders a year-column chart (the dashboard works-chart configuration) to a
/// PNG for visual inspection. Regression guard for the invisible-bars bug:
/// BarMark width .ratio has no bandwidth on a continuous year axis, which is
/// why charts draw columns via yearColumn() instead.
/// Opt-in: RENDER_OUT=/path/to/out.png swift test --filter YearChartRenderTest
final class YearChartRenderTest: XCTestCase {
    @MainActor
    func testRenderYearColumns() throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_OUT"] else {
            throw XCTSkip("Set RENDER_OUT=<path.png> to render")
        }
        // Sparse early years, dense recent ones — like real division data.
        var data: [(year: Int, count: Int)] = []
        for year in 1990...2026 where year < 2004 ? year % 3 == 0 : true {
            data.append((year: year, count: year < 2004 ? 2 : (year - 2000) * 6))
        }

        let chart = Chart(data, id: \.year) { item in
            yearColumn(year: item.year, label: "Works", value: Double(item.count))
                .foregroundStyle(.blue)
                .cornerRadius(2)
        }
        .yearXAxis(years: data.map(\.year))
        .frame(width: 480, height: 220)
        .padding(20)
        .background(Color.white)

        let renderer = ImageRenderer(content: chart)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: out))
    }
}
