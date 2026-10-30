import CommonCrypto
import Foundation
import LocalAuthentication
import Observation
import Security
import os

// Aresium's optional lock (Patrik, 2026-10-27; off by default; Settings → Lock): Face ID (Touch ID on such phones) and/or
// a 6-digit code of its own. With Face ID alone the iPhone's code is the fallback; with an own code, only Face ID or
// that code opens Aresium. It locks at launch and after more than 10 seconds in the background (being inactive, as
// under the Files picker, the share sheet or Control Center, does not lock). While it is on, the widgets show no
// numbers. The settings and the wrong-code count are in Aresium's own Keychain item (this device only, never the shared
// group); the code only as a salted PBKDF2-SHA256 hash. The pieces below are plain values and functions (tests pin
// them); `AppLock` puts them together, `LockScreen` and `LockSettingsSection` show it.

// MARK: - the code

/// The own code as it is kept: a salted PBKDF2-SHA256 hash, never the code itself.
nonisolated struct LockCodeHash: Codable, Equatable, Sendable {
    let salt: Data
    let hash: Data
    let rounds: Int

    /// At least 200,000 (the brief); 310,000 is OWASP's 2021 figure for PBKDF2-SHA256, about a tenth of a second on a
    /// recent iPhone.
    static let defaultRounds = 310_000
    static let saltLength = 16
    static let hashLength = 32

    /// A new hash of `code` with a new random salt.
    static func make(_ code: String, rounds: Int = defaultRounds) -> LockCodeHash {
        var salt = Data(count: saltLength)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, saltLength, $0.baseAddress!) }
        precondition(status == errSecSuccess, "no random bytes for the lock's salt")
        return LockCodeHash(salt: salt, hash: derive(code, salt: salt, rounds: rounds), rounds: rounds)
    }

    /// Whether `code` is the one this hash was made from (compared in constant time).
    func matches(_ code: String) -> Bool {
        let candidate = Self.derive(code, salt: salt, rounds: rounds)
        guard candidate.count == hash.count else { return false }
        return zip(candidate, hash).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    /// PBKDF2 with HMAC-SHA256 (CommonCrypto).
    static func derive(_ code: String, salt: Data, rounds: Int) -> Data {
        var derived = Data(count: hashLength)
        let password = Array(code.utf8).map { CChar(bitPattern: $0) }
        let status = derived.withUnsafeMutableBytes { output in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, password.count,
                                     saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(rounds),
                                     output.bindMemory(to: UInt8.self).baseAddress, hashLength)
            }
        }
        precondition(status == kCCSuccess, "PBKDF2 failed")
        return derived
    }
}

nonisolated enum LockCode {
    static let length = 6

    /// Six digits, 0 to 9.
    static func isValid(_ code: String) -> Bool {
        code.count == length && code.allSatisfy { ("0"..."9").contains($0) }
    }
}

/// The digits typed into a code pad, six at most.
struct CodeEntry: Equatable {
    private(set) var digits = ""

    var isComplete: Bool { digits.count == LockCode.length }

    mutating func type(_ digit: Character) {
        guard digits.count < LockCode.length, ("0"..."9").contains(digit) else { return }
        digits.append(digit)
    }

    mutating func delete() { if !digits.isEmpty { digits.removeLast() } }
    mutating func clear() { digits = "" }
}

// MARK: - wrong codes

/// Wrong codes in a row and when the last one was typed. Kept with the settings in the Keychain, so a restart does not
/// reset them; a right code (or Face ID) does.
nonisolated struct WrongCodes: Codable, Equatable, Sendable {
    var count = 0
    var last: Date?

    /// The wait after `count` wrong codes in a row: none for the first four; after 5 one minute, then 5, 15 and from
    /// the 8th on 60 minutes (like the iPhone's own).
    static func wait(after count: Int) -> TimeInterval {
        switch count {
        case ..<5: 0
        case 5: 60
        case 6: 5 * 60
        case 7: 15 * 60
        default: 60 * 60
        }
    }

    /// How long until the next code may be typed (0: now).
    func remaining(now: Date) -> TimeInterval {
        guard let last else { return 0 }
        return max(0, last.addingTimeInterval(Self.wait(after: count)).timeIntervalSince(now))
    }

    /// The clock was set back before the last wrong code: the wait counts from now (it never grows longer than its
    /// own length, and setting the clock back never shortens it).
    func clockChecked(now: Date) -> WrongCodes {
        guard let last, now < last else { return self }
        return WrongCodes(count: count, last: now)
    }

    func adding(at now: Date) -> WrongCodes { WrongCodes(count: count + 1, last: now) }
}

