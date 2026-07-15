import Charts
import SwiftUI

/// Division-level NIH funding: KPI tiles plus awards by fiscal year, by
/// activity code, and the most-funded faculty — from the grants attached via
/// RePORTER on each member's profile.
struct FundingView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("enableReporter") private var reporterEnabled = false

    private var funding: MetricsEngine.DivisionFunding? {
        MetricsEngine.divisionFunding(roster: store.filteredRoster, enrichment: store.enrichment)
    }

    var body: some View {
        if let funding {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if funding.missingFYBreakdown {
                        breakdownBanner
                    }
                    kpiRow(funding)
                    HStack(alignment: .top, spacing: 20) {
                        fiscalYearCard(funding)
                        activityCard(funding)
                    }
                    topFundedCard(funding)
                    Text("Multi-PI projects shared by two roster members count once in the totals and charts. Amounts are summed NIH award dollars across the fiscal years RePORTER reports.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Grant Data", systemImage: "dollarsign.circle")
        } description: {
            if reporterEnabled {
                Text("Click Enrich Data in the toolbar to attach NIH grants, or confirm investigators via Find Grants on their profiles.")
            } else {
                Text("Enable NIH RePORTER grants in Settings → Data Enrichment, then click Enrich Data in the toolbar.")
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
