import Foundation
import Testing
@testable import Arestia

// The trust review's round 7 (Codex gpt-6.2-astra, 2026-11-20): the dispatch lock fails closed and works across
// processes (a file, flock); a blind's commands reach flatd in the order given; the renewal and the stream start inside
// the gate; a Shortcut's answer counts only while its pairing is saved; Cooking's trouble survives a no-op end and is
// said after a late mode event.

/// A lock file of the test's own.
private func lockFile() -> String {
    FileManager.default.temporaryDirectory.appending(path: "arestia-\(UUID().uuidString).lock").path(percentEncoded: false)
}

struct DispatchLockTests {
    /// Without its file, the lock runs nothing: no request starts, Forget does not report done.
    @Test func theLockFailsClosed() async throws {
        let transport = FakeTransport()
        let connection = FlatdConnection(defaults: nil, names: nil, keychain: MemoryKeys(),
                                         lock: FlatdDispatchLock(path: "/nonexistent-arestia-folder/dispatch.lock"))
        try connection.save(Flat.pairing())
        let client = FlatdClient(Flat.pairing(), transport: transport).gated(by: connection)
        await #expect(throws: FlatdError.pairingUnreadable) { _ = try await client.devices() }
        #expect(transport.sent.isEmpty)
        await #expect(throws: (any Error).self) { try await connection.forgetSavedPairing() }
        #expect(connection.pairing?.id == Flat.id)                      // not forgotten: Forget says it failed
    }

    /// Two holders of the same file, as the app and its extension are: one waits for the other. Checked by order, not
    /// by time (a slow test machine woke late and measured a shorter wait): the second holder gets the lock only once
    /// the first one's work is done.
    @Test func theLockFileIsSharedBetweenHolders() async throws {
        let path = lockFile()
        let app = FlatdDispatchLock(path: path), controls = FlatdDispatchLock(path: path)
        let holding = Latch(), done = Latch()
        let cap = Deadline(after: .seconds(2))
        let holder = Task {
            try await cap.blocking { hold in
                try app.withLock(until: cap, hold: hold) {
                    holding.open()
                    Thread.sleep(forTimeInterval: 0.2)
                    done.open()
                }
            }
        }
        defer { holder.cancel() }
        try #require(await eventually { holding.isOpen })
        try await cap.blocking { hold in
            try controls.withLock(until: cap, hold: hold) {
                #expect(done.isOpen)
            }
        }
        try await holder.value
    }
}

/// Opens once, from any thread.
private nonisolated final class Latch: @unchecked Sendable {
    private let condition = NSCondition()
    private var opened = false
    func open() { condition.lock(); opened = true; condition.broadcast(); condition.unlock() }
    var isOpen: Bool { condition.lock(); defer { condition.unlock() }; return opened }
}

@MainActor
struct BlindOrderTests {
    func liveStore() async throws -> (FlatStore, FakeTransport, FakeEvents) {
        let (store, transport, events, _) = Flat.store()
        transport.answer("GET /api/scenes", body: ["scenes": []])
        store.start()
        #expect(await eventually { events.isOpen })
        events.send(try Flat.snapshot())
        #expect(await eventually { store.link == .live })
        return (store, transport, events)
    }

    func blindCommands(_ transport: FakeTransport) -> [String] {
        transport.sent.filter { $0.httpMethod == "POST" && $0.url?.path() == "/api/devices/rollo:blind_2" }
            .compactMap { request in
                request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                    .map { body in (body["command"] as? String) ?? "position \(body["position"] ?? "?")" }
            }
    }

    /// Let go, let go again, Stop: flatd gets the first position, then Stop; the waiting position is never sent, and
    /// Stop never arrives before the movement it stops.
    @Test func aBlindsCommandsArriveInOrderAndStopSupersedesWaitingOnes() async throws {
        let (store, transport, _) = try await liveStore()
        transport.answer("POST /api/devices/rollo:blind_2", body: Flat.rollo(2, moving: "down", target: 40),
                         delay: .milliseconds(200))
        store.setRollo("rollo:blind_2", position: 40)
        try await Task.sleep(for: .milliseconds(50))                   // the first position is out
        store.setRollo("rollo:blind_2", position: 85)
        store.moveRollo("rollo:blind_2", .stop)
        try await Task.sleep(for: .milliseconds(80))
        #expect(blindCommands(transport) == ["position 40"])           // Stop waits for the movement before it
        #expect(await eventually({ blindCommands(transport).count == 2 }, timeout: .seconds(3)))
        try await Task.sleep(for: .milliseconds(300))
        #expect(blindCommands(transport) == ["position 40", "stop"])
        #expect(store.pending["rollo:blind_2"] == nil)
        store.stop()
    }

