import Charts
import SwiftUI

/// What the division actually works on: OpenAlex primary topics aggregated
/// across the cohort — top topics, their trend over the last decade, and a
/// sortable topic table.
struct TopicsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var sortOrder = [KeyPathComparator(\MetricsEngine.TopicCount.works, order: .reverse)]

    private var fetched: [PersonData] { store.filteredPersonData }

    var body: some View {
        let topics = MetricsEngine.topicCounts(personData: fetched)
        if fetched.isEmpty {
            ContentUnavailableView(
                "No Data Fetched Yet",
                systemImage: "tag",
                description: Text("Resolve faculty and fetch metrics first; topics are read from each work's OpenAlex classification.")
            )
        } else if topics.isEmpty {
            ContentUnavailableView {
                Label("No Topic Data Yet", systemImage: "tag")
            } description: {
                Text("This data was fetched before topics were tracked. Refreshing everyone's works will load them.")
            } actions: {
                Button("Refresh All Data") {
                    Task { await store.fetchAll(refresh: true) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isBusy)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if MetricsEngine.staleTopicData(personData: fetched) {
                        staleBanner
                    }
                    HStack(alignment: .top, spacing: 20) {
                        topTopicsCard(topics)
                        trendCard(topics)
                    }
                    tableCard(topics)
                }
                .padding(20)
            }
        }
    }

    private var staleBanner: some View {
        HStack {
            Label("Some members' data predates topic tracking, so these charts undercount.",
                  systemImage: "exclamationmark.triangle")
                .font(.callout)
            Spacer()
            Button("Refresh All Data") {
                Task { await store.fetchAll(refresh: true) }
            }
            .disabled(store.isBusy)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Cards

    private func topTopicsCard(_ topics: [MetricsEngine.TopicCount]) -> some View {
        let top = Array(topics.prefix(12))
        return card("Top Topics", subtitle: "Distinct works per primary topic (coauthored works count once)") {
            Chart(top) { topic in
                BarMark(
                    x: .value("Works", topic.works),
                    y: .value("Topic", shortLabel(topic.name)),
                    height: .ratio(0.7)
                )
                .foregroundStyle(ChartPalette.series1)
                .cornerRadius(2)
                .annotation(position: .trailing, spacing: 4) {
                    Text(topic.works.formatted())
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

    private func trendCard(_ topics: [MetricsEngine.TopicCount]) -> some View {
        // Four topics at most — the palette's fixed categorical slots, assigned
        // in rank order and never cycled.
        let names = topics.prefix(4).map(\.name)
        let series = MetricsEngine.topicTrend(personData: fetched, topics: names)
        let palette = [ChartPalette.series1, ChartPalette.series2,
                       ChartPalette.series3, ChartPalette.series4]
        return card("Topic Trends", subtitle: "Works per year, top \(names.count) topics, last decade") {
            Chart(series) { point in
                LineMark(
                    x: .value("Year", point.year),
                    y: .value("Works", point.count)
                )
                .foregroundStyle(by: .value("Topic", shortLabel(point.topic)))
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartForegroundStyleScale(domain: names.map { shortLabel($0) },
                                       range: Array(palette.prefix(names.count)))
            .yearXAxis(years: series.map(\.year))
            .frame(height: 240)
        }
    }

    private func tableCard(_ topics: [MetricsEngine.TopicCount]) -> some View {
        card("All Topics", subtitle: "\(topics.count) primary topics across the cohort in view") {
            Table(topics.sorted(using: sortOrder), sortOrder: $sortOrder) {
                TableColumn("Topic", value: \.name)
                TableColumn("Field", value: \.fieldSort) { Text($0.field ?? "—") }
                    .width(min: 100, ideal: 160)
                TableColumn("Works", value: \.works) { Text("\($0.works)") }
                    .width(60)
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

    /// Topic names can run long ("Peripheral Neuropathies and Nerve Compression
    /// Syndromes"); trim for axis labels.
    private func shortLabel(_ name: String, max: Int = 34) -> String {
        name.count <= max ? name : String(name.prefix(max - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

// Sort key for the optional column; missing values sort first ascending.
private extension MetricsEngine.TopicCount {
    var fieldSort: String { field ?? "" }
}
