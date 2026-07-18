import SwiftUI

/// Global quick-open (Go → Find Faculty…, ⌘F): type a few letters, hit
/// return, land on that member's profile from anywhere in the app.
struct FacultySearchSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var matches: [FacultyMember] {
        store.roster
            .filter { $0.matches(search: query) }
            .sorted { ($0.surnameSortKey, $0.name) < ($1.surnameSortKey, $1.name) }
    }

    /// Members without fetched data can't show a profile yet.
    private func hasData(_ member: FacultyMember) -> Bool {
        store.personData[member.id] != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Name, rank, or division", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit { jumpToFirstMatch() }
                .padding(12)

            Divider()

            if matches.isEmpty {
                Text(store.roster.isEmpty
                     ? "No roster loaded yet."
                     : "No members match “\(query)”.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(matches) { member in
                    row(member)
                }
                .listStyle(.plain)
            }

            Divider()
            HStack {
                Text("Return opens the first match · Esc closes")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(10)
        }
        .frame(width: 440, height: 380)
        .onAppear { searchFocused = true }
    }

    private func row(_ member: FacultyMember) -> some View {
        Button {
            jump(to: member)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(member.name)
                    Text([member.rank, member.division].compactMap(\.self).joined(separator: " · ")
                        .nilIfEmpty ?? "—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !hasData(member) {
                    Text("no data")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasData(member))
        .help(hasData(member)
            ? "Open \(member.name)'s profile"
            : "No fetched data yet — resolve and fetch on the Resolution tab first")
    }

    private func jumpToFirstMatch() {
        if let first = matches.first(where: hasData) {
            jump(to: first)
        }
    }

    private func jump(to member: FacultyMember) {
        store.profileFocusID = member.id
        dismiss()
    }
}
