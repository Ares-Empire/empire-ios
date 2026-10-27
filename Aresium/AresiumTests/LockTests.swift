import Foundation
import Testing
@testable import Aresium

/// The optional lock (`AppLock`, brief 22): the code's salted hash and its check, the wrong-code waits (kept over a
/// restart), when it locks, Face ID, the install marker, the widgets' flag, and setting, changing and removing the code.
@MainActor
struct LockTests {
    /// A clock the tests move by hand.
    final class Clock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    /// A lock in memory (few rounds, so tests are quick), its storage and clock.
    private func makeLock(_ state: LockState? = nil, answer: LockAuthResult = .success, available: Bool = true,
                      storage: MemoryLockStorage? = nil, clock: Clock = Clock(),
                      widget: WidgetSnapshotPublisher? = nil) -> (AppLock, MemoryLockStorage, Clock) {
        let storage = storage ?? MemoryLockStorage(state)
        let lock = AppLock(storage: storage, marker: nil,
                           authenticator: SampleAuthenticator(available: available, answer: answer),
                           widget: widget, rounds: 1_000, now: { clock.now })
        return (lock, storage, clock)
    }

    private func withCode(_ code: String = "123456", faceID: Bool = false) -> LockState {
        LockState(faceID: faceID, code: LockCodeHash.make(code, rounds: 1_000))
    }

    // MARK: the code's hash

