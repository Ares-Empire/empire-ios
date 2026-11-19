import Foundation
import Security

/// Where flatd is: its address, and the Bonjour name it was found under (so the app and its controls can find it again
/// when the Mac's address changes). Kept in Arestia's App Group, shared with the Control Center controls; the key is in
/// the Keychain, never here.
nonisolated struct FlatdLink: Codable, Equatable, Sendable {
    var baseURL: URL
    /// The Bonjour service's name (`_flatd._tcp`), nil for an address typed or scanned by hand.
    var serviceName: String?
}

/// What Arestia shares between the app and its Control Center extension: the App Group's defaults and the Keychain
/// group (both in the entitlements; never the Empire's shared ones: Arestia has no Ares account).
nonisolated enum ArestiaGroup {
    static let appGroup = "group.de.ares-empire.arestia"
    /// Without the team prefix (entitlement: `$(AppIdentifierPrefix)` + this).
    static let keychainGroup = "de.ares-empire.arestia"
    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }
    /// "$(AppIdentifierPrefix)" from the bundle's Info.plist, plus the group (the prefix may be empty on the simulator).
    static var keychainAccessGroup: String {
        let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String ?? ""
        return prefix + keychainGroup
    }
}

/// Where flatd's key is kept: the Keychain in the app, memory in the tests.
nonisolated protocol FlatdKeyStore: Sendable {
    func read() throws -> String?
    func save(_ key: String) throws
    func delete() throws
}

/// flatd's key in Arestia's Keychain group, shared with the Control Center controls. Readable after the first unlock
/// (`AfterFirstUnlockThisDeviceOnly`), so a control works from the lock screen; never synced, never restored to another
/// device. (The Empire login's `TokenKeychain` is for the shared Ares account, which Arestia does not have.)
nonisolated struct FlatdKeychain: FlatdKeyStore {
    let service: String
    let account: String
    let accessGroup: String?

    private var query: [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: account]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    func read() throws -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw FlatdKeychainError(status: status) }
        return String(data: data, encoding: .utf8)
    }

    func save(_ key: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8),
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard added == errSecSuccess else { throw FlatdKeychainError(status: added) }
        } else if status != errSecSuccess {
            throw FlatdKeychainError(status: status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw FlatdKeychainError(status: status) }
    }
}

nonisolated struct FlatdKeychainError: Error {
    let status: OSStatus
}

/// The saved connection: the link in the App Group, the key in the Keychain.
nonisolated struct FlatdConnection: @unchecked Sendable {
    /// Thread-safe (`UserDefaults` is), hence the unchecked Sendable.
    let defaults: UserDefaults?
    let keychain: any FlatdKeyStore

    static let linkKey = "flatd.link"
    /// The devices' ids, kinds and names as last seen, for Shortcuts' pickers while flatd is out of reach.
    static let devicesKey = "flatd.devices"

    static var live: FlatdConnection {
        FlatdConnection(defaults: ArestiaGroup.defaults,
                        keychain: FlatdKeychain(service: "de.ares-empire.arestia.flatd", account: "flatd-key",
                                                accessGroup: ArestiaGroup.keychainAccessGroup))
    }

    var link: FlatdLink? {
        defaults?.data(forKey: Self.linkKey).flatMap { try? JSONDecoder().decode(FlatdLink.self, from: $0) }
    }

    func save(link: FlatdLink) {
        defaults?.set(try? JSONEncoder().encode(link), forKey: Self.linkKey)
    }

    var token: String? { (try? keychain.read()) ?? nil }

    func save(token: String) throws { try keychain.save(token) }

    /// Both, when they are there.
    var client: FlatdClient? {
        guard let link, let token, !token.isEmpty else { return nil }
        return FlatdClient(baseURL: link.baseURL, token: token)
    }

    /// Forgets the connection (Settings → Disconnect).
    func forget() {
        try? keychain.delete()
        defaults?.removeObject(forKey: Self.linkKey)
        defaults?.removeObject(forKey: Self.devicesKey)
    }

    // MARK: the devices as last seen (names only)

    nonisolated struct KnownDevice: Codable, Equatable, Sendable {
        let id: String
        let kind: String
        let label: String
    }

    var knownDevices: [KnownDevice] {
        defaults?.data(forKey: Self.devicesKey).flatMap { try? JSONDecoder().decode([KnownDevice].self, from: $0) } ?? []
    }

    func remember(_ devices: [Device]) {
        let known = devices.map { KnownDevice(id: $0.id, kind: $0.kind.raw, label: $0.label) }
        guard known != knownDevices else { return }
        defaults?.set(try? JSONEncoder().encode(known), forKey: Self.devicesKey)
    }
}

extension Device.Kind {
    nonisolated var raw: String {
        switch self {
        case .fan: "fan"
        case .light: "light"
        case .rollo: "rollo"
        case .plug: "plug"
        case let .other(value): value
        }
    }
}
