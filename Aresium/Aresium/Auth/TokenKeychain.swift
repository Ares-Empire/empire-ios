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

    init(service: String = "de.ares-empire.aresium.auth", account: String = "empire-token") {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
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

/// The install flag is deliberately separate from the Keychain, which survives uninstall.
enum FirstLaunchTokenReset {
    static let key = "aresium.hasLaunched"
    static func run(storage: any TokenStorage, defaults: UserDefaults) throws {
        guard !defaults.bool(forKey: key) else { return }
        try storage.delete()
        defaults.set(true, forKey: key)
    }
}
