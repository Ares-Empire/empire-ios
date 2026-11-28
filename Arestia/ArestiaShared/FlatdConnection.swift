import Foundation
import notify
import os
import Security

/// One pairing: flatd's identity (the pin), its key, and the address it was last reached at, kept together as one
/// Keychain item, so the app and its controls never read one pairing's address with another's key or pin (Codex's
/// review, 2026-11-19). The address is only where to look first: flatd is whoever proves the pin's key, wherever it is.
nonisolated struct FlatdPairing: Codable, Equatable, Sendable {
    var baseURL: URL
    let token: String
    let pin: FlatdPin
    var remote: RemoteListener?
    /// **The pairing's identity**: made new for every pairing, kept while the same flatd (the same pin) gets a new key
    /// or address. One flat per install (docs/ARESTIA-APP.md): the app's store lives for one identity (`FlatStore`), and
    /// another flat is paired only after Forget, so it always gets a new identity. A blind or fan chosen in a Shortcut or
    /// a control carries it (`SavedDevice`), so a choice made before Forget acts on nothing afterwards.
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

    func matches(route: HomeRoute?, pin: FlatdPin, url: URL, token: String, remoteGeneration: UUID?) -> Bool {
        guard self.token == token else { return false }
        return switch route {
        case .home: self.pin == pin
        case .remote: remote?.pin == pin && remote?.url == url && remote?.generation == remoteGeneration
        case nil: false
        }
    }

    private enum CodingKeys: String, CodingKey { case baseURL, token, pin, id, revision, remote }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try values.decode(URL.self, forKey: .baseURL)
        token = try values.decode(String.self, forKey: .token)
        pin = try values.decode(FlatdPin.self, forKey: .pin)
        id = try values.decode(UUID.self, forKey: .id)
        revision = try values.decode(UUID.self, forKey: .revision)
        if let saved = try? values.decode(RemoteListener.Saved.self, forKey: .remote) {
            remote = RemoteListener.parse(url: saved.url, pin: saved.pin, homePin: pin, generation: saved.generation ?? revision)
        }
    }
}

/// What Arestia shares between the app and its Control Center extension: the App Group's defaults and the Keychain
/// group (both in the entitlements; never the Empire's shared ones: Arestia has no Ares account).
nonisolated enum ArestiaGroup {
    static let appGroup = "group.de.ares-empire.arestia"
    /// Without the team prefix (entitlement: `$(AppIdentifierPrefix)` + this).
    static let keychainGroup = "de.ares-empire.arestia"
    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }
    /// Arestia's own folder in the App Group, the same one for the app and the extension (nil when the App Group's
    /// folder cannot be found). In Application Support: never in Caches, which iOS may empty at any time (two processes
    /// would then lock two different lock files).
    static let folder: URL? = {
        guard let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "Library/Application Support/Arestia", directoryHint: .isDirectory) else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()
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

