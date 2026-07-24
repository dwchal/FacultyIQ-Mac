import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Shared NSSavePanel wrapper for the Export tab and the File-menu export
/// commands. Nil means the user cancelled.
@MainActor
enum SavePanel {
    static func run(defaultName: String, type: UTType,
                    write: (URL) throws -> Void) -> Result<String, Error>? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = defaultName
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try write(url)
            return .success(url.lastPathComponent)
        } catch {
            return .failure(error)
        }
    }
}

struct ExportView: View {
    @EnvironmentObject private var store: AppStore
    @State private var confirmation: String?
    @State private var dossierMemberID: UUID?

    private var membersWithData: [FacultyMember] {
        store.filteredRoster.filter { store.personData[$0.id] != nil }
    }

    private var fundingCliffs: [MetricsEngine.FundingCliff] {
        MetricsEngine.fundingCliffs(roster: store.filteredRoster, enrichment: store.enrichment)
    }

    private var funderCredits: [FunderCredit] {
        MetricsEngine.funderCredits(roster: store.filteredRoster,
                                    personData: store.effectivePersonData)
    }

    var body: some View {
        Form {
            Section {
                exportRow(
                    "Faculty Metrics",
                    detail: "One row per faculty member: works, citations, h-index, i10, productivity, OA share.",
                    filename: "faculty_metrics.csv",
                    disabled: store.metrics.isEmpty
                ) {
                    MetricsEngine.metricsCSV(metrics: store.metrics, roster: store.filteredRoster,
                                             personData: store.effectivePersonData, enrichment: store.enrichment)
                }
                exportRow(
                    "Yearly Time Series",
                    detail: "Long format: name × year × works published × citations received.",
                    filename: "faculty_yearly.csv",
                    disabled: store.filteredPersonData.isEmpty
                ) {
                    MetricsEngine.yearlyCSV(roster: store.filteredRoster, personData: store.effectivePersonData)
                }
                exportRow(
                    "Coauthorship Edges",
                    detail: "One row per pair of roster members with shared publications.",
                    filename: "coauthorship_edges.csv",
                    disabled: store.coauthorNetwork.edges.isEmpty
                ) {
                    MetricsEngine.coauthorshipCSV(network: store.coauthorNetwork)
                }
                exportRow(
                    "Mentorship Pairs",
                    detail: "Directed senior-author → first-author pairs within the roster, from byline positions (approximate).",
                    filename: "mentorship_pairs.csv",
                    disabled: store.mentorshipEdges.isEmpty
                ) {
                    MetricsEngine.mentorshipCSV(edges: store.mentorshipEdges, roster: store.filteredRoster)
                }
                exportRow(
                    "External Collaborators",
                    detail: "One row per non-roster coauthor: shared works, roster partners, last shared year.",
                    filename: "external_collaborators.csv",
                    disabled: store.externalCollaborators.isEmpty
                ) {
                    MetricsEngine.externalCollaboratorsCSV(store.externalCollaborators)
                }
                exportRow(
                    "External Institutions",
                    detail: "External collaborators grouped by institution — needs Fetch Affiliations on the External Collaborators tab first.",
                    filename: "external_institutions.csv",
                    disabled: MetricsEngine.institutionRollup(
                        collaborators: store.externalCollaborators,
                        details: store.externalAuthorDetails).isEmpty
                ) {
                    MetricsEngine.institutionRollupCSV(MetricsEngine.institutionRollup(
                        collaborators: store.externalCollaborators,
                        details: store.externalAuthorDetails))
                }
                exportRow(
                    "Roster with Resolutions",
                    detail: "The imported roster plus each member's resolved OpenAlex ID.",
                    filename: "roster_resolved.csv",
                    disabled: store.roster.isEmpty
                ) {
                    rosterCSV()
                }
                exportRow(
                    "NIH Grants",
                    detail: "One row per NIH project attached via RePORTER: activity code, fiscal years, total award.",
                    filename: "nih_grants.csv",
                    disabled: !store.filteredRoster.contains {
                        !(store.enrichment[$0.id]?.grants?.grants.isEmpty ?? true)
                    }
                ) {
                    MetricsEngine.grantsCSV(roster: store.filteredRoster, enrichment: store.enrichment)
                }
                exportRow(
                    "NSF Awards",
                    detail: "One row per NSF award: role, program, project period, total award.",
                    filename: "nsf_awards.csv",
                    disabled: !store.filteredRoster.contains {
                        !(store.enrichment[$0.id]?.nsf?.awards.isEmpty ?? true)
                    }
                ) {
                    MetricsEngine.nsfAwardsCSV(roster: store.filteredRoster,
                                               enrichment: store.enrichment)
                }
                exportRow(
                    "Funding Cliffs",
                    detail: "Members whose last award ends within a year with nothing running past it.",
                    filename: "funding_cliffs.csv",
                    disabled: fundingCliffs.isEmpty
                ) {
                    MetricsEngine.fundingCliffsCSV(fundingCliffs)
                }
                exportRow(
                    "Funders",
                    detail: "Funders credited on the cohort's publications — every agency, from the papers themselves.",
                    filename: "funders.csv",
                    disabled: funderCredits.isEmpty
                ) {
                    MetricsEngine.fundersCSV(funderCredits)
                }
            } header: {
                Text("Data Exports")
            } footer: {
                if let scope = store.scopeName {
                    Text("Exports include only “\(scope)”; choose All Faculty in the toolbar to export everyone.")
                }
            }
            Section {
                summaryPDFRow
                dossierPDFRow
            } header: {
                Text("PDF Reports")
            }
            if let confirmation {
                Section {
                    Label(confirmation, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(ChartPalette.positive)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if dossierMemberID == nil { dossierMemberID = membersWithData.first?.id }
        }
    }

    // MARK: PDF reports

    private var summaryPDFRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Division Summary")
                Text("KPIs, publication and citation trends, open-access share, most-cited faculty, and rank benchmarks.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Save as PDF…") {
                let scope = store.scopeName
                save(defaultName: "\(sanitize(scope ?? "faculty"))_report.pdf", type: .pdf) { url in
                    try PDFComposer.write(
                        pages: SummaryPages.pages(
                            summary: store.summary,
                            metrics: store.metrics,
                            personData: store.filteredPersonData,
                            benchmarks: store.benchmarks,
                            divisionName: scope,
                            scopusLine: MetricsEngine.divisionScopusLine(
                                roster: store.filteredRoster, personData: store.personData,
                                enrichment: store.enrichment)),
                        to: url)
                }
            }
            .disabled(store.filteredPersonData.isEmpty)
        }
        .padding(.vertical, 4)
    }

    private var dossierPDFRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Promotion Dossier")
                Text("One member's metrics, promotion readiness, publication trend, and most-cited works.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Member", selection: $dossierMemberID) {
                ForEach(membersWithData) { member in
                    Text(member.name).tag(Optional(member.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 200)
            Button("Save as PDF…") {
                guard let member = membersWithData.first(where: { $0.id == dossierMemberID }),
                      let data = store.effectiveData(for: member.id) else { return }
                save(defaultName: "\(sanitize(member.name))_dossier.pdf", type: .pdf) { url in
                    try PDFComposer.write(
                        pages: DossierPages.pages(
                            member: member,
                            data: data,
                            resolution: store.resolution(for: member),
                            metrics: MetricsEngine.personMetrics(member: member, data: data),
                            promotion: store.promotionProgress.first { $0.id == member.id },
                            enrichment: store.enrichment[member.id]),
                        to: url)
                }
            }
            .disabled(dossierMemberID == nil || !membersWithData.contains { $0.id == dossierMemberID })
        }
        .padding(.vertical, 4)
    }

    private func sanitize(_ name: String) -> String {
        name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }

    private func exportRow(_ title: String, detail: String, filename: String,
                           disabled: Bool, content: @escaping () -> String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Save as CSV…") {
                saveCSV(defaultName: filename, content: content())
            }
            .disabled(disabled)
        }
        .padding(.vertical, 4)
    }

    private func saveCSV(defaultName: String, content: String) {
        save(defaultName: defaultName, type: .commaSeparatedText) { url in
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func save(defaultName: String, type: UTType, write: (URL) throws -> Void) {
        switch SavePanel.run(defaultName: defaultName, type: type, write: write) {
        case .success(let filename): confirmation = "Saved \(filename)"
        case .failure(let error): store.lastError = error.localizedDescription
        case nil: break   // user cancelled
        }
    }

    private func rosterCSV() -> String {
        var lines = ["Name,Email,Rank,Division,Hire Year,ORCID,Scopus ID,OpenAlex ID,Resolved Name,Resolution Method,Last Reviewed,Notes"]
        for member in store.filteredRoster {
            let res = store.resolution(for: member)
            lines.append([
                member.name,
                member.email ?? "",
                member.rank ?? "",
                member.division ?? "",
                member.hireYear.map(String.init) ?? "",
                member.orcid ?? "",
                member.scopusID ?? "",
                res?.openalexID ?? "",
                res?.displayName ?? "",
                res?.method.rawValue ?? "",
                member.lastReviewed.map { $0.formatted(.iso8601.year().month().day()) } ?? "",
                member.notes ?? "",
            ].map(MetricsEngine.csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
