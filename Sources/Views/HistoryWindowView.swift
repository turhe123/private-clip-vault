import SwiftUI

/// "Show All" window: a searchable list of the full history.
struct HistoryWindowView: View {
    @EnvironmentObject var model: VaultModel
    @AppStorage(PrefKey.requireAuth) private var requireAuth = false
    @State private var query = ""
    @State private var copiedID: UUID?

    private var filtered: [ClipEntry] {
        guard !query.isEmpty else { return model.entries }
        return model.entries.filter { !$0.sensitive && $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Group {
            if let error = model.vaultError {
                VaultErrorView(error: error)
            } else if requireAuth && !model.isUnlocked {
                LockedView()
            } else if model.entries.isEmpty {
                EmptyHistoryView()
            } else {
                List(filtered) { entry in
                    HStack {
                        EntryRow(entry: entry, lineLimit: 3)
                        if copiedID == entry.id {
                            Text("Copied").font(.caption).foregroundStyle(.green)
                        }
                    }
                    .onTapGesture { copy(entry) }
                    .contextMenu {
                        Button("Copy") { copy(entry) }
                        Button("Delete", role: .destructive) { model.delete(entry) }
                    }
                }
                .searchable(text: $query, prompt: "Search history")
                .overlay {
                    if filtered.isEmpty { Text("No matches").foregroundStyle(.secondary) }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
        .onAppear { model.prepareForDisplay() }
        .onChange(of: query) { model.touch() }
    }

    private func copy(_ entry: ClipEntry) {
        model.copy(entry)
        copiedID = entry.id
    }
}
