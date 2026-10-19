import SwiftUI

/// App entry point: a menu bar vault plus the history and settings windows.
@main
struct PrivateClipVaultApp: App {
    @StateObject private var model = VaultModel()
    @AppStorage(PrefKey.requireAuth) private var requireAuth = false

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(model)
        } label: {
            Image(systemName: requireAuth && model.isUnlocked ? "lock.open.fill" : "lock.fill")
        }
        .menuBarExtraStyle(.window)

        Window("Clipboard History", id: WindowID.history) {
            HistoryWindowView()
                .environmentObject(model)
        }
        .defaultSize(width: 520, height: 560)

        Window("PrivateClipVault Settings", id: WindowID.settings) {
            SettingsView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
    }
}

/// Identifiers for the app's auxiliary windows.
enum WindowID {
    static let history = "history"
    static let settings = "settings"
}

/// Shared link helpers.
enum Links {
    static func openDonation() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
    }
}
