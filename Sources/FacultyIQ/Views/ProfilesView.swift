import Charts
import SwiftUI

/// Individual faculty drill-down: metric grid, publication trend, top works.
struct ProfilesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedID: UUID?

    private var membersWithData: [FacultyMember] {
        store.filteredRoster.filter { store.personData[$0.id] != nil }
    }

    var body: some View {
        if membersWithData.isEmpty {
            ContentUnavailableView(
                "No Faculty Data",
                systemImage: "person.text.rectangle",
                description: Text("Fetch metrics on the Resolution tab to view individual profiles.")
            )
        } else {
            HSplitView {
                List(membersWithData, selection: $selectedID) { member in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(member.name)
                            Text([member.rank, member.division].compactMap(\.self).joined(separator: " · ")
                                .nilIfEmpty ?? "—")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if let data = store.personData[member.id] {
                            rowSparkline(data)
                        }
                    }
                    .tag(member.id)
                }
                .frame(minWidth: 200, maxWidth: 300)

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                if selectedID == nil { selectedID = membersWithData.first?.id }
            }
        }
    }

    /// Ten-year works sparkline with a growth arrow (last 3y vs prior 3y).
    private func rowSparkline(_ data: PersonData) -> some View {
        let points = MetricsEngine.worksSparkline(data: data)
        let growth = MetricsEngine.trendMetrics(data: data).worksGrowth
        return HStack(spacing: 4) {
            Chart(points, id: \.year) { point in
                LineMark(x: .value("Year", point.year), y: .value("Works", point.count))
                    .foregroundStyle(ChartPalette.series1)
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
            }
            // The automatic year domain collapses at sparkline sizes,
            // squashing the line into a vertical tick — pin it explicitly.
            .chartXScale(domain: (points.first?.year ?? 0)...(points.last?.year ?? 1))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(width: 56, height: 16)
            if let growth {
                Image(systemName: growth >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(growth >= 0 ? ChartPalette.positive : ChartPalette.critical)
                    .help(String(format: "Works, last 3y vs prior 3y: %+.0f%%", growth))
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let member = membersWithData.first(where: { $0.id == selectedID }),
           let data = store.personData[member.id] {
            ProfileDetail(member: member, data: data,
                          resolution: store.resolution(for: member),
                          metrics: MetricsEngine.personMetrics(member: member, data: data),
                          promotion: store.promotionProgress.first { $0.id == member.id },
                          cohortData: store.filteredPersonData,
                          enrichment: store.enrichment[member.id])
        } else {
            Text("Select a faculty member")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ProfileDetail: View {
    let member: FacultyMember
    let data: PersonData
    let resolution: Resolution?
    let metrics: PersonMetrics
    let promotion: PromotionProgress?
    let cohortData: [PersonData]
    let enrichment: Enrichment?
    @State private var worksSort = [KeyPathComparator(\Work.citedByCount, order: .reverse)]
    @State private var showGrantsSheet = false
    @AppStorage("enableReporter") private var reporterEnabled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                metricGrid
                promotionCard
                fundingCard
                trendChart
                trajectoryCard
                topWorks
            }
            .padding(20)
        }
        .sheet(isPresented: $showGrantsSheet) {
            GrantsConfirmSheet(member: member)
        }
    }

    // MARK: NIH funding

    @ViewBuilder
    private var fundingCard: some View {
        if let grantData = enrichment?.grants {
            let summary = MetricsEngine.fundingSummary(grantData.grants)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("NIH Funding").font(.headline)
                    Spacer()
                    Button("Find Grants…") { showGrantsSheet = true }
                        .controlSize(.small)
                }
                if grantData.grants.isEmpty {
                    Text("No NIH projects found for \(grantData.confirmedPIName ?? member.name).")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    Text("\(summary.grantCount) projects · \(currency(summary.totalAwarded)) awarded · \(summary.activeCount) active · \(summary.r01EquivalentCount) R01-equivalent")
                        .font(.callout)
                    if let pi = grantData.confirmedPIName {
                        Text("Matched to NIH investigator \(pi)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 5) {
                        ForEach(grantData.grants.prefix(8)) { grant in
                            GridRow {
                                Text(grant.activityCode ?? "—")
                                    .font(.caption.weight(.semibold))
                                    .frame(width: 34, alignment: .leading)
                                Text(grant.coreProjectNum)
                                    .font(.caption.monospaced())
                                Text(grant.title)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(fiscalSpan(grant.fiscalYears))
                                    .foregroundStyle(.secondary)
                                Text(currency(grant.totalAward))
                                    .monospacedDigit()
                                    .gridColumnAlignment(.trailing)
                            }
                            .font(.callout)
                        }
                    }
                    if grantData.grants.count > 8 {
                        Text("+ \(grantData.grants.count - 8) more (see the NIH Grants CSV export)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        } else if reporterEnabled {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NIH Funding").font(.headline)
                    Text("No grants attached — search RePORTER and confirm the investigator.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Find Grants…") { showGrantsSheet = true }
            }
            .padding(16)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func currency(_ amount: Int) -> String {
        amount.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    private func fiscalSpan(_ years: [Int]) -> String {
        guard let first = years.first, let last = years.last else { return "—" }
        return first == last ? "FY\(first)" : "FY\(first)–\(last)"
    }

    // MARK: Trajectory

    private var trajectoryCard: some View {
        let trend = MetricsEngine.trendMetrics(data: data)
        let projections = promotion.map {
            MetricsEngine.trajectoryProjections(data: data, promotion: $0)
        } ?? []
        let career = MetricsEngine.careerWorksSeries(data: data)
        let cohortMedian = MetricsEngine.careerMedianSeries(personData: cohortData)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Trajectory").font(.headline)
            HStack(spacing: 12) {
                growthTile("Works", recent: trend.recentWorks, prior: trend.priorWorks,
                           growth: trend.worksGrowth, trend: trend)
                growthTile("Citations", recent: trend.recentCitations, prior: trend.priorCitations,
                           growth: trend.citationsGrowth, trend: trend)
            }
            if !projections.isEmpty {
                projectionSection(projections)
            }
            if career.count >= 2 {
                careerChart(person: career, median: cohortMedian)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func growthTile(_ label: String, recent: Int, prior: Int,
                            growth: Double?, trend: TrendMetrics) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(growth.map { String(format: "%+.0f%%", $0) } ?? "—")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(growth.map { $0 >= 0 ? ChartPalette.positive : ChartPalette.critical }
                        ?? Color.primary)
                if let growth {
                    Image(systemName: growth >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(growth >= 0 ? ChartPalette.positive : ChartPalette.critical)
                }
            }
            Text("\(label) · \(yearSpan(trend.recentYears)) vs \(yearSpan(trend.priorYears)) (\(prior.formatted()) → \(recent.formatted()))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func yearSpan(_ range: ClosedRange<Int>) -> String {
        "\(range.lowerBound)–\(String(range.upperBound).suffix(2))"
    }

    @ViewBuilder
    private func projectionSection(_ projections: [TrajectoryProjection]) -> some View {
        let summary = projections
            .map { "\($0.label) target ≈ \(yearsLabel($0))" }
            .joined(separator: " · ")
        Text("At the current 5-year pace: \(summary)")
            .font(.caption)
            .foregroundStyle(.secondary)
        if let works = projections.first(where: { $0.label == "Works" }),
           works.yearsToTarget <= 15 {
            worksProjectionChart(works)
        }
    }

    private func yearsLabel(_ projection: TrajectoryProjection) -> String {
        projection.yearsToTarget > 15 ? "15+ years out" : String(projection.targetYear)
    }

    private func worksProjectionChart(_ projection: TrajectoryProjection) -> some View {
        let history = MetricsEngine.cumulativePoints(
            byYear: MetricsEngine.worksByYear(data), span: 10)
        let lastX = history.last?.x ?? Double(MetricsEngine.currentYear)
        let lastY = history.last?.y ?? 0
        let endX = Double(projection.targetYear)
        let projected = [(x: lastX, y: lastY),
                         (x: endX, y: lastY + projection.perYear * (endX - lastX))]

        return Chart {
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
            RuleMark(y: .value("Target", projection.target))
                .foregroundStyle(ChartPalette.series3)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("works target ≈ \(String(projection.targetYear))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
        }
        .yearXAxis(years: history.map { Int($0.x) } + [projection.targetYear])
        .frame(height: 160)
    }

    private func careerChart(person: [(careerYear: Int, cumulativeWorks: Int)],
                             median: [(careerYear: Int, median: Double)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cumulative works by career year, vs the cohort in view")
                .font(.caption)
                .foregroundStyle(.secondary)
            Chart {
                ForEach(median, id: \.careerYear) { point in
                    LineMark(x: .value("Career Year", point.careerYear),
                             y: .value("Cumulative Works", point.median),
                             series: .value("Series", "Cohort median"))
                        .foregroundStyle(by: .value("Series", "Cohort median"))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                }
                ForEach(person, id: \.careerYear) { point in
                    LineMark(x: .value("Career Year", point.careerYear),
                             y: .value("Cumulative Works", Double(point.cumulativeWorks)),
                             series: .value("Series", metrics.name))
                        .foregroundStyle(by: .value("Series", metrics.name))
                }
            }
            .chartForegroundStyleScale([
                metrics.name: ChartPalette.series1,
                "Cohort median": ChartPalette.series1Light,
            ])
            .chartXAxisLabel("Years since first publication")
            .frame(height: 160)
        }
    }

    // MARK: Promotion readiness

    @ViewBuilder
    private var promotionCard: some View {
        if let promotion {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Promotion Readiness").font(.headline)
                    Text("Against the \(promotion.targetRank.label) promotion targets (25th percentile of current rank-holders in view)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(promotion.checks) { check in
                    progressRow(check)
                }
                promotionSummary(promotion)
            }
            .padding(16)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func progressRow(_ check: PromotionProgress.MetricCheck) -> some View {
        HStack(spacing: 12) {
            Text(check.label)
                .frame(width: 70, alignment: .leading)
            ProgressView(value: min(Double(check.value) / max(check.benchmark, 1), 1))
                .tint(check.met ? ChartPalette.positive : ChartPalette.series1)
            Text("\(check.value.formatted()) / \(Int(check.benchmark.rounded()))")
                .monospacedDigit()
                .frame(width: 110, alignment: .trailing)
            Group {
                if check.met {
                    Label("met", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(ChartPalette.positive)
                } else {
                    Text("needs \(check.gap.formatted()) more")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .frame(width: 120, alignment: .leading)
        }
        .font(.callout)
    }

    private func promotionSummary(_ promotion: PromotionProgress) -> some View {
        let met = promotion.metCount
        return Group {
            if met >= 2 {
                Label("Meets the promotion criteria (\(met) of 3 targets; 2 required)",
                      systemImage: "checkmark.seal.fill")
                    .foregroundStyle(ChartPalette.positive)
            } else {
                Text("Meets \(met) of 3 targets — promotion candidates need 2. Targets shift with the division filter and as colleagues' data updates.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(member.name).font(.title.weight(.semibold))
            HStack(spacing: 8) {
                if let rank = member.rank { Text(rank) }
                if let aff = resolution?.affiliation {
                    Text("·").foregroundStyle(.tertiary)
                    Text(aff)
                }
            }
            .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                if let res = resolution,
                   let url = URL(string: "https://openalex.org/\(res.openalexID)") {
                    Link("OpenAlex ↗", destination: url)
                }
                if let orcid = member.orcid ?? resolution?.orcid.map(RosterImporter.cleanORCID),
                   let url = URL(string: "https://orcid.org/\(orcid)") {
                    Link("ORCID ↗", destination: url)
                }
            }
            .font(.callout)
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            tile("Works", "\(metrics.worksCount)")
            tile("Citations", metrics.citations.formatted())
            tile("h-index", "\(metrics.hIndex)")
            tile("i10-index", "\(metrics.i10Index)")
            tile("Citations / Work", String(format: "%.1f", metrics.citationsPerWork))
            tile("Works / Year", String(format: "%.2f", metrics.worksPerYear))
            tile("Open Access", metrics.oaPercent.map { String(format: "%.0f%%", $0) } ?? "—")
            tile("Works, Last 5y", "\(metrics.recentWorks5y)")
            if let rcr = MetricsEngine.meanRCR(works: data.works, icite: enrichment?.icite) {
                tile("Mean RCR", String(format: "%.2f", rcr))
                    .help("Mean Relative Citation Ratio (NIH iCite): 1.0 is the NIH field-normalized average")
            }
            if let s2 = enrichment?.semanticScholar {
                tile("Influential Citations", s2.influentialByDOI.values.reduce(0, +).formatted())
                    .help("Semantic Scholar influential citations across this member's works")
            }
        }
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var trendChart: some View {
        let series = MetricsEngine.worksByYear(data)
            .sorted { $0.key < $1.key }
            .map { (year: $0.key, count: $0.value) }

        return VStack(alignment: .leading, spacing: 10) {
            Text("Publications per Year").font(.headline)
            WorksPerYearChart(data: series)
                .frame(height: 180)
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var topWorks: some View {
        let top = Array(data.works.sorted { $0.citedByCount > $1.citedByCount }.prefix(15))
            .sorted(using: worksSort)
        let enriched = enrichment?.icite != nil || enrichment?.semanticScholar != nil
        // Conditional TableColumns (builder `if`) need macOS 14.4; the app
        // targets 14.0, so the enriched variant is a separate Table built
        // from shared column groups.
        return VStack(alignment: .leading, spacing: 10) {
            Text("Most-Cited Works").font(.headline)
            Group {
                if enriched {
                    Table(top, sortOrder: $worksSort) {
                        baseColumns
                        enrichedColumns
                        oaColumn
                    }
                } else {
                    Table(top, sortOrder: $worksSort) {
                        baseColumns
                        oaColumn
                    }
                }
            }
            .frame(height: 360)
        }
    }

    @TableColumnBuilder<Work, KeyPathComparator<Work>>
    private var baseColumns: some TableColumnContent<Work, KeyPathComparator<Work>> {
        TableColumn("Title", value: \.title) { work in
            if let doi = work.doi, let url = URL(string: doi) {
                Link(work.title, destination: url)
                    .foregroundStyle(.primary)
            } else {
                Text(work.title)
            }
        }
        TableColumn("Year", value: \.yearSort) { Text($0.year.map(String.init) ?? "—") }
            .width(45)
        TableColumn("Venue", value: \.venueSort) { Text($0.venue ?? "—") }
            .width(min: 100, ideal: 180)
        TableColumn("Citations", value: \.citedByCount) { Text("\($0.citedByCount)") }
            .width(60)
    }

    @TableColumnBuilder<Work, KeyPathComparator<Work>>
    private var enrichedColumns: some TableColumnContent<Work, KeyPathComparator<Work>> {
        TableColumn("RCR") { (work: Work) in
            Text(iciteMetric(work)?.rcr.map { String(format: "%.2f", $0) } ?? "—")
                .foregroundStyle(iciteMetric(work)?.rcr == nil ? Color.secondary : .primary)
                .help("Relative Citation Ratio (NIH iCite): 1.0 is the field-normalized average")
        }
        .width(45)
        TableColumn("NIH %ile") { (work: Work) in
            Text(iciteMetric(work)?.nihPercentile.map { String(format: "%.0f", $0) } ?? "—")
        }
        .width(55)
        TableColumn("Infl.") { (work: Work) in
            Text(work.doi
                .flatMap { enrichment?.semanticScholar?.influentialByDOI[$0.bareDOI] }
                .map(String.init) ?? "—")
                .help("Semantic Scholar influential citations")
        }
        .width(40)
    }

    @TableColumnBuilder<Work, KeyPathComparator<Work>>
    private var oaColumn: some TableColumnContent<Work, KeyPathComparator<Work>> {
        TableColumn("OA", value: \.oaSort) { work in
            if work.isOA == true {
                Text(work.oaStatus ?? "open")
                    .font(.caption)
                    .foregroundStyle(ChartPalette.positive)
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
        .width(55)
    }

    private func iciteMetric(_ work: Work) -> WorkCitationMetrics? {
        work.pmid.flatMap { enrichment?.icite?.byPMID[$0] }
    }
}

private extension Work {
    var yearSort: Int { year ?? 0 }
    var venueSort: String { venue ?? "" }
    var oaSort: String { isOA == true ? (oaStatus ?? "open") : "" }
}