/// The one lock that Forget and the start of every request with a pairing's key share, in the app and its Control
/// Center extension alike (a file in the App Group, `flock`): Forget deletes the pairing under it, and a request checks
/// under it that its pairing is still the saved one and starts there and then (`FlatdConnection.start(for:_:)`). So a
/// request either started before Forget or never starts: no await, no other process, can slip between the last check
/// and the start (Codex's review, round 6). Held only for that moment, never across an await (a process suspended with a
/// lock in the App Group is ended by iOS). It fails closed (round 7): without its file, nothing it guards runs.
nonisolated final class FlatdDispatchLock: @unchecked Sendable {
    private enum Kind {
        /// The production lock: this file, shared by the app and the extension.
        case file(String)
        /// Within this process only: the unit tests, which have no second process.
        case processOnly
        /// The App Group's folder could not be found: nothing the lock guards may run.
        case unavailable
    }

    /// The lock could not be taken (no lock file, or `open`/`flock` failed): the guarded work did not run.
    struct Unavailable: Error {}

    private let kind: Kind
    /// The same within the process (a second `flock` there would wait for the first anyway; this keeps threads tidy).
    private let local = NSLock()
    private static let log = Logger(subsystem: "de.ares-empire.arestia", category: "pairing")

    #if DEBUG
    private var onContention: (@Sendable () -> Void)?

    static func processOnly(onContention: @escaping @Sendable () -> Void) -> FlatdDispatchLock {
        let lock = FlatdDispatchLock(.processOnly)
        lock.onContention = onContention
        return lock
    }
    #endif

    private init(_ kind: Kind) { self.kind = kind }

    /// A lock on this file (another process opening the same file shares it).
    convenience init(path: String) { self.init(.file(path)) }

    /// For the unit tests only: within this process.
    static var processOnly: FlatdDispatchLock { FlatdDispatchLock(.processOnly) }

    /// The lock file in Arestia's App Group folder (`ArestiaGroup.folder`: the app and the extension see the same one).
    static let live: FlatdDispatchLock = {
        guard let folder = ArestiaGroup.folder else {
            log.error("no App Group folder: the dispatch lock is unavailable, nothing with the key is sent")
            return FlatdDispatchLock(.unavailable)
        }
        return FlatdDispatchLock(.file(folder.appending(path: "flatd-dispatch.lock").path(percentEncoded: false)))
    }()

    /// Runs `body` holding the lock; throws `Unavailable` (and runs nothing) when the lock cannot be taken.
    func withLock<T>(until deadline: Deadline, hold: Hold, _ body: () throws -> T) throws -> T {
        #if DEBUG
        dispatchPrecondition(condition: .notOnQueue(.main))
        #endif
        func check() throws {
            try deadline.check()
            try hold.check()
        }
        try check()
        while !local.lock(before: Date(timeIntervalSinceNow: min(0.01, max(0, deadline.remainingSeconds)))) {
            #if DEBUG
            onContention?()
            #endif
            try check()
        }
        defer { local.unlock() }
        try check()
        switch kind {
        case .processOnly:
            return try body()
        case .unavailable:
            throw Unavailable()
        case let .file(path):
            let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else {
                Self.log.error("the dispatch lock could not be opened (\(errno, privacy: .public))")
                throw Unavailable()
            }
            defer { close(descriptor) }
            while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
                if errno == EINTR { try check(); continue }
                guard errno == EWOULDBLOCK else {
                    Self.log.error("the dispatch lock could not be taken (\(errno, privacy: .public))")
                    throw Unavailable()
                }
                try check()
                Thread.sleep(forTimeInterval: min(0.01, max(0, deadline.remainingSeconds)))
            }
            defer { flock(descriptor, LOCK_UN) }
            try check()
            return try body()
        }
    }
}

