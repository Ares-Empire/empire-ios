import Foundation
import Testing
import WebKit
@testable import Arestia

// The trust review's round 6 (Codex gpt-6.2-astra, 2026-11-20), after one flat per install: no request with the key
// starts after Forget, whatever awaited before it, in any process; an outgoing root's store retires; a forgotten flat's
// late answer changes nothing; the 3D tab's fetch and WebKit's reloads are bounded; overlapping blind drags; dialogs.

struct ForgetGateTests {
    let transport = FakeTransport()

    /// A command whose checks all ran before Forget, but whose request starts after it, is never sent: the last check
    /// and the start are one step under the lock Forget takes (`FlatdGate.admit`).
    @Test func aRequestStartingAfterForgetIsNeverSent() async throws {
        let connection = Flat.connection()
        transport.answer("POST /api/devices/fan:fan_1", body: Flat.fan(1, on: true))
        let client = FlatdClient(Flat.pairing(), transport: transport).gated(by: connection)
        try await client.verify()                                      // all checks passed: paired, flatd answers
        try await connection.forgetSavedPairing()
        await #expect(throws: FlatdError.notPaired) { _ = try await client.send(.power(on: true), to: "fan:fan_1") }
        await #expect(throws: FlatdError.notPaired) { _ = try await client.devices() }
        #expect(transport.sent.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        // A new pairing (even with the same flatd and key) is not the old client's: still nothing.
        #expect(try connection.pairNew(Flat.pairing(id: UUID())))
        await #expect(throws: FlatdError.notPaired) { _ = try await client.send(.power(on: true), to: "fan:fan_1") }
        #expect(transport.bodies(for: "POST /api/devices/fan:fan_1").isEmpty)
    }

    /// The Keychain unreadable at the last check: nothing is sent either (and it says why).
    @Test func aRequestWhoseLastCheckCannotReadThePairingIsNotSent() async throws {
        let keys = MemoryKeys()
        let connection = FlatdConnection(defaults: nil, names: nil, keychain: keys, lock: .processOnly)
        try connection.save(Flat.pairing())
        let client = FlatdClient(Flat.pairing(), transport: transport).gated(by: connection)
        keys.failsToRead = true
        await #expect(throws: FlatdError.pairingUnreadable) { _ = try await client.send(.power(on: true), to: "fan:fan_1") }
        #expect(transport.sent.isEmpty)
    }

    /// The fans: Forget after the list was read and checked, before a fan's command starts: no fan is switched.
    @Test func noFanSwitchesAfterForgetEvenWhenTheListWasCheckedBefore() async throws {
        let connection = Flat.connection()
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1), Flat.fan(2)]]) {
            try? await connection.forgetSavedPairing()
        }
        let prepared = Counter2()
        transport.onPrepare = { request in
            if request.httpMethod == "POST" { _ = prepared.next() }
        }
        let reach = FlatdReach(connection: connection, transport: transport, rediscover: { [] })
        await #expect(throws: FlatdError.notPaired) { try await FlatActions(reach: reach).setFans(on: true) }
        #expect(transport.sent.allSatisfy { $0.httpMethod != "POST" })
        #expect(prepared.value == 2)   // both suspended requests were refused at admission
    }

    /// A Shortcut whose request went out before Forget gets no answer of the forgotten flat as its own.
    @Test func aResultOfAForgottenFlatIsDropped() async throws {
        let connection = Flat.connection()
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1)]], delay: .milliseconds(200))
        let reach = FlatdReach(connection: connection, transport: transport, rediscover: { [] })
        let reading = Task { try await reach.run { try await $0.devices() } }
        try await Task.sleep(for: .milliseconds(80))
        try await connection.forgetSavedPairing()
        await #expect(throws: FlatdError.notPaired) { _ = try await reading.value }
    }
}

/// Counts from any thread.
private nonisolated final class Counter2: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int { lock.withLock { count += 1; return count } }
    var value: Int { lock.withLock { count } }
}

@MainActor
struct SessionEndTests {
    /// A root built anew (a language switch) ends its session: the old store retires, so its queued command never
    /// goes out next to the new session's (and a Forget there could not reach it).
    @Test func anOutgoingSessionsStoreRetires() async throws {
        let connection = Flat.connection()
        let (session, transport, _, _) = Flat.session(connection: connection)
        let store = try #require(session.store)
        transport.answer("GET /api/health", body: ["ok": true, "version": "1.2.0-test"], delay: .milliseconds(200))
        transport.answer("POST /api/devices/fan:fan_1", body: Flat.fan(1, on: true))
        store.setFan("fan:fan_1", on: true)
        try await Task.sleep(for: .milliseconds(50))
        session.end()
        #expect(store.isRetired)
        try await Task.sleep(for: .milliseconds(300))
        #expect(transport.bodies(for: "POST /api/devices/fan:fan_1").isEmpty)
    }
}

