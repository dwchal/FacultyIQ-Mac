import SwiftUI
import UniformTypeIdentifiers

struct RosterView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingImporter = false
    @State private var confirmReplace = false
    @State private var selection: Set<FacultyMember.ID> = []
    @State private var editorTarget: EditorTarget?
    @State private var sortOrder: [KeyPathComparator<FacultyMember>] = [] // empty = import order

    private enum EditorTarget: Identifiable {
        case new
        case edit(FacultyMember)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let member): member.id.uuidString
            }
        }
    }

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
                    editorTarget = .new
                } label: {
                    Label("Add Person…", systemImage: "person.badge.plus")
                }
                .help("Add a faculty member to the roster")
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
        .sheet(item: $editorTarget) { target in
            switch target {
            case .new: MemberEditorSheet(member: nil)
            case .edit(let member): MemberEditorSheet(member: member)
            }
        }
    }

    private func edit(_ id: FacultyMember.ID?) {
        if let member = store.roster.first(where: { $0.id == id }) {
            editorTarget = .edit(member)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Roster Loaded", systemImage: "person.3")
        } description: {
            Text("Import a faculty roster CSV, build one person at a time, or load the sample to explore the app.")
        } actions: {
            Button("Import CSV…") { showingImporter = true }
                .buttonStyle(.borderedProminent)
            Button("Add Person…") { editorTarget = .new }
            Button("Load Sample Roster") { store.loadSampleRoster() }
        }
    }

    private var rosterTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            completenessHeader
            Divider()
            Table(store.roster.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name)
                TableColumn("Rank", value: \.rankSort) { Text($0.rank ?? "—") }
                TableColumn("Hired", value: \.hireYearSort) { Text($0.hireYear.map(String.init) ?? "—") }
                    .width(60)
                TableColumn("Last Promotion", value: \.promotionYearSort) { Text($0.lastPromotionYear.map(String.init) ?? "—") }
                    .width(100)
                TableColumn("ORCID", value: \.orcidSort) { member in
                    idCell(member.orcid)
                }
                TableColumn("Scopus ID", value: \.scopusSort) { member in
                    idCell(member.scopusID)
                }
                TableColumn("Scholar ID", value: \.scholarSort) { member in
                    idCell(member.scholarID)
                }
                TableColumn("Associations", value: \.associationsSort) { Text($0.associations ?? "—") }
            }
            .contextMenu(forSelectionType: FacultyMember.ID.self) { ids in
                if ids.count == 1 {
                    Button("Edit…") { edit(ids.first) }
                }
                if !ids.isEmpty {
                    Button("Delete", role: .destructive) { store.removeMembers(ids) }
                }
            } primaryAction: { ids in
                edit(ids.first) // double-click opens the editor
            }
            .onDeleteCommand {
                if !selection.isEmpty { store.removeMembers(selection) }
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

// Sort keys for optional columns; missing values sort first ascending.
private extension FacultyMember {
    var rankSort: String { rank ?? "" }
    var hireYearSort: Int { hireYear ?? 0 }
    var promotionYearSort: Int { lastPromotionYear ?? 0 }
    var orcidSort: String { orcid ?? "" }
    var scopusSort: String { scopusID ?? "" }
    var scholarSort: String { scholarID ?? "" }
    var associationsSort: String { associations ?? "" }
}
