import Charts
import SwiftUI

/// Builds the per-faculty promotion-dossier PDF pages: an overview page
/// (header, metric grid, promotion readiness, publications chart) followed by
/// paginated most-cited-works pages.
enum DossierPages {
    static let worksPerPage = 22
    static let topWorksLimit = 44

    /// Top-cited works split into page-sized chunks.
    static func workChunks(_ works: [Work],
                           perPage: Int = worksPerPage,
                           limit: Int = topWorksLimit) -> [[Work]] {
        let top = Array(works.sorted { $0.citedByCount > $1.citedByCount }.prefix(limit))
        return stride(from: 0, to: top.count, by: perPage).map {
            Array(top[$0..<min($0 + perPage, top.count)])
        }
    }

    static func pages(member: FacultyMember,
                      data: PersonData,
                      resolution: Resolution?,
                      metrics: PersonMetrics,
                      promotion: PromotionProgress?,
                      enrichment: Enrichment? = nil) -> [AnyView] {
        let chunks = workChunks(data.works)
        let total = 1 + chunks.count
        func footer(_ page: Int) -> String {
            "\(member.name) — Promotion Dossier · page \(page)/\(total) · \(ReportStyle.generatedLine)"
        }
        var pages: [AnyView] = [
            AnyView(overviewPage(member: member, data: data, resolution: resolution,
                                 metrics: metrics, promotion: promotion,
                                 enrichment: enrichment, footer: footer(1)))
        ]
        for (i, chunk) in chunks.enumerated() {
            pages.append(AnyView(worksPage(chunk, isFirst: i == 0,
                                           icite: enrichment?.icite, footer: footer(i + 2))))
        }
        return pages
    }

    // MARK: Page 1 — overview

