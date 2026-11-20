import Foundation
import Testing
import WebKit
@testable import Arestia

// The ordinary findings of the trust review's round 5 (Codex gpt-6.2-astra, 2026-11-20), each pinned so it cannot come
// back: a Keychain hiccup, the 3D tab's loading, "Live" after the background, a released blind, Cooking's failures, and
// a Blind control or Shortcut whose blind the flat does not have.

/// A connection on an in-memory Keychain the test can make fail.
private func flakyConnection() throws -> (FlatdConnection, MemoryKeys) {
    let keys = MemoryKeys()
    let connection = FlatdConnection(defaults: UserDefaults(suiteName: "arestia-tests-" + UUID().uuidString)!,
                                     keychain: keys, lock: .processOnly)
    try connection.save(Flat.pairing())
    return (connection, keys)
}

@MainActor
struct KeychainHiccupTests {
    /// A failed Keychain read is not "no pairing": the live loop tries again with its pauses and comes back once the
    /// Keychain answers (it used to stop for good).
    @Test func aKeychainHiccupDoesNotStopTheLiveConnection() async throws {
        let (connection, keys) = try flakyConnection()
        let (store, transport, events, _) = Flat.store(connection: connection)
        transport.answer("GET /api/scenes", body: ["scenes": []])
        store.start()
        #expect(await eventually { events.isOpen })
        events.send(try Flat.snapshot())
        #expect(await eventually { store.link == .live })
        keys.failsToRead = true
        events.end(FlatdError.unreachable)
        #expect(await eventually { store.link != .live })
        try await Task.sleep(for: .milliseconds(1500))                 // at least one reading failed meanwhile
        #expect(!store.isRetired && store.pairingID == Flat.id && store.devices.count == 4)
        keys.failsToRead = false
        #expect(await eventually({ events.isOpen }, timeout: .seconds(6)))
        events.send(try Flat.snapshot())
        #expect(await eventually { store.link == .live })
        // A loop that ended is never mistaken for a running one: stopped and started, it follows flatd again.
        store.stop()
        events.end(CancellationError())
        store.start()
        #expect(await eventually { events.isOpen })
        store.stop()
    }

    /// At launch: the session has no store while the Keychain cannot be read, and builds the right one once it can.
    @Test func aKeychainHiccupAtLaunchIsReadAgain() async throws {
        let (connection, keys) = try flakyConnection()
        keys.failsToRead = true
        let (session, _, _, _) = Flat.session(connection: connection)
        #expect(session.store == nil)
        keys.failsToRead = false
        #expect(await eventually({ session.store != nil }, timeout: .seconds(3)))
        #expect(session.store?.pairingID == Flat.id)
    }

    /// A command while the Keychain cannot be read says so quietly, sends nothing and keeps the pairing.
    @Test func aCommandDuringAKeychainHiccupSaysSo() async throws {
        let (connection, keys) = try flakyConnection()
        let (store, transport, _, _) = Flat.store(connection: connection)
        keys.failsToRead = true
        store.setFan("fan:fan_1", on: true)
        #expect(await eventually { store.offer != nil })
        #expect(store.offer?.message == FlatdError.pairingUnreadable.message())
        #expect(!store.isRetired && !store.isWorking("power:fan:fan_1"))
        #expect(transport.sent.isEmpty)
        keys.failsToRead = false
        #expect(connection.pairing?.id == Flat.id)
    }
}

@MainActor
struct FlatPageLoadingTests {
    /// The 3D tab never stays on "Loading the flat": without a pairing reading it shows Try again with the reason at
    /// once (it used to return before the deadline or the card was set up).
    @Test func thePageWithoutAPairingReadingShowsTryAgain() throws {
        let (connection, keys) = try flakyConnection()
        let (store, _, _, _) = Flat.store(connection: connection)
        let page = FlatPage()
        let coordinator = FlatWebView.Coordinator(store: store, page: page)
        let webView = WKWebView()
        coordinator.webView = webView
        keys.failsToRead = true
        coordinator.load("0-0")
        #expect(page.problem == FlatdError.pairingUnreadable.message() && !page.isReady)
        // Try again once the Keychain answers: loading, the card gone.
        keys.failsToRead = false
        page.reload()
        coordinator.load("1-0")
        #expect(page.problem == nil)
        coordinator.retire()
        _ = webView
    }

