import Charts
import SwiftUI
import XCTest
@testable import FacultyIQ

/// Renders the two novel chart configurations added with the Publications tab
/// and the Funding timeline — stacked RectangleMark OA composition and the
/// date-axis Gantt — to PNGs for visual inspection.
/// Opt-in: RENDER_DIR=/path/to/dir swift test --filter PublicationsRenderTest
final class PublicationsRenderTest: XCTestCase {
    @MainActor
    private func write(_ view: some View, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    private func renderDir() throws -> URL {
        guard let dir = ProcessInfo.processInfo.environment["RENDER_DIR"] else {
            throw XCTSkip("Set RENDER_DIR=<dir> to render")
        }
        return URL(fileURLWithPath: dir)
    }

    @MainActor
    func testRenderOAStackedComposition() throws {
        let dir = try renderDir()
        // Rising OA over the decade, like real division data.
        var shares: [MetricsEngine.OAStatusYearShare] = []
        for (i, year) in (2017...2026).enumerated() {
            let gold = Double(15 + 3 * i)
            let hybrid = 10.0
            let green = Double(12 + i)
            let bronze = 8.0
            shares.append(contentsOf: [
                .init(status: "gold", year: year, percent: gold),
                .init(status: "hybrid", year: year, percent: hybrid),
                .init(status: "green", year: year, percent: green),
                .init(status: "bronze", year: year, percent: bronze),
                .init(status: "closed", year: year, percent: 100 - gold - hybrid - green - bronze),
            ])
        }
        var running: [Int: Double] = [:]
        let segments = shares.map { share in
            let start = running[share.year, default: 0]
            running[share.year] = start + share.percent
            return (id: share.id, status: share.status, year: share.year,
                    yStart: start, yEnd: start + share.percent)
        }
        let statuses = ["gold", "hybrid", "green", "bronze", "closed"]
        let colors: [Color] = [ChartPalette.series3, ChartPalette.series2, ChartPalette.series4,
                               ChartPalette.series1Light, Color.gray.opacity(0.55)]
        let chart = Chart(segments, id: \.id) { segment in
            RectangleMark(
                xStart: .value("Year", Double(segment.year) - 0.35),
                xEnd: .value("Year", Double(segment.year) + 0.35),
                yStart: .value("Share", segment.yStart),
                yEnd: .value("Share", segment.yEnd)
            )
            .foregroundStyle(by: .value("Status", segment.status))
        }
        .chartForegroundStyleScale(domain: statuses, range: colors)
        .chartYScale(domain: 0...100)
        .yearXAxis(years: shares.map(\.year))
        .frame(width: 520, height: 240)
        .padding(20)
        .background(Color.white)

        try write(chart, to: dir.appendingPathComponent("oa_detail.png"))
    }

    @MainActor
    func testRenderGrantGantt() throws {
        let dir = try renderDir()
        let calendar = Calendar(identifier: .gregorian)
        func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
            calendar.date(from: DateComponents(year: y, month: m, day: d))!
        }
        func grant(_ core: String) -> Grant {
            Grant(coreProjectNum: core, latestProjectNum: "5\(core)-03", title: core,
                  activityCode: nil, fiscalYears: [2024], totalAward: 0,
                  startDate: nil, endDate: nil, orgName: nil)
        }
        let bars: [MetricsEngine.GrantBar] = [
            .init(memberName: "Alice", grant: grant("R01AI000001"),
                  start: date(2022, 4, 1), end: date(2029, 3, 31),
                  approximate: false, isActive: true, expiresSoon: false),
            .init(memberName: "Alice", grant: grant("K24HL000002"),
                  start: date(2021, 7, 1), end: date(2026, 12, 31),
                  approximate: false, isActive: true, expiresSoon: true),
            .init(memberName: "Bob", grant: grant("R01AI000001"),
                  start: date(2022, 4, 1), end: date(2029, 3, 31),
                  approximate: false, isActive: true, expiresSoon: false),
            .init(memberName: "Carol", grant: grant("U01CA000003"),
                  start: date(2023, 1, 1), end: date(2025, 12, 31),
                  approximate: true, isActive: false, expiresSoon: false),
        ]
        func label(_ bar: MetricsEngine.GrantBar) -> String {
            "\(bar.memberName) — \(bar.grant.coreProjectNum)"
        }
        func status(_ bar: MetricsEngine.GrantBar) -> String {
            bar.expiresSoon ? "Expiring ≤ 12 mo" : bar.isActive ? "Active" : "Ended"
        }
        let chart = Chart {
            ForEach(bars) { bar in
                BarMark(
                    xStart: .value("Start", bar.start),
                    xEnd: .value("End", bar.end),
                    y: .value("Grant", label(bar)),
                    height: .ratio(0.6)
                )
                .foregroundStyle(by: .value("Status", status(bar)))
                .cornerRadius(3)
                .annotation(position: .trailing, spacing: 4) {
                    Text((bar.approximate ? "≈ " : "")
                         + bar.end.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            RuleMark(x: .value("Today", date(2026, 7, 15)))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .chartForegroundStyleScale(
            domain: ["Expiring ≤ 12 mo", "Active", "Ended"],
            range: [ChartPalette.critical, ChartPalette.series1, ChartPalette.series1Light])
        .chartYScale(domain: bars.map(label))
        .chartXAxis {
            AxisMarks(values: .stride(by: .year)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.year())
            }
        }
        .frame(width: 640, height: CGFloat(bars.count) * 26 + 70)
        .padding(20)
        .background(Color.white)

        try write(chart, to: dir.appendingPathComponent("grant_gantt.png"))
    }
}
