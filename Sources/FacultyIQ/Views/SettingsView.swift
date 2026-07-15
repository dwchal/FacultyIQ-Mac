import SwiftUI

struct SettingsView: View {
    @AppStorage("openalexEmail") private var email = ""
    @AppStorage("enableICite") private var enableICite = false
    @AppStorage("enableReporter") private var enableReporter = false
    @AppStorage("enableSemanticScholar") private var enableSemanticScholar = false
    @State private var cacheInfo = CacheStore.shared.sizeDescription

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
                Text("Sources are fetched by the Enrich Data toolbar button after metrics are loaded; only author IDs, PMIDs, DOIs, and names are sent.")
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
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