    /// A page fetched with the old key whose refusal arrives after a fresh code of the flat began another load is not
    /// shown ("Pair again" over a working pairing).
    @Test func anOldKeysRefusalAfterANewLoadIsNotShown() async throws {
        let (store, transport, _, _) = Flat.store()
        transport.answer("GET /viewer", status: 401, body: ["error": "wrong token"], delay: .milliseconds(200))
        let page = FlatPage()
        let coordinator = FlatWebView.Coordinator(store: store, page: page)
        let webView = WKWebView()
        coordinator.webView = webView
        coordinator.load("0-0")
        try await Task.sleep(for: .milliseconds(50))                    // the old key's fetch is out
        transport.answer("GET /viewer", body: ["page": "made up"], delay: .seconds(5))   // the new key's fetch, slow
        coordinator.load("0-1")                                         // what `store.credentials` changing does
        try await Task.sleep(for: .milliseconds(500))
        #expect(page.problem == nil)
        coordinator.retire()
        _ = webView
    }

    /// The page's load follows a fresh code of the flat (`credentials` is part of what loads it).
    @Test func aFreshCodeLoadsThePageAgain() async throws {
        let connection = Flat.connection()
        let (store, transport, _, _) = Flat.store(connection: connection)
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1)]])
        let before = store.credentials
        #expect(await store.connect(to: Flat.base, token: Flat.renewedKey, pin: Flat.pin) == nil)
        #expect(store.credentials == before + 1)
        store.stop()
    }
}

@MainActor
struct LiveAfterBackgroundTests {
    func liveStore() async throws -> (FlatStore, FakeTransport, FakeEvents) {
        let (store, transport, events, _) = Flat.store()
        transport.answer("GET /api/scenes", body: ["scenes": []])
        store.start()
        #expect(await eventually { events.isOpen })
        events.send(try Flat.snapshot())
        #expect(await eventually { store.link == .live })
        return (store, transport, events)
    }

    /// Back from the background the last state shows as "Reconnecting", not "Live", until flatd's new snapshot.
    @Test func backFromTheBackgroundIsNotLiveUntilFlatdSaysSo() async throws {
        let (store, _, events) = try await liveStore()
        store.stop()                                                    // the app went to the background
        events.end(CancellationError())
        #expect(store.link == .connecting && store.isReconnecting && store.hasSnapshot)
        store.start()                                                   // back in the foreground
        #expect(await eventually { events.isOpen })
        #expect(store.link != .live)
        events.send(try Flat.snapshot())
        #expect(await eventually { store.link == .live && !store.isReconnecting })
        store.stop()
    }

    /// The stream cut while open: "Reconnecting" at once, not "Live" through the quick retry.
    @Test func aCutStreamIsReconnectingAtOnce() async throws {
        let (store, transport, events) = try await liveStore()
        transport.answer("GET /api/health", fails: true)
        events.end(FlatdError.unreachable)
        #expect(await eventually({ store.link != .live }, timeout: .milliseconds(300)))
        #expect(store.isReconnecting || store.link == .offline)
        store.stop()
    }
}

@MainActor
struct ReleasedBlindTests {
    func liveStore() async throws -> (FlatStore, FakeTransport, FakeEvents) {
        let (store, transport, events, _) = Flat.store()
        transport.answer("GET /api/scenes", body: ["scenes": []])
        store.start()
        #expect(await eventually { events.isOpen })
        events.send(try Flat.snapshot())
        #expect(await eventually { store.link == .live })
        return (store, transport, events)
    }

    /// Let go at 100 %: shown as sent ("Sending: closed"), never as "Closed", until flatd answered; then flatd's state.
    @Test func aReleasedBlindIsSendingUntilFlatdAnswers() async throws {
        let (store, transport, _) = try await liveStore()
        let blind = try #require(store.device("rollo:blind_1"))
        transport.answer("POST /api/devices/rollo:blind_1", body: Flat.rollo(1, position: 60, moving: "down",
                                                                             target: 100, favourite: 60),
                         delay: .milliseconds(300))
        store.drag("rollo:blind_1", to: 100)
        store.setRollo("rollo:blind_1", position: 100)
        #expect(store.dragging["rollo:blind_1"] == nil && store.pending["rollo:blind_1"] == 100)
        #expect(store.shownPosition(of: blind) == 100)
        #expect(FlatWords.rolloPending(100) == "Sending: closed")
        #expect(await eventually { store.pending["rollo:blind_1"] == nil })
        let answered = try #require(store.device("rollo:blind_1"))
        #expect(FlatWords.rolloStatus(answered.state) == "Going down")
        store.stop()
    }

    /// A send that fails puts flatd's position back, with the reason in the line at the bottom.
    @Test func aFailedSendPutsFlatdsPositionBack() async throws {
        let (store, transport, _) = try await liveStore()
        transport.answer("POST /api/devices/rollo:blind_1", status: 504, body: ["error": "timeout"])
        store.setRollo("rollo:blind_1", position: 100)
        #expect(await eventually { store.pending["rollo:blind_1"] == nil })
        let blind = try #require(store.device("rollo:blind_1"))
        #expect(store.shownPosition(of: blind) == 60)
        #expect(store.offer?.message == FlatdError.deviceDidNotAnswer.message())
        store.stop()
    }

