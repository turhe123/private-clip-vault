import CryptoKit
import Foundation
import Security

/// One captured clipboard item.
struct ClipEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let created: Date
    let expires: Date?
    let sensitive: Bool
    let sourceApp: String?

    func isExpired(at date: Date = Date()) -> Bool {
        guard let expires else { return false }
        return expires <= date
    }
}

/// Errors surfaced to the user when the vault cannot be opened.
enum VaultError: LocalizedError {
    case keyMissing, decryptFailed, keychain(OSStatus), io(String)

    var errorDescription: String? {
        switch self {
        case .keyMissing: return "The vault's encryption key is missing from the keychain."
        case .decryptFailed: return "The vault file could not be decrypted."
        case .keychain(let status): return "Keychain error (\(status))."
        case .io(let message): return "Could not access the vault file: \(message)"
        }
    }
}

/// Stores the 256-bit vault key as a generic password item in the login keychain.
enum KeychainStore {
    private static let service = "com.turhe123.privateclipvault"
    private static let account = "vault-key"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func loadKey() throws -> SymmetricKey? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
            throw VaultError.keychain(status)
        }
        return SymmetricKey(data: data)
    }

    static func createKey() throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        var query = baseQuery
        query[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
        return key
    }

    static func deleteKey() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// Reads and writes the AES-GCM sealed history file in Application Support.
struct VaultStore {
    let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        fileURL = base.appendingPathComponent("PrivateClipVault", isDirectory: true)
            .appendingPathComponent("vault.sealed")
    }

    private var fileExists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    func load() throws -> [ClipEntry] {
        guard fileExists else { return [] }
        guard let key = try KeychainStore.loadKey() else { throw VaultError.keyMissing }
        let data: Data
        do { data = try Data(contentsOf: fileURL) } catch { throw VaultError.io(error.localizedDescription) }
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            let plain = try AES.GCM.open(box, using: key)
            return try JSONDecoder().decode([ClipEntry].self, from: plain)
        } catch {
            throw VaultError.decryptFailed
        }
    }

    /// Writes only unexpired entries, so expired items are physically removed from disk.
    func save(_ entries: [ClipEntry]) throws {
        let key: SymmetricKey
        if let existing = try KeychainStore.loadKey() {
            key = existing
        } else if fileExists {
            throw VaultError.keyMissing
        } else {
            key = try KeychainStore.createKey()
        }
        let now = Date()
        let live = entries.filter { !$0.isExpired(at: now) }
        do {
            let plain = try JSONEncoder().encode(live)
            guard let sealed = try AES.GCM.seal(plain, using: key).combined else { throw VaultError.decryptFailed }
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try sealed.write(to: fileURL, options: [.atomic, .completeFileProtection])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch let error as VaultError {
            throw error
        } catch {
            throw VaultError.io(error.localizedDescription)
        }
    }

    /// Deletes the file and key; a fresh key is created on the next save.
    func reset() {
        try? FileManager.default.removeItem(at: fileURL)
        KeychainStore.deleteKey()
    }
}
