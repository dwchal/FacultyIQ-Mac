import SwiftUI

/// Frequent coauthors from outside the roster: who the division collaborates
/// with externally, ranked by shared works. Rows come from cached works;
/// affiliations are fetched on demand.
struct ExternalCollaboratorsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search = ""
    @State private var minShared = 2
    @State private var selectedID: String?
    @State private var sortOrder = [KeyPathComparator(\Row.sharedWorks, order: .reverse)]
    @State private var grouping: Grouping = .people
    @State private var institutionSort = [KeyPathComparator(\MetricsEngine.InstitutionRollup.sharedWorks, order: .reverse)]

    enum Grouping: String, CaseIterable {
        case people = "People"
        case institutions = "Institutions"
    }

    /// Flattened row so every column, including fetched details, is sortable.
    fileprivate struct Row: Identifiable {
        var collaborator: ExternalCollaborator
        var affiliation: String      // "" until details are fetched

        var id: String { collaborator.openalexID }
        var name: String { collaborator.displayName }
        var sharedWorks: Int { collaborator.sharedWorks }
        var partnerCount: Int { collaborator.partnerCount }
        var lastSharedYear: Int { collaborator.lastSharedYear ?? 0 }
    }

    var body: some View {
        let all = store.externalCollaborators
        if all.isEmpty {
            emptyState
        } else {
            content(all)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.coauthorNetwork.staleAuthorData {
            ContentUnavailableView {
                Label("No Coauthor Data", systemImage: "person.2.wave.2")
            } description: {
                Text("Works were fetched before coauthor data was tracked. Refresh to download it.")
            } actions: {
                refreshButton
            }
        } else {
            ContentUnavailableView(
                "No External Collaborators",
                systemImage: "person.2.wave.2",
                description: Text("Fetch metrics on the Resolution tab to find coauthors outside the roster.")
            )
        }
    }

    private var refreshButton: some View {
        Button("Refresh Works") {
            Task { await store.fetchAll(refresh: true) }
        }
        .disabled(store.isBusy)
        .help("Re-download publications for all resolved members, including coauthor lists")
    }

    private func content(_ all: [ExternalCollaborator]) -> some View {
        let rows = rows(from: all)
        return VStack(spacing: 0) {
            if store.coauthorNetwork.staleAuthorData {
                staleBanner
            }
            controls(all: all, shown: rows)
            Divider()
            if grouping == .institutions {
                institutionsContent(all)
            } else {
                HSplitView {
                    table(rows)
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                    sidebar(all)
                        .frame(minWidth: 230, maxWidth: 330)
                }
            }
        }
    }

    // MARK: Institution rollup

    /// Externals grouped by last known institution — the strategic-partnership
    /// view. Needs fetched details, so coverage is reported up front.
    @ViewBuilder
    private func institutionsContent(_ all: [ExternalCollaborator]) -> some View {
        let shown = all.filter { $0.sharedWorks >= minShared }
        let withDetails = shown.count { store.externalAuthorDetails[$0.openalexID] != nil }
        let rollup = MetricsEngine.institutionRollup(
            collaborators: shown, details: store.externalAuthorDetails)
            .filter {
                search.trimmingCharacters(in: .whitespaces).isEmpty
                    || $0.name.localizedCaseInsensitiveContains(search)
                    || $0.topNames.contains { $0.localizedCaseInsensitiveContains(search) }
            }
        if withDetails == 0 {
            ContentUnavailableView {
                Label("No Affiliations Fetched", systemImage: "building.2")
            } description: {
                Text("Institution grouping needs author details — click Fetch Affiliations above.")
            }
        } else {
            VStack(spacing: 0) {
                if withDetails < shown.count {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("Affiliations fetched for \(withDetails) of \(shown.count) listed collaborators — the rollup covers those.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.quaternary.opacity(0.5))
                }
                Table(rollup.sorted(using: institutionSort), sortOrder: $institutionSort) {
                    TableColumn("Institution", value: \.name)
                        .width(min: 200)
                    TableColumn("Collaborators", value: \.collaborators) { row in
                        Text("\(row.collaborators)").monospacedDigit()
                    }
                    .width(90)
                    TableColumn("Shared Works", value: \.sharedWorks) { row in
                        Text("\(row.sharedWorks)").monospacedDigit()
                    }
                    .width(90)
                    TableColumn("Top Collaborators") { row in
                        Text(row.topNames.joined(separator: ", "))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 160)
                }
            }
        }
    }

    private func rows(from all: [ExternalCollaborator]) -> [Row] {
        all.filter { $0.sharedWorks >= minShared }
            .filter {
                search.trimmingCharacters(in: .whitespaces).isEmpty
                    || $0.displayName.localizedCaseInsensitiveContains(search)
                    || $0.partners.contains { $0.name.localizedCaseInsensitiveContains(search) }
            }
            .map { Row(collaborator: $0,
                       affiliation: store.externalAuthorDetails[$0.openalexID]?.affiliation ?? "") }
            .sorted(using: sortOrder)
    }

    private var staleBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            Text("Some works were fetched before coauthor data was tracked, so this list may be incomplete.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            refreshButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5))
    }

    private func controls(all: [ExternalCollaborator], shown: [Row]) -> some View {
        let maxShared = all.map(\.sharedWorks).max() ?? 1
        return HStack(spacing: 16) {
            Picker("", selection: $grouping) {
                ForEach(Grouping.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            TextField("Filter by name or roster member", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
            Stepper("Min shared works: \(minShared)",
                    value: $minShared, in: 1...max(maxShared, 1))
            Button("Fetch Affiliations") {
                let ids = Array(shown.prefix(200).map(\.id))
                Task { await store.fetchExternalAuthorDetails(ids: ids) }
            }
            .disabled(store.isBusy || shown.isEmpty)
            .help("Look up current institution and metrics for the listed authors (top 200)")
            Spacer()
            Text("\(shown.count) of \(all.count) external collaborators")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Table

    private func table(_ rows: [Row]) -> some View {
        tableContent(rows)
            .contextMenu(forSelectionType: Row.ID.self) { ids in
                if let id = ids.first,
                   let collaborator = rows.first(where: { $0.id == id })?.collaborator {
                    Button("Add \(collaborator.displayName) to Roster") {
                        Task { await store.addToRoster(external: collaborator) }
                    }
                    .disabled(store.isBusy)
                    Button("Add as Emeritus") {
                        Task { await store.addToRoster(external: collaborator, status: .emeritus) }
                    }
                    .disabled(store.isBusy)
                }
            }
    }

    private func tableContent(_ rows: [Row]) -> some View {
        Table(rows, selection: $selectedID, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name)
                .width(min: 140)
            TableColumn("Affiliation", value: \.affiliation) { row in
                Text(row.affiliation.isEmpty ? "—" : row.affiliation)
                    .foregroundStyle(row.affiliation.isEmpty ? .secondary : .primary)
            }
            .width(min: 120)
            TableColumn("Shared Works", value: \.sharedWorks) { row in
                Text("\(row.sharedWorks)").monospacedDigit()
            }
            .width(90)
            TableColumn("Roster Partners", value: \.partnerCount) { row in
                Text("\(row.partnerCount)").monospacedDigit()
            }
            .width(100)
            TableColumn("Last Shared", value: \.lastSharedYear) { row in
                Text(row.lastSharedYear == 0 ? "—" : String(row.lastSharedYear))
                    .monospacedDigit()
            }
            .width(80)
        }
    }

    // MARK: Detail sidebar

    @ViewBuilder
    private func sidebar(_ all: [ExternalCollaborator]) -> some View {
        if let collaborator = all.first(where: { $0.openalexID == selectedID }) {
            detail(collaborator)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("External Collaborators").font(.headline)
                Text("Authors who appear on roster members' publications but aren't on the roster themselves — frequent partners at other divisions and institutions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Select a row to see which roster members they publish with. Unresolved roster members can show up here; resolve them to filter them out.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(12)
        }
    }

    private func detail(_ collaborator: ExternalCollaborator) -> some View {
        let details = store.externalAuthorDetails[collaborator.openalexID]
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(collaborator.displayName).font(.headline)
                if let affiliation = details?.affiliation {
                    Text(affiliation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(collaborator.sharedWorks) shared works with \(collaborator.partnerCount) roster members")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let details {
                    Text("\(details.worksCount) total works · \(details.citedByCount) citations"
                         + (details.hIndex.map { " · h-index \($0)" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let url = URL(string: "https://openalex.org/\(collaborator.openalexID)") {
                Link("View on OpenAlex", destination: url)
                    .font(.caption)
            }
            HStack(spacing: 8) {
                Button("Add to Roster") {
                    Task { await store.addToRoster(external: collaborator) }
                }
                .help("Add \(collaborator.displayName) as a roster member, resolved to this OpenAlex author, and fetch their data. Set rank and division afterward on the Roster tab.")
                Button("Add as Emeritus") {
                    Task { await store.addToRoster(external: collaborator, status: .emeritus) }
                }
                .help("Same, marked Emeritus: in the division views but out of promotion benchmarks")
            }
            .disabled(store.isBusy)
            Text("Publishes with")
                .font(.subheadline.weight(.semibold))
            List(collaborator.partners) { partner in
                HStack {
                    Text(partner.name)
                    Spacer()
                    Text("\(partner.weight)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .listStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(12)
    }
}
