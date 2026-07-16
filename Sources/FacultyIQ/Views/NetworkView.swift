import SwiftUI

/// Coauthorship network: which roster members publish together. Nodes are
/// resolved faculty, edges are weighted by shared works.
struct NetworkView: View {
    @EnvironmentObject private var store: AppStore
    @State private var minWeight = 1
    @State private var showIsolated = false
    @State private var showMentorship = false
    @State private var selectedID: UUID?
    @State private var hoveredID: UUID?
    @State private var positions: [UUID: NetworkLayout.Point] = [:]

    var body: some View {
        let network = store.coauthorNetwork
        if network.nodes.isEmpty {
            ContentUnavailableView(
                "No Faculty Data",
                systemImage: "point.3.connected.trianglepath.dotted",
                description: Text("Fetch metrics on the Resolution tab to map coauthorships.")
            )
        } else if network.edges.isEmpty {
            ContentUnavailableView {
                Label("No Coauthorships Found", systemImage: "point.3.connected.trianglepath.dotted")
            } description: {
                Text(network.staleAuthorData
                    ? "Works were fetched before coauthor data was tracked. Refresh to download it."
                    : "No shared publications were found among resolved members.")
            } actions: {
                if network.staleAuthorData {
                    refreshButton
                }
            }
        } else {
            content(network)
        }
    }

    private func content(_ network: CoauthorNetwork) -> some View {
        VStack(spacing: 0) {
            if network.staleAuthorData {
                staleBanner
            }
            controls(network)
            Divider()
            HSplitView {
                graph(network)
                    .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                sidebar(network)
                    .frame(minWidth: 220, maxWidth: 320)
            }
        }
        .onAppear { relayout(network) }
        .onChange(of: network.edges) { relayout(network) }
    }

    /// Layout uses the full edge set so filtering never moves nodes.
    private func relayout(_ network: CoauthorNetwork) {
        let connected = network.nodes.filter { $0.degree > 0 }.map(\.memberID)
        let isolated = network.nodes.filter { $0.degree == 0 }.map(\.memberID)
        positions = NetworkLayout.layout(nodeIDs: connected, edges: network.edges)
            .merging(NetworkLayout.ring(nodeIDs: isolated)) { a, _ in a }
        if let selected = selectedID, !network.nodes.contains(where: { $0.memberID == selected }) {
            selectedID = nil
        }
    }

    // MARK: Header

    private var staleBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            Text("Some works were fetched before coauthor data was tracked, so this network may be incomplete.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            refreshButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5))
    }

    private var refreshButton: some View {
        Button("Refresh Works") {
            Task { await store.fetchAll(refresh: true) }
        }
        .disabled(store.isBusy)
        .help("Re-download publications for all resolved members, including coauthor lists")
    }

