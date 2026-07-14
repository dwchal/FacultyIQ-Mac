import SwiftUI

struct SettingsView: View {
    @AppStorage("openalexEmail") private var email = ""
    @State private var cacheInfo = CacheStore.shared.sizeDescription

    var body: some View {
        Form {
            Section("OpenAlex") {
                TextField("Contact email", text: $email, prompt: Text("you@institution.edu"))
                Text("Optional, but recommended: requests that include an email join OpenAlex's polite pool and get faster, more reliable rate limits. Only sent to api.openalex.org — roster emails are never sent anywhere.")
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