// MARK: - when it locks

nonisolated enum LockTiming {
    /// Away longer than this locks again.
    static let awayLimit: TimeInterval = 10

    /// Coming back from the background (`leftAt`: when the app went there): more than 10 seconds away locks again; a
    /// clock that went backwards counts as long away. Being inactive without going to the background never sets
    /// `leftAt`, so it never locks.
    static func locksAgain(leftAt: Date?, now: Date) -> Bool {
        guard let leftAt else { return false }
        let away = now.timeIntervalSince(leftAt)
        return away > awayLimit || away < 0
    }
}

// MARK: - storage

/// Everything the lock keeps: whether Face ID is on, the own code's hash, the wrong codes in a row.
nonisolated struct LockState: Codable, Equatable, Sendable {
    var faceID = false
    var code: LockCodeHash?
    var wrong = WrongCodes()

    var isOn: Bool { faceID || code != nil }
}

protocol LockStorage {
    func read() throws -> LockState?
    func save(_ state: LockState) throws
    func delete() throws
}

/// Aresium's own Keychain item (its app id's group, never the shared one), readable after the iPhone's first unlock,
/// on this device only (not in backups that move to another iPhone).
struct LockKeychain: LockStorage {
    let service: String
    let account = "lock"
    /// `$(AppIdentifierPrefix)de.ares-empire.aresium`: the app's own group. Named, because without a group new items
    /// would go to the first group in the entitlements, the shared one.
    let accessGroup: String

