import Foundation
import Security

protocol TokenStorage {
    func read() throws -> String?
    func save(_ token: String) throws
    func delete() throws
}

struct TokenKeychain: TokenStorage {
    let service: String
    let account: String
    /// nil: the app's own Keychain (tests). The default is the group every Empire app shares: one login for all.
    let accessGroup: String?

    init(service: String = "de.ares-empire.session", account: String = "empire-token",
         accessGroup: String? = EmpireShared.keychainAccessGroup) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
            .merging(accessGroup.map { [kSecAttrAccessGroup as String: $0] } ?? [:]) { _, new in new }
    }

    func read() throws -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else { throw KeychainError(status: status) }
        return token
    }

    func save(_ token: String) throws {
        let attributes = [kSecValueData as String: Data(token.utf8),
                          kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as [String: Any]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError(status: status) }
        } else if status != errSecSuccess { throw KeychainError(status: status) }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "Secure token storage failed (\(status)). Please try again." }
}

/// A token left in the Keychain by an earlier install is wiped on the first launch. "First" means: no Empire app has
/// run since all of them were removed. The flag therefore lives in the shared App Group (`EmpireShared.defaults`),
/// which iOS deletes only with the last Empire app; installing a second app keeps the login of the first.
enum FirstLaunchTokenReset {
    static let key = "empire.hasLaunched"
    static func run(storage: any TokenStorage, defaults: UserDefaults) throws {
        guard !defaults.bool(forKey: key) else { return }
        try storage.delete()
        LoginMarker.clear(in: defaults)
        defaults.set(true, forKey: key)
    }
}