@MainActor
struct ViewerBoundsTests {
    /// WebKit ending the page's process again and again while it starts: a few reloads, then Try again.
    @Test func aPageThatKeepsEndingWebKitEndsInTryAgain() throws {
        let (store, transport, _, _) = Flat.store()
        transport.answer("GET /viewer", body: ["page": "made up"], delay: .seconds(30))   // never arrives in the test
        let page = FlatPage()
        let coordinator = FlatWebView.Coordinator(store: store, page: page)
        let webView = WKWebView()
        coordinator.webView = webView
        coordinator.load("0-0")
        for _ in 0..<FlatWebView.Coordinator.maxAutomaticReloads {
            coordinator.webViewWebContentProcessDidTerminate(webView)
            #expect(page.problem == nil)
        }
        coordinator.webViewWebContentProcessDidTerminate(webView)
        #expect(page.problem == String(localized: "The 3D flat didn't start."))
        // Try again starts afresh, with its own few reloads.
        page.reload()
        coordinator.load("1-0")
        coordinator.webViewWebContentProcessDidTerminate(webView)
        #expect(page.problem == nil)
        coordinator.retire()
        _ = webView
    }
}

@MainActor
struct OverlappingDragTests {
    func liveStore() async throws -> (FlatStore, FakeTransport, FakeEvents) {
        let (store, transport, events, _) = Flat.store()
        transport.answer("GET /api/scenes", body: ["scenes": []])
        store.start()
        #expect(await eventually { events.isOpen })
        events.send(try Flat.snapshot())
        #expect(await eventually { store.link == .live })
        return (store, transport, events)
    }

    /// Two drags out at once: the first one's movement and answer never clear the second's "Sending".
    @Test func anOlderDragNeverClearsANewerOne() async throws {
        let (store, transport, events) = try await liveStore()
        transport.answer("POST /api/devices/rollo:blind_2", body: Flat.rollo(2, moving: "down", target: 40),
                         delay: .milliseconds(150))
        store.setRollo("rollo:blind_2", position: 40)
        try await Task.sleep(for: .milliseconds(30))                  // the first request is out
        transport.answer("POST /api/devices/rollo:blind_2", body: Flat.rollo(2, moving: "down", target: 85),
                         delay: .milliseconds(500))
        store.setRollo("rollo:blind_2", position: 85)
        // The first one's movement in the stream, then its answer: the second is still being sent.
        events.send(.state(id: "rollo:blind_2", state: DeviceState(fields: ["moving": .string("down"),
                                                                            "target": .number(40)]), source: "device"))
        try await Task.sleep(for: .milliseconds(250))
        #expect(store.pending["rollo:blind_2"] == 85)
        #expect(await eventually { store.pending["rollo:blind_2"] == nil })
        store.stop()
    }

    /// The same position asked twice: the first answer does not clear the second request.
    @Test func anOlderAnswerToTheSamePositionLeavesTheNewerPending() async throws {
        let (store, transport, _) = try await liveStore()
        transport.answer("POST /api/devices/rollo:blind_2", body: Flat.rollo(2, moving: "down", target: 85),
                         delay: .milliseconds(100))
        store.setRollo("rollo:blind_2", position: 85)
        try await Task.sleep(for: .milliseconds(30))
        transport.answer("POST /api/devices/rollo:blind_2", body: Flat.rollo(2, moving: "down", target: 85),
                         delay: .milliseconds(500))
        store.setRollo("rollo:blind_2", position: 85)
        try await Task.sleep(for: .milliseconds(250))
        #expect(store.pending["rollo:blind_2"] == 85)
        #expect(await eventually { store.pending["rollo:blind_2"] == nil })
        store.stop()
    }
}

struct DialogTests {
    /// A scene says what it does only when every device followed.
    @Test func aSceneSaysWhatDidNotFollow() {
        let done = LocalizedStringResource("All blinds are going down.", table: "ArestiaShared")
        #expect(SceneDialog.text(done: done, failed: []) == "All blinds are going down.")
        #expect(SceneDialog.text(done: done, failed: ["Blind 1", "Blind 2"])
                == "Not everything followed. Didn't answer: Blind 1, Blind 2.")
    }

    /// A blind's dialog is flatd's answer: a Stop that leaves it moving is not told as stopped.
    @Test func aBlindsDialogIsFlatdsAnswer() throws {
        let moving = try Flat.decode(Device.self, Flat.rollo(1, position: 95, moving: "up", target: 0))
        #expect(RolloDialog.text(moving) == "Blind 1: Going up.")
        let still = try Flat.decode(Device.self, Flat.rollo(1, position: 40))
        #expect(RolloDialog.text(still) == "Blind 1: 40\u{202F}% closed.")
    }
}
