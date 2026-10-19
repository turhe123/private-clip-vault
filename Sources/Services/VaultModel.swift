import AppKit
import LocalAuthentication

/// Global lifetime choices for captured entries.
enum Lifetime: Int, CaseIterable, Identifiable {
    case oneMinute = 60, fiveMinutes = 300, oneHour = 3600, oneDay = 86400, never = 0

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .oneMinute: return "1 minute"
        case .fiveMinutes: return "5 minutes"
        case .oneHour: return "1 hour"
        case .oneDay: return "1 day"
        case .never: return "Never"
        }
    }
}

/// UserDefaults keys shared by the model and the settings UI.
enum PrefKey {
    static let historySize = "historySize"
    static let lifetime = "lifetimeSeconds"
    static let skipSecrets = "skipSecrets"
    static let requireAuth = "requireAuth"
    static let ignoredApps = "ignoredApps"
    static let paused = "pauseCapture"
}

/// Owns the clipboard history: polls the pasteboard, filters secrets, expires items,
/// persists through `VaultStore`, and manages the optional authentication lock.
@MainActor
final class VaultModel: ObservableObject {
    static let sensitiveLifetime: TimeInterval = 30
    static let maxEntryBytes = 100 * 1024
    static let unlockTimeout: TimeInterval = 60

    @Published private(set) var entries: [ClipEntry] = []
    @Published private(set) var isUnlocked = false
    @Published private(set) var vaultError: VaultError?
    @Published var authMessage: String?
    @Published var paused: Bool {
        didSet { defaults.set(paused, forKey: PrefKey.paused) }
    }

    private let store = VaultStore()
    private let defaults = UserDefaults.standard
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var loaded = false
    private var lastActivity = Date()
    private var timers: [Timer] = []

    var requireAuth: Bool { defaults.bool(forKey: PrefKey.requireAuth) }
    /// True when history may be shown: no lock configured, or the user has authenticated.
    var canView: Bool { !requireAuth || isUnlocked }

    private var historySize: Int {
        let value = defaults.integer(forKey: PrefKey.historySize)
        return value > 0 ? value : 50
    }

    private var ignoredApps: Set<String> {
        Set((defaults.string(forKey: PrefKey.ignoredApps) ?? "").split(separator: "\n").map(String.init))
    }

    init() {
        defaults.register(defaults: [PrefKey.historySize: 50, PrefKey.lifetime: Lifetime.oneDay.rawValue,
                                     PrefKey.skipSecrets: true, PrefKey.requireAuth: false])
        paused = defaults.bool(forKey: PrefKey.paused)
        lastChangeCount = NSPasteboard.general.changeCount
        reload()
        startTimers()
        observeScreenLock()
    }

    // MARK: Timers & notifications

    private func startTimers() {
        let poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollPasteboard() }
        }
        let purge = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.purgeExpired() }
        }
        let idle = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkInactivity() }
        }
        timers = [poll, purge, idle]
    }

    private func observeScreenLock() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lock() }
        }
        center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.requireAuth else { return }
                self.reload()
            }
        }
    }

    // MARK: Capture

    private func pollPasteboard() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard !paused, vaultError == nil else { return }

        let types = Set(pasteboard.types?.map(\.rawValue) ?? [])
        if !types.isDisjoint(with: SecretDetector.transientTypes) { return }
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= Self.maxEntryBytes else { return }

        let app = NSWorkspace.shared.frontmostApplication
        if let bundleID = app?.bundleIdentifier, ignoredApps.contains(bundleID) { return }

        let sensitive = !types.isDisjoint(with: SecretDetector.concealedTypes) || SecretDetector.isSensitive(text)
        if sensitive && defaults.bool(forKey: PrefKey.skipSecrets) { return }

        let now = Date()
        let lifetime = Lifetime(rawValue: defaults.integer(forKey: PrefKey.lifetime)) ?? .oneDay
        let expires: Date? = sensitive ? now.addingTimeInterval(Self.sensitiveLifetime)
            : (lifetime == .never ? nil : now.addingTimeInterval(TimeInterval(lifetime.rawValue)))
        let entry = ClipEntry(id: UUID(), text: text, created: now, expires: expires,
                              sensitive: sensitive, sourceApp: app?.localizedName)
        let limit = historySize
        mutate { list in
            list.removeAll { $0.text == text }
            list.insert(entry, at: 0)
            if list.count > limit { list.removeLast(list.count - limit) }
            return true
        }
    }

    private func purgeExpired() {
        let now = Date()
        mutate { list in
            let before = list.count
            list.removeAll { $0.isExpired(at: now) }
            return list.count != before
        }
    }

    /// Applies a change to the history (in memory if loaded, otherwise straight from disk) and saves it.
    private func mutate(_ change: (inout [ClipEntry]) -> Bool) {
        guard vaultError == nil else { return }
        do {
            var list = loaded ? entries : try store.load()
            guard change(&list) else { return }
            try store.save(list)
            if loaded { entries = list }
        } catch let error as VaultError {
            vaultError = error
        } catch {
            vaultError = .io(error.localizedDescription)
        }
    }

    // MARK: Actions

    func copy(_ entry: ClipEntry) {
        touch()
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        if entry.sensitive {
            pasteboard.setData(Data(), forType: .init(SecretDetector.concealedTypes[0]))
        }
        lastChangeCount = pasteboard.changeCount
    }

    func delete(_ entry: ClipEntry) {
        touch()
        mutate { list in
            list.removeAll { $0.id == entry.id }
            return true
        }
    }

    func clearAll() {
        guard vaultError == nil else { return }
        entries = []
        do { try store.save([]) } catch { store.reset() }
    }

    func resetVault() {
        store.reset()
        entries = []
        vaultError = nil
        loaded = true
    }

    /// Trims the in-memory list after the history size setting changes.
    func applyHistorySize() {
        let limit = historySize
        mutate { list in
            guard list.count > limit else { return false }
            list.removeLast(list.count - limit)
            return true
        }
    }

    // MARK: Lock

    func touch() { lastActivity = Date() }

    func reload() {
        do {
            entries = try store.load().filter { !$0.isExpired() }
            loaded = true
            vaultError = nil
        } catch let error as VaultError {
            entries = []
            loaded = false
            vaultError = error
        } catch {
            vaultError = .io(error.localizedDescription)
        }
    }

    /// Drops decrypted history from memory and relocks the vault.
    func lock() {
        entries = []
        loaded = false
        isUnlocked = false
    }

    private func checkInactivity() {
        guard requireAuth, isUnlocked, Date().timeIntervalSince(lastActivity) > Self.unlockTimeout else { return }
        lock()
    }

    /// Touch ID with automatic fallback to the account password (`.deviceOwnerAuthentication`).
    func authenticate(reason: String = "unlock your clipboard history", completion: ((Bool) -> Void)? = nil) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authMessage = "This Mac has no password or Touch ID available for authentication."
            completion?(false)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, _ in
            Task { @MainActor in
                guard let self else { return }
                if success {
                    self.authMessage = nil
                    self.unlock()
                } else {
                    self.authMessage = "Authentication was cancelled or failed."
                }
                completion?(success)
            }
        }
    }

    private func unlock() {
        touch()
        isUnlocked = true
        reload()
    }

    /// Called when the menu or window appears so a non-locked vault reloads after a screen lock.
    func prepareForDisplay() {
        touch()
        if canView && !loaded && vaultError == nil { reload() }
    }
}
