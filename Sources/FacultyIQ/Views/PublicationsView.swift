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
                    retractionsCard
                    preprintsCard
                    journalQualityCard
                    oaDetailCard
                    venuesCard
                }
                .padding(20)
            }
        }
    }

    /// Only appears when OpenAlex flags something — silence is the good news.
    @ViewBuilder
    private var retractionsCard: some View {
        let retracted = MetricsEngine.retractedWorks(
            roster: store.filteredRoster, personData: store.effectivePersonData)
        if !retracted.isEmpty {
            card("Retracted Works",
                 subtitle: "\(retracted.count) works in the cohort are flagged retracted by OpenAlex") {
                VStack(alignment: .leading, spacing: 6) {
                    // A shared retracted work lists each affected member, so
                    // work.id alone isn't unique here.
                    ForEach(Array(retracted.prefix(10).enumerated()), id: \.offset) { _, entry in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .foregroundStyle(ChartPalette.critical)
                            VStack(alignment: .leading, spacing: 1) {
                                if let doi = entry.work.doi, let url = URL(string: doi) {
                                    Link(entry.work.title, destination: url)
                                        .foregroundStyle(.primary)
                                } else {
                                    Text(entry.work.title)
                                }
                                Text("\(entry.memberName) · \(entry.work.year.map(String.init) ?? "—") · \(entry.work.venue ?? "—")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.callout)
                    }
                    if retracted.count > 10 {
                        Text("+ \(retracted.count - 10) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Preprints

    /// Preprints and what became of them. Metrics run on the collapsed view
    /// (a preprint whose journal version is also indexed is dropped), so this
    /// card reads from the raw works — it's the one place the pairs are visible.
    @ViewBuilder
    private var preprintsCard: some View {
        let summary = MetricsEngine.preprintSummary(
            roster: store.filteredRoster,
            personData: store.filteredRoster.reduce(into: [UUID: PersonData]()) { result, member in
                result[member.id] = store.personData[member.id]
            })
        if summary.total > 0 {
            let shareLabel = summary.publishedShare
                .map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—"
            card("Preprints",
                 subtitle: "\(summary.total) preprints across the cohort · \(shareLabel) have a journal version indexed") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        preprintTile("Published", "\(summary.published)",
                                     caption: "matched to a journal article",
                                     tint: ChartPalette.positive)
                        preprintTile("Preprint only", "\(summary.unpublished)",
                                     caption: "no journal version indexed",
                                     tint: nil)
                        preprintTile("Stale", "\(summary.stale.count)",
                                     caption: "unpublished after \(MetricsEngine.stalePreprintYears)+ years",
                                     tint: summary.stale.isEmpty ? nil : ChartPalette.series3)
                    }
                    if !summary.stale.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(summary.stale.prefix(8)) { entry in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(entry.yearsOut)y")
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(ChartPalette.series3)
                                        .frame(width: 28, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 1) {
                                        if let doi = entry.work.doi, let url = URL(string: doi) {
                                            Link(entry.work.title, destination: url)
                                                .foregroundStyle(.primary)
                                        } else {
                                            Text(entry.work.title)
                                        }
                                        Text("\(entry.memberName) · \(entry.work.year.map(String.init) ?? "—") · \(entry.work.venue ?? "preprint server")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .font(.callout)
                            }
                            if summary.stale.count > 8 {
                                Text("+ \(summary.stale.count - 8) more")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text("Matched on normalized title, so a preprint retitled before publication reads as unpublished. Preprints with a match are dropped from works counts and the per-year charts; turn that off in Settings → Data Sources.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func preprintTile(_ label: String, _ value: String,
                              caption: String, tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint ?? .primary)
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(caption).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
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

    private var journals: [String: ScopusJournalMetrics] {
        MetricsEngine.mergedJournals(enrichment: store.enrichment)
    }

    /// Which source is carrying the quality numbers, for the card's caption.
    private var ratingSourceLabel: String {
        let ratings = store.journalRatings
        let scopus = ratings.values.count { $0.source == .scopus }
        if scopus == 0 { return "OpenAlex 2-year mean citedness" }
        if scopus == ratings.count { return "Scopus CiteScore" }
        return "Scopus CiteScore where available, OpenAlex elsewhere"
    }

    /// True when no work carries a venue ISSN — journal quality can't be
    /// joined at all until the works are refetched with ISSNs.
    private var missingISSNs: Bool {
        let withVenue = fetched.flatMap(\.works).filter { $0.venue != nil }
        guard !withVenue.isEmpty else { return false }
        return withVenue.allSatisfy { $0.venueISSN == nil }
    }

    /// Division-level journal quality. Uses Scopus CiteScore quartiles when a
    /// key is configured and falls back to OpenAlex citedness — which is
    /// keyless, so this card appears for everyone once works carry ISSNs.
    @ViewBuilder
    private var journalQualityCard: some View {
        let ratings = store.journalRatings
        if missingISSNs {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Journal Quality").font(.headline)
                    Text("Works were fetched before venue ISSNs were tracked, and journal metrics are joined by ISSN. Refresh all works to fill them in, then click Enrich Data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh All Works") {
                    Task { await store.fetchAll(refresh: true) }
                }
                .disabled(store.isBusy)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        } else if ratings.isEmpty && !fetched.isEmpty {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Journal Quality").font(.headline)
                    Text("No journal metrics fetched yet — click Enrich Data in the toolbar. OpenAlex journal metrics are keyless and on by default.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Fetch Journal Metrics") {
                    Task { await store.fetchJournalMetrics() }
                }
                .disabled(store.isBusy)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        if !ratings.isEmpty {
            let distribution = MetricsEngine.quartileDistribution(
                personData: fetched, ratings: ratings)
            let rated = distribution.values.reduce(0, +)
            if rated > 0 {
                let q1 = distribution[1] ?? 0
                let q1Share = (Double(q1) / Double(rated)).formatted(.percent.precision(.fractionLength(0)))
                let relative = ratings.values.allSatisfy { $0.source == .openalex }
                card("Journal Quality",
                     subtitle: "\(ratingSourceLabel) · \(rated) rated works · \(q1Share) in Q1 journals"
                         + (relative ? " (quartiles relative to the venues this cohort publishes in)" : "")) {
                    Chart((1...4).map { ($0, distribution[$0] ?? 0) }, id: \.0) { quartile, count in
                        BarMark(
                            x: .value("Works", count),
                            y: .value("Quartile", "Q\(quartile)"),
                            height: .ratio(0.7)
                        )
                        .foregroundStyle(quartile == 1 ? ChartPalette.positive : ChartPalette.series1)
                        .cornerRadius(2)
                        .annotation(position: .trailing, spacing: 4) {
                            Text(count.formatted())
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
                    .frame(height: 4 * 26)
                }
            }
        }
    }

    private var venuesCard: some View {
        let ratings = store.journalRatings
        let venues = MetricsEngine.venueCounts(personData: fetched, journals: journals,
                                               ratings: ratings)
        return card("Top Venues", subtitle: ratings.isEmpty
                    ? "\(venues.count) venues across the cohort in view"
                    : "\(venues.count) venues across the cohort in view · impact and quartile from \(ratingSourceLabel)") {
            Table(venues.sorted(using: sortOrder), sortOrder: $sortOrder) {
                TableColumn("Venue", value: \.name)
                TableColumn("Works", value: \.works) { Text("\($0.works)") }
                    .width(60)
                TableColumn("Citations", value: \.citations) { Text($0.citations.formatted()) }
                    .width(80)
                TableColumn("Faculty", value: \.people) { Text("\($0.people)") }
                    .width(60)
                TableColumn("Impact", value: \.citeScoreSort) { venue in
                    Text(venue.rating?.impact.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—")
                        .help(venue.rating?.source == .scopus
                              ? "Scopus CiteScore"
                              : "OpenAlex 2-year mean citedness")
                }
                .width(70)
                TableColumn("SJR", value: \.sjrSort) { venue in
                    Text(venue.rating?.sjr.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "—")
                }
                .width(55)
                TableColumn("Quartile", value: \.quartileSort) { venue in
                    quartileBadge(venue.rating?.quartile)
                }
                .width(60)
            }
            .frame(height: 320)
        }
    }

    @ViewBuilder
    private func quartileBadge(_ quartile: Int?) -> some View {
        if let quartile {
            Text("Q\(quartile)")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(quartile == 1 ? ChartPalette.positive.opacity(0.2) : Color.clear,
                            in: Capsule())
                .foregroundStyle(quartile == 1 ? ChartPalette.positive : .secondary)
        } else {
            Text("—").foregroundStyle(.tertiary)
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
