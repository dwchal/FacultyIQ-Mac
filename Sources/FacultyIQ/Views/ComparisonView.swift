import SwiftUI
import UniformTypeIdentifiers

/// Side-by-side metrics for 2–4 members — the sheet a division chief brings
/// to a promotion committee: the candidate against recently promoted peers,
/// with each rank's division medians for context.
struct ComparisonView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedIDs: [UUID] = []

    private var membersWithData: [FacultyMember] {
        store.roster
            .filter { store.personData[$0.id] != nil }
            .sorted { $0.surnameSortKey < $1.surnameSortKey }
    }

    private var selectedMembers: [FacultyMember] {
        selectedIDs.compactMap { id in membersWithData.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            picker
            Divider()
            if selectedMembers.count < 2 {
                ContentUnavailableView(
                    "Pick Faculty to Compare",
                    systemImage: "person.line.dotted.person",
                    description: Text("Choose 2–4 members — e.g. a promotion candidate next to recently promoted peers at the target rank.")
                )
            } else {
                let columns = selectedMembers.map { ComparisonColumn(store: store, member: $0) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ComparisonGrid(columns: columns, benchmarks: store.benchmarks)
                            .padding(16)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        savePDFButton(columns)
                    }
                    .padding(20)
                }
            }
        }
    }

    private var picker: some View {
        HStack(spacing: 8) {
            ForEach(selectedMembers) { member in
                HStack(spacing: 4) {
                    Text(member.name).lineLimit(1)
                    Button {
                        selectedIDs.removeAll { $0 == member.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
            }
            Menu("Add Member") {
                ForEach(membersWithData.filter { !selectedIDs.contains($0.id) }) { member in
                    Button(member.name) { selectedIDs.append(member.id) }
                }
            }
            .frame(maxWidth: 160)
            .disabled(selectedIDs.count >= 4)
            Spacer()
            if selectedIDs.count >= 2 {
                Button("Clear") { selectedIDs.removeAll() }
                    .controlSize(.small)
            }
        }
        .padding(12)
    }

    private func savePDFButton(_ columns: [ComparisonColumn]) -> some View {
        Button("Save Comparison as PDF…") {
            let names = columns.map { $0.member.surnameSortKey }.joined(separator: "_")
            if case .failure(let error) = SavePanel.run(
                defaultName: "comparison_\(names).pdf", type: .pdf,
                write: { url in
                    try PDFComposer.write(
                        pages: ComparisonPages.pages(columns: columns, benchmarks: store.benchmarks),
                        to: url)
                }) {
                store.lastError = error.localizedDescription
            }
        }
    }
}