    @Test func theCodeIsKeptAsASaltedHashAndChecked() {
        #expect(LockCodeHash.defaultRounds >= 200_000)
        let one = LockCodeHash.make("482913", rounds: 2_000)
        let two = LockCodeHash.make("482913", rounds: 2_000)
        #expect(one.salt.count == 16 && one.hash.count == 32 && one.rounds == 2_000)
        #expect(one.salt != two.salt && one.hash != two.hash)          // a new salt each time
        #expect(one.matches("482913") && !one.matches("482914") && !one.matches(""))
        let encoded = String(decoding: (try? JSONEncoder().encode(one)) ?? Data(), as: UTF8.self)
        #expect(!encoded.contains("482913"))                           // the code itself is nowhere
        // PBKDF2-HMAC-SHA256 as RFC 7914's test vector has it ("passwd", "salt", 1 round, first 32 bytes).
        let vector = LockCodeHash.derive("passwd", salt: Data("salt".utf8), rounds: 1)
        #expect(vector.map { String(format: "%02x", $0) }.joined()
                == "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc")
    }

    @Test func aCodeIsSixDigits() {
        #expect(LockCode.isValid("012345") && !LockCode.isValid("12345") && !LockCode.isValid("1234567")
                && !LockCode.isValid("12a456") && !LockCode.isValid("١٢٣٤٥٦"))
        var entry = CodeEntry()
        for digit in "1234567x" { entry.type(digit) }
        #expect(entry.digits == "123456" && entry.isComplete)
        entry.delete()
        #expect(entry.digits == "12345" && !entry.isComplete)
    }

    // MARK: wrong codes

    @Test func wrongCodesWaitOneFiveFifteenThenSixtyMinutes() {
        #expect((0...4).map(WrongCodes.wait(after:)) == [0, 0, 0, 0, 0])
        #expect([5, 6, 7, 8, 12].map(WrongCodes.wait(after:)) == [60, 300, 900, 3600, 3600])
        let last = Date(timeIntervalSince1970: 1_000)
        let five = WrongCodes(count: 5, last: last)
        #expect(five.remaining(now: last) == 60 && five.remaining(now: last.addingTimeInterval(45)) == 15)
        #expect(five.remaining(now: last.addingTimeInterval(61)) == 0)
        #expect(WrongCodes(count: 4, last: last).remaining(now: last) == 0)
        // A clock set back before the last wrong code: the wait counts from now, never longer than its own length.
        let back = last.addingTimeInterval(-86_400)
        let checked = five.clockChecked(now: back)
        #expect(checked.last == back && checked.remaining(now: back) == 60)
        #expect(five.clockChecked(now: last.addingTimeInterval(5)) == five)
    }

    @Test func wrongCodesCountAndSurviveARestart() async {
        let (first, storage, clock) = makeLock(withCode())
        for _ in 0..<4 { #expect(await first.enterCode("000000") == .wrong) }
        #expect(first.isLocked && first.remainingWait() == 0)
        #expect(await first.enterCode("000000") == .wrong)              // the 5th: one minute
        #expect(first.remainingWait() == 60)
        #expect(await first.enterCode("123456") == .waiting && first.isLocked)   // not even the right one now
        // A restart: a new lock from the same storage keeps the count and the wait.
        let (again, _, _) = makeLock(storage: storage, clock: clock)
        #expect(again.isLocked && again.wrong.count == 5 && again.remainingWait() == 60)
        clock.advance(61)
        #expect(await again.enterCode("111111") == .wrong && again.remainingWait() == 300)   // the 6th: five minutes
        clock.advance(301)
        #expect(await again.enterCode("123456") == .right && !again.isLocked)
        #expect(again.wrong == WrongCodes() && storage.state?.wrong == WrongCodes())
    }

    // MARK: when it locks

    @Test func itLocksAfterMoreThanTenSecondsAwayOnly() {
        let left = Date(timeIntervalSince1970: 5_000)
        #expect(!LockTiming.locksAgain(leftAt: nil, now: left))                    // only inactive, never away
        #expect(!LockTiming.locksAgain(leftAt: left, now: left.addingTimeInterval(10)))
        #expect(LockTiming.locksAgain(leftAt: left, now: left.addingTimeInterval(10.5)))
        #expect(LockTiming.locksAgain(leftAt: left, now: left.addingTimeInterval(-60)))   // the clock went back
    }

    @Test func theLockClosesAtLaunchAndAfterTenSecondsInTheBackground() async {
        let (open, _, _) = makeLock()                                       // off: never locks
        #expect(!open.isOn && !open.isLocked)
        open.enteredBackground()
        open.willEnterForeground()
        #expect(!open.isLocked)

        let (lock, _, clock) = makeLock(withCode())
        var changes: [Bool] = []
        lock.lockedChanged = { changes.append($0) }
        #expect(lock.isLocked)                                          // at launch
        #expect(await lock.enterCode("123456") == .right && !lock.isLocked)
        lock.enteredBackground()
        clock.advance(8)
        lock.willEnterForeground()
        #expect(!lock.isLocked)                                         // 8 seconds: still open
        lock.enteredBackground()
        clock.advance(11)
        lock.willEnterForeground()
        #expect(lock.isLocked && changes == [false, true])
    }

    // MARK: Face ID

    @Test func faceIDUnlocksAndIsOfferedOnceByItself() async {
        let (lock, _, _) = makeLock(LockState(faceID: true))
        #expect(lock.isLocked && lock.policy == .biometricsOrIPhoneCode)  // without an own code: the iPhone's code too
        await lock.unlockWithBiometrics()
        #expect(!lock.isLocked)

        let (refused, _, _) = makeLock(LockState(faceID: true), answer: .cancelled)
        await refused.unlockWithBiometrics()
        #expect(refused.isLocked)

        let (both, _, _) = makeLock(withCode(faceID: true))
        #expect(both.policy == .biometrics)                             // with an own code: never the iPhone's code
    }

    @Test func faceIDAloneOpensWhenTheIPhoneHasNoCodeAnyMore() async {
        let (lock, _, _) = makeLock(LockState(faceID: true), answer: .unavailable(noIPhoneCode: true))
        await lock.unlockWithBiometrics()
        #expect(!lock.isLocked)
        // With an own code the code still guards it.
        let (coded, _, _) = makeLock(withCode(faceID: true), answer: .unavailable(noIPhoneCode: true))
        await coded.unlockWithBiometrics()
        #expect(coded.isLocked)
    }

    @Test func turningFaceIDOnAndOffAsksFaceIDFirst() async {
        let (lock, storage, _) = makeLock()
        #expect(await lock.setFaceID(true) && lock.faceID && storage.state?.faceID == true)
        #expect(await lock.setFaceID(false) && !lock.isOn && storage.state == nil)

        let (refused, refusedStorage, _) = makeLock(answer: .cancelled)
        #expect(!(await refused.setFaceID(true)) && !refused.faceID && refusedStorage.state == nil)

        // With an own code, turning Face ID off leaves the code as the lock: nothing to ask.
        let (coded, _, _) = makeLock(withCode(faceID: true), answer: .cancelled)
        #expect(await coded.setFaceID(false) && !coded.faceID && coded.hasCode)
    }

    // MARK: setting, changing, removing the code

    @Test func settingChangingAndRemovingTheCode() async throws {
        let (lock, storage, _) = makeLock()
        let set = LockCodeChange(goal: .set, lock: lock)
        #expect(set.step == .new)
        for digit in "246810" { await set.type(digit) }
        #expect(set.step == .again)
        for digit in "246811" { await set.type(digit) }                 // typed differently: start again
        #expect(set.step == .new && set.problem == .differ && !lock.hasCode)
        for digit in "246810246810" { await set.type(digit) }
        #expect(set.isDone && lock.hasCode && storage.state?.code?.matches("246810") == true)
        #expect(!lock.isLocked)                                         // setting it does not lock the open app

        let change = LockCodeChange(goal: .change, lock: lock)
        #expect(change.step == .current)
        for digit in "000000" { await change.type(digit) }
        #expect(change.problem == .wrongCurrent && change.step == .current && lock.wrong.count == 1)
        for digit in "246810135790135790" { await change.type(digit) }
        #expect(change.isDone && storage.state?.code?.matches("135790") == true && lock.wrong.count == 0)

        let remove = LockCodeChange(goal: .remove, lock: lock)
        for digit in "135790" { await remove.type(digit) }
        #expect(remove.isDone && !lock.hasCode && !lock.isOn && storage.state == nil)
    }

    @Test func changingTheCodeCountsTowardsTheWait() async {
        let (lock, _, _) = makeLock(withCode())
        for _ in 0..<5 { _ = await lock.check("999999") }
        let change = LockCodeChange(goal: .change, lock: lock)
        for digit in "123456" { await change.type(digit) }
        #expect(change.problem == .waiting && change.step == .current)
    }

    // MARK: the widgets and an earlier install

    @Test func theWidgetsShowNoNumbersWhileTheLockIsOn() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "lock-widget-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = WidgetSnapshotStore(directory: root)
        let publisher = WidgetSnapshotPublisher(store: files, reloadTimelines: {})
        try publisher.publish(Dashboard.sample(), phone: true)
        #expect(files.load() != nil && !files.isLocked)
        let (lock, _, _) = makeLock(widget: publisher)
        #expect(await lock.setFaceID(true))
        #expect(files.isLocked && files.load() == nil)                  // the numbers went
        try publisher.publish(Dashboard.sample(), phone: true)
        #expect(files.load() == nil)                                    // and none are kept while it is on
        #expect(await lock.setFaceID(false))
        #expect(!files.isLocked)
        try publisher.publish(Dashboard.sample(), phone: true)
        #expect(files.load()?.phone == true)
    }

    @Test func aLockLeftByAnEarlierInstallIsRemoved() {
        let root = FileManager.default.temporaryDirectory.appending(path: "lock-marker-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = LockInstallMarker(url: root.appending(path: "Aresium/lock-in-use"))
        let storage = MemoryLockStorage(withCode())
        // The Keychain kept the lock, the deleted app's container did not keep the marker: no lock.
        let fresh = AppLock(storage: storage, marker: marker, authenticator: SampleAuthenticator(), widget: nil, rounds: 1_000)
        #expect(!fresh.isOn && !fresh.isLocked && storage.state == nil && !marker.exists)
        // A lock set in this install keeps its marker, and opens locked at the next launch.
        storage.state = withCode()
        marker.set(true)
        let again = AppLock(storage: storage, marker: marker, authenticator: SampleAuthenticator(), widget: nil, rounds: 1_000)
        #expect(again.isOn && again.isLocked && marker.exists)
        again.reset()                                                   // "Forgot the code?" after the data went
        #expect(!again.isOn && !again.isLocked && storage.state == nil && !marker.exists)
    }

    @Test func anUnreadableKeychainKeepsItLockedUntilItCanBeRead() {
        final class Unreadable: LockStorage {
            var fails = true
            var state: LockState?
            func read() throws -> LockState? { if fails { throw KeychainError(status: -25308) }; return state }
            func save(_ state: LockState) throws { self.state = state }
            func delete() throws { state = nil }
        }
        let storage = Unreadable()
        let lock = AppLock(storage: storage, marker: nil, authenticator: SampleAuthenticator(answer: .cancelled),
                           widget: nil, rounds: 1_000)
        #expect(lock.isLocked && lock.unreadable)
        storage.fails = false                                           // the iPhone was unlocked: no lock after all
        lock.becameActive()
        #expect(!lock.isLocked && !lock.unreadable)
    }

    @Test func theKeychainItemIsAresiumsOwnOnTheSimulator() throws {
        let keychain = LockKeychain(service: "de.ares-empire.aresium.lock.tests.\(UUID().uuidString)")
        defer { try? keychain.delete() }
        #expect(keychain.accessGroup.hasSuffix("de.ares-empire.aresium") && !keychain.accessGroup.contains("shared"))
        #expect(try keychain.read() == nil)
        let state = withCode(faceID: true)
        try keychain.save(state)
        #expect(try keychain.read() == state)
        try keychain.delete()
        #expect(try keychain.read() == nil)
    }
}