    @Test func thePendingWords() {
        #expect(FlatWords.rolloPending(0) == "Sending: open")
        #expect(FlatWords.rolloPending(40) == "Sending: 40\u{202F}% closed")
        #expect(FlatWords.rolloPending(40, language: .german) == "Wird gesendet: 40\u{202F}% zu")
    }
}

struct CookingFailureTests {
    let transport = FakeTransport()

    func actions(_ connection: FlatdConnection) -> FlatActions {
        FlatActions(reach: FlatdReach(connection: connection, transport: transport, rediscover: { [] }))
    }

    var active: [String: Any] {
        var mode = Flat.cooking
        mode["active"] = true
        return mode
    }

    /// The Cooking control's action keeps the devices that did not follow, by name; its state shows them while they
    /// still describe cooking; a change where all followed clears them.
    @Test func theCookingControlReflectsDevicesThatDidNotFollow() async throws {
        let connection = Flat.connection()
        connection.remember(try Flat.devices([Flat.fan(1), Flat.fan(2)]), for: Flat.id)
        transport.answer("GET /api/modes", body: ["modes": [Flat.cooking]])
        transport.answer("POST /api/modes/cooking", body: active.merging(["failed": ["fan:fan_2": "timeout"]]) { $1 })
        let change = try await actions(connection).setCooking(true)
        #expect(change == CookingChange(isActive: true, failed: ["Fan 2"]))
        transport.answer("GET /api/modes", body: ["modes": [active]])
        #expect(try await actions(connection).cookingState() == CookingState(active: true, notFollowed: ["Fan 2"]))
        // Ended elsewhere since (the state differs): the old trouble no longer describes cooking.
        transport.answer("GET /api/modes", body: ["modes": [Flat.cooking]])
        #expect(try await actions(connection).cookingState().notFollowed.isEmpty)
        // A change where every device followed clears it.
        transport.answer("POST /api/modes/cooking", body: Flat.cooking.merging(["failed": [:]]) { $1 })
        _ = try await actions(connection).setCooking(false)
        #expect(connection.trouble(mode: "cooking", active: true, pairing: Flat.id) == nil)
    }

    /// The dialogs say only what flatd's answer confirmed: no reading before, no claims about the devices.
    @Test func cookingsDialogIsFlatdsAnswer() async throws {
        let connection = Flat.connection()
        transport.answer("POST /api/modes/cooking", body: Flat.cooking.merging(["failed": [:]]) { $1 })
        let change = try await actions(connection).setCooking(false)
        #expect(change == CookingChange(isActive: false, failed: []))
        #expect(CookingDialog.text(change) == "Cooking is off.")
        #expect(CookingDialog.text(CookingChange(isActive: true, failed: ["Fan 2"])) == "Cooking is on. Didn't answer: Fan 2.")
        #expect(transport.sent.allSatisfy { $0.url?.path() != "/api/modes" })      // nothing read before the command
    }

