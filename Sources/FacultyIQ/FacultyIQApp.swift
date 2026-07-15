import SwiftUI

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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1200, height: 780)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
