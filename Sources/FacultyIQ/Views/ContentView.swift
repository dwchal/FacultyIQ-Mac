import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case roster = "Roster"
    case resolution = "Resolution"
    case dashboard = "Dashboard"
    case profiles = "Faculty Profiles"
    case promotion = "Promotion Insights"
    case network = "Network"
    case export = "Export"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .roster: "person.3"
        case .resolution: "person.crop.circle.badge.checkmark"
        case .dashboard: "chart.bar.xaxis"
        case .profiles: "person.text.rectangle"
        case .promotion: "arrow.up.right.circle"
        case .network: "point.3.connected.trianglepath.dotted"
        case .export: "square.and.arrow.up"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection: SidebarItem? = .roster

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .badge(badge(for: item))
                    .tag(item) // selection is SidebarItem?, so rows must tag the item, not its ID
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            detailView
                .navigationTitle(selection?.rawValue ?? "FacultyIQ")
                .toolbar {
                    if showsRefresh {
                        DivisionFilterToolbar(store: store)
                        EnrichDataToolbar(store: store)
                        RefreshDataToolbar(store: store)
                    }
                }
        }
        .safeAreaInset(edge: .bottom) {
            if store.isBusy {
                statusBar
            }
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .roster {
        case .roster: RosterView()
        case .resolution: ResolutionView()
        case .dashboard: DashboardView()
        case .profiles: ProfilesView()
        case .promotion: PromotionView()
        case .network: NetworkView()
        case .export: ExportView()
        }
    }

    /// Data tabs get the shared refresh button; Roster and Resolution manage
    /// their own workflow toolbars.
    private var showsRefresh: Bool {
        switch selection ?? .roster {
        case .dashboard, .profiles, .promotion, .network, .export: true
        case .roster, .resolution: false
        }
    }

    private func badge(for item: SidebarItem) -> Int {
        switch item {
        case .roster: store.roster.count
        case .resolution: store.roster.count - store.resolutions.count
        case .promotion: store.promotionCandidates.count
        default: 0
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            ProgressView(value: store.progress)
                .frame(maxWidth: 240)
            Text(store.progressText)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.lastError != nil && !store.isBusy },
            set: { if !$0 { store.lastError = nil } }
        )
    }
}
