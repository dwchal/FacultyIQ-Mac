import SwiftUI

/// Form for adding or editing a single roster member — the one-person-at-a-time
/// alternative to CSV import.
struct MemberEditorSheet: View {
    /// nil creates a new member; otherwise edits the given one.
    let member: FacultyMember?

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private static let standardRanks = [
        "Instructor", "Assistant Professor", "Associate Professor",
        "Full Professor", "Research Faculty",
    ]
    private static let customRankTag = "Other…"

    @State private var name = ""
    @State private var email = ""
    @State private var rankChoice = ""
    @State private var customRank = ""
    @State private var division = ""
    @State private var status: MemberStatus = .active
    @State private var hireYear = ""
    @State private var lastPromotionYear = ""
    @State private var assistantStartYear = ""
    @State private var associateStartYear = ""
    @State private var fullStartYear = ""
    @State private var orcid = ""
    @State private var scopusID = ""
    @State private var scholarID = ""
    @State private var semanticScholarID = ""
    @State private var associations = ""

    private var isNew: Bool { member == nil }

    private var rank: String? {
        (rankChoice == Self.customRankTag ? customRank : rankChoice)
            .trimmingCharacters(in: .whitespaces).nilIfEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Identity") {
                    TextField("Name (required)", text: $name)
                    TextField("Email", text: $email, prompt: Text("kept local, never sent to APIs"))
                    Picker("Academic rank", selection: $rankChoice) {
                        Text("None").tag("")
                        ForEach(Self.standardRanks, id: \.self) { Text($0).tag($0) }
                        Text(Self.customRankTag).tag(Self.customRankTag)
                    }
                    if rankChoice == Self.customRankTag {
                        TextField("Custom rank", text: $customRank)
                    }
                    TextField("Division / department", text: $division,
                              prompt: Text("e.g. Infectious Diseases"))
                    Picker("Status", selection: $status) {
                        ForEach(MemberStatus.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    if status != .active {
                        Text("\(status.label) members stay in the division views and off the external-collaborators list, but are excluded from promotion benchmarks and candidacy.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Career") {
                    yearField("Initial hire year", $hireYear)
                    yearField("Last promotion year", $lastPromotionYear)
                    DisclosureGroup("Rank start years") {
                        yearField("Assistant Professor", $assistantStartYear)
                        yearField("Associate Professor", $associateStartYear)
                        yearField("Full Professor", $fullStartYear)
                    }
                }
                Section("External IDs") {
                    TextField("ORCID", text: $orcid, prompt: Text("0000-0000-0000-0000 or orcid.org URL"))
                    TextField("Scopus ID", text: $scopusID, prompt: Text("digits only"))
                    TextField("Google Scholar ID", text: $scholarID)
                    TextField("Semantic Scholar ID", text: $semanticScholarID)
                    Text("An ORCID or Scopus ID enables one-click auto-resolution; otherwise use name search on the Resolution tab.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Notes") {
                    TextField("Associations & roles", text: $associations, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isNew ? "Add to Roster" : "Save Changes") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 520, height: 560)
        .onAppear(perform: populate)
    }

    private func yearField(_ label: String, _ binding: Binding<String>) -> some View {
        TextField(label, text: binding, prompt: Text("e.g. 2015"))
    }

    private func populate() {
        guard let member else { return }
        name = member.name
        email = member.email ?? ""
        if let r = member.rank {
            rankChoice = Self.standardRanks.contains(r) ? r : Self.customRankTag
            customRank = Self.standardRanks.contains(r) ? "" : r
        }
        division = member.division ?? ""
        status = member.status ?? .active
        hireYear = member.hireYear.map(String.init) ?? ""
        lastPromotionYear = member.lastPromotionYear.map(String.init) ?? ""
        assistantStartYear = member.assistantStartYear.map(String.init) ?? ""
        associateStartYear = member.associateStartYear.map(String.init) ?? ""
        fullStartYear = member.fullStartYear.map(String.init) ?? ""
        orcid = member.orcid ?? ""
        scopusID = member.scopusID ?? ""
        scholarID = member.scholarID ?? ""
        semanticScholarID = member.semanticScholarID ?? ""
        associations = member.associations ?? ""
    }

    private func save() {
        var result = member ?? FacultyMember(name: "")
        result.name = name.trimmingCharacters(in: .whitespaces)
        result.email = email.trimmingCharacters(in: .whitespaces).nilIfEmpty
        result.rank = rank
        result.division = division.trimmingCharacters(in: .whitespaces).nilIfEmpty
        result.status = status == .active ? nil : status
        result.hireYear = hireYear.extractedYear
        result.lastPromotionYear = lastPromotionYear.extractedYear
        result.assistantStartYear = assistantStartYear.extractedYear
        result.associateStartYear = associateStartYear.extractedYear
        result.fullStartYear = fullStartYear.extractedYear
        result.orcid = RosterImporter.cleanORCID(orcid).nilIfEmpty
        result.scopusID = scopusID.filter(\.isNumber).nilIfEmpty
        result.scholarID = scholarID.trimmingCharacters(in: .whitespaces).nilIfEmpty
        result.semanticScholarID = semanticScholarID.trimmingCharacters(in: .whitespaces).nilIfEmpty
        result.associations = associations.trimmingCharacters(in: .whitespaces).nilIfEmpty

        if isNew {
            store.addMember(result)
        } else {
            store.updateMember(result)
        }
        dismiss()
    }
}
