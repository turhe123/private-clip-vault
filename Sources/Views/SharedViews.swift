import SwiftUI

/// A single history row: truncated preview, dotted mask for secrets, and a lifetime countdown.
struct EntryRow: View {
    let entry: ClipEntry
    var lineLimit = 1
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            if entry.sensitive {
                Image(systemName: "key.fill").foregroundStyle(.orange).font(.caption)
            }
            Text(preview)
                .lineLimit(lineLimit)
                .truncationMode(.tail)
                .font(entry.sensitive && !hovering ? .body.monospaced() : .body)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let expires = entry.expires {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Label(Self.remaining(until: expires, now: context.date), systemImage: "clock")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(entry.sourceApp.map { "Copied from \($0)" } ?? "")
    }

    private var preview: String {
        if entry.sensitive && !hovering { return String(repeating: "•", count: 12) }
        return entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ⏎ ")
    }

    static func remaining(until date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        if seconds >= 86400 { return "\(seconds / 86400)d" }
        if seconds >= 3600 { return "\(seconds / 3600)h" }
        if seconds >= 60 { return "\(seconds / 60)m" }
        return "\(seconds)s"
    }
}

/// Shown while the vault requires authentication.
struct LockedView: View {
    @EnvironmentObject var model: VaultModel

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.secondary)
            Button("Unlock") { model.authenticate() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            if let message = model.authMessage {
                Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// Shown when the key is missing or the vault file cannot be decrypted.
struct VaultErrorView: View {
    @EnvironmentObject var model: VaultModel
    let error: VaultError
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.lock.fill").font(.largeTitle).foregroundStyle(.orange)
            Text(error.localizedDescription).multilineTextAlignment(.center)
            Text("You can reset the vault to start a new, empty encrypted history.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack {
                Button("Try Again") { model.reload() }
                Button("Reset Vault…", role: .destructive) { confirmReset = true }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog("Reset the vault? Existing history will be permanently deleted.",
                            isPresented: $confirmReset) {
            Button("Reset Vault", role: .destructive) { model.resetVault() }
        }
    }
}

/// Empty-state placeholder.
struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard").font(.title).foregroundStyle(.secondary)
            Text("History is empty, copy something to get started.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// Opens a window and brings this accessory app to the front.
@MainActor
func bringToFront(_ openWindow: OpenWindowAction, id: String) {
    openWindow(id: id)
    NSApp.activate(ignoringOtherApps: true)
}
