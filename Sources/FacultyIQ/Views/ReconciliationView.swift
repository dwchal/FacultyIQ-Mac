import SwiftUI
import UniformTypeIdentifiers

/// Imports a faculty member's CV/reference export and compares it with the
/// locally fetched OpenAlex works by DOI first and normalized title second.
struct ReconciliationView: View {
    @EnvironmentObject private var store: AppStore
    @State private var memberID: UUID?
    @State private var showingImporter = false
    @State private var searchText = ""

    private var members: [FacultyMember] {
        store.filteredRoster
            .filter { store.personData[$0.id] != nil }
            .sorted { $0.surnameSortKey < $1.surnameSortKey }
    }

    private var selectedMember: FacultyMember? {
        members.first { $0.id == memberID }
    }

    private var matches: [ReconciliationMatch] {
        guard let memberID else { return [] }
        let imported = store.importedPublications.filter { $0.memberID == memberID }
        let works = store.personData[memberID]?.works ?? []
        return MetricsEngine.reconciliationMatches(imported: imported, works: works)
            .filter {
                searchText.isEmpty
                    || $0.imported.title.localizedCaseInsensitiveContains(searchText)
                    || ($0.imported.doi?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            if members.isEmpty {
                ContentUnavailableView(
                    "No Fetched Faculty",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Resolve and fetch at least one faculty member before reconciling a publication list."))
            } else if memberID == nil {
                ContentUnavailableView(
                    "Choose a Faculty Member",
                    systemImage: "person.crop.circle",
                    description: Text("Select whose CV, ORCID export, or reference-manager file you want to compare."))
            } else if matches.isEmpty {
                emptyState
            } else {
                reconciliationContent
            }
        }
        .searchable(text: $searchText, prompt: "Title or DOI")
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: allowedTypes
        ) { result in
            guard case .success(let url) = result, let memberID else { return }
            store.importPublications(from: url, for: memberID)
        }
        .onAppear {
            if memberID == nil { memberID = members.first?.id }
        }
        .onChange(of: store.scopeName) {
            if let memberID, !members.contains(where: { $0.id == memberID }) {
                self.memberID = members.first?.id
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Picker("Faculty", selection: $memberID) {
                Text("Choose Faculty").tag(UUID?.none)
                ForEach(members) { member in
                    Text(member.name).tag(UUID?.some(member.id))
                }
            }
            .frame(maxWidth: 260)
            Button {
                showingImporter = true
            } label: {
                Label("Import Publications…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(memberID == nil)
            .help("Import BibTeX, RIS, or CSV exported from ORCID, a CV system, or a reference manager")
            if let memberID,
               store.importedPublications.contains(where: { $0.memberID == memberID }) {
                Button("Clear Imported List", role: .destructive) {
                    store.clearImportedPublications(for: memberID)
                }
            }
            Spacer()
            Text("BibTeX · RIS · CSV")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Import a Publication List", systemImage: "doc.text.magnifyingglass")
        } description: {
            Text("Export BibTeX or RIS from ORCID, Zotero, EndNote, or another CV system. CSV files need title and optional DOI/year columns.")
        } actions: {
            Button("Import Publications…") { showingImporter = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var reconciliationContent: some View {
        let all = unfilteredMatches
        let doi = all.count { $0.kind == .doi }
        let title = all.count { $0.kind == .title }
        let missing = all.count {
            $0.kind == .missing && $0.imported.disposition == .pending
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 24) {
                stat("Imported", all.count, color: .primary)
                stat("DOI matches", doi, color: ChartPalette.positive)
                stat("Title matches", title, color: .blue)
                stat("Needs review", missing, color: .orange)
                Spacer()
                if let member = selectedMember {
                    Text("Compared with \(store.personData[member.id]?.works.count ?? 0) OpenAlex works")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            Divider()
            List(matches) { match in
                reconciliationRow(match)
            }
        }
    }

    private var unfilteredMatches: [ReconciliationMatch] {
        guard let memberID else { return [] }
        return MetricsEngine.reconciliationMatches(
            imported: store.importedPublications.filter { $0.memberID == memberID },
            works: store.personData[memberID]?.works ?? [])
    }

    private func reconciliationRow(_ match: ReconciliationMatch) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: matchIcon(match))
                .foregroundStyle(matchColor(match))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(match.imported.title)
                    .font(.callout.weight(.medium))
                HStack(spacing: 10) {
                    if let year = match.imported.year { Text(String(year)) }
                    if let doi = match.imported.doi {
                        Text(doi).font(.caption.monospaced())
                    }
                    Text(match.imported.sourceFormat.rawValue)
                    Text(match.kind.label)
                        .foregroundStyle(matchColor(match))
                    if match.imported.disposition != .pending {
                        Text(match.imported.disposition.label)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if match.kind == .title, let work = match.matchedWork,
                   work.title != match.imported.title {
                    Text("Matched OpenAlex title: \(work.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if match.kind == .missing {
                Menu(match.imported.disposition.label) {
                    ForEach(ReconciliationDisposition.allCases, id: \.self) { disposition in
                        Button(disposition.label) {
                            store.setReconciliationDisposition(
                                disposition, publicationID: match.imported.id)
                        }
                    }
                }
                .frame(width: 110)
            } else if let work = match.matchedWork, let doi = work.doi,
                      let url = URL(string: "https://doi.org/\(doi.bareDOI)") {
                Link("Open DOI", destination: url)
            }
        }
        .padding(.vertical, 4)
    }

    private func stat(_ label: String, _ value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.formatted())
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func matchIcon(_ match: ReconciliationMatch) -> String {
        if match.imported.disposition == .ignored { return "minus.circle" }
        if match.imported.disposition == .resolved { return "checkmark.circle" }
        switch match.kind {
        case .doi: return "checkmark.seal.fill"
        case .title: return "checkmark.circle"
        case .missing: return "exclamationmark.triangle.fill"
        }
    }

    private func matchColor(_ match: ReconciliationMatch) -> Color {
        if match.imported.disposition != .pending { return .secondary }
        switch match.kind {
        case .doi: return ChartPalette.positive
        case .title: return Color.blue
        case .missing: return Color.orange
        }
    }

    private var allowedTypes: [UTType] {
        ["bib", "bibtex", "ris", "csv"].compactMap { UTType(filenameExtension: $0) }
    }
}
