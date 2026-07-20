import SwiftUI

/// Sheet for searching OpenAlex institutions by name and adding one to the
/// peer-benchmark list (Settings → Promotion). Institution-name search is
/// ambiguity-prone (e.g. "Washington University" vs "University of
/// Washington", multiple campuses of the same system), so this always shows
/// a picker rather than guessing the first result.
struct InstitutionSearchSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [InstitutionCandidate] = []
    @State private var isSearching = false
    @State private var hasSearched = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Institution name", text: $query)
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
                ProgressView("Searching OpenAlex…")
                Spacer()
            } else if results.isEmpty {
                Spacer()
                Text(hasSearched
                     ? "No institutions found — try a different name."
                     : "Search OpenAlex by institution name, then pick from the results.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Spacer()
            } else {
                List(results) { candidate in
                    row(candidate)
                }
                .listStyle(.plain)
            }

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 440, height: 400)
    }

    private func row(_ candidate: InstitutionCandidate) -> some View {
        Button {
            store.addPeerInstitution(candidate)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.displayName)
                    Text([candidate.type, candidate.countryCode].compactMap(\.self).joined(separator: " · ")
                        .nilIfEmpty ?? "—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func search() {
        guard !query.isEmpty else { return }
        isSearching = true
        Task {
            results = await store.searchPeerInstitutions(name: query)
            hasSearched = true
            isSearching = false
        }
    }
}
