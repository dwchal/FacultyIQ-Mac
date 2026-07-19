import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct FacultyIQApp: App {
    @StateObject private var store = AppStore()

    init() {
        // When launched from `swift run` (no app bundle) the process starts as
        // a background executable; promote it to a regular app so the window
        // shows and gets focus. Harmless when running from FacultyIQ.app.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
    }

    /// Hourly heartbeat for the Settings-controlled automatic update check;
    /// autoCheckIfDue() itself decides whether a check is actually due.
    private let autoCheckTimer = Timer.publish(every: 3600, on: .main, in: .common).autoconnect()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 640)
                .task { await store.autoCheckIfDue() }
                .onReceive(autoCheckTimer) { _ in
                    Task { await store.autoCheckIfDue() }
                }
        }
        .defaultSize(width: 1200, height: 780)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About FacultyIQ") { showAboutPanel() }
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Save Metrics CSV…") { saveMetricsCSV() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Save Division Summary PDF…") { saveSummaryPDF() }
            }
            CommandMenu("Go") {
                Button("Find Faculty…") { store.showFacultySearch = true }
                    .keyboardShortcut("f")
            }
            CommandMenu("Data") {
                Button("Refresh Data") {
                    Task { await store.refreshData() }
                }
                .keyboardShortcut("r")
                Button("Check for Updates Now") {
                    Task { await store.checkForUpdates() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Enrich Data") {
                    Task { await store.enrichAll() }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }

    /// File-menu twin of the Export tab's Faculty Metrics row — exports the
    /// division in view without leaving the current tab.
    private func saveMetricsCSV() {
        guard !store.metrics.isEmpty else {
            store.lastError = "No metrics to export yet — fetch data first."
            return
        }
        let csv = MetricsEngine.metricsCSV(
            metrics: store.metrics, roster: store.filteredRoster,
            personData: store.effectivePersonData, enrichment: store.enrichment)
        if case .failure(let error) = SavePanel.run(
            defaultName: "faculty_metrics.csv", type: .commaSeparatedText,
            write: { try csv.write(to: $0, atomically: true, encoding: .utf8) }) {
            store.lastError = error.localizedDescription
        }
    }

    private func saveSummaryPDF() {
        guard !store.filteredPersonData.isEmpty else {
            store.lastError = "No data to report yet — fetch data first."
            return
        }
        let scope = store.divisionFilter
        let pages = SummaryPages.pages(
            summary: store.summary,
            metrics: store.metrics,
            personData: store.filteredPersonData,
            benchmarks: store.benchmarks,
            divisionName: scope,
            scopusLine: MetricsEngine.divisionScopusLine(
                roster: store.filteredRoster, personData: store.personData,
                enrichment: store.enrichment))
        if case .failure(let error) = SavePanel.run(
            defaultName: "\(scope?.lowercased().replacingOccurrences(of: " ", with: "_") ?? "faculty")_report.pdf",
            type: .pdf,
            write: { try PDFComposer.write(pages: pages, to: $0) }) {
            store.lastError = error.localizedDescription
        }
    }

    /// Standard About panel with explicit values, so it reads correctly both
    /// from the app bundle and under `swift run` (where there's no Info.plist).
    private func showAboutPanel() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let credits = NSAttributedString(
            string: "Faculty analytics from OpenAlex, with optional enrichment "
                + "from NIH iCite, NIH RePORTER, and Semantic Scholar.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "FacultyIQ",
            .applicationVersion: version,
            .version: "",
            .credits: credits,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"):
                "© 2026 dcProductions · MIT License",
        ])
    }
}