    init(service: String = "de.ares-empire.aresium.lock") {
        self.service = service
        let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String ?? ""
        accessGroup = prefix + "de.ares-empire.aresium"
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrAccessGroup as String: accessGroup]
    }

    func read() throws -> LockState? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError(status: status) }
        return try JSONDecoder().decode(LockState.self, from: data)
    }

    func save(_ state: LockState) throws {
        let attributes = [kSecValueData as String: try JSONEncoder().encode(state),
                          kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as [String: Any]
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

/// The lock in memory only: tests and the DEBUG samples.
final class MemoryLockStorage: LockStorage {
    var state: LockState?
    init(_ state: LockState? = nil) { self.state = state }
    func read() throws -> LockState? { state }
    func save(_ state: LockState) throws { self.state = state }
    func delete() throws { state = nil }
}

/// A file in the app's own container while a lock is set. The Keychain keeps its items when the app is deleted, the
/// container does not: a lock item without this file is left from an earlier install and is removed, so a new install
/// never opens with an old code.
nonisolated struct LockInstallMarker: Sendable {
    let url: URL

    static var standard: LockInstallMarker {
        LockInstallMarker(url: URL.applicationSupportDirectory.appending(path: "Aresium/lock-in-use"))
    }

    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    func set(_ on: Bool) {
        if on {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !exists { FileManager.default.createFile(atPath: url.path, contents: Data()) }
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - Face ID

/// Which unlock iOS is asked for.
enum LockPolicy: Equatable {
    /// Face ID (Touch ID) only: an own code is set, so the iPhone's code must not open Aresium.
    case biometrics
    /// Face ID, with the iPhone's code as the fallback (no own code).
    case biometricsOrIPhoneCode
}

enum LockAuthResult: Equatable {
    case success
    /// The person cancelled, chose the code instead, or iOS took the prompt away.
    case cancelled
    case failed
    /// Not possible on this iPhone now (`noIPhoneCode`: the iPhone has no code at all).
    case unavailable(noIPhoneCode: Bool)
}

enum Biometry: Equatable {
    case faceID, touchID, opticID, none
}

/// iOS's Face ID / Touch ID and code prompts, behind a protocol so tests and samples stand in for them.
protocol LockAuthenticator {
    var biometry: Biometry { get }
    func canEvaluate(_ policy: LockPolicy) -> Bool
    func authenticate(_ policy: LockPolicy, reason: String) async -> LockAuthResult
}

struct DeviceAuthenticator: LockAuthenticator {
    var biometry: Biometry {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .none
        }
    }

    func canEvaluate(_ policy: LockPolicy) -> Bool {
        LAContext().canEvaluatePolicy(Self.policy(policy), error: nil)
    }

    func authenticate(_ policy: LockPolicy, reason: String) async -> LockAuthResult {
        let context = LAContext()
        // With an own code the keypad is the fallback, right under the prompt: no "Enter Password" button.
        if policy == .biometrics { context.localizedFallbackTitle = "" }
        do {
            return try await context.evaluatePolicy(Self.policy(policy), localizedReason: reason) ? .success : .failed
        } catch let error as LAError {
            switch error.code {
            case .passcodeNotSet: return .unavailable(noIPhoneCode: true)
            case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout: return .unavailable(noIPhoneCode: false)
            case .authenticationFailed: return .failed
            default: return .cancelled
            }
        } catch {
            return .cancelled
        }
    }

    private static func policy(_ policy: LockPolicy) -> LAPolicy {
        policy == .biometrics ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
    }
}

// MARK: - the lock

/// The lock's state for the whole app (one per launch, `AresiumApp`; a language restart keeps it). The lock window
/// (`LockWindow`) shows `LockScreen` while `isLocked`; Settings changes it through the methods below.
@MainActor @Observable
final class AppLock {
    enum CodeResult: Equatable {
        case right, wrong
        /// Too many wrong codes: nothing was checked.
        case waiting
    }

    private(set) var isLocked = false
    private(set) var faceID = false
    private(set) var hasCode = false
    private(set) var wrong = WrongCodes()
    /// A code is being checked (PBKDF2 takes about a tenth of a second).
    private(set) var isChecking = false
    /// iOS's Face ID or code prompt is up.
    private(set) var isAuthenticating = false
    /// The Keychain could not be read (before the iPhone's first unlock): locked until it can be.
    private(set) var unreadable = false
    var isOn: Bool { faceID || hasCode }

    /// Told when `isLocked` changes (the lock window shows or hides).
    @ObservationIgnored var lockedChanged: ((Bool) -> Void)?
    @ObservationIgnored var messagePrivacyChanged: ((Bool) -> Void)?
    @ObservationIgnored let authenticator: any LockAuthenticator
    @ObservationIgnored private let storage: any LockStorage
    @ObservationIgnored private let marker: LockInstallMarker?
    @ObservationIgnored private let widget: WidgetSnapshotPublisher?
    @ObservationIgnored private let rounds: Int
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var code: LockCodeHash?
    /// When the app went to the background (nil while it is in front).
    @ObservationIgnored private var leftAt: Date?
    /// Face ID was offered once for this lock already (it is not asked again by itself).
    @ObservationIgnored private var offeredBiometrics = false
    private static let log = Logger(subsystem: "de.ares-empire.aresium", category: "lock")

    /// - Parameters:
    ///   - marker: the install marker (nil: tests and samples, which have no earlier install).
    ///   - widget: where the widgets learn that the lock is on (nil: tests and samples).
    ///   - rounds: PBKDF2 rounds for a new code.
    init(storage: any LockStorage, marker: LockInstallMarker?, authenticator: any LockAuthenticator,
         widget: WidgetSnapshotPublisher?, rounds: Int = LockCodeHash.defaultRounds, now: @escaping () -> Date = Date.init) {
        self.storage = storage
        self.marker = marker
        self.authenticator = authenticator
        self.widget = widget
        self.rounds = rounds
        self.now = now
        load()
        isLocked = isOn || unreadable              // locks at launch
    }

    var biometry: Biometry { authenticator.biometry }

    /// Face ID can unlock now (with an own code: Face ID alone; without: Face ID or the iPhone's code).
    var policy: LockPolicy { hasCode ? .biometrics : .biometricsOrIPhoneCode }

    /// Whether the Face ID row can be turned on: the iPhone has a code (Face ID needs one, and it is the fallback).
    var canUseFaceID: Bool { authenticator.canEvaluate(.biometricsOrIPhoneCode) }

    /// How long until the next code may be typed (0: now).
    func remainingWait() -> TimeInterval { wrong.remaining(now: now()) }

    // MARK: reading and saving

    private func load() {
        do {
            var state = try storage.read()
            if state != nil, let marker, !marker.exists {
                try storage.delete()
                state = nil
                Self.log.notice("a lock left by an earlier install was removed")
            }
            apply(state ?? LockState())
            unreadable = false
        } catch {
            Self.log.error("the lock's settings could not be read: \(String(describing: error), privacy: .public)")
            unreadable = true
        }
        if !unreadable { marker?.set(isOn) }
        syncWidget()
    }

    private func apply(_ state: LockState) {
        faceID = state.faceID
        code = state.code
        hasCode = state.code != nil
        wrong = state.wrong
    }

    private var state: LockState { LockState(faceID: faceID, code: code, wrong: wrong) }

    private func save() throws {
        if isOn { try storage.save(state) } else { try storage.delete() }
        marker?.set(isOn)
        syncWidget()
    }

    private func syncWidget() {
        messagePrivacyChanged?(isOn || unreadable)
        guard !unreadable else { return }
        do { try widget?.setLocked(isOn) }
        catch { Self.log.error("the widgets' lock flag was not saved: \(String(describing: error), privacy: .public)") }
    }

    // MARK: locking

    private func setLocked(_ locked: Bool) {
        guard locked != isLocked else { return }
        isLocked = locked
        if locked { offeredBiometrics = false }
        lockedChanged?(locked)
    }

    /// The scene went to the background.
    func enteredBackground() {
        leftAt = now()
    }

    /// The scene comes back from the background, before it is shown: more than 10 seconds away locks again.
    func willEnterForeground() {
        readAgainIfNeeded()
        if (isOn || unreadable) && LockTiming.locksAgain(leftAt: leftAt, now: now()) { setLocked(true) }
        leftAt = nil
    }

    /// The scene is active (shown and taking touches): while locked with Face ID on, Face ID is offered once by itself.
    func becameActive() {
        readAgainIfNeeded()
        guard isLocked, faceID, !offeredBiometrics, !isAuthenticating else { return }
        offeredBiometrics = true
        Task { await unlockWithBiometrics() }
    }

    /// Settings that could not be read at launch are read again; when there is no lock after all, the app opens.
    private func readAgainIfNeeded() {
        guard unreadable else { return }
        load()
        if !unreadable && !isOn { setLocked(false) }
    }

    // MARK: unlocking

    /// Face ID (or, without an own code, the iPhone's code).
    func unlockWithBiometrics() async {
        guard isLocked, faceID, !isAuthenticating else { return }
        isAuthenticating = true
        let result = await authenticator.authenticate(policy, reason: String(localized: "Unlock Aresium"))
        isAuthenticating = false
        switch result {
        case .success:
            unlock()
        case .unavailable(noIPhoneCode: true) where !hasCode:
            // The iPhone has no code any more (removing it needs the code, and turns Face ID off too): nothing here can
            // tell who holds it, so the lock opens rather than locking its owner out of their data.
            Self.log.notice("the lock opens: this iPhone has no code any more")
            unlock()
        default:
            break
        }
    }

    /// A code typed on the lock screen: the right one opens Aresium.
    @discardableResult
    func enterCode(_ typed: String) async -> CodeResult {
        let result = await check(typed)
        if result == .right { unlock() }
        return result
    }

    private func unlock() {
        if wrong.count > 0 {
            wrong = WrongCodes()
            try? save()
        }
        setLocked(false)
    }

    /// Checks a code against the own code, counting wrong ones (the lock screen, and changing or removing the code in
    /// Settings, so neither can be used to try codes faster).
    func check(_ typed: String) async -> CodeResult {
        guard let code, !isChecking else { return .wrong }
        let checked = wrong.clockChecked(now: now())
        if checked != wrong {
            wrong = checked
            try? save()
        }
        guard remainingWait() == 0 else { return .waiting }
        isChecking = true
        let right = await Task.detached { LockCode.isValid(typed) && code.matches(typed) }.value
        isChecking = false
        if right {
            if wrong.count > 0 { wrong = WrongCodes(); try? save() }
            return .right
        }
        wrong = wrong.adding(at: now())
        do { try save() } catch { Self.log.error("the wrong code was not counted: \(String(describing: error), privacy: .public)") }
        return .wrong
    }

    // MARK: Settings

    /// Turns Face ID on or off. Turning it on asks Face ID once (so it is known to work); turning it off while it is the
    /// whole lock asks it too (the lock is not taken away by someone else holding the open app). Returns whether it
    /// changed.
    @discardableResult
    func setFaceID(_ on: Bool) async -> Bool {
        guard on != faceID, !isAuthenticating else { return false }
        if on || !hasCode {
            isAuthenticating = true
            let result = await authenticator.authenticate(policy, reason: on ? String(localized: "Turn on the lock")
                                                                             : String(localized: "Turn off the lock"))
            isAuthenticating = false
            guard result == .success else { return false }
        }
        faceID = on
        do { try save() } catch {
            faceID = !on
            Self.log.error("the Face ID setting was not saved: \(String(describing: error), privacy: .public)")
            return false
        }
        return true
    }

    /// Sets (or replaces) the own code. The caller has checked the current one, if there was one.
    func setCode(_ new: String) async throws {
        guard LockCode.isValid(new) else { throw LockError.invalidCode }
        let rounds = rounds
        let hash = await Task.detached { LockCodeHash.make(new, rounds: rounds) }.value
        let previous = (code, wrong)
        code = hash
        hasCode = true
        wrong = WrongCodes()
        do { try save() } catch {
            (code, wrong) = previous
            hasCode = code != nil
            throw error
        }
    }

    /// Removes the own code (the caller has checked it). With Face ID still on, Face ID with the iPhone's code locks.
    func removeCode() throws {
        let previous = code
        code = nil
        hasCode = false
        wrong = WrongCodes()
        do { try save() } catch {
            code = previous
            hasCode = previous != nil
            throw error
        }
    }

    /// "Forgot the code?": after Aresium's data on this iPhone was deleted, the lock goes too and the app opens.
    func reset() {
        do { try storage.delete() } catch { Self.log.error("the lock was not deleted: \(String(describing: error), privacy: .public)") }
        apply(LockState())
        unreadable = false
        marker?.set(false)
        syncWidget()
        setLocked(false)
    }
}

enum LockError: LocalizedError {
    case invalidCode
    var errorDescription: String? { String(localized: "The code needs 6 digits.") }
}

#if DEBUG
// MARK: - samples

/// iOS's prompts in the samples and tests: never shown; Face ID answers as told.
struct SampleAuthenticator: LockAuthenticator {
    var biometry: Biometry = .faceID
    var available = true
    var answer: LockAuthResult = .cancelled

    func canEvaluate(_ policy: LockPolicy) -> Bool { available }
    func authenticate(_ policy: LockPolicy, reason: String) async -> LockAuthResult { answer }
}

extension AppLock {
    /// The lock for this launch: Aresium's Keychain item, the install marker, iOS's Face ID and the App Group's widget
    /// flag; in tests and samples a lock in memory, off unless `-sampleLock faceID|code|both` (the code is 123456)
    /// asks for one (`-sampleUnlocked`: open at launch, for Settings; `-sampleWrongCodes <n>`: n wrong codes just now).
    static func forLaunch(arguments: [String] = LaunchArguments.current) -> AppLock {
        func value(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        let sample = arguments.contains("-sampleData") || arguments.contains("-samplePhone")
            || arguments.contains("-samplePhoneEmpty")
        guard DebugLaunch.isTesting || sample || arguments.contains("-sampleLock") else { return .device() }
        var state = LockState()
        switch value("-sampleLock") {
        case "faceID": state.faceID = true
        case "code": state.code = LockCodeHash.make("123456", rounds: 1_000)
        case "both":
            state.faceID = true
            state.code = LockCodeHash.make("123456", rounds: 1_000)
        default: break
        }
        if let wrong = value("-sampleWrongCodes").flatMap(Int.init) {
            state.wrong = WrongCodes(count: wrong, last: .now)
        }
        let lock = AppLock(storage: MemoryLockStorage(state.isOn ? state : nil), marker: nil,
                           authenticator: SampleAuthenticator(), widget: nil, rounds: 1_000)
        if arguments.contains("-sampleUnlocked") { lock.setLocked(false) }
        return lock
    }
}
#else
extension AppLock {
    static func forLaunch() -> AppLock { .device() }
}
#endif

extension AppLock {
    /// The real lock: Aresium's Keychain item, the install marker, iOS's Face ID, the widgets' flag.
    static func device() -> AppLock {
        AppLock(storage: LockKeychain(), marker: .standard, authenticator: DeviceAuthenticator(),
                widget: WidgetSnapshotPublisher())
    }
}