    /// Positions given and then Stop before any went out: only Stop is sent (nothing was moving yet).
    @Test func stopBeforeAnythingWentOutSendsOnlyStop() async throws {
        let (store, transport, _) = try await liveStore()
        transport.answer("POST /api/devices/rollo:blind_2", body: Flat.rollo(2))
        store.setRollo("rollo:blind_2", position: 40)
        store.setRollo("rollo:blind_2", position: 85)
        store.moveRollo("rollo:blind_2", .stop)
        #expect(await eventually { !blindCommands(transport).isEmpty })
        try await Task.sleep(for: .milliseconds(200))
        #expect(blindCommands(transport) == ["stop"])
        #expect(store.pending["rollo:blind_2"] == nil)
        store.stop()
    }
}

@MainActor
struct GatedStartTests {
    private struct ForgetBeforeStart: PreparingTransport {
        let connection: FlatdConnection
        let transport: FakeTransport

        func prepare(_ request: URLRequest, reply: Attempt<HTTPReply>) throws -> any SuspendedRequest {
            if request.value(forHTTPHeaderField: "Authorization") != nil {
                // Preparation already runs on a worker. Forget before launch enters admission.
                let cap = Deadline(after: .seconds(5))
                try connection.forget(Attempt<Void>(until: cap), lockBy: cap)
            }
            return try transport.prepare(request, reply: reply)
        }
    }

    @Test func renewalCannotStartAfterForgetBetweenEarlyCheckAndDispatch() async throws {
        let connection = Flat.connection()
        let transport = FakeTransport()
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1)]])
        let store = FlatStore(pairing: connection.pairing, connection: connection,
                              transport: ForgetBeforeStart(connection: connection, transport: transport),
                              reloadControls: {})
        #expect(await store.connect(to: Flat.base, token: Flat.renewedKey, pin: Flat.pin) == .notPaired)
        #expect(transport.sent.map { $0.url?.path() } == ["/api/health"])
        #expect(connection.pairing == nil)
    }

    @Test(arguments: [true, false]) func productionDispatchStopsWaitingForHeldLock(fileLock: Bool) async throws {
        let path = Flat.nameFile().url.deletingLastPathComponent().appending(path: "dispatch.lock").path()
        let lock = fileLock ? FlatdDispatchLock(path: path) : .processOnly
        let holder = fileLock ? FlatdDispatchLock(path: path) : lock
        let connection = FlatdConnection(defaults: nil, names: nil, keychain: MemoryKeys(), lock: lock)
        let pairing = Flat.pairing(at: URL(string: "https://127.0.0.1:0")!)
        try connection.save(pairing)

        let (held, notifyHeld) = AsyncStream<Bool>.makeStream()
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let holding = Task {
            defer { notifyHeld.finish() }
            do {
                let cap = Deadline(after: .seconds(3))
                try await cap.blocking { hold in
                    try holder.withLock(until: cap, hold: hold) {
                        notifyHeld.yield(true)
                        _ = release.wait(timeout: .now() + 2)
                    }
                }
            } catch {
                notifyHeld.yield(false)
            }
        }
        defer { holding.cancel() }
        var heldIterator = held.makeAsyncIterator()
        try #require(await heldIterator.next() == true)

        var client = FlatdClient(pairing).gated(by: connection)
        client.commandTimeout = 0.25
        let action = FlatdActionDispatch()
        client.action = action
        let start = ContinuousClock().now
        await #expect(throws: FlatdError.unreachable) {
            try await client.setMode(FlatMode.cookingID, active: true)
        }
        #expect(start.duration(to: ContinuousClock().now) < .seconds(1))
        #expect(!action.writeStarted)
    }

    /// A fresh code of the flat asks flatd with its key only while the flat is still the saved one.
    @Test func aRenewalOfAForgottenFlatAsksNothingWithTheKey() async throws {
        let connection = Flat.connection()
        let (store, transport, _, _) = Flat.store(connection: connection)
        transport.answer("GET /api/health", body: ["ok": true, "version": "1.2.0-test"], delay: .milliseconds(200))
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1)]])
        let renewal = Task { await store.connect(to: Flat.base, token: Flat.renewedKey, pin: Flat.pin) }
        try await Task.sleep(for: .milliseconds(50))
        try await connection.forgetSavedPairing()
        #expect(await renewal.value == .notPaired)
        #expect(transport.sent.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
    }

    /// The event stream (the key in its header) opens only inside the gate.
    @Test func theStreamDoesNotOpenForAForgottenFlat() async throws {
        let connection = Flat.connection()
        let (store, transport, events, _) = Flat.store(connection: connection)
        transport.answer("GET /api/scenes", body: ["scenes": []], delay: .milliseconds(200))
        store.start()
        try await Task.sleep(for: .milliseconds(80))                   // the scenes are on their way
        try await connection.forgetSavedPairing()
        try await Task.sleep(for: .milliseconds(400))
        #expect(events.requests.isEmpty)
        store.stop()
    }
}

