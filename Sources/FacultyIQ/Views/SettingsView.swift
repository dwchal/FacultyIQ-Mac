import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings, split into standard macOS preference tabs: General (OpenAlex +
/// automatic updates), Data Sources (the opt-in enrichment services), Reports
/// (unattended PDF generation), and Storage (cache, history, and the
/// workspace archive).
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            DataSourcesSettingsTab()
                .tabItem { Label("Data Sources", systemImage: "sparkles") }
            ReportsSettingsTab()
                .tabItem { Label("Reports", systemImage: "doc.richtext") }
            PromotionSettingsTab()
                .tabItem { Label("Promotion", systemImage: "arrow.up.right.circle") }
            StorageSettingsTab()
                .tabItem { Label("Storage", systemImage: "internaldrive") }
        }
        .frame(width: 520, height: 500)
    }
}

/// Unattended report generation, riding the same hourly heartbeat as the
/// automatic update check.
private struct ReportsSettingsTab: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("scheduledReportEnabled") private var enabled = false
    @AppStorage("scheduledReportIntervalDays") private var intervalDays = 30
    @AppStorage("scheduledReportFolder") private var folderPath = ""
    @AppStorage("scheduledReportKind") private var kind = ScheduledReport.Kind.divisionSummary.rawValue

    var body: some View {
        Form {
            Section("Scheduled Reports") {
                Toggle("Generate a report automatically", isOn: $enabled)
                Picker("Report", selection: $kind) {
                    ForEach(ScheduledReport.Kind.allCases, id: \.rawValue) { kind in
                        Text(kind.label).tag(kind.rawValue)
                    }
                }
                .disabled(!enabled)
                Picker("Every", selection: $intervalDays) {
                    Text("Week").tag(7)
                    Text("Month").tag(30)
                    Text("Quarter").tag(90)
                }
                .disabled(!enabled)
                LabeledContent("Save to") {
                    HStack(spacing: 8) {
                        Text(folderLabel)
                            .foregroundStyle(folderPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { chooseFolder() }
                    }
                }
                .disabled(!enabled)
                Text("While the app is open, writes a dated PDF of the whole roster to that folder once the interval has passed. Existing files are never overwritten — each run adds a new dated file. Last report: \(lastRunLabel).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if enabled && folderPath.isEmpty {
                    Label("Choose a folder — nothing is written until you do.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(ChartPalette.series3)
                }
                Button("Generate Now") {
                    Task { await ScheduledReport.run(store: store, force: true) }
                }
                .disabled(folderPath.isEmpty || store.filteredPersonData.isEmpty || store.isBusy)
            }
        }
        .formStyle(.grouped)
    }

    private var folderLabel: String {
        folderPath.isEmpty ? "not set" : URL(fileURLWithPath: folderPath).lastPathComponent
    }

    private var lastRunLabel: String {
        ScheduledReport.lastRun.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "never"
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.path
        }
    }
}