    /// Kept only for the paired flat, for the state it describes, and for a while.
    @Test func aTroubleNoteBelongsToItsPairingAndState() throws {
        let connection = Flat.connection()
        let now = Date.now
        connection.note(ModeTrouble(pairing: UUID(), mode: "cooking", active: true, names: ["Fan 2"], at: now))
        #expect(connection.trouble(mode: "cooking", active: true, pairing: Flat.id) == nil)   // another pairing's: not kept
        connection.note(ModeTrouble(pairing: Flat.id, mode: "cooking", active: true, names: ["Fan 2"], at: now))
        #expect(connection.trouble(mode: "cooking", active: true, pairing: Flat.id)?.names == ["Fan 2"])
        #expect(connection.trouble(mode: "cooking", active: false, pairing: Flat.id) == nil)
        #expect(connection.trouble(mode: "cooking", active: true, pairing: Flat.id,
                                   now: now + ModeTrouble.lasts + 1) == nil)
        try connection.forget()
        try connection.save(Flat.pairing())
        #expect(connection.trouble(mode: "cooking", active: true, pairing: Flat.id) == nil)    // Forget wiped it
    }

    /// The app says it once, when it next hears flatd; the control goes on showing it (the note stays, said).
    @Test @MainActor func theAppSaysOnceWhatDidNotFollowOutsideIt() async throws {
        let connection = Flat.connection()
        connection.note(ModeTrouble(pairing: Flat.id, mode: "cooking", active: true, names: ["Fan 2"], at: .now))
        let (store, transport, events, _) = Flat.store(connection: connection)
        transport.answer("GET /api/scenes", body: ["scenes": []])
        store.start()
        #expect(await eventually { events.isOpen })
        events.send(try Flat.snapshot(cookingActive: true))
        #expect(await eventually { store.offer != nil })
        #expect(store.offer?.message == "Cooking was started outside the app. Didn't answer: Fan 2.")
        let kept = try #require(connection.trouble(mode: "cooking", active: true, pairing: Flat.id))
        #expect(connection.hasSaid(kept))
        // Said once: the next snapshot says nothing again.
        store.offer = nil
        events.send(try Flat.snapshot(cookingActive: true))
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.offer == nil)
        store.stop()
    }

    /// While the app follows flatd, a trouble a control keeps after flatd's mode event is said at once (the Darwin
    /// notification), not only at the next reconnect.
    @Test @MainActor func aTroubleKeptWhileLiveIsSaidAtOnce() async throws {
        let connection = Flat.connection()
        let (store, transport, events, _) = Flat.store(connection: connection)
        transport.answer("GET /api/scenes", body: ["scenes": []])
        store.start()
        #expect(await eventually { events.isOpen })
        events.send(try Flat.snapshot(cookingActive: false))
        #expect(await eventually { store.link == .live })
        events.send(.mode(FlatMode(id: "cooking", label: "Cooking", active: true, since: .now)))
        #expect(await eventually { store.isCooking })
        #expect(store.offer == nil)
        connection.note(ModeTrouble(pairing: Flat.id, mode: "cooking", active: true, names: ["Fan 2"], at: .now))
        #expect(await eventually { store.offer?.message == "Cooking was started outside the app. Didn't answer: Fan 2." })
        store.stop()
    }

    /// A late answer of a forgotten flat never clears the next flat's trouble, nor keeps one of its own.
    @Test func aForgottenFlatsLateAnswerLeavesTheNextFlatsTroubleAlone() throws {
        let connection = Flat.connection()
        let old = Flat.id
        try connection.forget()
        let next = Flat.pairing(id: UUID())
        #expect(try connection.pairNew(next))
        connection.note(ModeTrouble(pairing: next.id, mode: "cooking", active: true, names: ["Fan 1"], at: .now))
        connection.clearTrouble(mode: "cooking", pairing: old, now: false)   // the old flat's answer, late
        connection.note(ModeTrouble(pairing: old, mode: "cooking", active: true, names: ["Fan 9"], at: .now))
        #expect(connection.trouble(mode: "cooking", active: true, pairing: next.id)?.names == ["Fan 1"])
    }
}

struct GoneDeviceTests {
    let transport = FakeTransport()

    func actions(_ connection: FlatdConnection = Flat.connection()) -> FlatActions {
        FlatActions(reach: FlatdReach(connection: connection, transport: transport, rediscover: { [] }))
    }

    /// The Blind control never shows the preview's state or a gone blind's old name as live.
    @Test func theBlindControlSaysWhatItHas() async throws {
        transport.answer("GET /api/devices", body: ["devices": [Flat.rollo(1, position: 100)]])
        #expect(try await actions().rolloControl(nil) == .notChosen)
        #expect(try await actions().rolloControl(SavedDevice.id(for: "rollo:blind_2", of: Flat.id)) == .gone)
        #expect(try await actions().rolloControl(SavedDevice.id(for: "rollo:blind_1", of: UUID())) == .gone)
        #expect(try await actions().rolloControl(SavedDevice.id(for: "rollo:blind_1", of: Flat.id))
                == .blind(name: "Blind 1", isOpen: false))
        // There, but with no position read yet (or offline): unknown, never Up.
        var unread = Flat.rollo(1)
        unread["state"] = ["position": NSNull(), "moving": NSNull(), "online": true]
        transport.answer("GET /api/devices", body: ["devices": [unread]])
        #expect(try await actions().rolloControl(SavedDevice.id(for: "rollo:blind_1", of: Flat.id))
                == .unknown(name: "Blind 1"))
    }

    /// A blind flatd no longer has (404) fails cleanly with the app's words, as one chosen before Forget does.
    @Test func aBlindTheFlatNoLongerHasFailsCleanly() async throws {
        transport.answer("POST /api/devices/rollo:blind_9", status: 404, body: ["error": "unknown device"])
        await #expect(throws: ChosenDeviceGone.blind) {
            try await actions().move(rollo: SavedDevice.id(for: "rollo:blind_9", of: Flat.id), .up)
        }
        #expect(FlatIntentError(ChosenDeviceGone.blind).message == "This blind isn't in your flat anymore. Choose it again.")
        #expect(FlatIntentError(ChosenDeviceGone.fan).message == "This fan isn't in your flat anymore. Choose it again.")
        // A fan chosen that the flat no longer lists switches nothing, not even the others.
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1)]])
        await #expect(throws: ChosenDeviceGone.fan) {
            try await actions().setFans(on: true, only: [SavedDevice.id(for: "fan:fan_2", of: Flat.id)])
        }
        #expect(transport.bodies(for: "POST /api/devices/fan:fan_1").isEmpty)
    }
}
