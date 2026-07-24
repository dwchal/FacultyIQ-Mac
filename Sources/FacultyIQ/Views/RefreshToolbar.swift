import SwiftUI

/// Shared scope menu for every analysis tab: all faculty, one division, or a
/// reusable saved cohort.
struct DivisionFilterToolbar: ToolbarContent {
    @ObservedObject var store: AppStore

    var body: some ToolbarContent {
        ToolbarItem {
            if !store.divisions.isEmpty || !store.cohorts.isEmpty {
                Menu {
                    Button {
                        store.selectDivision(nil)
                    } label: {
                        if store.scopeName == nil {
                            Label("All Faculty", systemImage: "checkmark")
                        } else {
                            Text("All Faculty")
                        }
                    }
                    if !store.divisions.isEmpty {
                        Section("Divisions") {
                            ForEach(store.divisions, id: \.self) { division in
                                Button {
                                    store.selectDivision(division)
                                } label: {
                                    if store.divisionFilter == division {
                                        Label(division, systemImage: "checkmark")
                                    } else {
                                        Text(division)
                                    }
                                }
                            }
                        }
                    }
                    if !store.cohorts.isEmpty {
                        Section("Saved Cohorts") {
                            ForEach(store.cohorts) { cohort in
                                Button {
                                    store.selectCohort(cohort.id)
                                } label: {
                                    if store.cohortFilterID == cohort.id {
                                        Label(cohort.name, systemImage: "checkmark")
                                    } else {
                                        Text(cohort.name)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Label(store.scopeName ?? "All Faculty",
                          systemImage: store.cohortFilterID == nil
                              ? "person.3" : "person.3.sequence")
                }
                .help("Choose the faculty scope used by every analysis tab and export")
            }
        }
    }
}

/// Toolbar button for the data tabs: after roster or resolution edits, one
/// click auto-resolves members with new IDs and fetches anyone missing data.
struct RefreshDataToolbar: ToolbarContent {
    @ObservedObject var store: AppStore

    var body: some ToolbarContent {
        ToolbarItem {
            Button {
                Task { await store.refreshData() }
            } label: {
                Label(title, systemImage: "arrow.clockwise")
            }
            .disabled(store.isBusy)
            .help(store.pendingRefreshCount > 0
                ? "Resolve and fetch data for \(store.pendingRefreshCount) pending members"
                : "Roster data is up to date; resolves and fetches anything new")
        }
    }

    private var title: String {
        store.pendingRefreshCount > 0
            ? "Refresh Data (\(store.pendingRefreshCount))"
            : "Refresh Data"
    }
}

/// Toolbar button for the opt-in enrichment phase (iCite / RePORTER /
/// Semantic Scholar, per the Settings toggles). Hidden until at least one
/// source is enabled.
struct EnrichDataToolbar: ToolbarContent {
    @ObservedObject var store: AppStore
    @AppStorage("enableICite") private var enableICite = false
    @AppStorage("enableReporter") private var enableReporter = false
    @AppStorage("enableSemanticScholar") private var enableSemanticScholar = false

    var body: some ToolbarContent {
        ToolbarItem {
            if enableICite || enableReporter || enableSemanticScholar {
                Button {
                    Task { await store.enrichAll() }
                } label: {
                    Label("Enrich Data", systemImage: "sparkles")
                }
                .disabled(store.isBusy || store.personData.isEmpty)
                .help("Fetch citation metrics, NIH grants, and influence data from the sources enabled in Settings")
            }
        }
    }
}
