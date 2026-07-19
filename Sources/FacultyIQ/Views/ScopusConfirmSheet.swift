import SwiftUI

/// Sheet for searching Scopus authors by name and confirming which record
/// belongs to the member — Scopus name search is fuzzy, so an author is never
/// attached without this confirmation. Confirming writes the ID back to the
/// roster, so OpenAlex resolution can use it too.
struct ScopusConfirmSheet: View {
    let member: FacultyMember

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [ScopusAuthorCandidate] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var isAttaching = false
    @State private var selection: ScopusAuthorCandidate.ID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Author name", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { search() }
                Button("Search") { search() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(query.isEmpty || isSearching)
            }
            .padding()

            Divider()

            if isSearching {
                Spacer()
                ProgressView("Searching Scopus…")
                Spacer()
            } else if results.isEmpty {
                Spacer()
                Text(hasSearched
                     ? "No Scopus authors found — try a name variation, or check the network (Scopus keys need the institutional network or VPN)."
                     : "Search Scopus by name, then select the matching author record.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Spacer()
            } else {
                Table(results, selection: $selection) {
                    TableColumn("Author", value: \.name)
                    TableColumn("Affiliation") { Text($0.affiliation ?? "—") }
                    TableColumn("City") { Text($0.city ?? "—") }
                        .width(110)
                    TableColumn("Documents") {
                        Text($0.documentCount.map(String.init) ?? "—")
                    }
                    .width(75)
                }
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                if isAttaching { ProgressView().controlSize(.small) }
                Button("Use Selected Author") { attach() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selection == nil || isAttaching)
            }
            .padding()
        }
        .frame(width: 640, height: 400)
        .onAppear {
            query = member.name
            search()
        }
    }

    private func search() {
        guard !query.isEmpty else { return }
        isSearching = true
        Task {
            results = await store.searchScopusAuthors(name: query)
            hasSearched = true
            isSearching = false
        }
    }

    private func attach() {
        guard let candidate = results.first(where: { $0.id == selection }) else { return }
        isAttaching = true
        Task {
            await store.attachScopusAuthor(member, candidate: candidate)
            isAttaching = false
            dismiss()
        }
    }
}