    private func controls(_ network: CoauthorNetwork) -> some View {
        let maxWeight = network.edges.map(\.weight).max() ?? 1
        let isolatedCount = network.nodes.count { $0.degree == 0 }
        return HStack(spacing: 16) {
            Stepper("Min shared works: \(minWeight)",
                    value: $minWeight, in: 1...max(maxWeight, 1))
            if isolatedCount > 0 {
                Toggle("Show \(isolatedCount) without coauthors", isOn: $showIsolated)
                    .toggleStyle(.checkbox)
            }
            if !store.mentorshipEdges.isEmpty {
                Toggle("Mentorship arrows (\(store.mentorshipEdges.count))", isOn: $showMentorship)
                    .toggleStyle(.checkbox)
                    .help("Arrows point from a senior (last) author to a roster member who first-authored their shared works — an approximate mentorship signal from byline order")
            }
            Spacer()
            Text("\(network.nodes.count - isolatedCount) members · \(network.edges.count) collaborations")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Graph

    private func graph(_ network: CoauthorNetwork) -> some View {
        NetworkGraphView(
            nodes: showIsolated ? network.nodes : network.nodes.filter { $0.degree > 0 },
            edges: network.edges.filter { $0.weight >= minWeight },
            mentorship: showMentorship ? store.mentorshipEdges : [],
            positions: positions,
            maxWorks: network.nodes.map(\.worksCount).max() ?? 1,
            selectedID: $selectedID,
            hoveredID: $hoveredID)
    }

    // MARK: Detail sidebar

    @ViewBuilder
    private func sidebar(_ network: CoauthorNetwork) -> some View {
        if let node = network.nodes.first(where: { $0.memberID == selectedID }) {
            memberDetail(node, network: network)
        } else {
            topPairs(network)
        }
    }

    private func memberDetail(_ node: CoauthorNode, network: CoauthorNetwork) -> some View {
        let nameByID = Dictionary(uniqueKeysWithValues: network.nodes.map { ($0.memberID, $0.name) })
        let coauthors = network.edges
            .filter { $0.involves(node.memberID) }
            .compactMap { edge in
                edge.other(than: node.memberID).map { (name: nameByID[$0] ?? "—", weight: edge.weight) }
            }
            .sorted { ($0.weight, $1.name) > ($1.weight, $0.name) }

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name).font(.headline)
                Text("\(node.worksCount) works · \(node.sharedWorks) shared with \(node.degree) roster coauthors")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            let mentees = mentorshipPartners(of: node.memberID, asMentor: true, names: nameByID)
            let mentors = mentorshipPartners(of: node.memberID, asMentor: false, names: nameByID)
            if coauthors.isEmpty {
                Text("No coauthorships with other roster members.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(coauthors, id: \.name) { coauthor in
                        HStack {
                            Text(coauthor.name)
                            Spacer()
                            Text("\(coauthor.weight)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    if !mentees.isEmpty {
                        mentorshipSection(
                            "Mentees — they first-author, \(node.name.components(separatedBy: " ").first ?? "member") is senior author",
                            partners: mentees)
                    }
                    if !mentors.isEmpty {
                        mentorshipSection(
                            "Mentors — senior authors on their first-author works",
                            partners: mentors)
                    }
                }
                .listStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private func mentorshipPartners(of memberID: UUID, asMentor: Bool,
                                    names: [UUID: String]) -> [(name: String, weight: Int)] {
        store.mentorshipEdges
            .filter { (asMentor ? $0.mentor : $0.mentee) == memberID }
            .map { (name: names[asMentor ? $0.mentee : $0.mentor] ?? "—", weight: $0.weight) }
            .sorted { ($0.weight, $1.name) > ($1.weight, $0.name) }
    }

    private func mentorshipSection(_ title: String,
                                   partners: [(name: String, weight: Int)]) -> some View {
        Section {
            ForEach(partners, id: \.name) { partner in
                HStack {
                    Text(partner.name)
                    Spacer()
                    Text("\(partner.weight)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .help("\(partner.weight) shared \(partner.weight == 1 ? "work" : "works") in this first/last-author pairing (byline order — approximate)")
            }
        } header: {
            Text(title).font(.caption)
        }
    }

    private func topPairs(_ network: CoauthorNetwork) -> some View {
        let nameByID = Dictionary(uniqueKeysWithValues: network.nodes.map { ($0.memberID, $0.name) })
        let suggestions = MetricsEngine.collaborationSuggestions(
            roster: store.filteredRoster, personData: store.effectivePersonData,
            network: network, limit: 6)
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Top Collaborations").font(.headline)
                Text("Click a member in the graph for their detail.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            List {
                ForEach(Array(network.edges.prefix(15))) { edge in
                    HStack {
                        Text("\(nameByID[edge.memberA] ?? "—") · \(nameByID[edge.memberB] ?? "—")")
                            .lineLimit(1)
                        Spacer()
                        Text("\(edge.weight)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                let topMentorships = Array(store.mentorshipEdges.prefix(8))
                if !topMentorships.isEmpty {
                    Section {
                        ForEach(topMentorships) { edge in
                            HStack {
                                Text("\(nameByID[edge.mentor] ?? "—") → \(nameByID[edge.mentee] ?? "—")")
                                    .lineLimit(1)
                                Spacer()
                                Text("\(edge.weight)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .help("\(nameByID[edge.mentor] ?? "—") is senior (last) author on \(edge.weight) \(edge.weight == 1 ? "work" : "works") first-authored by \(nameByID[edge.mentee] ?? "—") — byline order, so approximate")
                        }
                    } header: {
                        Text("Mentorship — senior author → first author")
                            .font(.caption)
                    }
                }
                if !suggestions.isEmpty {
                    Section {
                        ForEach(suggestions) { suggestion in
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(suggestion.nameA) · \(suggestion.nameB)")
                                    .lineLimit(1)
                                Text(suggestion.sharedTopics.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .help("Both publish on these topics but have never co-published (overlap score \(suggestion.score))")
                        }
                    } header: {
                        Text("Suggested — same topics, never co-published")
                            .font(.caption)
                    }
                }
            }
            .listStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

/// The node-link graph itself, independent of AppStore so it can be
/// previewed and render-tested with synthetic data.
struct NetworkGraphView: View {
    let nodes: [CoauthorNode]
    let edges: [CoauthorEdge]                     // pre-filtered for display
    var mentorship: [MentorshipEdge] = []         // directed overlay; empty = off
    let positions: [UUID: NetworkLayout.Point]
    let maxWorks: Int
    @Binding var selectedID: UUID?
    @Binding var hoveredID: UUID?

    var body: some View {
        let focusID = hoveredID ?? selectedID
        let neighbors = focusID.map { id in
            Set(edges.compactMap { $0.other(than: id) })
                .union(mentorship.filter { $0.involves(id) }.flatMap { [$0.mentor, $0.mentee] })
                .union([id])
        }

        GeometryReader { geo in
            ZStack {
                // Click-through background clears the selection.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { selectedID = nil }

                edgeCanvas(focusID: focusID, size: geo.size)
                if !mentorship.isEmpty {
                    mentorshipCanvas(focusID: focusID, size: geo.size)
                }

                ForEach(nodes) { node in
                    let dimmed = neighbors.map { !$0.contains(node.memberID) } ?? false
                    nodeView(node)
                        .position(point(node.memberID, in: geo.size))
                        .opacity(dimmed ? 0.25 : 1)
                }
            }
        }
        .overlay(alignment: .bottomLeading) { legend }
        .padding(8)
    }

    /// Fixed rank → color slots; a rank keeps its color no matter which ranks
    /// are on screen. Unknown ranks are gray.
    static func color(for rank: AcademicRank?) -> Color {
        switch rank {
        case .assistant: ChartPalette.series1
        case .associate: ChartPalette.series2
        case .full: ChartPalette.series3
        case .instructor: ChartPalette.series4
        case nil: Color.gray
        }
    }

    private static func shortLabel(for rank: AcademicRank?) -> String {
        switch rank {
        case .instructor: "Instructor"
        case .assistant: "Assistant"
        case .associate: "Associate"
        case .full: "Full"
        case nil: "Unknown rank"
        }
    }

    @ViewBuilder
    private var legend: some View {
        let present: [AcademicRank?] = AcademicRank.allCases.filter { rank in
            nodes.contains { $0.rank == rank }
        } + (nodes.contains { $0.rank == nil } ? [nil] : [])
        if present.count >= 2 {
            HStack(spacing: 12) {
                ForEach(present, id: \.self) { rank in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Self.color(for: rank))
                            .frame(width: 9, height: 9)
                        Text(Self.shortLabel(for: rank))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.background.opacity(0.85), in: Capsule())
            .padding(6)
        }
    }

    private func edgeCanvas(focusID: UUID?, size: CGSize) -> some View {
        Canvas { context, _ in
            for edge in edges {
                let a = point(edge.memberA, in: size)
                let b = point(edge.memberB, in: size)
                let highlighted = focusID.map(edge.involves) ?? false
                let dimmed = focusID != nil && !highlighted

                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                context.stroke(
                    path,
                    with: highlighted
                        ? .color(.primary.opacity(0.6))
                        : .color(.gray.opacity(dimmed ? 0.12 : 0.35)),
                    lineWidth: 1 + min(5, 1.5 * log2(1 + Double(edge.weight))))

                if highlighted {
                    let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                    context.draw(
                        Text("\(edge.weight)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary),
                        at: CGPoint(x: mid.x, y: mid.y - 8))
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Directed mentor→mentee arrows over the coauthorship edges. The arrow
    /// stops at the mentee node's rim so the head stays visible.
    private func mentorshipCanvas(focusID: UUID?, size: CGSize) -> some View {
        let visible = Set(nodes.map(\.memberID))
        let radiusByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.memberID, radius(for: $0)) })
        return Canvas { context, _ in
            for edge in mentorship
            where visible.contains(edge.mentor) && visible.contains(edge.mentee) {
                let from = point(edge.mentor, in: size)
                let to = point(edge.mentee, in: size)
                let dx = to.x - from.x, dy = to.y - from.y
                let length = (dx * dx + dy * dy).squareRoot()
                guard length > 1 else { continue }
                let (ux, uy) = (dx / length, dy / length)
                let tip = CGPoint(x: to.x - ux * ((radiusByID[edge.mentee] ?? 8) + 3),
                                  y: to.y - uy * ((radiusByID[edge.mentee] ?? 8) + 3))
                let dimmed = focusID.map { !edge.involves($0) } ?? false
                let color = ChartPalette.series3.opacity(dimmed ? 0.15 : 0.85)
                let width = 1 + min(3, log2(1 + Double(edge.weight)))

                var line = Path()
                line.move(to: from)
                line.addLine(to: tip)
                context.stroke(line, with: .color(color), lineWidth: width)

                let headLength = 7.0
                var head = Path()
                head.move(to: tip)
                head.addLine(to: CGPoint(x: tip.x - ux * headLength - uy * headLength * 0.5,
                                         y: tip.y - uy * headLength + ux * headLength * 0.5))
                head.addLine(to: CGPoint(x: tip.x - ux * headLength + uy * headLength * 0.5,
                                         y: tip.y - uy * headLength - ux * headLength * 0.5))
                head.closeSubpath()
                context.fill(head, with: .color(color))
            }
        }
        .allowsHitTesting(false)
    }

    private func radius(for node: CoauthorNode) -> Double {
        6 + 10 * (Double(node.worksCount) / Double(max(maxWorks, 1))).squareRoot()
    }

    private func nodeView(_ node: CoauthorNode) -> some View {
        let radius = radius(for: node)
        return VStack(spacing: 3) {
            Circle()
                .fill(Self.color(for: node.rank))
                .overlay(Circle().strokeBorder(
                    selectedID == node.memberID ? Color.primary : Color(nsColor: .windowBackgroundColor),
                    lineWidth: 2))
                .frame(width: radius * 2, height: radius * 2)
            Text(node.name)
                .font(.caption)
                .lineLimit(1)
                .fixedSize()
        }
        .onHover { hovering in
            hoveredID = hovering ? node.memberID : (hoveredID == node.memberID ? nil : hoveredID)
        }
        .onTapGesture {
            selectedID = selectedID == node.memberID ? nil : node.memberID
        }
        .help("\(node.name): \(node.worksCount) works, \(node.degree) roster coauthors")
    }

    private func point(_ id: UUID, in size: CGSize) -> CGPoint {
        let p = positions[id] ?? NetworkLayout.Point(x: 0.5, y: 0.5)
        return CGPoint(x: p.x * size.width, y: p.y * size.height)
    }
}
