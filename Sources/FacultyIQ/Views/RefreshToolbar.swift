import SwiftUI

/// Toolbar picker for the data tabs: restrict every analysis view to one
/// division. Hidden while the roster has no division data.
struct DivisionFilterToolbar: ToolbarContent {
    @ObservedObject var store: AppStore

    var body: some ToolbarContent {
        ToolbarItem {
            if !store.divisions.isEmpty {
                Picker("Division", selection: $store.divisionFilter) {
                    Text("All Divisions").tag(String?.none)
                    Divider()
                    ForEach(store.divisions, id: \.self) { division in
                        Text(division).tag(String?.some(division))
                    }
                }
                .pickerStyle(.menu)
                .help("Filter the analysis tabs to one division")
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
