import SwiftUI

struct CohortsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection: UUID?
    @State private var compareID: UUID?
    @State private var editor: SavedCohort?
    @State private var showingNew = false

    var body: some View {
        if store.roster.isEmpty {
            ContentUnavailableView(
                "No Roster Loaded",
                systemImage: "person.3.sequence",
                description: Text("Load a roster before building reusable cohorts."))
        } else {
            HSplitView {
                cohortList
                    .frame(minWidth: 210, idealWidth: 240, maxWidth: 300)
                detail
                    .frame(minWidth: 620)
            }
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        showingNew = true
                    } label: {
                        Label("New Cohort…", systemImage: "plus")
                    }
                    .help("Create a reusable faculty cohort")
                    if selectedCohort != nil {
                        Button {
                            editor = selectedCohort
                        } label: {
                            Label("Edit Cohort…", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            if let selection { store.deleteCohort(selection) }
                            selection = store.cohorts.first?.id
                        } label: {
                            Label("Delete Cohort", systemImage: "trash")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingNew) {
                CohortEditorSheet(cohort: nil)
            }
            .sheet(item: $editor) { cohort in
                CohortEditorSheet(cohort: cohort)
            }
            .onAppear {
                if selection == nil { selection = store.cohorts.first?.id }
            }
            .onChange(of: store.cohorts) {
                if let selection, !store.cohorts.contains(where: { $0.id == selection }) {
                    self.selection = store.cohorts.first?.id
                }
            }
        }
    }

    private var selectedCohort: SavedCohort? {
        store.cohorts.first { $0.id == selection }
    }

    private var cohortList: some View {
        List(selection: $selection) {
            ForEach(store.cohorts) { cohort in
                VStack(alignment: .leading, spacing: 2) {
                    Text(cohort.name)
                    Text("\(store.cohortMembers(cohort).count) faculty")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(cohort.id)
                .contextMenu {
                    Button("Use as Analysis Scope") { store.selectCohort(cohort.id) }
                    Button("Edit…") { editor = cohort }
                    Button("Delete", role: .destructive) { store.deleteCohort(cohort.id) }
                }
            }
        }
        .overlay {
            if store.cohorts.isEmpty {
                ContentUnavailableView(
                    "No Saved Cohorts",
                    systemImage: "person.3.sequence",
                    description: Text("Create a named cross-division group for analysis and comparison."))
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let cohort = selectedCohort {
            let snapshot = MetricsEngine.cohortSnapshot(
                cohort, roster: store.roster, resolutions: store.resolutions,
                personData: store.effectivePersonData)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(cohort.name).font(.title2.weight(.semibold))
                            Text("\(snapshot.memberCount) faculty · updated \(cohort.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Use as Analysis Scope") { store.selectCohort(cohort.id) }
                            .buttonStyle(.borderedProminent)
                    }
                    snapshotCard(snapshot)
                    comparisonCard(snapshot)
                    membersCard(cohort)
                }
                .padding(20)
            }
        } else {
            ContentUnavailableView(
                "Select a Cohort",
                systemImage: "person.3.sequence",
                description: Text("Choose a saved cohort or create a new one."))
        }
    }

    private func snapshotCard(_ snapshot: MetricsEngine.CohortSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cohort Snapshot").font(.headline)
            HStack(spacing: 28) {
                stat("Faculty", snapshot.memberCount.formatted())
                stat("Resolved", snapshot.resolvedCount.formatted())
                stat("Works", snapshot.totalWorks.formatted())
                stat("Citations", snapshot.totalCitations.formatted())
                stat("Median h-index", snapshot.medianHIndex.formatted(.number.precision(.fractionLength(1))))
                stat("Open access", snapshot.openAccessPercent.map {
                    ($0 / 100).formatted(.percent.precision(.fractionLength(0)))
                } ?? "—")
            }
            if !snapshot.topTopics.isEmpty {
                Text("Top topics: \(snapshot.topTopics.joined(separator: " · "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func comparisonCard(_ snapshot: MetricsEngine.CohortSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Compare With").font(.headline)
                Picker("Comparison cohort", selection: $compareID) {
                    Text("Choose a cohort").tag(UUID?.none)
                    ForEach(store.cohorts.filter { $0.id != snapshot.id }) { cohort in
                        Text(cohort.name).tag(UUID?.some(cohort.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)
            }
            if let compareID,
               let other = store.cohorts.first(where: { $0.id == compareID }) {
                let comparison = MetricsEngine.cohortSnapshot(
                    other, roster: store.roster, resolutions: store.resolutions,
                    personData: store.effectivePersonData)
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        Text("Metric").font(.caption.weight(.semibold))
                        Text(snapshot.name).font(.caption.weight(.semibold))
                        Text(comparison.name).font(.caption.weight(.semibold))
                    }
                    comparisonRow("Faculty", snapshot.memberCount, comparison.memberCount)
                    comparisonRow("Works", snapshot.totalWorks, comparison.totalWorks)
                    comparisonRow("Citations", snapshot.totalCitations, comparison.totalCitations)
                    GridRow {
                        Text("Median h-index")
                        Text(snapshot.medianHIndex.formatted(.number.precision(.fractionLength(1))))
                        Text(comparison.medianHIndex.formatted(.number.precision(.fractionLength(1))))
                    }
                }
            } else {
                Text("Choose another saved cohort for a side-by-side summary.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func comparisonRow(_ label: String, _ lhs: Int, _ rhs: Int) -> some View {
        GridRow {
            Text(label)
            Text(lhs.formatted())
            Text(rhs.formatted())
        }
    }

    private func membersCard(_ cohort: SavedCohort) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Members").font(.headline)
            ForEach(store.cohortMembers(cohort)) { member in
                HStack {
                    Text(member.name)
                    Spacer()
                    Text(member.rank ?? "—").foregroundStyle(.secondary)
                    Text(member.division ?? "—").foregroundStyle(.secondary)
                        .frame(width: 160, alignment: .leading)
                }
                Divider()
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct CohortEditorSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    private let cohortID: UUID?
    @State private var name: String
    @State private var selection: Set<UUID>
    @State private var searchText = ""

    init(cohort: SavedCohort?) {
        cohortID = cohort?.id
        _name = State(initialValue: cohort?.name ?? "")
        _selection = State(initialValue: cohort?.memberIDs ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(cohortID == nil ? "New Saved Cohort" : "Edit Saved Cohort")
                .font(.title2.weight(.semibold))
            TextField("Cohort name", text: $name)
            Table(
                store.roster.filter { $0.matches(search: searchText) }
                    .sorted { $0.surnameSortKey < $1.surnameSortKey },
                selection: $selection
            ) {
                TableColumn("Name", value: \.name)
                TableColumn("Rank") { Text($0.rank ?? "—") }
                TableColumn("Division") { Text($0.division ?? "—") }
            }
            .searchable(text: $searchText, prompt: "Filter faculty")
            HStack {
                Text("\(selection.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    store.saveCohort(id: cohortID, name: name, memberIDs: selection)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || selection.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 720, height: 560)
    }
}