    private static func overviewPage(member: FacultyMember,
                                     data: PersonData,
                                     resolution: Resolution?,
                                     metrics: PersonMetrics,
                                     promotion: PromotionProgress?,
                                     enrichment: Enrichment?,
                                     footer: String) -> some View {
        let series = MetricsEngine.worksByYear(data)
            .sorted { $0.key < $1.key }
            .map { (year: $0.key, count: $0.value) }
        let projections = promotion.map {
            MetricsEngine.trajectoryProjections(data: data, promotion: $0)
        } ?? []

        return ReportPage(footer: footer) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(member.name).font(.title.weight(.semibold))
                    let rankLine = [member.rank, member.division]
                        .compactMap(\.self).joined(separator: " · ")
                    if !rankLine.isEmpty {
                        Text(rankLine).foregroundStyle(.secondary)
                    }
                    if let affiliation = resolution?.affiliation {
                        Text(affiliation).font(.callout).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 14) {
                        if let resolution {
                            Text("OpenAlex \(resolution.openalexID)")
                        }
                        if let orcid = member.orcid ?? resolution?.orcid.map(RosterImporter.cleanORCID) {
                            Text("ORCID \(orcid)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                metricGrid(metrics)

                if let line = enrichmentLine(data: data, enrichment: enrichment) {
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let promotion {
                    readinessSection(promotion)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Publications per Year").font(.headline)
                    WorksPerYearChart(data: series)
                        .frame(height: promotion == nil ? 240 : 170)
                }

                if !projections.isEmpty {
                    Text("At the current 5-year pace: " + projections
                        .map { "\($0.label) target ≈ \($0.yearsToTarget > 15 ? "15+ years out" : String($0.targetYear))" }
                        .joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// One-line iCite / NIH-funding summary for page 1, when enrichment exists.
    private static func enrichmentLine(data: PersonData, enrichment: Enrichment?) -> String? {
        var parts: [String] = []
        if let rcr = MetricsEngine.meanRCR(works: data.works, icite: enrichment?.icite) {
            parts.append(String(format: "Mean RCR %.2f (NIH field-normalized average = 1.0)", rcr))
        }
        if let grants = enrichment?.grants?.grants, !grants.isEmpty {
            let funding = MetricsEngine.fundingSummary(grants)
            let total = funding.totalAwarded.formatted(.currency(code: "USD").precision(.fractionLength(0)))
            parts.append("NIH funding: \(total) across \(funding.grantCount) projects · \(funding.activeCount) active · \(funding.r01EquivalentCount) R01-equivalent")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }

    private static func metricGrid(_ metrics: PersonMetrics) -> some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                ReportTile(label: "Works", value: "\(metrics.worksCount)")
                ReportTile(label: "Citations", value: metrics.citations.formatted())
                ReportTile(label: "h-index", value: "\(metrics.hIndex)")
                ReportTile(label: "i10-index", value: "\(metrics.i10Index)")
            }
            GridRow {
                ReportTile(label: "Citations / Work", value: String(format: "%.1f", metrics.citationsPerWork))
                ReportTile(label: "Works / Year", value: String(format: "%.2f", metrics.worksPerYear))
                ReportTile(label: "Open Access",
                           value: metrics.oaPercent.map { String(format: "%.0f%%", $0) } ?? "—")
                ReportTile(label: "Works, Last 5y", value: "\(metrics.recentWorks5y)")
            }
        }
    }

    private static func readinessSection(_ promotion: PromotionProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Promotion Readiness").font(.headline)
                Text("Against the \(promotion.targetRank.label) promotion targets (25th percentile of current rank-holders in view)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(promotion.checks) { check in
                HStack(spacing: 12) {
                    Text(check.label)
                        .frame(width: 70, alignment: .leading)
                    ReportBar(fraction: Double(check.value) / max(check.benchmark, 1),
                              color: check.met ? ChartPalette.positive : ChartPalette.series1)
                    Text("\(check.value.formatted()) / \(Int(check.benchmark.rounded()))")
                        .monospacedDigit()
                        .frame(width: 110, alignment: .trailing)
                    Text(check.met ? "met" : "needs \(check.gap.formatted()) more")
                        .font(.caption)
                        .foregroundStyle(check.met ? ChartPalette.positive : Color.secondary)
                }
                .font(.callout)
            }
            Text(promotion.metCount >= 2
                 ? "Meets the promotion criteria (\(promotion.metCount) of 3 targets; 2 required)."
                 : "Meets \(promotion.metCount) of 3 targets — promotion candidates need 2.")
                .font(.caption)
                .foregroundStyle(promotion.metCount >= 2 ? ChartPalette.positive : Color.secondary)
        }
        .padding(12)
        .background(ReportStyle.cardFill, in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Works pages

    private static func worksPage(_ works: [Work], isFirst: Bool,
                                  icite: ICiteData?, footer: String) -> some View {
        let showRCR = icite != nil
        return ReportPage(footer: footer) {
            VStack(alignment: .leading, spacing: 10) {
                if isFirst {
                    Text("Most-Cited Works").font(.headline)
                }
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 7) {
                    GridRow {
                        Text("Title").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Year").gridColumnAlignment(.trailing)
                        Text("Venue")
                        Text("Citations").gridColumnAlignment(.trailing)
                        if showRCR {
                            Text("RCR").gridColumnAlignment(.trailing)
                        }
                        Text("OA")
                    }
                    .font(.caption.weight(.semibold))
                    Rectangle().fill(ReportStyle.rowRule).frame(height: 0.5)
                        .gridCellColumns(showRCR ? 6 : 5)
                    ForEach(works) { work in
                        GridRow {
                            Text(work.title)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(work.year.map(String.init) ?? "—")
                            Text(work.venue ?? "—")
                                .lineLimit(1)
                                .frame(width: showRCR ? 110 : 130, alignment: .leading)
                            Text("\(work.citedByCount)").monospacedDigit()
                            if showRCR {
                                Text(work.pmid
                                    .flatMap { icite?.byPMID[$0]?.rcr }
                                    .map { String(format: "%.2f", $0) } ?? "—")
                                    .monospacedDigit()
                            }
                            Text(work.isOA == true ? (work.oaStatus ?? "open") : "—")
                                .foregroundStyle(work.isOA == true ? ChartPalette.positive : Color.secondary)
                        }
                        .font(.footnote)
                    }
                }
            }
        }
    }
}
