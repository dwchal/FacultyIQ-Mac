import SwiftUI

/// What changed since the last review: new publications and citation/h-index
/// movement per member, accumulated from cache-bypassing re-fetches.
struct WhatsNewView: View {
    @EnvironmentObject private var store: AppStore
    @State private var mode: Mode = .latest

    private enum Mode: String, CaseIterable {
        case latest = "Since Last Review"
        case between = "Between Dates"
    }

    private var changed: [(member: FacultyMember, delta: RefreshDelta)] {
        store.filteredRoster
            .compactMap { member in store.deltas[member.id].map { (member, $0) } }
            .sorted {
                ($0.delta.newWorkIDs.count, $0.delta.citationsDelta)
                    > ($1.delta.newWorkIDs.count, $1.delta.citationsDelta)
            }
    }

    var body: some View {
        Group {
            if store.personData.isEmpty {
                ContentUnavailableView(
                    "No Data Fetched Yet",
                    systemImage: "bell.badge",
                    description: Text("Fetch metrics first — subsequent checks will report new publications and citation changes here.")
                )
            } else {
                VStack(spacing: 0) {
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 340)
                    .padding(.top, 10)
                    switch mode {
                    case .latest: changed.isEmpty ? AnyView(upToDate) : AnyView(changeList)
                    case .between: AnyView(SnapshotDiffView())
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                if !store.deltas.isEmpty {
                    Button {
                        store.markReviewed()
                    } label: {
                        Label("Mark Reviewed", systemImage: "checkmark.circle")
                    }
                    .help("Clear these changes; the next check reports against today's data")
                }
                Button {
                    Task { await store.checkForUpdates() }
                } label: {
                    Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(store.isBusy || store.personData.isEmpty)
                .help("Re-fetch everyone from OpenAlex (skipping the local cache) and report what changed")
            }
        }
    }

    private var upToDate: some View {
        ContentUnavailableView {
            Label("You're Up to Date", systemImage: "checkmark.circle")
        } description: {
            if let checked = store.lastUpdateCheck {
                Text("No changes since the last check (\(checked.formatted(date: .abbreviated, time: .shortened))).")
            } else {
                Text("Click Check for Updates to re-fetch everyone and see what's new.")
            }
        } actions: {
            Button("Check for Updates") {
                Task { await store.checkForUpdates() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isBusy)
        }
    }

    private var changeList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryHeader
                ForEach(changed, id: \.member.id) { entry in
                    memberCard(entry.member, entry.delta)
                }
            }
            .padding(20)
        }
    }

    private var summaryHeader: some View {
        let newWorks = changed.map { $0.delta.newWorkIDs.count }.reduce(0, +)
        let citations = changed.map(\.delta.citationsDelta).reduce(0, +)
        let earliest = changed.map(\.delta.since).min()
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(changed.count) members with changes · \(newWorks) new works · \(signed(citations)) citations")
                .font(.headline)
            if let earliest {
                Text("Since \(earliest.formatted(date: .abbreviated, time: .omitted))" +
                     (store.divisionFilter.map { " · \($0)" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func memberCard(_ member: FacultyMember, _ delta: RefreshDelta) -> some View {
        let works = store.newWorks(for: member.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(member.name).font(.headline)
                    Text([member.rank, member.division].compactMap(\.self).joined(separator: " · ")
                        .nilIfEmpty ?? "—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    if !delta.newWorkIDs.isEmpty {
                        chip("\(delta.newWorkIDs.count) new \(delta.newWorkIDs.count == 1 ? "work" : "works")",
                             emphasized: true)
                    }
                    if delta.citationsDelta != 0 {
                        chip("\(signed(delta.citationsDelta)) citations")
                    }
                    if delta.hIndexDelta != 0 {
                        chip("h-index \(signed(delta.hIndexDelta))")
                    }
                }
            }
            if !works.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(works) { work in
                        workRow(work)
                    }
                }
            }
            Text("Since \(delta.since.formatted(date: .abbreviated, time: .omitted)) · checked \(delta.checkedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func workRow(_ work: Work) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let doi = work.doi, let url = URL(string: doi) {
                Link(work.title, destination: url)
                    .foregroundStyle(.primary)
            } else {
                Text(work.title)
            }
            Text([work.year.map(String.init), work.venue, work.type]
                .compactMap(\.self).joined(separator: " · ")
                .nilIfEmpty ?? "—")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private func chip(_ text: String, emphasized: Bool = false) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(emphasized ? ChartPalette.positive : Color.primary)
            .background(emphasized ? AnyShapeStyle(ChartPalette.positive.opacity(0.12))
                                   : AnyShapeStyle(.quaternary),
                        in: Capsule())
    }

    private func signed(_ value: Int) -> String {
        value >= 0 ? "+\(value.formatted())" : "−\((-value).formatted())"
    }
}
