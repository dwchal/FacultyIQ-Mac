import SwiftUI

/// Sheet for searching NIH RePORTER principal investigators by name and
/// confirming which profile the member's grants belong to — name search is
/// fuzzy, so grants are never attached without this confirmation (unless the
/// search was unambiguous).
struct GrantsConfirmSheet: View {
    let member: FacultyMember

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [PICandidate] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var isAttaching = false
    @State private var selection: PICandidate.ID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Principal investigator name", text: $query)
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
                ProgressView("Searching NIH RePORTER…")
                Spacer()
            } else if results.isEmpty {
                Spacer()
                Text(hasSearched
                     ? "No NIH principal investigators found — try a name variation."
                     : "Search NIH RePORTER by name, then select the matching investigator.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Table(results, selection: $selection) {
                    TableColumn("Investigator", value: \.name)
                    TableColumn("Organization") { Text($0.orgName ?? "—") }
                    TableColumn("Projects") { Text("\($0.projectCount)") }
                        .width(60)
                    TableColumn("Latest FY") { Text($0.latestFiscalYear.map(String.init) ?? "—") }
                        .width(65)
                }
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                if isAttaching { ProgressView().controlSize(.small) }
                Button("Use Selected Investigator") { attach() }
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
            results = await store.searchPIs(name: query)
            hasSearched = true
            isSearching = false
        }
    }

    private func attach() {
        guard let candidate = results.first(where: { $0.id == selection }) else { return }
        isAttaching = true
        Task {
            do {
                try await store.attachGrants(member, candidate: candidate)
                dismiss()
            } catch {
                store.lastError = error.localizedDescription
            }
            isAttaching = false
        }
    }
}
