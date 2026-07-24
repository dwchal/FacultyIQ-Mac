import SwiftUI

/// Searches the public Grants.gov catalog and ranks faculty teams using the
/// topics, leadership signals, and prior NIH/NSF funding already in FacultyIQ.
struct OpportunityRadarView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var selection: String?

    private var suggestedQueries: [String] {
        MetricsEngine.suggestedOpportunityQueries(
            personData: store.filteredPersonData, limit: 8)
    }

    private var selectedOpportunity: FundingOpportunity? {
        store.opportunities.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider()
            if store.personData.isEmpty {
                ContentUnavailableView(
                    "No Research Topics Yet",
                    systemImage: "scope",
                    description: Text("Fetch faculty works first; the radar uses their OpenAlex topics to recommend teams."))
            } else if store.opportunities.isEmpty {
                emptyState
            } else {
                HSplitView {
                    opportunityList
                        .frame(minWidth: 320, idealWidth: 390, maxWidth: 480)
                    detail
                        .frame(minWidth: 560)
                }
            }
        }
        .onAppear {
            if selection == nil { selection = store.opportunities.first?.id }
        }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Search Grants.gov opportunities", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { search() }
                Button("Search") { search() }
                    .buttonStyle(.borderedProminent)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || store.isBusy)
                if !store.opportunities.isEmpty {
                    Button("Clear Results", role: .destructive) {
                        store.clearOpportunities()
                        selection = nil
                    }
                }
            }
            if !suggestedQueries.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        Text("From your topics:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(suggestedQueries, id: \.self) { suggestion in
                            Button(shortLabel(suggestion)) {
                                query = suggestion
                                search()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help(suggestion)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(12)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Find Funding Opportunities", systemImage: "scope")
        } description: {
            Text("Search the live Grants.gov catalog by a topic above. FacultyIQ will rank potential internal teams and connected external collaborators.")
        } actions: {
            if let first = suggestedQueries.first {
                Button("Search “\(shortLabel(first))”") {
                    query = first
                    search()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var opportunityList: some View {
        List(store.opportunities, selection: $selection) { opportunity in
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(opportunity.number)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    statusLabel(opportunity)
                }
                Text(opportunity.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(3)
                HStack {
                    Text(opportunity.agencyName)
                    Spacer()
                    if let close = opportunity.closeDate {
                        Text("Due \(close.formatted(date: .abbreviated, time: .omitted))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .tag(opportunity.id)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let opportunity = selectedOpportunity {
            let matches = MetricsEngine.opportunityFacultyMatches(
                opportunity: opportunity,
                roster: store.filteredRoster,
                personData: store.effectivePersonData,
                enrichment: store.enrichment)
            let teamIDs = Set(matches.prefix(4).map(\.member.id))
            let external = store.externalCollaborators
                .filter { collaborator in
                    collaborator.partners.contains { teamIDs.contains($0.memberID) }
                }
                .sorted { ($0.sharedWorks, $1.displayName) > ($1.sharedWorks, $0.displayName) }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(opportunity.number)
                                .font(.callout.monospaced().weight(.semibold))
                            statusLabel(opportunity)
                            Spacer()
                            if let url = opportunity.detailsURL {
                                Link("Open on Grants.gov", destination: url)
                            }
                        }
                        Text(opportunity.title).font(.title2.weight(.semibold))
                        Text(opportunity.agencyName).foregroundStyle(.secondary)
                        HStack(spacing: 18) {
                            if let open = opportunity.openDate {
                                Label("Opened \(open.formatted(date: .abbreviated, time: .omitted))",
                                      systemImage: "calendar")
                            }
                            if let close = opportunity.closeDate {
                                Label("Due \(close.formatted(date: .abbreviated, time: .omitted))",
                                      systemImage: "calendar.badge.clock")
                            }
                        }
                        .font(.callout)
                    }
                    teamCard(matches)
                    externalCard(external, teamIDs: teamIDs)
                    methodologyCard(opportunity)
                }
                .padding(20)
            }
        } else {
            ContentUnavailableView(
                "Select an Opportunity",
                systemImage: "scope",
                description: Text("Choose a funding opportunity to build a candidate team."))
        }
    }

    private func teamCard(_ matches: [MetricsEngine.OpportunityFacultyMatch]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recommended Internal Team").font(.headline)
            Text("Ranked from publication-topic overlap, research leadership, and agency-specific funding history.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if matches.isEmpty {
                Text("No strong match was found in the current faculty scope. Try a broader search term or choose All Faculty.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .frame(width: 24, height: 24)
                            .background(Color.accentColor.opacity(0.14), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Button(match.member.name) {
                                store.profileFocusID = match.member.id
                                store.pendingSidebarTarget = .profiles
                            }
                            .buttonStyle(.link)
                            Text(match.reasons.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(match.score.formatted())
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .help("Relative match score")
                    }
                    if index < matches.count - 1 { Divider() }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func externalCard(_ collaborators: [ExternalCollaborator],
                              teamIDs: Set<UUID>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connected External Collaborators").font(.headline)
            Text("Frequent coauthors already connected to the leading internal candidates.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if collaborators.isEmpty {
                Text("No external collaborator links are available for this team.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(collaborators.prefix(6)) { collaborator in
                    let partners = collaborator.partners
                        .filter { teamIDs.contains($0.memberID) }
                        .map(\.name)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(collaborator.displayName)
                            Text("Connected to \(partners.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(collaborator.sharedWorks) shared works")
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func methodologyCard(_ opportunity: FundingOpportunity) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Match basis").font(.headline)
            Text("Catalog search: “\(opportunity.matchedQuery)”. Recommendations are explainable keyword/topic matches, not eligibility determinations. Always confirm the full announcement, institutional eligibility, and due dates on Grants.gov.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func search() {
        let requested = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requested.isEmpty else { return }
        Task {
            await store.searchOpportunities(query: requested)
            selection = store.opportunities.first { $0.matchedQuery == requested }?.id
                ?? store.opportunities.first?.id
        }
    }

    private func statusLabel(_ opportunity: FundingOpportunity) -> some View {
        Text(opportunity.status.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                opportunity.status == "forecasted"
                    ? Color.orange.opacity(0.14) : Color.green.opacity(0.14),
                in: Capsule())
    }

    private func shortLabel(_ value: String, max: Int = 28) -> String {
        value.count <= max ? value : String(value.prefix(max - 1)) + "…"
    }
}
