import Charts
import SwiftUI
import XCTest
@testable import FacultyIQ

/// Renders a year-axis chart to a PNG for visual inspection.
/// Opt-in: RENDER_OUT=/path/to/out.png swift test --filter AxisRenderTest
final class AxisRenderTest: XCTestCase {
    @MainActor
    func testRenderYearAxis() throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_OUT"] else {
            throw XCTSkip("Set RENDER_OUT=<path.png> to render")
        }
        let counts = [310, 420, 505, 480, 620, 700, 655, 810, 905, 870, 990, 430]
        let data = zip(2015...2026, counts).map { (year: $0, count: $1) }

        let chart = Chart(data, id: \.year) { item in
            LineMark(x: .value("Year", item.year), y: .value("Citations", item.count))
                .lineStyle(StrokeStyle(lineWidth: 2))
            PointMark(x: .value("Year", item.year), y: .value("Citations", item.count))
                .symbolSize(36)
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
