import SwiftUI

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
