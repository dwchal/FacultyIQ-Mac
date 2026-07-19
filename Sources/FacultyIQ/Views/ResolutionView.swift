import SwiftUI

/// Maps roster members to OpenAlex author IDs: auto-resolution via
/// ORCID/Scopus, and a manual name-search sheet for the rest.
struct ResolutionView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchTarget: FacultyMember?
    @State private var scopusTarget: FacultyMember?
    @State private var editTarget: FacultyMember?
    @State private var showHealthDetail = false
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
                VStack(spacing: 0) {
                    dataHealthBar
                    table
                }
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
        .sheet(item: $scopusTarget) { member in
            ScopusConfirmSheet(member: member)
        }
        .sheet(item: $editTarget) { member in
            MemberEditorSheet(member: member)
        }
    }

    // MARK: Data health

    /// ID gaps that quietly degrade downstream sources: no ORCID (weakest
    /// resolution), no Scopus ID (no Scopus metrics), unresolved members, and
    /// works that can't be joined to PubMed/DOI-keyed sources.
    @ViewBuilder
    private var dataHealthBar: some View {
        let health = MetricsEngine.dataHealth(
            roster: store.roster, resolutions: store.resolutions, personData: store.personData)
        if !health.isClean {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "stethoscope")
                        .foregroundStyle(.secondary)
                    Text(healthSummary(health))
                        .font(.caption)
                    Spacer()
                    if !health.gaps.isEmpty {
                        Button(showHealthDetail ? "Hide" : "Review Gaps") {
                            showHealthDetail.toggle()
                        }
                        .controlSize(.small)
                    }
                }
                if showHealthDetail {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(health.gaps) { gap in
                                HStack(spacing: 8) {
                                    Text(gap.member.name)
                                        .frame(width: 180, alignment: .leading)
                                        .lineLimit(1)
                                    if gap.unresolved { gapBadge("unresolved") }
                                    if gap.missingORCID { gapBadge("no ORCID") }
                                    if gap.missingScopusID { gapBadge("no Scopus ID") }
                                    Spacer()
                                    if gap.missingORCID {
                                        Link("ORCID search",
                                             destination: orcidSearchURL(gap.member.name))
                                            .font(.caption)
                                    }
                                    if gap.missingScopusID {
                                        Button("Find Scopus Author…") { scopusTarget = gap.member }
                                            .buttonStyle(.link)
                                            .font(.caption)
                                    }
                                    Button("Edit…") { editTarget = gap.member }
                                        .buttonStyle(.link)
                                        .font(.caption)
                                }
                                .font(.callout)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 170)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.35))
        }
    }

    private func healthSummary(_ health: MetricsEngine.DataHealth) -> String {
        var parts: [String] = []
        let unresolved = health.gaps.count(where: \.unresolved)
        let noORCID = health.gaps.count(where: \.missingORCID)
        let noScopus = health.gaps.count(where: \.missingScopusID)
        if unresolved > 0 { parts.append("\(unresolved) unresolved") }
        if noORCID > 0 { parts.append("\(noORCID) missing ORCID") }
        if noScopus > 0 { parts.append("\(noScopus) missing Scopus ID") }
        if health.totalWorks > 0, health.worksMissingDOI > 0 {
            parts.append("\(health.worksMissingDOI)/\(health.totalWorks) works lack a DOI (skip Scopus/S2 joins)")
        }
        if health.totalWorks > 0, health.worksMissingPMID > 0 {
            parts.append("\(health.worksMissingPMID) lack a PMID (skip iCite)")
        }
        return "Data health: " + parts.joined(separator: " · ")
    }

    private func gapBadge(_ label: String) -> some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(ChartPalette.series3.opacity(0.2), in: Capsule())
    }

    private func orcidSearchURL(_ name: String) -> URL {
        var components = URLComponents(string: "https://orcid.org/orcid-search/search")!
        components.queryItems = [URLQueryItem(name: "searchQuery", value: name)]
        return components.url!
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
