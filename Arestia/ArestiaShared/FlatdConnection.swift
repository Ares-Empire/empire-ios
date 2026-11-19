import Foundation
import Security

/// One pairing: flatd's identity (the pin), its key, and the address it was last reached at, kept together as one
/// Keychain item, so the app and its controls never read one pairing's address with another's key or pin (Codex's
/// review, 2026-11-19). The address is only where to look first: flatd is whoever proves the pin's key, wherever it is.
nonisolated struct FlatdPairing: Codable, Equatable, Sendable {
    var baseURL: URL
    let token: String
    let pin: FlatdPin
    /// Names this pairing (also the Keychain item's label), so moving it to a new address changes only this pairing.
    var id = UUID()
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

/// Where the pairing is kept: the Keychain in the app, memory in the tests. `label` names the saved item, so a change can
/// be made only while that item is still the one saved.
nonisolated protocol FlatdKeyStore: Sendable {
    func read() throws -> String?
    func save(_ value: String, label: String) throws
    /// Replaces the value only while the saved item has this label; false when there is none (deleted or replaced).
    func update(_ value: String, ifLabel label: String) -> Bool
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

    func update(_ value: String, ifLabel label: String) -> Bool {
        var query = query
        query[kSecAttrLabel as String] = label
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data(value.utf8)] as CFDictionary)
        return status == errSecSuccess
    }

    func save(_ value: String, label: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrLabel as String: label,
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

/// The saved connection: the pairing (address and key) as one Keychain item, the devices' names in the App Group.
nonisolated struct FlatdConnection: @unchecked Sendable {
    /// Thread-safe (`UserDefaults` is), hence the unchecked Sendable.
    let defaults: UserDefaults?
    let keychain: any FlatdKeyStore

    /// The devices' ids, kinds and names as last seen, for Shortcuts' pickers while flatd is out of reach.
    static let devicesKey = "flatd.devices"

    static var live: FlatdConnection {
        FlatdConnection(defaults: ArestiaGroup.defaults,
                        keychain: FlatdKeychain(service: "de.ares-empire.arestia.flatd", account: "flatd-pairing",
                                                accessGroup: ArestiaGroup.keychainAccessGroup))
    }

    /// What the Keychain holds: no pairing, a pairing, or something that cannot be used as one (the item could not be
    /// read right now, or it is not a whole pairing: one without a pin or with a plain-HTTP address, from a build before
    /// flatd had an identity). The last is not "nothing": a pairing may be there, so replacing it takes the same
    /// deliberate Connect as replacing a known one (`ConnectModel.needsConfirmation`).
    nonisolated enum Saved: Equatable, Sendable {
        case none
        case paired(FlatdPairing)
        case unusable
    }

    var saved: Saved {
        let text: String?
        do { text = try keychain.read() } catch { return .unusable }
        guard let text else { return .none }
        guard let pairing = try? JSONDecoder().decode(FlatdPairing.self, from: Data(text.utf8)),
              pairing.baseURL.scheme == "https", !pairing.token.isEmpty else { return .unusable }
        return .paired(pairing)
    }

    /// The pairing to work with; nil without a usable one (then the app asks to pair).
    var pairing: FlatdPairing? {
        if case let .paired(pairing) = saved { pairing } else { nil }
    }

    var token: String? { pairing?.token }

    func save(_ pairing: FlatdPairing) throws {
        let data = try JSONEncoder().encode(pairing)
        try keychain.save(String(decoding: data, as: UTF8.self), label: pairing.id.uuidString)
    }

    /// A new address for this pairing (flatd found again over Bonjour and proved by its key), in one conditional
    /// Keychain update: it changes
    /// nothing once the pairing was replaced or forgotten, so a late lookup (in the app or a control) never brings an
    /// old pairing back.
    func move(_ pairing: FlatdPairing, to baseURL: URL) {
        guard pairing.baseURL != baseURL, baseURL.scheme == "https" else { return }
        var moved = pairing
        moved.baseURL = baseURL
        guard let data = try? JSONEncoder().encode(moved) else { return }
        _ = keychain.update(String(decoding: data, as: UTF8.self), ifLabel: pairing.id.uuidString)
    }

    /// The client for the saved pairing, at its saved address.
    var client: FlatdClient? { pairing.map { FlatdClient($0) } }

    /// Forgets the connection (Settings → Disconnect). Throws when the Keychain kept the item.
    func forget() throws {
        try keychain.delete()
        defaults?.removeObject(forKey: Self.devicesKey)
    }

    // MARK: the devices as last seen (names only)

    nonisolated struct KnownDevice: Codable, Equatable, Sendable {
        let id: String
        let kind: String
        let label: String
    }

    /// The names as saved, with the pairing they came from: read only while that pairing is the saved one, so names
    /// written late (after Disconnect, or after pairing with another flatd) are never shown.
    private nonisolated struct KnownDevices: Codable {
        let pairing: UUID
        let devices: [KnownDevice]
    }

    var knownDevices: [KnownDevice] {
        guard let id = pairing?.id,
              let known = defaults?.data(forKey: Self.devicesKey)
                .flatMap({ try? JSONDecoder().decode(KnownDevices.self, from: $0) }),
              known.pairing == id else { return [] }
        return known.devices
    }

    /// Whether this client still speaks for the saved pairing: the same flatd (its identity) and the same key. False
    /// after Disconnect or after pairing with another flatd, also one that happens to use the same key.
    func isCurrent(_ client: FlatdClient) -> Bool {
        guard let pairing else { return false }
        return pairing.pin == client.pin && pairing.token == client.token
    }

    /// Keeps the devices' names for Shortcuts' pickers, only while the pairing they came from (`client`'s) is the saved
    /// one: a late answer never brings names back after Disconnect, or another flat's names into a new pairing.
    func remember(_ devices: [Device], from client: FlatdClient? = nil) {
        guard let pairing, client.map({ $0.pin == pairing.pin && $0.token == pairing.token }) ?? true else { return }
        let known = devices.map { KnownDevice(id: $0.id, kind: $0.kind.raw, label: $0.label) }
        guard known != knownDevices else { return }
        defaults?.set(try? JSONEncoder().encode(KnownDevices(pairing: pairing.id, devices: known)),
                      forKey: Self.devicesKey)
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