private struct GeneralSettingsTab: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("openalexEmail") private var email = ""
    @AppStorage("autoCheckEnabled") private var autoCheckEnabled = false
    @AppStorage("autoCheckIntervalDays") private var autoCheckIntervalDays = 7

    var body: some View {
        Form {
            Section("OpenAlex") {
                TextField("Contact email", text: $email, prompt: Text("you@institution.edu"))
                Text("Optional, but recommended: requests that include an email join OpenAlex's polite pool and get faster, more reliable rate limits. Only sent to api.openalex.org — roster emails are never sent anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Automatic Updates") {
                Toggle("Check for new activity automatically", isOn: $autoCheckEnabled)
                Picker("Check every", selection: $autoCheckIntervalDays) {
                    Text("Day").tag(1)
                    Text("Week").tag(7)
                    Text("Month").tag(30)
                }
                .disabled(!autoCheckEnabled)
                Text("While the app is open, re-fetches everyone's data once the interval has passed and posts a notification when What's New has changes. Last check: \(lastCheckLabel).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var lastCheckLabel: String {
        store.lastUpdateCheck.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "never"
    }
}

/// Tunable criteria for the Promotion tab's rank benchmarks and candidacy
/// filter — different institutions set the bar differently, so these aren't
/// baked-in constants.
private struct PromotionSettingsTab: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("promotionTargetPercentile") private var targetPercentile: Double = 25
    @AppStorage("promotionRequiredCount") private var requiredCount = 2
    @State private var showInstitutionSearch = false

    var body: some View {
        Form {
            Section("Promotion Targets") {
                Picker("Target percentile", selection: $targetPercentile) {
                    Text("10th").tag(10.0)
                    Text("25th (default)").tag(25.0)
                    Text("40th").tag(40.0)
                    Text("50th (median)").tag(50.0)
                }
                Text("A promotion target is this percentile of current rank-holders' works, citations, and h-index. Lower sets a lower bar (the low end of the rank); higher raises it toward the rank's median.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Metrics required", selection: $requiredCount) {
                    Text("1 of 3").tag(1)
                    Text("2 of 3 (default)").tag(2)
                    Text("3 of 3").tag(3)
                }
                Text("How many of works / citations / h-index a member must meet or exceed to appear as a Promotion Candidate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Peer Institutions") {
                if store.peerInstitutions.isEmpty {
                    Text("No peer institutions added — the “vs Peers” benchmark on each profile stays hidden until at least one is added.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.peerInstitutions) { institution in
                        HStack {
                            Text(institution.displayName)
                            Spacer()
                            Button {
                                store.removePeerInstitution(institution.id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                    Text("Profiles get a second Field Benchmark card restricted to authors at these institutions, alongside the existing random field-wide sample.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Add Institution…") { showInstitutionSearch = true }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showInstitutionSearch) {
            InstitutionSearchSheet()
        }
    }
}

private struct DataSourcesSettingsTab: View {
    @AppStorage("enableICite") private var enableICite = false
    @AppStorage("enableReporter") private var enableReporter = false
    @AppStorage("enableSemanticScholar") private var enableSemanticScholar = false
    @AppStorage("enableTrials") private var enableTrials = false
    @AppStorage("enableNSF") private var enableNSF = false
    @AppStorage("enableJournalMetrics") private var enableJournalMetrics = true
    @AppStorage("collapsePreprints") private var collapsePreprints = true
    @AppStorage("enableScopus") private var enableScopus = false
    @AppStorage("scopusAPIKey") private var scopusAPIKey = ""
    @AppStorage("scopusInsttoken") private var scopusInsttoken = ""
    @State private var scopusQuota: [String: Int] = [:]

    var body: some View {
        Form {
            Section {
                Toggle("OpenAlex journal metrics", isOn: $enableJournalMetrics)
                Text("Journal impact and quartiles for every venue the cohort publishes in. Keyless, and the fallback for Scopus CiteScore — quartiles are relative to the cohort's own venues rather than a subject area.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Collapse preprint / published pairs", isOn: $collapsePreprints)
                Text("Drops a preprint from the metrics when its journal version is also indexed, so one paper isn't counted twice. Both stay visible on the Publications tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Publication Quality")
            }
            Section {
                Toggle("NIH iCite citation metrics", isOn: $enableICite)
                Text("Relative Citation Ratio and NIH percentile per paper. PubMed-indexed works only; no key required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("NIH RePORTER grants", isOn: $enableReporter)
                Text("Grant funding by principal investigator. Name matches are fuzzy — ambiguous names need a one-time confirmation on the member's profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("NSF awards", isOn: $enableNSF)
                Text("Awards where the member is PI or co-PI, for work NIH never sees. Keyless, matched by name only — no investigator IDs exist — so check the award list on the profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Semantic Scholar influence", isOn: $enableSemanticScholar)
                Text("Influential-citation counts per paper. The keyless API shares a global rate pool, so this source can be slow or temporarily throttled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("ClinicalTrials.gov trials", isOn: $enableTrials)
                Text("Registered clinical trials where the member is an overall official (PI/chair), matched by name. No key required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Enrichment Sources")
            } footer: {
                Text("Sources are fetched by the Enrich Data toolbar button after metrics are loaded; only author IDs, PMIDs, DOIs, and names are sent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Scopus (Elsevier)") {
                Toggle("Scopus author + journal metrics", isOn: $enableScopus)
                SecureField("API key", text: $scopusAPIKey, prompt: Text("from dev.elsevier.com"))
                SecureField("Insttoken (optional)", text: $scopusInsttoken, prompt: Text("only if issued by Elsevier"))
                Text("Official Scopus h-index and citation counts per member, plus CiteScore/SNIP/SJR journal quality per publication. Keys are free from dev.elsevier.com but are authorized by the institution's IP range — calls only work on the institutional network or VPN unless Elsevier has issued an insttoken.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !scopusQuota.isEmpty {
                    LabeledContent("Weekly quota remaining", value: scopusQuotaLabel)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            scopusQuota = await ScopusClient.shared.remainingQuota()
        }
    }

    private var scopusQuotaLabel: String {
        scopusQuota.sorted { $0.key < $1.key }
            .map { "\($0.key) \($0.value)" }
            .joined(separator: " · ")
    }
}

private struct StorageSettingsTab: View {
    @EnvironmentObject private var store: AppStore
    @State private var cacheInfo = CacheStore.shared.sizeDescription
    @State private var confirmation: String?
    @State private var pendingImport: URL?

    var body: some View {
        Form {
            Section("Workspace Archive") {
                LabeledContent("Contents", value: archiveInfo)
                Text("One file holding the roster, resolutions, fetched works, enrichment, and metric history — for backups, moving to another Mac, or handing the dataset to a colleague. The API response cache is left out; it re-fetches on its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Export Archive…") { exportArchive() }
                        .disabled(store.roster.isEmpty)
                    Button("Import Archive…") { chooseImport() }
                        .disabled(store.isBusy)
                }
                if let confirmation {
                    Label(confirmation, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(ChartPalette.positive)
                }
            }
            Section("Cache") {
                LabeledContent("API response cache", value: cacheInfo)
                Text("Responses are cached for 7 days in Application Support to minimize API traffic.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Clear Cache") {
                    CacheStore.shared.clear()
                    cacheInfo = CacheStore.shared.sizeDescription
                }
            }
            Section("Metric History") {
                LabeledContent("Tracked readings", value: historyInfo)
                Text("Each data fetch records works, citations, and h-index per author when they change, powering the Tracked History charts. History is keyed by author, so it survives roster re-imports.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Clear History") {
                    store.clearSnapshots()
                }
                .disabled(store.snapshots.isEmpty)
            }
        }
        .formStyle(.grouped)
        .alert("Replace this workspace?", isPresented: .constant(pendingImport != nil)) {
            Button("Cancel", role: .cancel) { pendingImport = nil }
            Button("Replace", role: .destructive) {
                if let url = pendingImport { performImport(url) }
                pendingImport = nil
            }
        } message: {
            Text("Importing replaces the current roster, fetched data, enrichment, and metric history with the archive's. Export the current workspace first if you want to keep it.")
        }
    }

    private var historyInfo: String {
        guard let earliest = store.snapshots.map(\.date).min() else { return "none yet" }
        let authors = Set(store.snapshots.map(\.openalexID)).count
        return "\(store.snapshots.count) readings · \(authors) authors · since \(earliest.formatted(date: .abbreviated, time: .omitted))"
    }

    private var archiveInfo: String {
        guard !store.roster.isEmpty else { return "nothing to export yet" }
        let fetched = store.personData.count
        return "\(store.roster.count) members · \(fetched) fetched · \(store.snapshots.count) history readings"
    }

    private func exportArchive() {
        let stamp = Date().formatted(.iso8601.year().month().day())
        switch SavePanel.run(defaultName: "facultyiq_workspace_\(stamp).json", type: .json,
                             write: { try store.archiveData().write(to: $0, options: .atomic) }) {
        case .success(let name): confirmation = "Exported \(name)"
        case .failure(let error): store.lastError = error.localizedDescription
        case nil: break
        }
    }

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.prompt = "Import"
        if panel.runModal() == .OK, let url = panel.url {
            pendingImport = url
        }
    }

    private func performImport(_ url: URL) {
        do {
            try store.importArchive(from: url)
            confirmation = "Imported \(store.roster.count) members from \(url.lastPathComponent)"
        } catch {
            store.lastError = error.localizedDescription
        }
    }
}
