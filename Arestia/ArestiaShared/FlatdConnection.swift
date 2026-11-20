import Foundation
import Security

/// One pairing: flatd's identity (the pin), its key, and the address it was last reached at, kept together as one
/// Keychain item, so the app and its controls never read one pairing's address with another's key or pin (Codex's
/// review, 2026-11-19). The address is only where to look first: flatd is whoever proves the pin's key, wherever it is.
nonisolated struct FlatdPairing: Codable, Equatable, Sendable {
    var baseURL: URL
    let token: String
    let pin: FlatdPin
    /// **The pairing's identity**, the one value everything done for a pairing carries: the store and its event stream,
    /// the 3D page, a command, a Shortcut's or a control's device choice (`SavedDevice`). Work tagged with another
    /// identity is dropped, never acted on (the trust reviews' rounds 1–4 each found work of one pairing that could
    /// reach the next; one value checked everywhere ends that class). Made new for every pairing with a flatd; kept
    /// only while the same flatd (the same pin) gets a new key or address. Another flatd is paired only after a full
    /// Disconnect (`FlatStore.connect`), so it always gets a new identity.
    let id: UUID
    /// This version of the saved item, also the Keychain item's label: every write makes a new one, and a change is
    /// written only over the version it was read from (`FlatdKeyStore.update`), in the app and in its extension alike.
    /// So a late address update never puts back an older key.
    var revision: UUID

    init(baseURL: URL, token: String, pin: FlatdPin, id: UUID = UUID(), revision: UUID = UUID()) {
        self.baseURL = baseURL
        self.token = token
        self.pin = pin
        self.id = id
        self.revision = revision
    }
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

/// Where the pairing is kept: the Keychain in the app, memory in the tests. `label` names the saved version
/// (`FlatdPairing.revision`), so a change can be made only to the version it was read from.
nonisolated protocol FlatdKeyStore: Sendable {
    func read() throws -> String?
    /// Saves, replacing whatever is there (Debug launch arguments and the tests; the app pairs with `add`).
    func save(_ value: String, label: String) throws
    /// Saves only while nothing is saved: false when an item is there (another pairing came first).
    func add(_ value: String, label: String) throws -> Bool
    /// Replaces the value and the label only while the saved item has `label`; false when it has another one (changed
    /// meanwhile), or there is none (forgotten).
    func update(_ value: String, ifLabel label: String, newLabel: String) -> Bool
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
        // nil means "no item" and nothing else: an item that is there but unreadable is an error, not an absence.
        guard let text = String(data: data, encoding: .utf8) else { throw FlatdKeychainError(status: errSecDecode) }
        return text
    }

    func update(_ value: String, ifLabel label: String, newLabel: String) -> Bool {
        var query = query
        query[kSecAttrLabel as String] = label
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data(value.utf8),
                                                           kSecAttrLabel as String: newLabel] as CFDictionary)
        return status == errSecSuccess
    }

    private func attributes(_ value: String, label: String) -> [String: Any] {
        [kSecValueData as String: Data(value.utf8), kSecAttrLabel as String: label,
         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
    }

    func save(_ value: String, label: String) throws {
        let attributes = attributes(value, label: label)
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard added == errSecSuccess else { throw FlatdKeychainError(status: added) }
        } else if status != errSecSuccess {
            throw FlatdKeychainError(status: status)
        }
    }

    func add(_ value: String, label: String) throws -> Bool {
        let status = SecItemAdd(query.merging(attributes(value, label: label)) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem { return false }
        guard status == errSecSuccess else { throw FlatdKeychainError(status: status) }
        return true
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

        /// The same pairing (identity), whatever its address or key now; or both none, or both unusable.
        func isSamePairing(as other: Saved) -> Bool {
            switch (self, other) {
            case (.none, .none), (.unusable, .unusable): true
            case let (.paired(a), .paired(b)): a.id == b.id && a.pin == b.pin
            default: false
            }
        }
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

    /// Saves this pairing over whatever is saved (Debug launch arguments and the tests; the app pairs with `pairNew`
    /// and `renew`, which change only what they were decided against).
    func save(_ pairing: FlatdPairing) throws {
        try keychain.save(Self.text(pairing), label: pairing.revision.uuidString)
    }

    /// A new pairing, saved only while nothing is saved: a pairing made meanwhile (in the app or anywhere) is never
    /// overwritten. False when one was there.
    func pairNew(_ pairing: FlatdPairing) throws -> Bool {
        try keychain.add(Self.text(pairing), label: pairing.revision.uuidString)
    }

    /// The same flatd (the same identity) with a new key or address, written only over the version `saved` was read
    /// as: false when the pairing changed meanwhile. Keeps the pairing's identity, so its work and choices go on.
    func renew(_ saved: FlatdPairing, with renewed: FlatdPairing) -> Bool {
        guard renewed.id == saved.id, renewed.pin == saved.pin, renewed.revision != saved.revision,
              let text = try? Self.text(renewed) else { return false }
        return keychain.update(text, ifLabel: saved.revision.uuidString, newLabel: renewed.revision.uuidString)
    }

    private static func text(_ pairing: FlatdPairing) throws -> String {
        String(decoding: try JSONEncoder().encode(pairing), as: UTF8.self)
    }

    /// A new address for this pairing (flatd found again over Bonjour and proved by its key), written only over the
    /// version it was read as: it changes nothing once the pairing was renewed, replaced or forgotten, so a late lookup
    /// (in the app or a control) never brings an old pairing or an old key back.
    func move(_ pairing: FlatdPairing, to baseURL: URL) {
        guard pairing.baseURL != baseURL, baseURL.scheme == "https" else { return }
        var moved = pairing
        moved.baseURL = baseURL
        moved.revision = UUID()
        _ = renew(pairing, with: moved)
    }

    /// The client for the saved pairing, at its saved address.
    var client: FlatdClient? { pairing.map { FlatdClient($0) } }

    /// The client for the pairing with this identity, while it is the saved one: built from that one reading of the
    /// Keychain, so the identity checked and the key and pin used are the same pairing's. Nil once it is not.
    func client(for id: UUID, transport: (any HTTPTransport & Sendable)? = nil) -> FlatdClient? {
        guard let pairing, pairing.id == id else { return nil }
        return FlatdClient(pairing, transport: transport)
    }

    /// Forgets the connection (Settings → Disconnect, and before pairing with another flatd): the pairing and every
    /// choice kept for it here. Throws when the Keychain kept the item.
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
    nonisolated struct KnownDevices: Codable, Equatable, Sendable {
        let pairing: UUID
        let devices: [KnownDevice]
    }

    /// The names with their pairing's identity, as one reading: the pairing read once, the names only when they were
    /// kept for it. A picker labels its choices with this identity (`DeviceChoices`), never with one read separately,
    /// so a pairing made between two readings cannot lend its identity to the other's names (round 4).
    var known: KnownDevices? {
        guard let id = pairing?.id,
              let known = defaults?.data(forKey: Self.devicesKey)
                .flatMap({ try? JSONDecoder().decode(KnownDevices.self, from: $0) }),
              known.pairing == id else { return nil }
        return known
    }

    var knownDevices: [KnownDevice] { known?.devices ?? [] }

    /// Whether this client still speaks for the saved pairing: the same identity (and so the same flatd). False after
    /// Disconnect or after pairing with another flatd, also one that happens to use the same key, and for a client made
    /// for no pairing (a code being tried).
    func isCurrent(_ client: FlatdClient) -> Bool {
        guard let id = client.pairingID, let pairing else { return false }
        return pairing.id == id && pairing.pin == client.pin
    }

    /// Keeps the devices' names for Shortcuts' pickers, tagged with the pairing they came from, and only while that
    /// pairing is the saved one: a late answer never brings names back after Disconnect, or another flat's names into
    /// a new pairing.
    func remember(_ devices: [Device], for pairing: UUID) {
        guard self.pairing?.id == pairing else { return }
        let known = devices.map { KnownDevice(id: $0.id, kind: $0.kind.raw, label: $0.label) }
        guard known != knownDevices else { return }
        defaults?.set(try? JSONEncoder().encode(KnownDevices(pairing: pairing, devices: known)),
                      forKey: Self.devicesKey)
    }

    /// The same, for what a client of a pairing read (nothing for a client made for no pairing).
    func remember(_ devices: [Device], from client: FlatdClient) {
        guard let id = client.pairingID, isCurrent(client) else { return }
        remember(devices, for: id)
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
