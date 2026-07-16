import SwiftUI

/// Review every work OpenAlex attributes to a member and mark misattributed
/// ones "not theirs". Excluded works leave all metrics but stay listed here
/// so the call can be reversed. Suspects (field differs from the member's
/// dominant field) and retractions sort to the top.
struct WorksAuditSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let member: FacultyMember
    @State private var search = ""
    @State private var suspectsOnly = false

    private var works: [Work] {
        store.personData[member.id]?.works ?? []
    }

    private var suspectIDs: Set<String> {
        MetricsEngine.suspectWorkIDs(works: works)
    }

    var body: some View {
        let suspects = suspectIDs
        let rows = filteredRows(suspects: suspects)
        let excludedCount = store.excludedWorks[member.id]?.count ?? 0
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Audit Works — \(member.name)").font(.headline)
                Text("Uncheck a work to keep it out of every metric (persisted across refreshes). ⚑ marks works whose OpenAlex field differs from the profile's dominant field — worth a look, not a verdict.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            HStack(spacing: 16) {
                TextField("Filter by title or venue", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                if !suspects.isEmpty {
                    Toggle("Flagged only (\(suspects.count))", isOn: $suspectsOnly)
                        .toggleStyle(.checkbox)
                }
                Spacer()
                Text("\(works.count) works · \(excludedCount) excluded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            Divider()
            List(rows, id: \.id) { work in
                row(work, suspect: suspects.contains(work.id))
            }
            .listStyle(.plain)
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 660, minHeight: 460)
    }

    /// Suspects and retractions first, then newest first.
    private func filteredRows(suspects: Set<String>) -> [Work] {
        works
            .filter { !suspectsOnly || suspects.contains($0.id) || $0.isRetracted == true }
            .filter {
                search.trimmingCharacters(in: .whitespaces).isEmpty
                    || $0.title.localizedCaseInsensitiveContains(search)
                    || ($0.venue?.localizedCaseInsensitiveContains(search) ?? false)
            }
            .sorted {
                let flagged0 = suspects.contains($0.id) || $0.isRetracted == true
                let flagged1 = suspects.contains($1.id) || $1.isRetracted == true
                if flagged0 != flagged1 { return flagged0 }
                return ($0.year ?? 0, $0.citedByCount) > (($1.year ?? 0), $1.citedByCount)
            }
    }

    private func row(_ work: Work, suspect: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { !store.isWorkExcluded(work.id, for: member.id) },
                set: { store.setWorkExcluded(work.id, for: member.id, excluded: !$0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help("Unchecked = not \(member.name)'s work; kept out of all metrics")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if work.isRetracted == true {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .foregroundStyle(ChartPalette.critical)
                            .help("Flagged as retracted by OpenAlex")
                    }
                    if suspect {
                        Image(systemName: "flag.fill")
                            .foregroundStyle(ChartPalette.series3)
                            .help("Field differs from this profile's dominant field")
                    }
                    Text(work.title)
                        .lineLimit(1)
                        .strikethrough(store.isWorkExcluded(work.id, for: member.id))
                }
                Text([work.year.map(String.init), work.venue, work.topicField]
                    .compactMap(\.self).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(work.citedByCount) cites")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if let doi = work.doi, let url = URL(string: doi) {
                Link(destination: url) { Image(systemName: "arrow.up.right.square") }
                    .foregroundStyle(.secondary)
                    .help("Open the paper")
            }
        }
        .padding(.vertical, 2)
        .opacity(store.isWorkExcluded(work.id, for: member.id) ? 0.5 : 1)
    }
}