/// The devices' names as last accepted, with their version: **one file** in the App Group, the one source of truth for
/// the app and its Control Center extension. Every change replaces the whole file in one step (`rename(2)`), under the
/// lock both processes share (`FlatdConnection.lock`), so a reader in either process sees one complete version or the
/// next, and what a writer read under the lock is what the other process last wrote.
///
/// Never `UserDefaults`: a value set there reaches other processes some time later, so the extension could take the
/// lock and still read the names from before the app's write, then write an older list over it (Codex's review of the
/// renaming, round 2, finding 2). A file has no such copy per process.
nonisolated struct DeviceNameFile: Sendable {
    let url: URL
    private static let log = Logger(subsystem: "de.ares-empire.arestia", category: "names")

    /// The file in Arestia's App Group folder; nil when that folder cannot be found (then no names are kept).
    static let live: DeviceNameFile? = ArestiaGroup.folder.map { DeviceNameFile(url: $0.appending(path: "device-names.json")) }

    /// What the file holds now; nil when there is none or it cannot be read (no names kept).
    func read() -> FlatdConnection.KnownDevices? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FlatdConnection.KnownDevices.self, from: data)
    }

    /// Replaces the file in one step. Readable after the first unlock, as the pairing is (a control on the lock screen
    /// reads the names). Call under the shared lock.
    func write(_ known: FlatdConnection.KnownDevices) {
        do {
            try JSONEncoder().encode(known)
                .write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Self.log.error("the devices' names could not be kept: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Removes the file (Forget); throws when a file that is there could not be removed. Call under the shared lock.
    func remove() throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }
}

/// The saved connection: the pairing (address and key) as one Keychain item, the devices' names as one file in the App
/// Group (`DeviceNameFile`), a mode's trouble in the App Group's defaults.
nonisolated struct FlatdConnection: @unchecked Sendable {
    /// Thread-safe (`UserDefaults` is), hence the unchecked Sendable. A mode's trouble only; never the names.
    let defaults: UserDefaults?
    /// The devices' names, for Shortcuts' pickers and the Blind control (nil: none are kept).
    let names: DeviceNameFile?
    let keychain: any FlatdKeyStore
    /// Shared by Forget and the start of every request with a pairing's key (`FlatdDispatchLock`): `.live` in the app
    /// and the extension, `.processOnly` only in the unit tests.
    let lock: FlatdDispatchLock

    /// Where build 2 kept the names (the App Group's defaults): nothing reads it any more, and it is removed with
    /// the next snapshot or Forget.
    static let namesKeyOfBuild2 = "flatd.devices"

    static var live: FlatdConnection {
        FlatdConnection(defaults: ArestiaGroup.defaults, names: .live,
                        keychain: FlatdKeychain(service: "de.ares-empire.arestia.flatd", account: "flatd-pairing",
                                                accessGroup: ArestiaGroup.keychainAccessGroup),
                        lock: .live)
    }

    /// What the Keychain holds right now.
    nonisolated enum Saved: Equatable, Sendable {
        case none
        case paired(FlatdPairing)
        /// The Keychain could not be read just now (before the iPhone's first unlock after a restart, a hiccup): a
        /// pairing may well be there, so this is never taken as none. Whoever reads it tries again later.
        case unreadable
        /// An item that is no pairing (one without a pin or with a plain-HTTP address, from a build before flatd had an
        /// identity, or a damaged one): it never becomes usable, so it counts as none and a first pairing replaces it.
        case invalid
    }

    var saved: Saved {
        let text: String?
        do { text = try keychain.read() } catch { return .unreadable }
        guard let text else { return .none }
        guard let pairing = try? JSONDecoder().decode(FlatdPairing.self, from: Data(text.utf8)),
              pairing.baseURL.scheme == "https", !pairing.token.isEmpty else { return .invalid }
        return .paired(pairing)
    }

    /// The pairing to work with; nil without a usable one, or while it cannot be read (`saved` tells them apart).
    var pairing: FlatdPairing? {
        if case let .paired(pairing) = saved { pairing } else { nil }
    }

    /// The pairing to work with, or why there is none: `.notPaired` (none, or no usable one), `.pairingUnreadable`
    /// (the Keychain could not be read just now; try again).
    func current() throws -> FlatdPairing {
        switch saved {
        case let .paired(pairing): return pairing
        case .unreadable: throw FlatdError.pairingUnreadable
        case .none, .invalid: throw FlatdError.notPaired
        }
    }

    var token: String? { pairing?.token }


    /// Saves this pairing over whatever is saved (Debug launch arguments and the tests; the app pairs with `pairNew`
    /// and `renew`, which change only what they were read as).
    func save(_ pairing: FlatdPairing) throws {
        try keychain.save(Self.text(pairing), label: pairing.revision.uuidString)
    }

    /// A first pairing, saved only while nothing is saved: a pairing that is there is never overwritten. False when one
    /// was there.
    func pairNew(_ pairing: FlatdPairing) throws -> Bool {
        try keychain.add(Self.text(pairing), label: pairing.revision.uuidString)
    }

    /// The same flatd (the same identity) with a new key or address, written only over the version `saved` was read
    /// as: false when the pairing changed meanwhile. Keeps the pairing's identity, so its choices go on.
    func renew(_ saved: FlatdPairing, with renewed: FlatdPairing, hold: Hold,
               isLatest: () -> Bool = { true }) throws -> Bool {
        guard renewed.id == saved.id, renewed.pin == saved.pin, renewed.revision != saved.revision else { return false }
        var renewed = renewed
        if renewed.token != saved.token { renewed.remote = nil }
        let text = try Self.text(renewed)
        return try lock.withLock(until: hold.deadline, hold: hold) {
            guard isLatest() else { return false }
            // An admitted CAS holds the dispatch lock until Keychain returns.
            try hold.commit {}
            return keychain.update(text, ifLabel: saved.revision.uuidString, newLabel: renewed.revision.uuidString)
        }
    }

    private static func text(_ pairing: FlatdPairing) throws -> String {
        String(decoding: try JSONEncoder().encode(pairing), as: UTF8.self)
    }

    /// A new address for this pairing (flatd found again over Bonjour and proved by its key), written only over the
    /// version it was read as: it changes nothing once the pairing was renewed, replaced or forgotten, so a late lookup
    /// (in the app or a control) never brings an old pairing or an old key back.
    func move(_ pairing: FlatdPairing, to client: FlatdClient, hold: Hold) throws -> Bool {
        guard client.route == .home, client.pairingID == pairing.id, client.pin == pairing.pin else { return false }
        let baseURL = client.baseURL
        guard pairing.baseURL != baseURL, baseURL.scheme == "https" else { return false }
        var moved = pairing
        moved.baseURL = baseURL
        moved.revision = UUID()
        return try renew(pairing, with: moved, hold: hold)
    }

    /// The client for the saved pairing, at its saved address.
    var client: FlatdClient? { pairing.map { FlatdClient($0).gated(by: self) } }

    /// The client for the pairing with this identity, while it is the saved one: built from that one reading of the
    /// Keychain, so the identity checked and the key and pin used are the same pairing's. Nil once it is not.
    func client(for id: UUID, transport: FlatdTransportOverride? = nil) -> FlatdClient? {
        guard let pairing, pairing.id == id else { return nil }
        return FlatdClient(pairing, transport: transport).gated(by: self)
    }

    /// Forgets the flat (Settings → Forget this flat, `FlatSession.forget`): the pairing and everything kept for it here
    /// (the devices' names, a mode's trouble), under the lock every writer of the names takes.
    ///
    /// The names file goes first, and a file that could not be removed stops Forget with the pairing still saved
    /// (thrown, so Settings says it and Forget can be tried again): the names never outlive their pairing, not even
    /// when the process ends between the two steps (Codex's review of the renaming, round 3, finding 5: the Keychain
    /// item went first and the removal's failure was swallowed). Throws when the Keychain kept the item too; the names
    /// are gone then, which is harmless: the pairing's next snapshot keeps them again.
    func forget(_ hold: Hold, lockBy: Deadline, onlyIfInvalid: Bool = false) throws {
        try lock.withLock(until: lockBy, hold: hold) {
            if onlyIfInvalid {
                guard case .invalid = saved else { return }
            }
            try hold.commit {}
            try names?.remove()
            try keychain.delete()
            defaults?.removeObject(forKey: Self.namesKeyOfBuild2)
            defaults?.removeObject(forKey: Self.troubleKey)
            defaults?.removeObject(forKey: Self.troubleSeenKey)
        }
    }

    func forgetSavedPairing(onlyIfInvalid: Bool = false,
                            deadline: Deadline = Deadline(after: .seconds(3600))) async throws {
        let lockBy = deadline.capped(by: .seconds(10))
        let outcome = await deadline.blockingOutcome(finishAdmittedWork: true) { hold in
            try forget(hold, lockBy: lockBy, onlyIfInvalid: onlyIfInvalid)
        }
        try outcome.result.get()
    }

    // MARK: the devices as last seen (names only)

    nonisolated struct KnownDevice: Codable, Equatable, Sendable {
        let id: String
        let kind: String
        let label: String
    }

    /// The names as kept (`DeviceNameFile`), with the pairing they came from: read only while that pairing is the saved
    /// one, so names written late (after Forget) are never shown.
    nonisolated struct KnownDevices: Codable, Equatable, Sendable {
        let pairing: UUID
        var devices: [KnownDevice]
        /// New with every write: a reading of flatd's list keeps its answer only while the names kept are still the
        /// version it started from (`remember(_:for:readSince:)`).
        var version: UUID
    }

    /// The names with their pairing's identity, as one reading: the pairing read once, the names only when they were
    /// kept for it. A picker labels its choices with this identity (`DeviceChoices`), never with one read separately.
    var known: KnownDevices? {
        guard let id = pairing?.id, let known = names?.read(), known.pairing == id else { return nil }
        return known
    }

    /// The version of the names kept now (nil: none kept), taken before reading flatd's list: its answer is kept only
    /// while this is still the version (`remember(_:for:readSince:)`).
    var devicesVersion: UUID? { names?.read()?.version }

    var knownDevices: [KnownDevice] { known?.devices ?? [] }

    /// The devices' names for these ids, as kept for this pairing (the id itself where none is kept, or the names are
    /// another pairing's).
    func names(_ ids: [String], pairing: UUID?) -> [String] {
        let known = self.known.flatMap { $0.pairing == pairing ? $0.devices : nil } ?? []
        return ids.map { id in known.first { $0.id == id }?.label ?? id }
    }

    /// Whether this client still speaks for the saved pairing: the same identity (and so the same flatd). False after
    /// Forget, and for a client made for no pairing (a code being tried).
    func isCurrent(_ client: FlatdClient) -> Bool {
        (try? checkCurrent(client)) != nil
    }

    func checkCurrent(_ client: FlatdClient) throws {
        let saved = try current()
        guard saved.id == client.pairingID else { throw FlatdError.notPaired }
        guard saved.matches(route: client.route, pin: client.pin, url: client.baseURL, token: client.token,
                            remoteGeneration: client.remoteGeneration) else {
            throw FlatdError.unreachable
        }
    }

    // Three ways names come in, each with its own rule (Codex's review of the renaming, round 2):
    // - a snapshot of the app's stream: flatd's whole list, in the stream's order. Replaces the list.
    // - one device's name, confirmed (a `device` event, a rename's answer): laid over that one device. The app's list
    //   of the other devices may be older than what a picker read meanwhile, so it is never written with it.
    // - flatd's list as a request read it (a picker, a control): replaces the list only while nothing was kept since
    //   the request began.
    // Each is one read and one write under the lock Forget takes (in the app and the extension alike), and only while
    // its pairing is the saved one: a late writer never puts a forgotten flat's names back (round 7).

    /// A snapshot of the app's event stream: flatd's whole list. The stream brings flatd's changes in their order, so
    /// its list is the newest: always kept, under a new version, so a list read before it is not kept after it.
    func remember(_ devices: [Device], for pairing: UUID, hold: Hold) {
        keep(for: pairing, hold: hold, removesLegacyNames: true) { _ in Self.known(devices) }
    }

    /// One device's name as flatd confirmed it (a `device` event, a rename's answer): laid over that device alone in
    /// the names kept, under a new version. The other devices' names stay as kept: a picker may have read a newer
    /// name for one of them while the app's stream was down (finding 3). Nothing while no names are kept for this
    /// pairing: one name is no list, and the next snapshot brings them all.
    func rememberName(of device: Device, for pairing: UUID, hold: Hold) {
        keep(for: pairing, hold: hold) { kept in Self.laying(device, over: kept, for: pairing) }
    }

    /// The same for a command's answer (a rename's, or flatd's device read again), which may have been on its way
    /// while names were kept: laid over its device only while the names kept are still the version taken just before
    /// the request was sent (`devicesVersion`). False when names were kept since (a picker or a control read flatd's
    /// list, in either process, while the app's stream was down): nothing is written then, as that list may be newer
    /// than this answer, or older; the caller asks flatd again (Codex's review of the renaming, round 3, finding 3: a
    /// late answer put "Desk" back over the "Kitchen" a picker had read since).
    func rememberName(of device: Device, for pairing: UUID, unchangedSince version: UUID?,
                      hold: Hold) -> Bool {
        var unchanged = true
        keep(for: pairing, hold: hold) { kept in
            guard kept?.version == version else {
                unchanged = false
                return nil
            }
            return Self.laying(device, over: kept, for: pairing)
        }
        return unchanged
    }

    /// The names kept with this one device's laid over it (nil: no list is kept for this pairing).
    private static func laying(_ device: Device, over kept: KnownDevices?, for pairing: UUID) -> [KnownDevice]? {
        let named = KnownDevice(id: device.id, kind: device.kind.raw, label: device.label)
        guard var devices = kept.flatMap({ $0.pairing == pairing ? $0.devices : nil }) else { return nil }
        if let index = devices.firstIndex(where: { $0.id == named.id }) {
            devices[index] = named
        } else {
            devices.append(named)
        }
        return devices
    }

    /// The names a reading of flatd's list brought (`GET /api/devices`), kept only while the names kept are still the
    /// version taken before the reading began (`devicesVersion`): a list answered after newer names were kept (a
    /// rename heard meanwhile, in either process) changes nothing (round 1, finding 3). False when it was not taken;
    /// the names to show are then the ones kept (`known`), never this list's.
    @discardableResult
    func remember(_ devices: [Device], for pairing: UUID, readSince version: UUID?,
                  hold: Hold) -> Bool {
        let known = Self.known(devices)
        var taken = false
        keep(for: pairing, hold: hold) { kept in
            guard kept?.version == version else { return nil }
            taken = true
            // The same names for the same pairing: taken, and nothing to write.
            return kept?.pairing == pairing && kept?.devices == known ? nil : known
        }
        return taken
    }

    /// The same, for what a client of a pairing read (nothing for a client made for no pairing).
    @discardableResult
    func remember(_ devices: [Device], from client: FlatdClient, readSince version: UUID?, hold: Hold) -> Bool {
        guard let id = client.pairingID, isCurrent(client) else { return false }
        return remember(devices, for: id, readSince: version, hold: hold)
    }

    /// flatd's list as a request of `client` read it, each device under the name to show: offered to the names kept
    /// (`remember(_:for:readSince:)`), then named as kept after that, both in one hold of the lock Forget takes. Call it
    /// inside `FlatdReach.run`, whose last check of the pairing then covers what this returns (Codex's review of the
    /// renaming, round 3, finding 2: run it after and a Forget in between gave a forgotten flat's blind back).
    ///
    /// Throws `.notPaired` once the client's pairing is not the saved one (forgotten, or another flat paired): the
    /// list is a retired pairing's and shows nothing. `.pairingUnreadable` while the Keychain cannot say. Only when no
    /// names can be kept at all (no App Group folder, no lock file, a file that cannot be written) are the names flatd
    /// just sent shown: the cache is unavailable, which is not the same as a retired pairing.
    func named(_ devices: [Device], from client: FlatdClient, readSince version: UUID?, hold: Hold) throws -> [Device] {
        guard let id = client.pairingID else { throw FlatdError.notPaired }
        guard let names else {
            try checkCurrent(client)
            return devices
        }
        let kept: [KnownDevice]?
        do {
            kept = try lock.withLock(until: hold.deadline, hold: hold) { () throws -> [KnownDevice]? in
                try checkCurrent(client)
                let known = Self.known(devices)
                let now = names.read()
                if now?.version == version, !(now?.pairing == id && now?.devices == known) {
                    try hold.commit {}
                    names.write(KnownDevices(pairing: id, devices: known, version: UUID()))
                }
                return names.read().flatMap { $0.pairing == id ? $0.devices : nil }
            }
        } catch is Deadline.Expired {
            throw FlatdError.unreachable
        } catch is FlatdDispatchLock.Unavailable {
            try checkCurrent(client)                       // no lock, so no names: nothing could have been kept either
            return devices
        }
        guard let kept else { return devices }      // none kept for this pairing: the file could not be written
        return devices.map { device in kept.first { $0.id == device.id }.map { device.named($0.label) } ?? device }
    }

    /// One change of the names kept: `change` gets what the file holds now and gives the list to keep (nil: nothing is
    /// written). Read, decided and written under the lock, only while `pairing` is the saved one, and always under a
    /// new version.
    private func keep(for pairing: UUID, hold: Hold, removesLegacyNames: Bool = false,
                      _ change: (KnownDevices?) -> [KnownDevice]?) {
        guard let names else { return }
        try? lock.withLock(until: hold.deadline, hold: hold) {
            guard self.pairing?.id == pairing else { return }
            let saved = names.read()
            try hold.check()
            guard let devices = change(saved) else { return }
            try hold.commit {}
            if removesLegacyNames { defaults?.removeObject(forKey: Self.namesKeyOfBuild2) }
            names.write(KnownDevices(pairing: pairing, devices: devices, version: UUID()))
        }
    }

    private static func known(_ devices: [Device]) -> [KnownDevice] {
        devices.map { KnownDevice(id: $0.id, kind: $0.kind.raw, label: $0.label) }
    }

    // MARK: a mode whose devices did not all follow, outside the app

    static let troubleKey = "flatd.modeTrouble"
    /// The trouble the app has said (its id): the app says each once, while the control keeps showing it.
    static let troubleSeenKey = "flatd.modeTroubleSeen"
    /// Posted (a Darwin notification) when a trouble is kept, so a running app says it at once.
    static let troubleNotification = "de.ares-empire.arestia.modeTrouble"

    /// Keeps what a change of a mode made outside the app left undone: the Cooking control shows it next to its state,
    /// and the app says it once (`FlatStore`). Written only while its pairing is the saved one, under the lock Forget
    /// takes, so a late writer never puts one back after Forget.
    func note(_ trouble: ModeTrouble, hold: Hold) throws {
        let kept = try lock.withLock(until: hold.deadline, hold: hold) {
            guard pairing?.id == trouble.pairing, let data = try? JSONEncoder().encode(trouble) else { return false }
            if let saved = savedTrouble, saved.pairing == trouble.pairing, saved.at > trouble.at { return false }
            try hold.commit {}
            defaults?.set(data, forKey: Self.troubleKey)
            return true
        }
        if kept { notify_post(Self.troubleNotification) }
    }

    /// A change of the mode where every device followed: the trouble kept for it is cleared, only when it is this
    /// pairing's (a late answer of a forgotten flat never clears the next one's). A start sends every device its
    /// command again (flatd's contract), so one where all followed clears any trouble (round 8); ending a mode that is
    /// already off sends nothing to any device, so it never clears a fan left running by the first end (round 7).
    func clearTrouble(mode: String, pairing: UUID, now active: Bool, through date: Date = .now,
                      hold: Hold) throws {
        try lock.withLock(until: hold.deadline, hold: hold) {
            guard let saved = savedTrouble, saved.mode == mode, saved.pairing == pairing,
                  active || saved.active, saved.at <= date else { return }
            try hold.commit {}
            defaults?.removeObject(forKey: Self.troubleKey)
        }
    }

    /// The trouble kept for this mode while it still describes the mode as it is: the same pairing, the same state
    /// (`active`), and recent (`ModeTrouble.lasts`). A mode changed since (anywhere) makes it moot.
    func trouble(mode: String, active: Bool, pairing: UUID, now: Date = .now) -> ModeTrouble? {
        guard let trouble = savedTrouble, trouble.pairing == pairing, trouble.mode == mode, trouble.active == active,
              now.timeIntervalSince(trouble.at) < ModeTrouble.lasts else { return nil }
        return trouble
    }

    /// Whether the app has said this trouble already.
    func hasSaid(_ trouble: ModeTrouble) -> Bool {
        defaults?.string(forKey: Self.troubleSeenKey) == trouble.id.uuidString
    }

    func markSaid(_ trouble: ModeTrouble) {
        defaults?.set(trouble.id.uuidString, forKey: Self.troubleSeenKey)
    }

    private var savedTrouble: ModeTrouble? {
        defaults?.data(forKey: Self.troubleKey).flatMap { try? JSONDecoder().decode(ModeTrouble.self, from: $0) }
    }
}

/// A mode changed outside the app (a Control Center control, a Shortcut, Siri) while some of its devices did not
/// follow (flatd changes the mode anyway and lists them in `failed`; it keeps no record of them itself).
nonisolated struct ModeTrouble: Codable, Equatable, Sendable {
    /// This trouble (the app says each once).
    var id = UUID()
    let pairing: UUID
    let mode: String
    /// The mode's state the change left.
    let active: Bool
    /// The devices that did not follow, by name.
    let names: [String]
    let at: Date

    /// How long it is shown at most: after that the devices may long have been switched by hand.
    static let lasts: TimeInterval = 2 * 60 * 60
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
