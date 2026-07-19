import Charts
import SwiftUI

/// Division-level NIH funding: KPI tiles plus awards by fiscal year, by
/// activity code, and the most-funded faculty — from the grants attached via
/// RePORTER on each member's profile.
struct FundingView: View {
    private enum FundingTab: String, CaseIterable {
        case overview = "Overview"
        case timeline = "Timeline"
        case funders = "Funders"
    }

    @EnvironmentObject private var store: AppStore
    @AppStorage("enableReporter") private var reporterEnabled = false
    @State private var tab: FundingTab = .overview
    @State private var showCompleted = false

    private var funding: MetricsEngine.DivisionFunding? {
        MetricsEngine.divisionFunding(roster: store.filteredRoster, enrichment: store.enrichment)
    }

    private var funders: [FunderCredit] {
        MetricsEngine.funderCredits(roster: store.filteredRoster,
                                    personData: store.effectivePersonData)
    }

    /// The funders tab stands on its own: work-level funder credits need no
    /// grant attachment, so it has data even when nobody's NIH grants are on.
    private var hasAnyFunding: Bool { funding != nil || !funders.isEmpty }

    var body: some View {
        if hasAnyFunding {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("View", selection: $tab) {
                        ForEach(FundingTab.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 340)
                    switch tab {
                    case .overview:
                        if let funding {
                            overviewSection(funding)
                        } else {
                            noGrantsAttachedNote
                        }
                    case .timeline: timelineSection
                    case .funders: fundersSection
                    }
                }
                .padding(20)
            }
        } else {
            emptyState
        }
    }

    private var noGrantsAttachedNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No grants attached yet")
                .font(.headline)
            Text("The Funders tab works from funder credits on the publications themselves and needs no attachment. For award amounts and project periods, enable NIH RePORTER or NSF Awards in Settings → Data Sources and click Enrich Data.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func overviewSection(_ funding: MetricsEngine.DivisionFunding) -> some View {
        if funding.missingFYBreakdown {
            breakdownBanner
        }
        kpiRow(funding)
        cliffCard
        HStack(alignment: .top, spacing: 20) {
            fiscalYearCard(funding)
            activityCard(funding)
        }
        topFundedCard(funding)
        nsfCard
        trialsCard
        Text("Multi-PI projects shared by two roster members count once in the totals and charts. Amounts are summed NIH award dollars across the fiscal years RePORTER reports.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: Funding cliffs

    /// Members whose funding runs out within a year with nothing behind it —
    /// the one thing on this tab that's actionable rather than retrospective,
    /// so it sits directly under the KPIs. Silence means nobody's exposed.
    @ViewBuilder
    private var cliffCard: some View {
        let cliffs = MetricsEngine.fundingCliffs(roster: store.filteredRoster,
                                                 enrichment: store.enrichment)
        if !cliffs.isEmpty {
            let atRisk = cliffs.map(\.totalAtRisk).reduce(0, +)
            card("Funding Cliffs",
                 subtitle: "\(cliffs.count) \(cliffs.count == 1 ? "member's" : "members'") last award ends within \(MetricsEngine.fundingCliffMonths) months with nothing running past it · \(compactCurrency(atRisk)) on the ending projects") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(cliffs) { cliff in
                        cliffRow(cliff)
                    }
                    Text("Covers the awards attached in FacultyIQ only — pending applications, internal support, and awards the name match missed aren't visible here.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func cliffRow(_ cliff: MetricsEngine.FundingCliff) -> some View {
        let months = cliff.monthsOut()
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: months <= 3 ? "exclamationmark.triangle.fill" : "clock.badge.exclamationmark")
                .foregroundStyle(months <= 3 ? ChartPalette.critical : ChartPalette.series3)
            VStack(alignment: .leading, spacing: 1) {
                Text(cliff.memberName).font(.callout.weight(.medium))
                Text("\(cliff.source) \(cliff.projectNumber) · \(cliff.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(months == 0 ? "ends this month" : "\(months) mo")
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(months <= 3 ? ChartPalette.critical : .primary)
                Text((cliff.approximate ? "≈ " : "")
                     + cliff.endDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: NSF

    /// NSF awards, once the NSF source has run — kept separate from the NIH
    /// rollup above rather than summed into it, since the two APIs report
    /// award amounts on different bases.
    @ViewBuilder
    private var nsfCard: some View {
        if let nsf = MetricsEngine.nsfSummary(roster: store.filteredRoster,
                                              enrichment: store.enrichment) {
            card("NSF Awards",
                 subtitle: "Matched by investigator name · awards shared within the roster count once") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
                          spacing: 12) {
                    kpi("Total Awarded", compactCurrency(nsf.totalAwarded))
                    kpi("Awards", "\(nsf.awardCount)")
                    kpi("Active", "\(nsf.activeCount)")
                    kpi("As PI", "\(nsf.asPI)")
                    kpi("Funded Faculty", "\(nsf.fundedMembers)")
                }
            }
        }
    }

    // MARK: Funders

    @ViewBuilder
    private var fundersSection: some View {
        let funders = funders
        if MetricsEngine.funderDataMissing(roster: store.filteredRoster,
                                           personData: store.effectivePersonData) {
            HStack {
                Label("Works were fetched before funder credits were tracked. Refresh all works to populate this tab.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout)
                Spacer()
                Button("Refresh All Works") {
                    Task { await store.fetchAll(refresh: true) }
                }
                .disabled(store.isBusy)
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        } else if funders.isEmpty {
            Text("No funder credits on the cohort's publications.")
                .foregroundStyle(.secondary)
                .padding(16)
        } else {
            let top = Array(funders.prefix(15))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                kpi("Funders", "\(funders.count)")
                kpi("Credited Works", "\(funders.map(\.works).reduce(0, +))")
                kpi("Named Awards", "\(funders.map(\.awardCount).reduce(0, +))")
            }
            card("Who Funds This Cohort",
                 subtitle: "Funders credited on the publications themselves — every agency and foundation, not just NIH and NSF · top \(top.count)") {
                Chart(top) { funder in
                    BarMark(
                        x: .value("Works", funder.works),
                        y: .value("Funder", funder.name),
                        height: .ratio(0.7)
                    )
                    .foregroundStyle(ChartPalette.series1)
                    .cornerRadius(2)
                    .annotation(position: .trailing, spacing: 4) {
                        Text("\(funder.works) · \(funder.people) faculty")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .chartYScale(domain: top.map(\.name))
                .frame(height: CGFloat(top.count) * 28)
            }
            Text("Counts are distinct publications crediting each funder, so a paper with three funders is counted by all three. Amounts aren't available at work level — see the Overview tab for award dollars.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Division rollup of registered trials, once ClinicalTrials.gov
    /// enrichment has run. Shared trials (co-officials on the roster) count
    /// once in the totals.
    @ViewBuilder
    private var trialsCard: some View {
        let entries = store.filteredRoster.compactMap { member in
            (store.enrichment[member.id]?.trials).map { (member: member, trials: $0.trials) }
        }
        if !entries.isEmpty {
            let distinct = Dictionary(
                entries.flatMap(\.trials).map { ($0.nctID, $0) },
                uniquingKeysWith: { first, _ in first })
            let summary = MetricsEngine.trialsSummary(Array(distinct.values))
            let leaders = entries
                .map { (name: $0.member.name, count: $0.trials.count) }
                .filter { $0.count > 0 }
                .sorted { $0.count > $1.count }
            card("Clinical Trials",
                 subtitle: "ClinicalTrials.gov · \(entries.count) members checked · trials shared within the roster count once") {
                if summary.total == 0 {
                    Text("No registered trials list checked members as overall officials.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(summary.total) registered \(summary.total == 1 ? "trial" : "trials") · \(summary.asPI) with a roster member as PI · \(summary.active) active")
                            .font(.callout)
                        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 4) {
                            ForEach(leaders.prefix(8), id: \.name) { leader in
                                GridRow {
                                    Text(leader.name)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(leader.count) \(leader.count == 1 ? "trial" : "trials")")
                                        .foregroundStyle(.secondary)
                                        .gridColumnAlignment(.trailing)
                                        .monospacedDigit()
                                }
                                .font(.callout)
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Grant Data", systemImage: "dollarsign.circle")
        } description: {
            if reporterEnabled {
                Text("Click Enrich Data in the toolbar to attach NIH grants, or confirm investigators via Find Grants on their profiles. Refreshing works also fills the Funders tab from funder credits on the publications.")
            } else {
                Text("Enable NIH RePORTER grants or NSF Awards in Settings → Data Sources, then click Enrich Data in the toolbar.")
            }
        } actions: {
            if reporterEnabled {
                Button("Enrich Data") {
                    Task { await store.enrichAll() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isBusy || store.personData.isEmpty)
            }
        }
    }

    private var breakdownBanner: some View {
        HStack {
            Label("Some grants were fetched before per-year amounts were tracked, so the fiscal-year chart undercounts.",
                  systemImage: "exclamationmark.triangle")
                .font(.callout)
            Spacer()
            Button("Refresh Grants") {
                Task { await store.refreshGrants() }
            }
            .disabled(store.isBusy)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: KPI tiles

    private func kpiRow(_ funding: MetricsEngine.DivisionFunding) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
            kpi("Total Awarded", compactCurrency(funding.totalAwarded))
            kpi("Funded Faculty", "\(funding.fundedMembers)")
            kpi("Projects", "\(funding.projectCount)")
            kpi("Active", "\(funding.activeCount)")
            kpi("R01-Equivalent", "\(funding.r01EquivalentCount)")
        }
    }

    private func kpi(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 26, weight: .semibold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Charts

    @ViewBuilder
    private func fiscalYearCard(_ funding: MetricsEngine.DivisionFunding) -> some View {
        if !funding.byFiscalYear.isEmpty {
            card("Awards by Fiscal Year", subtitle: "NIH dollars awarded to the cohort in view") {
                Chart(funding.byFiscalYear, id: \.year) { item in
                    yearColumn(year: item.year, label: "Awarded", value: Double(item.amount))
                        .foregroundStyle(ChartPalette.series1)
                        .cornerRadius(2)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(compactCurrency(Int(amount)))
                            }
                        }
                    }
                }
                .yearXAxis(years: funding.byFiscalYear.map(\.year))
                .frame(height: 220)
            }
        }
    }

    private func activityCard(_ funding: MetricsEngine.DivisionFunding) -> some View {
        let top = Array(funding.byActivity.prefix(8))
        return card("Funding by Activity Code", subtitle: "Total awarded per NIH mechanism (project count in parentheses)") {
            Chart(top, id: \.code) { item in
                BarMark(
                    x: .value("Awarded", item.amount),
                    y: .value("Activity", item.code),
                    height: .ratio(0.7)
                )
                .foregroundStyle(ChartPalette.series1)
                .cornerRadius(2)
                .annotation(position: .trailing, spacing: 4) {
                    Text("\(compactCurrency(item.amount)) (\(item.count))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 220)
        }
    }

    private func topFundedCard(_ funding: MetricsEngine.DivisionFunding) -> some View {
        let top = Array(funding.topFunded.prefix(10))
        return card("Most-Funded Faculty", subtitle: "Total attached NIH awards per member, top 10") {
            Chart(top, id: \.name) { item in
                BarMark(
                    x: .value("Awarded", item.amount),
                    y: .value("Name", item.name),
                    height: .ratio(0.7)
                )
                .foregroundStyle(ChartPalette.series1)
                .cornerRadius(2)
                .annotation(position: .trailing, spacing: 4) {
                    Text(compactCurrency(item.amount))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(top.count) * 28)
        }
    }

    // MARK: Grant timeline

    private static let statusActive = "Active"
    private static let statusExpiring = "Expiring ≤ 12 mo"
    private static let statusEnded = "Ended"

    private static let statusColors: [String: Color] = [
        statusActive: ChartPalette.series1,
        statusExpiring: ChartPalette.critical,
        statusEnded: ChartPalette.series1Light,
    ]

    private func statusLabel(_ bar: MetricsEngine.GrantBar) -> String {
        if bar.expiresSoon { return Self.statusExpiring }
        return bar.isActive ? Self.statusActive : Self.statusEnded
    }

    private func rowLabel(_ bar: MetricsEngine.GrantBar) -> String {
        "\(bar.memberName) — \(bar.grant.coreProjectNum)"
    }

    @ViewBuilder
    private var timelineSection: some View {
        let bars = MetricsEngine.grantTimeline(roster: store.filteredRoster,
                                               enrichment: store.enrichment,
                                               includeCompleted: showCompleted)
        let expiring = bars.count(where: \.expiresSoon)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            kpi("Active", "\(bars.count(where: \.isActive))")
            kpi("Expiring ≤ 12 mo", "\(expiring)")
            kpi("Shown", "\(bars.count)")
        }
        timelineCard(bars)
        Text("One row per PI, so multi-PI projects appear on each investigator's row (unlike the deduplicated Overview totals). Periods marked ≈ are approximated from fiscal years because RePORTER omitted the project dates.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func timelineCard(_ bars: [MetricsEngine.GrantBar]) -> some View {
        let statuses = [Self.statusExpiring, Self.statusActive, Self.statusEnded]
            .filter { status in bars.contains { statusLabel($0) == status } }
        card("Grant Periods", subtitle: showCompleted
                ? "Project start to end per attached grant, including grants ended in the last 5 years"
                : "Project start to end per attached grant, current and upcoming") {
            if bars.isEmpty {
                Text("No grants with a resolvable project period in view.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart {
                    ForEach(bars) { bar in
                        BarMark(
                            xStart: .value("Start", bar.start),
                            xEnd: .value("End", bar.end),
                            y: .value("Grant", rowLabel(bar)),
                            height: .ratio(0.6)
                        )
                        .foregroundStyle(by: .value("Status", statusLabel(bar)))
                        .cornerRadius(3)
                        .annotation(position: .trailing, spacing: 4) {
                            Text((bar.approximate ? "≈ " : "")
                                 + bar.end.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    RuleMark(x: .value("Today", Date()))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartForegroundStyleScale(
                    domain: statuses,
                    range: statuses.map { Self.statusColors[$0] ?? .gray })
                .chartYScale(domain: bars.map(rowLabel)) // keep name/start order, not alphabetical
                .chartXAxis {
                    AxisMarks(values: .stride(by: .year)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.year())
                    }
                }
                // Per-row height plus room for the x-axis labels and legend,
                // which render inside the chart frame.
                .frame(height: CGFloat(bars.count) * 26 + 70)
            }
            Toggle("Show grants ended in the last 5 years", isOn: $showCompleted)
                .toggleStyle(.checkbox)
                .font(.callout)
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

    private func compactCurrency(_ amount: Int) -> String {
        "$" + Double(amount).formatted(.number.notation(.compactName).precision(.significantDigits(3)))
    }
}
