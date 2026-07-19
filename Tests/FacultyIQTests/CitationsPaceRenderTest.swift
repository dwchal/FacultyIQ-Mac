import SwiftUI
import XCTest
@testable import FacultyIQ

/// Renders the citations-per-year chart with a partial current year to a PNG
/// for visual inspection of the prorated full-year pace marker.
/// Opt-in: RENDER_OUT=/path/to/out.png swift test --filter CitationsPaceRenderTest
final class CitationsPaceRenderTest: XCTestCase {
    @MainActor
    func testRenderProratedCurrentYear() throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_OUT"] else {
            throw XCTSkip("Set RENDER_OUT=<path.png> to render")
        }
        let current = MetricsEngine.currentYear
        var data = (current - 9..<current).map { year in
            (year: year, count: 800 + (year - current + 10) * 120)
        }
        // A little over half the prior year's total — a realistic mid-July
        // reading that used to draw as a collapse.
        data.append((year: current, count: 1100))

        let chart = CitationsPerYearChart(data: data)
            .frame(width: 480, height: 220)
            .padding(20)
            .background(Color.white)
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: chart)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: out))
    }
}
