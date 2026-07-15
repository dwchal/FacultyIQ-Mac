import SwiftUI

/// Maps roster members to OpenAlex author IDs: auto-resolution via
/// ORCID/Scopus, and a manual name-search sheet for the rest.
struct ResolutionView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchTarget: FacultyMember?
    @State private var sortOrder: [KeyPathComparator<ResolutionRow>] = [] // empty = roster order
    @State private var searchText = ""

    /// Row model so store-derived columns (status, resolved author, data) are
    /// sortable; TableColumn sort keys must live on the row type.
    private struct ResolutionRow: Identifiable {
        var member: FacultyMember
        var idCount: Int          // available external IDs
        var status: String        // resolution method; "" = unresolved
        var resolvedName: String
        var worksCount: Int       // -1 = not fetched

        var id: UUID { member.id }
        var name: String { member.name }
    }

    private var rows: [ResolutionRow] {
        store.roster
            .filter {
                $0.matches(search: searchText)
                    || (store.resolution(for: $0)?.displayName
                        .localizedCaseInsensitiveContains(searchText) ?? false)
            }
            .map { member in
                let res = store.resolution(for: member)
                return ResolutionRow(
                    member: member,
                    idCount: (member.orcid != nil ? 1 : 0) + (member.scopusID != nil ? 1 : 0),
                    status: res?.method.rawValue ?? "",
                    resolvedName: res?.displayName ?? "",
                    worksCount: store.personData[member.id]?.works.count ?? -1)
            }
            .sorted(using: sortOrder)
    }

    var body: some View {
        Group {
            if store.roster.isEmpty {
                ContentUnavailableView(
                    "No Roster Loaded",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Import a roster first, then resolve each member to an OpenAlex author.")
                )
            } else {
                table
            }
        }
        .searchable(text: $searchText, prompt: "Name, rank, or division")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await store.autoResolveAll() }
                } label: {
                    Label("Auto-Resolve All", systemImage: "wand.and.stars")
                }
                .disabled(store.isBusy || store.roster.isEmpty)
                .help("Resolve members with an ORCID or Scopus ID automatically")

                Button {
                    Task { await store.fetchAll() }
                } label: {
                    Label("Fetch Metrics", systemImage: "arrow.down.circle")
                }
                .disabled(store.isBusy || store.resolutions.isEmpty)
                .help("Download publications and metrics for all resolved members")
            }
        }
        .sheet(item: $searchTarget) { member in
            AuthorSearchSheet(member: member)
        }
    }

    private var table: some View {
        Table(rows, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name)
            TableColumn("Available IDs", value: \.idCount) { row in
                HStack(spacing: 4) {
                    if row.member.orcid != nil { idBadge("ORCID") }
                    if row.member.scopusID != nil { idBadge("Scopus") }
                    if row.member.orcid == nil && row.member.scopusID == nil {
                        Text("name only").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            TableColumn("Status", value: \.status) { row in
                statusCell(row.member)
            }
            TableColumn("Resolved Author", value: \.resolvedName) { row in
                if let res = store.resolution(for: row.member) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(res.displayName)
                        if let aff = res.affiliation {
                            Text(aff).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            TableColumn("Data", value: \.worksCount) { row in
                if let data = store.personData[row.member.id] {
                    Text("\(data.works.count) works · \(data.fetchedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("not fetched").font(.caption).foregroundStyle(.tertiary)
                }
            }
            TableColumn("") { row in
                actionButtons(row.member)
            }
            .width(150)
        }
    }

    private func idBadge(_ label: String) -> some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }

    @ViewBuilder
    private func statusCell(_ member: FacultyMember) -> some View {
        if let res = store.resolution(for: member) {
            Label(res.method.rawValue, systemImage: "checkmark.circle.fill")
                .foregroundStyle(ChartPalette.positive)
                .font(.callout)
        } else {
            Label("Unresolved", systemImage: "circle.dashed")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    @ViewBuilder
    private func actionButtons(_ member: FacultyMember) -> some View {
        HStack {
            if store.resolution(for: member) == nil {
                Button("Search…") { searchTarget = member }
                    .buttonStyle(.link)
            } else {
                Button("Change…") { searchTarget = member }
                    .buttonStyle(.link)
                Button("Remove") { store.unresolve(member) }
                    .buttonStyle(.link)
                    .foregroundStyle(.red)
            }
        }
    }
}

/// Sheet for searching OpenAlex authors by name and picking the right match.
struct AuthorSearchSheet: View {
    let member: FacultyMember

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [AuthorCandidate] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var selection: AuthorCandidate.ID?
    @State private var sortOrder: [KeyPathComparator<AuthorCandidate>] = [] // empty = relevance order

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Author name", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { search() }
                Button("Search") { search() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(query.isEmpty || isSearching)
            }
            .padding()

            Divider()

            if isSearching {
                Spacer()
                ProgressView("Searching OpenAlex…")
                Spacer()
            } else if results.isEmpty {
                Spacer()
                Text(hasSearched ? "No authors found — try a name variation." : "Search OpenAlex by name, then select the matching author.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Table(results.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Author", value: \.displayName)
                    TableColumn("Affiliation", value: \.affiliationSort) { Text($0.affiliation ?? "—") }
                    TableColumn("Works", value: \.worksCount) { Text("\($0.worksCount)") }
                        .width(55)
                    TableColumn("Citations", value: \.citedByCount) { Text("\($0.citedByCount)") }
                        .width(70)
                    TableColumn("h", value: \.hIndexSort) { Text($0.hIndex.map(String.init) ?? "—") }
                        .width(35)
                    TableColumn("ORCID", value: \.orcidSort) { Text($0.orcid?.shortORCID ?? "—").font(.caption) }
                }
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Use Selected Author") {
                    if let selected = results.first(where: { $0.id == selection }) {
                        store.resolve(member, with: selected, method: .manual)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selection == nil)
            }
            .padding()
        }
        .frame(width: 720, height: 440)
        .onAppear { query = member.name }
    }

    private func search() {
        guard !query.isEmpty else { return }
        isSearching = true
        Task {
            results = await store.searchAuthors(name: query)
            hasSearched = true
            isSearching = false
        }
    }
}

private extension String {
    var shortORCID: String {
        replacingOccurrences(of: "https://orcid.org/", with: "")
    }
}

// Sort keys for optional columns; missing values sort first ascending.
private extension AuthorCandidate {
    var affiliationSort: String { affiliation ?? "" }
    var hIndexSort: Int { hIndex ?? -1 }
    var orcidSort: String { orcid ?? "" }
}
