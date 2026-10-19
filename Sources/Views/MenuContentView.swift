import SwiftUI

/// The menu bar popover: last ten entries followed by the main commands.
struct MenuContentView: View {
    @EnvironmentObject var model: VaultModel
    @AppStorage(PrefKey.requireAuth) private var requireAuth = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content.frame(minHeight: 120)
            Divider()
            commands.padding(6)
        }
        .frame(width: 340)
        .onAppear { model.prepareForDisplay() }
    }

    @ViewBuilder private var content: some View {
        if let error = model.vaultError {
            VaultErrorView(error: error)
        } else if requireAuth && !model.isUnlocked {
            LockedView()
        } else if model.entries.isEmpty {
            EmptyHistoryView()
        } else {
            VStack(spacing: 0) {
                ForEach(model.entries.prefix(10)) { entry in
                    MenuRowButton(action: { model.copy(entry); dismiss() }) {
                        EntryRow(entry: entry)
                    }
                }
            }
            .padding(6)
        }
    }

    private var commands: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuRowButton(action: { bringToFront(openWindow, id: WindowID.history); dismiss() }) {
                Label("Show All…", systemImage: "list.bullet")
            }
            Toggle(isOn: $model.paused) { Label("Pause Capture", systemImage: "pause.circle") }
                .toggleStyle(.switch).controlSize(.small)
                .padding(.horizontal, 8).padding(.vertical, 4)
            MenuRowButton(action: { confirmClear = true }) {
                Label("Clear Everything", systemImage: "trash")
            }
            .confirmationDialog("Clear all clipboard history?", isPresented: $confirmClear) {
                Button("Clear Everything", role: .destructive) { model.clearAll() }
            }
            MenuRowButton(action: { bringToFront(openWindow, id: WindowID.settings); dismiss() }) {
                Label("Settings…", systemImage: "gearshape")
            }
            MenuRowButton(action: Links.openDonation) {
                Label("Support / Donate ❤️", systemImage: "heart")
            }
            Divider().padding(.vertical, 4)
            MenuRowButton(action: { NSApp.terminate(nil) }) {
                Label("Quit PrivateClipVault", systemImage: "power")
            }
        }
    }
}

/// A full-width, menu-like button with hover highlight.
struct MenuRowButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(hovering ? Color.accentColor.opacity(0.18) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
