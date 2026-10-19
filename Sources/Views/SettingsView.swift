import ServiceManagement
import SwiftUI

/// Preferences: history size, lifetime, secret filtering, lock, ignored apps and launch at login.
struct SettingsView: View {
    @EnvironmentObject var model: VaultModel
    @AppStorage(PrefKey.historySize) private var historySize = 50
    @AppStorage(PrefKey.lifetime) private var lifetime = Lifetime.oneDay.rawValue
    @AppStorage(PrefKey.skipSecrets) private var skipSecrets = true
    @AppStorage(PrefKey.requireAuth) private var requireAuth = false
    @AppStorage(PrefKey.ignoredApps) private var ignoredAppsRaw = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private var ignoredApps: [String] {
        ignoredAppsRaw.split(separator: "\n").map(String.init)
    }

    var body: some View {
        Form {
            Section("History") {
                Stepper("History size: \(historySize) entries", value: $historySize, in: 10...500, step: 10)
                    .onChange(of: historySize) { model.applyHistorySize() }
                Picker("Item lifetime", selection: $lifetime) {
                    ForEach(Lifetime.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }
            Section("Privacy") {
                Toggle("Skip detected secrets", isOn: $skipSecrets)
                Text(skipSecrets
                     ? "Passwords, card numbers, API keys and long tokens are never recorded."
                     : "Detected secrets are kept for only 30 seconds and shown as dots.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Require Touch ID or password to view history", isOn: authBinding)
                if let message = model.authMessage {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Ignored apps") {
                if ignoredApps.isEmpty {
                    Text("Nothing copied from these apps is ever captured.").foregroundStyle(.secondary)
                }
                ForEach(ignoredApps, id: \.self) { bundleID in
                    HStack {
                        Text(Self.appName(for: bundleID))
                        Text(bundleID).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) { remove(bundleID) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                Menu("Add Running App…") {
                    ForEach(runningApps, id: \.bundleID) { app in
                        Button(app.name) { add(app.bundleID) }
                    }
                }
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.orange)
                }
            }
            Section {
                Label("Nothing leaves your Mac. History is encrypted with AES-GCM using a key kept in your "
                      + "keychain, is never synced or sent anywhere, and clipboard contents are never logged.",
                      systemImage: "hand.raised.fill")
                    .font(.callout)
                HStack {
                    Spacer()
                    Button("Support / Donate ❤️", action: Links.openDonation)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
    }

    /// Turning the lock off requires authenticating first.
    private var authBinding: Binding<Bool> {
        Binding(get: { requireAuth }, set: { newValue in
            if newValue {
                requireAuth = true
                model.lock()
            } else {
                model.authenticate(reason: "turn off the history lock") { success in
                    if success { requireAuth = false }
                }
            }
        })
    }

    private var runningApps: [(name: String, bundleID: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                      !ignoredApps.contains(id) else { return nil }
                return (app.localizedName ?? id, id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func add(_ bundleID: String) {
        ignoredAppsRaw = (ignoredApps + [bundleID]).joined(separator: "\n")
    }

    private func remove(_ bundleID: String) {
        ignoredAppsRaw = ignoredApps.filter { $0 != bundleID }.joined(separator: "\n")
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Could not update login item: \(error.localizedDescription)"
        }
        if SMAppService.mainApp.status == .requiresApproval {
            loginError = "Approve PrivateClipVault in System Settings › General › Login Items."
        }
    }
}
