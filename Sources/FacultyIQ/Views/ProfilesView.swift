import Charts
import SwiftUI

/// Individual faculty drill-down: metric grid, publication trend, top works.
struct ProfilesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedID: UUID?
    @State private var searchText = ""

    private var membersWithData: [FacultyMember] {
        store.filteredRoster.filter { store.personData[$0.id] != nil }
    }

    /// The member list under the current search; the detail pane keeps showing
    /// a filtered-out selection so searching doesn't blank the profile.
    private var visibleMembers: [FacultyMember] {
        membersWithData.filter { $0.matches(search: searchText) }
    }

    var body: some View {
        Group {
            if membersWithData.isEmpty {
                ContentUnavailableView(
                    "No Faculty Data",
                    systemImage: "person.text.rectangle",
                    description: Text("Fetch metrics on the Resolution tab to view individual profiles.")
                )
            } else {
                splitView
            }
        }
        .searchable(text: $searchText, prompt: "Name, rank, or division")
    }

    private var splitView: some View {
        HSplitView {
            List(visibleMembers, selection: $selectedID) { member in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(member.name)
                        Text([member.rank, member.division].compactMap(\.self).joined(separator: " · ")
                            .nilIfEmpty ?? "—")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if let data = store.effectiveData(for: member.id) {
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
                    .help(String(format: "Works per year, last 3y vs prior 3y (current year pro-rated): %+.0f%%", growth))
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let member = membersWithData.first(where: { $0.id == selectedID }),
           let data = store.effectiveData(for: member.id) {
            ProfileDetail(member: member, data: data,
                          resolution: store.resolution(for: member),
                          metrics: MetricsEngine.personMetrics(member: member, data: data),
                          promotion: store.promotionProgress.first { $0.id == member.id },
                          cohortData: store.filteredPersonData,
                          enrichment: store.enrichment[member.id],
                          history: store.resolution(for: member).map {
                              MetricsEngine.personHistory(snapshots: store.snapshots,
                                                          openalexID: $0.openalexID)
                          } ?? [])
        } else {
            Text("Select a faculty member")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ProfileDetail: View {
    @EnvironmentObject private var store: AppStore
    let member: FacultyMember
    let data: PersonData
    let resolution: Resolution?
    let metrics: PersonMetrics
    let promotion: PromotionProgress?
    let cohortData: [PersonData]
    let enrichment: Enrichment?
    let history: [MetricSnapshot]
    @State private var worksSort = [KeyPathComparator(\Work.citedByCount, order: .reverse)]
    @State private var showGrantsSheet = false
    @State private var showAuditSheet = false
    @AppStorage("enableReporter") private var reporterEnabled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                metricGrid
                dataQualityCard
                peerBenchmarkCard
                promotionCard
                fundingCard
                trendChart
                authorshipCard
                trajectoryCard
                historyCard
                topWorks
            }
            .padding(20)
        }
        .sheet(isPresented: $showGrantsSheet) {
            GrantsConfirmSheet(member: member)
        }
        .sheet(isPresented: $showAuditSheet) {
            WorksAuditSheet(member: member)
        }
    }

    // MARK: Data quality

    /// Exclusion state, misattribution candidates, and retractions — the
    /// signals that decide whether the metrics above can be trusted.
    @ViewBuilder
    private var dataQualityCard: some View {
        let raw = store.personData[member.id]?.works ?? []
        let excluded = store.excludedWorks[member.id]?.count ?? 0
        let suspects = MetricsEngine.suspectWorkIDs(works: raw, authorID: resolution?.openalexID)
            .subtracting(store.excludedWorks[member.id] ?? [])
        let retracted = data.works.count { $0.isRetracted == true }
        if excluded > 0 || !suspects.isEmpty || retracted > 0 {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Data Quality").font(.headline)
                    Group {
                        if excluded > 0 {
                            Text("\(excluded) \(excluded == 1 ? "work" : "works") marked not \(member.name)'s — kept out of all metrics.")
                        }
                        if !suspects.isEmpty {
                            Text("\(suspects.count) \(suspects.count == 1 ? "work differs" : "works differ") from the usual field — possible OpenAlex misattributions.")
                        }
                        if retracted > 0 {
                            Text("\(retracted) \(retracted == 1 ? "work is" : "works are") flagged retracted by OpenAlex.")
                                .foregroundStyle(ChartPalette.critical)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Audit Works…") { showAuditSheet = true }
            }
            .padding(16)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        } else {
            HStack {
                Text("No misattribution or retraction flags on this profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Audit Works…") { showAuditSheet = true }
                    .controlSize(.small)
            }
        }
    }

    // MARK: Peer benchmark

    @ViewBuilder
    private var peerBenchmarkCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Field Benchmark").font(.headline)
                    if let cohort = enrichment?.peerCohort {
                        Text("vs \(cohort.cohortSize) OpenAlex authors publishing on \(cohort.topicName) (≥10 works each), sampled \(cohort.fetchedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Percentile standing among a random sample of authors on this member's dominant topic — context the in-division benchmarks can't give.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(enrichment?.peerCohort == nil ? "Benchmark vs Field" : "Refresh") {
                    Task { await store.fetchPeerCohort(for: member) }
                }
                .disabled(store.isBusy)
            }
            if let cohort = enrichment?.peerCohort {
                HStack(spacing: 12) {
                    percentileTile("Works", cohort.worksPercentile)
                    percentileTile("Citations", cohort.citationsPercentile)
                    percentileTile("h-index", cohort.hIndexPercentile)
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func percentileTile(_ label: String, _ percentile: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Int(percentile.rounded()))th")
                .font(.title2.weight(.semibold))
                .foregroundStyle(percentile >= 50 ? ChartPalette.positive : Color.primary)
            Text("\(label) percentile").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Authorship positions

    /// First/middle/last split over time — the first-author → senior-author
    /// transition promotion committees look for.
    @ViewBuilder
    private var authorshipCard: some View {
        if let authorID = resolution?.openalexID {
            let summary = MetricsEngine.authorshipSummary(data: data, authorID: authorID)
            let series = MetricsEngine.authorshipByYear(data: data, authorID: authorID)
            if summary.tracked > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Authorship Position").font(.headline)
                        Text("First author \(summary.first) · middle \(summary.middle) · senior (last) \(summary.last) · corresponding \(summary.corresponding), across \(summary.tracked) works with position data")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !series.isEmpty {
                        Chart(series) { point in
                            BarMark(
                                x: .value("Year", point.year),
                                y: .value("Works", point.count)
                            )
                            .foregroundStyle(by: .value("Position", positionLabel(point.position)))
                        }
                        .chartForegroundStyleScale([
                            "First": ChartPalette.series1,
                            "Middle": ChartPalette.series1Light,
                            "Senior (last)": ChartPalette.series3,
                        ])
                        .yearXAxis(years: series.map(\.year))
                        .frame(height: 160)
                    }
                    independenceSection(authorID: authorID)
                    if summary.tracked < data.works.count {
                        Text("\(data.works.count - summary.tracked) works predate position tracking — Refresh Data to include them.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Positions come from OpenAlex byline order, which can't see co-first or co-senior designations — treat as approximate.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    /// The first→senior transition: senior-author share per year plus the
    /// crossover callout — the independence signal promotion committees
    /// look for.
    @ViewBuilder
    private func independenceSection(authorID: String) -> some View {
        let shares = MetricsEngine.seniorShareByYear(data: data, authorID: authorID)
        let crossover = MetricsEngine.seniorTransitionYear(data: data, authorID: authorID)
        if shares.count >= 3 {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Senior-author share by year").font(.caption).foregroundStyle(.secondary)
                    if let crossover {
                        Label("senior-author-dominant since \(String(crossover))",
                              systemImage: "flag.checkered")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ChartPalette.positive)
                            .help("First year whose trailing 3-year window has at least 2 last-author works and at least as many last-author as first-author works — and the current window still does")
                    } else if let latest = metrics.seniorShare5y {
                        Text(String(format: "· still first-author-leaning (%.0f%% senior over the last 5y)", latest))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Chart(shares, id: \.year) { point in
                    LineMark(x: .value("Year", point.year), y: .value("Senior %", point.share))
                        .foregroundStyle(ChartPalette.series3)
                    PointMark(x: .value("Year", point.year), y: .value("Senior %", point.share))
                        .foregroundStyle(ChartPalette.series3)
                        .symbolSize(20)
                    if let crossover {
                        RuleMark(x: .value("Crossover", crossover))
                            .foregroundStyle(ChartPalette.positive.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .chartYScale(domain: 0...100)
                .yearXAxis(years: shares.map(\.year))
                .frame(height: 110)
            }
        }
    }

    private func positionLabel(_ position: AuthorPosition) -> String {
        switch position {
        case .first: "First"
        case .middle: "Middle"
        case .last: "Senior (last)"
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
                                Button {
                                    store.excludeGrant(member, coreProjectNum: grant.coreProjectNum)
                                } label: {
                                    Image(systemName: "xmark.circle")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.tertiary)
                                .help("Remove this grant — it stays off through future refreshes")
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
                excludedFooter
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

    /// Notes hand-removed grants and offers to bring them back.
    @ViewBuilder
    private var excludedFooter: some View {
        if let excluded = enrichment?.excludedGrants, !excluded.isEmpty {
            HStack(spacing: 8) {
                Text("\(excluded.count) \(excluded.count == 1 ? "grant" : "grants") removed by hand — kept off on refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Restore") {
                    Task { await store.restoreExcludedGrants(member) }
                }
                .controlSize(.small)
                .disabled(store.isBusy)
            }
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
            Text("\(label)/yr · \(yearSpan(trend.recentYears)) vs \(yearSpan(trend.priorYears)) (\(prior.formatted()) → \(recent.formatted()))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .help(String(format: "Annualized rate change — %d counts as %.0f%% of a year, so a partial year doesn't read as a slump",
                     MetricsEngine.currentYear, trend.currentYearFraction * 100))
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

    // MARK: Tracked history

    /// Observed metric movement across this app's own fetches — appears once
    /// two readings with different values exist.
    @ViewBuilder
    private var historyCard: some View {
        if history.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tracked History").font(.headline)
                    Text("Readings recorded at each data fetch, since \(history.first!.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Different scales, separate charts — never a second y-axis.
                HStack(alignment: .top, spacing: 12) {
                    historyChart(value: \.works, label: "Works")
                    historyChart(value: \.citations, label: "Citations")
                    historyChart(value: \.hIndex, label: "h-index")
                }
            }
            .padding(16)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func historyChart(value: KeyPath<MetricSnapshot, Int>, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Chart(history) { snapshot in
                LineMark(
                    x: .value("Date", snapshot.date),
                    y: .value(label, snapshot[keyPath: value])
                )
                .foregroundStyle(ChartPalette.series1)
                .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(
                    x: .value("Date", snapshot.date),
                    y: .value(label, snapshot[keyPath: value])
                )
                .foregroundStyle(ChartPalette.series1)
                .symbolSize(30)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .dayXAxis(dates: history.map(\.date))
            .frame(height: 120)
        }
        .frame(maxWidth: .infinity)
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
            HStack(spacing: 10) {
                Text(member.name).font(.title.weight(.semibold))
                if !member.isActive {
                    Text((member.status ?? .active).label.uppercased())
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                        .help("Excluded from promotion benchmarks and candidacy")
                }
            }
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
            topicsLine
        }
    }

    @ViewBuilder
    private var topicsLine: some View {
        if metrics.positionTracked > 0 {
            let topics = MetricsEngine.personTopicRoles(data: data)
            if !topics.isEmpty {
                Text("Topics: " + topics.map { "\($0.name) (\($0.led) led of \($0.works))" }
                    .joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    .help("Led = first, last, or corresponding author — this member's own program on the topic rather than a collaboration credit")
            }
        } else {
            let topics = MetricsEngine.personTopics(data: data)
            if !topics.isEmpty {
                Text("Topics: " + topics.map { "\($0.name) (\($0.works))" }.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        typesLine
    }

    @ViewBuilder
    private var typesLine: some View {
        let types = MetricsEngine.personTypeCounts(data: data)
        if !types.isEmpty {
            Text("Types: " + types.map { "\($0.name) (\($0.works))" }.joined(separator: " · "))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            tile("Works", "\(metrics.worksCount)")
            tile("Citations", metrics.citations.formatted())
            tile("h-index", "\(metrics.hIndex)")
            tile("i10-index", "\(metrics.i10Index)")
            if let independent = metrics.independentHIndex {
                tile("Independent h-index", "\(independent)")
                    .help("h-index over first/last/corresponding-author works only — the member's own program with middle authorships stripped out (approximate: OpenAlex can't see co-first or co-senior designations)")
            }
            tile("Citations / Work", String(format: "%.1f", metrics.citationsPerWork))
            tile("Works / Year", String(format: "%.2f", metrics.worksPerYear))
            tile("Open Access", metrics.oaPercent.map { String(format: "%.0f%%", $0) } ?? "—")
            tile("Works, Last 5y", "\(metrics.recentWorks5y)")
            if let rcr = MetricsEngine.meanRCR(works: data.works, icite: enrichment?.icite) {
                tile("Mean RCR", String(format: "%.2f", rcr))
                    .help("Mean Relative Citation Ratio (NIH iCite): 1.0 is the NIH field-normalized average")
            }
            if let apt = MetricsEngine.meanAPT(works: data.works, icite: enrichment?.icite) {
                tile("Mean APT", String(format: "%.2f", apt))
                    .help("Mean Approximate Potential to Translate (NIH iCite), 0–1: works at 0.75+ are likely to be cited by clinical articles")
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
            HStack(spacing: 4) {
                if work.isRetracted == true {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundStyle(ChartPalette.critical)
                        .help("Flagged as retracted by OpenAlex")
                }
                if let doi = work.doi, let url = URL(string: doi) {
                    Link(work.title, destination: url)
                        .foregroundStyle(.primary)
                } else {
                    Text(work.title)
                }
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
        TableColumn("APT") { (work: Work) in
            Text(iciteMetric(work)?.apt.map { String(format: "%.2f", $0) } ?? "—")
                .foregroundStyle(iciteMetric(work)?.apt == nil ? Color.secondary : .primary)
                .help("Approximate Potential to Translate (NIH iCite), 0–1")
        }
        .width(45)
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
