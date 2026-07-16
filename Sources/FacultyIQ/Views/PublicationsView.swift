import Charts
import SwiftUI

/// The shape of the division's output: work types, open-access status
/// detail, and the venues the cohort publishes in.
struct PublicationsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var sortOrder = [KeyPathComparator(\MetricsEngine.VenueCount.works, order: .reverse)]

    private var fetched: [PersonData] { store.filteredPersonData }

    var body: some View {
        if fetched.isEmpty {
            ContentUnavailableView(
                "No Data Fetched Yet",
                systemImage: "doc.text",
                description: Text("Resolve faculty and fetch metrics first; types and venues are read from each work's OpenAlex record.")
            )
        } else {
            let types = MetricsEngine.typeCounts(personData: fetched)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 20) {
                        typesCard(types)
                        trendCard(types)
                    }
                    oaDetailCard
                    venuesCard
                }
                .padding(20)
            }
        }
    }

    // MARK: Cards

    private func typesCard(_ types: [MetricsEngine.TypeCount]) -> some View {
        let top = Array(types.prefix(10))
        return card("Publication Types", subtitle: "Distinct works per type (coauthored works count once)") {
            Chart(top) { type in
                BarMark(
                    x: .value("Works", type.works),
                    y: .value("Type", type.name),
                    height: .ratio(0.7)
                )
                .foregroundStyle(ChartPalette.series1)
                .cornerRadius(2)
                .annotation(position: .trailing, spacing: 4) {
                    Text(type.works.formatted())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                }
            }
            .frame(height: CGFloat(top.count) * 26)
        }
    }

    private func trendCard(_ types: [MetricsEngine.TypeCount]) -> some View {
        // Four types at most — the palette's fixed categorical slots, assigned
        // in rank order and never cycled.
        let names = types.prefix(4).map(\.name)
        let series = MetricsEngine.typeTrend(personData: fetched, types: names)
        let palette = [ChartPalette.series1, ChartPalette.series2,
                       ChartPalette.series3, ChartPalette.series4]
        return card("Types over Time", subtitle: "Works per year, top \(names.count) types, last decade") {
            Chart(series) { point in
                LineMark(
                    x: .value("Year", point.year),
                    y: .value("Works", point.count)
                )
                .foregroundStyle(by: .value("Type", point.type))
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartForegroundStyleScale(domain: names,
                                       range: Array(palette.prefix(names.count)))
            .yearXAxis(years: series.map(\.year))
            .frame(height: 240)
        }
    }

    /// OA statuses have fixed semantic colors (never rank-assigned): the
    /// palette's greens/yellows for the open routes, gray for closed.
    private static let oaStatusColors: [String: Color] = [
        "diamond": ChartPalette.positive,
        "gold": ChartPalette.series3,
        "hybrid": ChartPalette.series2,
        "green": ChartPalette.series4,
        "bronze": ChartPalette.series1Light,
        "closed": Color.gray.opacity(0.55),
    ]

    private var oaDetailCard: some View {
        let shares = MetricsEngine.oaStatusByYear(personData: fetched)
        // Cumulative segments per year: Swift Charts can't stack RectangleMarks
        // itself, and BarMark stacking needs a categorical x.
        var running: [Int: Double] = [:]
        let segments = shares.map { share in
            let start = running[share.year, default: 0]
            running[share.year] = start + share.percent
            return (id: share.id, status: share.status, year: share.year,
                    yStart: start, yEnd: start + share.percent)
        }
        let statuses = orderedStatuses(in: shares)
        return card("Open Access Detail", subtitle: "OA-status composition of each year's works, percent") {
            Chart(segments, id: \.id) { segment in
                RectangleMark(
                    xStart: .value("Year", Double(segment.year) - 0.35),
                    xEnd: .value("Year", Double(segment.year) + 0.35),
                    yStart: .value("Share", segment.yStart),
                    yEnd: .value("Share", segment.yEnd)
                )
                .foregroundStyle(by: .value("Status", segment.status))
            }
            .chartForegroundStyleScale(
                domain: statuses,
                range: statuses.map { Self.oaStatusColors[$0] ?? Color.gray.opacity(0.55) })
            .chartYScale(domain: 0...100)
            .yearXAxis(years: shares.map(\.year))
            .frame(height: 240)
        }
    }

    /// The statuses present in the data, in the engine's canonical order.
    private func orderedStatuses(in shares: [MetricsEngine.OAStatusYearShare]) -> [String] {
        let present = Set(shares.map(\.status))
        let known = MetricsEngine.oaStatusOrder.filter(present.contains)
        return known + present.subtracting(known).sorted()
    }

    private var venuesCard: some View {
        let venues = MetricsEngine.venueCounts(personData: fetched)
        return card("Top Venues", subtitle: "\(venues.count) venues across the cohort in view") {
            Table(venues.sorted(using: sortOrder), sortOrder: $sortOrder) {
                TableColumn("Venue", value: \.name)
                TableColumn("Works", value: \.works) { Text("\($0.works)") }
                    .width(60)
                TableColumn("Citations", value: \.citations) { Text($0.citations.formatted()) }
                    .width(80)
                TableColumn("Faculty", value: \.people) { Text("\($0.people)") }
                    .width(60)
            }
            .frame(height: 320)
        }
    }

    private func card(_ title: String, subtitle: String,
                      @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
