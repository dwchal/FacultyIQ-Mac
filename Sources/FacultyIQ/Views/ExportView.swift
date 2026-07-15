import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ExportView: View {
    @EnvironmentObject private var store: AppStore
    @State private var confirmation: String?

    var body: some View {
        Form {
            Section {
                exportRow(
                    "Faculty Metrics",
                    detail: "One row per faculty member: works, citations, h-index, i10, productivity, OA share.",
                    filename: "faculty_metrics.csv",
                    disabled: store.metrics.isEmpty
                ) {
                    MetricsEngine.metricsCSV(metrics: store.metrics, roster: store.filteredRoster)
                }
                exportRow(
                    "Yearly Time Series",
                    detail: "Long format: name × year × works published × citations received.",
                    filename: "faculty_yearly.csv",
                    disabled: store.personData.isEmpty
                ) {
                    MetricsEngine.yearlyCSV(roster: store.filteredRoster, personData: store.personData)
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
                    "Roster with Resolutions",
                    detail: "The imported roster plus each member's resolved OpenAlex ID.",
                    filename: "roster_resolved.csv",
                    disabled: store.roster.isEmpty
                ) {
                    rosterCSV()
                }
            } header: {
                Text("Data Exports")
            } footer: {
                if store.divisionFilter != nil {
                    Text("Exports include only the selected division; choose All Divisions in the toolbar to export everyone.")
                }
            }
            if let confirmation {
                Section {
                    Label(confirmation, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(ChartPalette.positive)
                }
            }
        }
        .formStyle(.grouped)
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
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = defaultName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            confirmation = "Saved \(url.lastPathComponent)"
        } catch {
            store.lastError = error.localizedDescription
        }
    }

    private func rosterCSV() -> String {
        var lines = ["Name,Email,Rank,Division,Hire Year,ORCID,Scopus ID,OpenAlex ID,Resolved Name,Resolution Method"]
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
            ].map(MetricsEngine.csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