struct ShortcutAnswerTests {
    let transport = FakeTransport()

    /// A confirmed Forget overrides a write's reply. An unreadable pairing leaves a confirmed write intact.
    @Test func anAnswerCountsOnlyWhileItsPairingIsSaved() async throws {
        let keys = MemoryKeys()
        let connection = FlatdConnection(defaults: nil, names: nil, keychain: keys, lock: .processOnly)
        try connection.save(Flat.pairing())
        transport.answer("POST /api/scenes/all_down", status: 404, body: ["error": "unknown scene"],
                         delay: .milliseconds(200))
        let reach = FlatdReach(connection: connection, transport: transport, rediscover: { [] })
        let refused = Task { try await FlatActions(reach: reach).runScene("all_down") }
        try await Task.sleep(for: .milliseconds(80))
        try await connection.forgetSavedPairing()
        await #expect(throws: FlatdError.notPaired) { _ = try await refused.value }

        try connection.save(Flat.pairing())
        transport.answer("POST /api/scenes/all_down", body: ["id": "all_down", "failed": [:]], delay: .milliseconds(200))
        let unvouched = Task { try await FlatActions(reach: reach).runScene("all_down") }
        try await Task.sleep(for: .milliseconds(80))
        keys.failsToRead = true
        #expect(try await unvouched.value.isEmpty)
    }
}

struct CookingTroubleTests {
    let transport = FakeTransport()

    /// A second End cooking (flatd sends no device commands for it) leaves the first one's trouble standing.
    @Test func aNoOpEndKeepsTheTroubleOfTheRealEnd() async throws {
        let connection = Flat.connection()
        try? await connection.note(ModeTrouble(pairing: Flat.id, mode: "cooking", active: false, names: ["Fan 2"], at: .now))
        transport.answer("POST /api/modes/cooking", body: Flat.cooking.merging(["failed": [:]]) { $1 })
        let reach = FlatdReach(connection: connection, transport: transport, rediscover: { [] })
        _ = try await FlatActions(reach: reach).setCooking(false)
        #expect(connection.trouble(mode: "cooking", active: false, pairing: Flat.id)?.names == ["Fan 2"])
        // Starting cooking (a real change) where all followed clears it.
        var active = Flat.cooking
        active["active"] = true
        transport.answer("POST /api/modes/cooking", body: active.merging(["failed": [:]]) { $1 })
        _ = try await FlatActions(reach: reach).setCooking(true)
        #expect(connection.trouble(mode: "cooking", active: false, pairing: Flat.id) == nil)
    }

    /// The trouble kept before the app heard the mode change: said when the mode event arrives.
    @Test @MainActor func aTroubleKeptBeforeTheModeEventIsSaidWithIt() async throws {
        let connection = Flat.connection()
        let (store, transport, events, _) = Flat.store(connection: connection)
        transport.answer("GET /api/scenes", body: ["scenes": []])
        store.start()
        #expect(await eventually { events.isOpen })
        events.send(try Flat.snapshot(cookingActive: false))
        #expect(await eventually { store.link == .live })
        try? await connection.note(ModeTrouble(pairing: Flat.id, mode: "cooking", active: true, names: ["Fan 2"], at: .now))
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.offer == nil)                                     // cooking is still off here: not yet
        events.send(.mode(FlatMode(id: "cooking", label: "Cooking", active: true, since: .now)))
        #expect(await eventually { store.offer?.message == "Cooking was started outside the app. Didn't answer: Fan 2." })
        store.stop()
    }
}
