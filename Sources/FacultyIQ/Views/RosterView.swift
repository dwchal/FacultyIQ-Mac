import SwiftUI
import UniformTypeIdentifiers

struct RosterView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingImporter = false
    @State private var confirmReplace = false

    var body: some View {
        Group {
            if store.roster.isEmpty {
                emptyState
            } else {
                rosterTable
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showingImporter = true
                } label: {
                    Label("Import CSV…", systemImage: "square.and.arrow.down")
                }
                if !store.roster.isEmpty {
                    Button(role: .destructive) {
                        confirmReplace = true
                    } label: {
                        Label("Clear Roster", systemImage: "trash")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            if case .success(let url) = result {
                store.importRoster(from: url)
            }
        }
        .confirmationDialog(
            "Clear the roster? Resolutions and fetched data will also be removed.",
            isPresented: $confirmReplace
        ) {
            Button("Clear Everything", role: .destructive) { store.clearAll() }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Roster Loaded", systemImage: "person.3")
        } description: {
            Text("Import a faculty roster CSV with names and optional ORCID / Scopus IDs, or load the sample to explore the app.")
        } actions: {
            Button("Import CSV…") { showingImporter = true }
                .buttonStyle(.borderedProminent)
            Button("Load Sample Roster") { store.loadSampleRoster() }
        }
    }

    private var rosterTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            completenessHeader
            Divider()
            Table(store.roster) {
                TableColumn("Name", value: \.name)
                TableColumn("Rank") { Text($0.rank ?? "—") }
                TableColumn("Hired") { Text($0.hireYear.map(String.init) ?? "—") }
                    .width(60)
                TableColumn("Last Promotion") { Text($0.lastPromotionYear.map(String.init) ?? "—") }
                    .width(100)
                TableColumn("ORCID") { member in
                    idCell(member.orcid)
                }
                TableColumn("Scopus ID") { member in
                    idCell(member.scopusID)
                }
                TableColumn("Scholar ID") { member in
                    idCell(member.scholarID)
                }
                TableColumn("Associations") { Text($0.associations ?? "—") }
            }
        }
    }

    private func idCell(_ value: String?) -> some View {
        Group {
            if let value {
                Text(value).font(.body.monospaced())
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
    }

    private var completenessHeader: some View {
        HStack(spacing: 24) {
            stat("Faculty", "\(store.roster.count)")
            stat("With ORCID", "\(store.roster.count { $0.orcid != nil })")
            stat("With Scopus ID", "\(store.roster.count { $0.scopusID != nil })")
            stat("With Rank", "\(store.roster.count { AcademicRank.parse($0.rank) != nil })")
            Spacer()
        }
        .padding(12)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
