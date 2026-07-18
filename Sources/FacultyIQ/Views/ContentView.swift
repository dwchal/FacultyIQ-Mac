import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case roster = "Roster"
    case resolution = "Resolution"
    case dashboard = "Dashboard"
    case whatsNew = "What's New"
    case profiles = "Faculty Profiles"
    case promotion = "Promotion Insights"
    case topics = "Topics"
    case publications = "Publications"
    case funding = "Funding"
    case network = "Network"
    case external = "External Collaborators"
    case export = "Export"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .roster: "person.3"
        case .resolution: "person.crop.circle.badge.checkmark"
        case .dashboard: "chart.bar.xaxis"
        case .whatsNew: "bell.badge"
        case .profiles: "person.text.rectangle"
        case .promotion: "arrow.up.right.circle"
        case .topics: "tag"
        case .publications: "doc.text"
        case .funding: "dollarsign.circle"
        case .network: "point.3.connected.trianglepath.dotted"
        case .external: "person.2.wave.2"
        case .export: "square.and.arrow.up"
        }
    }
}

/// Sidebar grouping: analysis sections ordered by daily use, with roster
/// management and exports together in a Data section at the bottom.
enum SidebarSection: String, CaseIterable {
    case overview = "Overview"
    case faculty = "Faculty"
    case research = "Research Output"
    case collaboration = "Collaboration"
    case data = "Data"

    var items: [SidebarItem] {
        switch self {
        case .overview: [.dashboard, .whatsNew]
        case .faculty: [.profiles, .promotion]
        case .research: [.topics, .publications, .funding]
        case .collaboration: [.network, .external]
        case .data: [.roster, .resolution, .export]
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection: SidebarItem?
    @AppStorage("lastSidebarSelection") private var lastSelection = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarSection.allCases, id: \.self) { section in
                    Section(section.rawValue) {
                        ForEach(section.items) { item in
                            Label(item.rawValue, systemImage: item.icon)
                                .badge(badge(for: item))
                                .tag(item) // selection is SidebarItem?, so rows must tag the item, not its ID
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .onAppear {
                // Return to the last-used tab; before that habit exists,
                // land where the work is: setup until data exists, then
                // the dashboard.
                guard selection == nil else { return }
                if store.roster.isEmpty {
                    selection = .roster
                } else if let saved = SidebarItem(rawValue: lastSelection) {
                    selection = saved
                } else {
                    selection = store.personData.isEmpty ? .resolution : .dashboard
                }
            }
            .onChange(of: selection) {
                if let selection { lastSelection = selection.rawValue }
            }
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
        .sheet(isPresented: $store.showFacultySearch) {
            FacultySearchSheet()
        }
        .onChange(of: store.profileFocusID) {
            // The Find Faculty sheet picked someone: show their profile.
            if store.profileFocusID != nil { selection = .profiles }
        }
        .onChange(of: store.pendingSidebarTarget) {
            if let target = store.pendingSidebarTarget {
                selection = target
                store.pendingSidebarTarget = nil
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
        switch selection ?? .dashboard {
        case .roster: RosterView()
        case .resolution: ResolutionView()
        case .dashboard: DashboardView()
        case .whatsNew: WhatsNewView()
        case .profiles: ProfilesView()
        case .promotion: PromotionView()
        case .topics: TopicsView()
        case .publications: PublicationsView()
        case .funding: FundingView()
        case .network: NetworkView()
        case .external: ExternalCollaboratorsView()
        case .export: ExportView()
        }
    }

    /// Data tabs get the shared refresh button; Roster and Resolution manage
    /// their own workflow toolbars.
    private var showsRefresh: Bool {
        switch selection ?? .dashboard {
        case .dashboard, .whatsNew, .profiles, .promotion, .topics, .publications, .funding,
             .network, .external, .export: true
        case .roster, .resolution: false
        }
    }

    private func badge(for item: SidebarItem) -> Int {
        switch item {
        case .roster: store.roster.count
        case .resolution: store.roster.count - store.resolutions.count
        case .whatsNew: store.deltas.count
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
