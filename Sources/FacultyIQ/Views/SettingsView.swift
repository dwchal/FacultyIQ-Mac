import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("openalexEmail") private var email = ""
    @AppStorage("enableICite") private var enableICite = false
    @AppStorage("enableReporter") private var enableReporter = false
    @AppStorage("enableSemanticScholar") private var enableSemanticScholar = false
    @AppStorage("enableScopus") private var enableScopus = false
    @AppStorage("scopusAPIKey") private var scopusAPIKey = ""
    @AppStorage("scopusInsttoken") private var scopusInsttoken = ""
    @AppStorage("enableTrials") private var enableTrials = false
    @AppStorage("autoCheckEnabled") private var autoCheckEnabled = false
    @AppStorage("autoCheckIntervalDays") private var autoCheckIntervalDays = 7
    @State private var cacheInfo = CacheStore.shared.sizeDescription
    @State private var scopusQuota: [String: Int] = [:]

    var body: some View {
        Form {
            Section("OpenAlex") {
                TextField("Contact email", text: $email, prompt: Text("you@institution.edu"))
                Text("Optional, but recommended: requests that include an email join OpenAlex's polite pool and get faster, more reliable rate limits. Only sent to api.openalex.org — roster emails are never sent anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Data Enrichment") {
                Toggle("NIH iCite citation metrics", isOn: $enableICite)
                Text("Relative Citation Ratio and NIH percentile per paper. PubMed-indexed works only; no key required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("NIH RePORTER grants", isOn: $enableReporter)
                Text("Grant funding by principal investigator. Name matches are fuzzy — ambiguous names need a one-time confirmation on the member's profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Semantic Scholar influence", isOn: $enableSemanticScholar)
                Text("Influential-citation counts per paper. The keyless API shares a global rate pool, so this source can be slow or temporarily throttled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("ClinicalTrials.gov trials", isOn: $enableTrials)
                Text("Registered clinical trials where the member is an overall official (PI/chair). Name matches are fuzzy — ambiguous names need a one-time confirmation on the member's profile. No key required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            scopusQuota = await ScopusClient.shared.remainingQuota()
        }
    }

    private var scopusQuotaLabel: String {
        scopusQuota.sorted { $0.key < $1.key }
            .map { "\($0.key) \($0.value)" }
            .joined(separator: " · ")
    }

    private var lastCheckLabel: String {
        store.lastUpdateCheck.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "never"
    }

    private var historyInfo: String {
        guard let earliest = store.snapshots.map(\.date).min() else { return "none yet" }
        let authors = Set(store.snapshots.map(\.openalexID)).count
        return "\(store.snapshots.count) readings · \(authors) authors · since \(earliest.formatted(date: .abbreviated, time: .omitted))"
    }
}
