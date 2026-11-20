import Foundation
import Testing
@testable import Arestia

/// What Codex's review of 2026-11-19 found (round 1), each pinned so it cannot come back.
struct KeySafetyTests {
    let transport = FakeTransport()

    func reach(_ connection: FlatdConnection, resolve: URL? = nil) -> FlatdReach {
        FlatdReach(connection: connection, transport: transport, rediscover: { resolve.map { [$0] } ?? [] })
    }

    @Test func nothingWithTheKeyGoesToAnAddressWhereFlatdDoesNotAnswer() async {
        // The address settles first (who answers is the pinned transport's check, `TrustTests`): no health, no work.
        transport.answer("GET /api/health", status: 404, body: ["detail": "not found"])
        transport.answer("GET /api/devices", body: ["devices": []])
        await #expect(throws: FlatdError.unreachable) {
            try await reach(Flat.connection()).run { try await $0.devices() }
        }
        #expect(transport.sent.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
    }

    @Test func aHealthWithoutFlatdsShapeIsNotFlatd() async throws {
        transport.answer("GET /api/health", body: ["status": "up"])
        let client = FlatdClient(Flat.pairing(), transport: transport)
        #expect(try await client.health() == false)
        await #expect(throws: FlatdError.unreachable) { try await client.verify() }
    }

    @Test func aNewAddressIsKeptOnlyOnceTheWorkSucceededThere() async throws {
        let connection = Flat.connection()
        let moved = URL(string: "https://192.0.2.77:8788")!
        transport.answer("GET 192.0.2.10/api/health", fails: true)        // the saved address: nobody there any more
        transport.answer("POST /api/scenes/all_down", status: 500, body: ["error": "boom"])
        let actions = FlatActions(reach: reach(connection, resolve: moved))
        await #expect(throws: FlatdError.self) { try await actions.runScene("all_down") }
        #expect(connection.pairing?.baseURL == Flat.base)                  // failed there: not kept

        transport.answer("POST /api/scenes/all_down", body: ["id": "all_down", "failed": [:]])
        try await actions.runScene("all_down")
        #expect(connection.pairing?.baseURL == moved)                      // worked there: kept
        #expect(connection.pairing?.pin == Flat.pin && connection.token == Flat.key)
    }

    @Test func aTimeoutIsNeverSentAgainElsewhere() async {
        let moved = URL(string: "https://192.0.2.77:8788")!
        transport.answer("POST /api/scenes/air_out", fails: true, failure: .timedOut)
        await #expect(throws: FlatdError.noAnswer) {
            try await FlatActions(reach: reach(Flat.connection(), resolve: moved)).runScene("air_out")
        }
        #expect(transport.bodies(for: "POST /api/scenes/air_out").count == 1)
        #expect(transport.requests(to: "192.0.2.77").isEmpty)
    }

    @Test func aLateLookupNeverMovesANewerOrForgottenPairing() throws {
        let connection = Flat.connection()
        let old = try #require(connection.pairing)
        let newer = Flat.pairing(token: "newer-key-0123456789")
        try connection.save(newer)
        connection.move(old, to: URL(string: "https://192.0.2.77:8788")!)          // the old pairing's late lookup
        #expect(connection.pairing == newer)
        connection.move(newer, to: URL(string: "https://192.0.2.77:8788")!)
        #expect(connection.pairing?.baseURL.host() == "192.0.2.77")
        #expect(connection.token == "newer-key-0123456789")
        try connection.forget()
        connection.move(newer, to: Flat.base)                                     // after Disconnect: nothing comes back
        #expect(connection.pairing == nil)
    }

    @Test func aCommandRunsOnceEvenWhenItsConnectionIsLost() async {
        let moved = URL(string: "https://192.0.2.77:8788")!
        transport.answer("POST /api/scenes/air_out", fails: true)                 // lost after flatd may have taken it
        await #expect(throws: FlatdError.unreachable) {
            try await FlatActions(reach: reach(Flat.connection(), resolve: moved)).runScene("air_out")
        }
        #expect(transport.bodies(for: "POST /api/scenes/air_out").count == 1)
        #expect(transport.requests(to: "192.0.2.77").isEmpty)
    }

    @Test func aPairingChangedDuringTheLookupSendsNothing() async throws {
        let connection = Flat.connection()
        transport.answer("GET 192.0.2.10/api/health", fails: true)
        transport.answer("POST /api/scenes/all_down", body: ["id": "all_down", "failed": [:]])
        let reach = FlatdReach(connection: connection, transport: transport, rediscover: {
            try? connection.forget()                                  // Disconnect while flatd is looked up again
            return [URL(string: "https://192.0.2.77:8788")!]
        })
        await #expect(throws: FlatdError.refused) { try await FlatActions(reach: reach).runScene("all_down") }
        #expect(transport.bodies(for: "POST /api/scenes/all_down").isEmpty)
    }

    @Test func repeatedFailureIdsAreReadOnce() throws {
        #expect(try Flat.decode(CommandFailures.self, ["failed": ["fan:fan_1", "fan:fan_1"]]).ids == ["fan:fan_1"])
    }

    @Test func addressAndKeyAreOneItem() throws {
        let connection = Flat.connection(linked: false)
        let pairing = Flat.pairing()
        try connection.save(pairing)
        #expect(connection.pairing == pairing)
        try connection.forget()
        #expect(connection.pairing == nil && connection.client == nil)
    }
}

@MainActor
struct StoreReviewTests {
    func liveStore() async throws -> (FlatStore, FakeTransport, FakeEvents, Counter) {
        let (store, transport, events, reloads) = Flat.store()
        transport.answer("GET /api/scenes", body: ["scenes": []])
        store.start()
        #expect(await eventually { events.isOpen })
        events.send(try Flat.snapshot())
        #expect(await eventually { store.link == .live })
        return (store, transport, events, reloads)
    }

    @Test func tryAgainDuringABonjourLookupLeavesOneHealthyLoop() async throws {
        // The lookup waits until the test lets it answer; meanwhile Try again replaces the loop.
        let gate = Gate()
        let transport = FakeTransport(), events = FakeEvents()
        transport.answer("GET /api/scenes", fails: true)
        let store = FlatStore(connection: Flat.connection(), transport: transport, eventSource: events,
                              rediscover: { await gate.wait() }, reloadControls: {})
        store.start()
        #expect(await eventually({ gate.isWaiting }, timeout: .seconds(5)))
        store.retry()
        gate.open()                                   // the old loop's lookup answers nil after its loop was replaced
        transport.answer("GET /api/scenes", body: ["scenes": []])
        #expect(await eventually({ events.isOpen }, timeout: .seconds(5)))
        events.send(try Flat.snapshot())
        #expect(await eventually { store.link == .live })
        store.stop()
    }

    @Test func aModeEventIsToldOnce() async throws {
        let (store, _, events, _) = try await liveStore()
        var heard: [FlatEvent] = []
        let pairing = try #require(store.pairingID)
        let token = try #require(store.listen(for: pairing) { heard.append($0) })
        events.send(.mode(FlatMode(id: "cooking", label: "Cooking", active: true)))
        #expect(await eventually { store.isCooking })
        try await Task.sleep(for: .milliseconds(50))
        #expect(heard.count == 1)
        store.unlisten(token)
        store.stop()
    }

    @Test func aSnapshotWithoutModesKeepsThemForThePageToo() async throws {
        let (store, _, events, _) = try await liveStore()
        var heard: [FlatEvent] = []
        let pairing = try #require(store.pairingID)
        let token = try #require(store.listen(for: pairing) { heard.append($0) })
        events.send(.snapshot(devices: try Flat.devices([Flat.fan(1)]), modes: nil))
        #expect(await eventually { store.devices.count == 1 })
        #expect(store.cooking != nil)
        guard case let .snapshot(_, modes)? = heard.last else {
            Issue.record("no snapshot told")
            return
        }
        #expect(modes?.map(\.id) == ["cooking"])
        store.unlisten(token)
        store.stop()
    }

    @Test func anAnswerOlderThanTheStreamIsLeftOut() async throws {
        let (store, transport, events, _) = try await liveStore()
        var newer = Flat.fan(1, on: true)
        newer["state"] = ["on": true, "updated_at": "2026-11-19T18:00:05Z"]
        events.send(.state(id: "fan:fan_1", state: try Flat.decode(DeviceState.self, newer["state"]!), source: "device"))
        #expect(await eventually { store.device("fan:fan_1")?.state.on == true })
        var older = Flat.fan(1, on: false)
        older["state"] = ["on": false, "updated_at": "2026-11-19T18:00:01Z"]
        transport.answer("POST /api/devices/fan:fan_1", body: older)
        store.setFan("fan:fan_1", on: false)
        #expect(await eventually { !store.isWorking("power:fan:fan_1") })
        #expect(store.device("fan:fan_1")?.state.on == true)
        store.stop()
    }

    @Test func aLateAnswerAfterDisconnectingChangesNothing() async throws {
        let (store, transport, _, _) = try await liveStore()
        transport.answer("POST /api/devices/fan:fan_2", status: 401, body: ["error": "wrong token"])
        store.setFan("fan:fan_2", on: true)
        store.disconnect()
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.link == .notSetUp)                  // not .refused from the old pairing's answer
        #expect(store.working.isEmpty)
    }

    @Test func aDraggedPositionClearsOnceFlatdAnswered() async throws {
        let (store, transport, _, _) = try await liveStore()
        transport.answer("POST /api/devices/rollo:blind_2", body: Flat.rollo(2, position: 0, moving: "down", target: 70))
        store.setRollo("rollo:blind_2", position: 70)
        #expect(await eventually { store.dragging["rollo:blind_2"] == nil })
        store.drag("rollo:blind_1", to: 30)
        store.endDrag("rollo:blind_1")
        #expect(store.dragging.isEmpty)
        store.stop()
    }

    @Test func homesCommandsCheckTheAddressWhileNotLive() async throws {
        let (store, transport, events, _) = try await liveStore()
        transport.answer("GET /api/scenes", fails: true)
        events.end(FlatdError.unreachable)
        #expect(await eventually({ store.link == .offline }, timeout: .seconds(5)))
        // flatd does not answer at the address now: the command is not sent.
        transport.answer("GET /api/health", status: 404, body: [:])
        let before = transport.sent.count
        store.setFan("fan:fan_1", on: true)
        #expect(await eventually { !store.isWorking("power:fan:fan_1") })
        #expect(transport.sent.dropFirst(before).allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        store.stop()
    }

    @Test func aCommandInTheRetryPauseChecksTheAddressAgain() async throws {
        let (store, transport, events, _) = try await liveStore()
        // The stream drops; the store still says live during its quick retry, but its address no longer counts.
        transport.answer("GET /api/health", status: 404, body: [:])
        events.end(FlatdError.unreachable)
        try await Task.sleep(for: .milliseconds(50))
        let before = transport.sent.count
        store.setFan("fan:fan_1", on: true)
        #expect(await eventually { !store.isWorking("power:fan:fan_1") })
        #expect(transport.sent.dropFirst(before).allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        store.stop()
    }

    @Test func anAnswerIsLeftOutWhenTheStreamSpokeMeanwhile() async throws {
        let (store, transport, events, _) = try await liveStore()
        var active = Flat.cooking
        active["active"] = true
        transport.answer("POST /api/modes/cooking", body: active.merging(["failed": [:]]) { $1 },
                         delay: .milliseconds(400))
        store.setMode("cooking", active: true)
        try await Task.sleep(for: .milliseconds(150))
        // While the slow answer to Start cooking is out, the stream says cooking ended (Claude ended it, say).
        events.send(.mode(FlatMode(id: "cooking", label: "Cooking", active: false)))
        #expect(await eventually { !store.isWorking("mode:cooking") })
        #expect(!store.isCooking)        // the stream's newer word stands
        store.stop()
    }

    @Test func aLateConnectKeepsNothingAfterADisconnect() async throws {
        let connection = Flat.connection(linked: false)
        let (store, transport, _, _) = Flat.store(connection: connection)
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1)]])
        let attempt = Task { await store.connect(to: Flat.base, token: Flat.key, pin: Flat.pin) }
        attempt.cancel()
        #expect(await attempt.value == .notPossible)
        #expect(connection.pairing == nil && store.link == .notSetUp)
    }

    @Test func aDisconnectTheKeychainRefusesSaysSo() async throws {
        let keys = MemoryKeys()
        let connection = FlatdConnection(defaults: UserDefaults(suiteName: "arestia-tests-" + UUID().uuidString)!,
                                         keychain: keys)
        try connection.save(Flat.pairing())
        let (store, _, _, _) = Flat.store(connection: connection)
        keys.failsToDelete = true
        store.disconnect()
        #expect(store.offer != nil)
        #expect(connection.pairing != nil)
    }

    @Test func aMalformedRequestStillGetsItsResult() {
        #expect(PageMessage.parse(["type": "request", "reqId": "r9", "id": "fan:fan_1", "body": "on"]) == .invalid(reqId: "r9"))
        #expect(PageMessage.parse(["type": "mode", "reqId": "r10", "body": ["active": false]]) == .invalid(reqId: "r10"))
        #expect(PageScript.errorWord(.noAnswer) == "timeout")
    }
}

/// A Bonjour lookup that answers only when the test says so.
@MainActor
final class Gate: Sendable {
    private var waiters: [CheckedContinuation<[URL], Never>] = []
    var isWaiting: Bool { !waiters.isEmpty }

    nonisolated func wait() async -> [URL] {
        await withCheckedContinuation { continuation in
            Task { @MainActor in self.waiters.append(continuation) }
        }
    }

    func open() {
        waiters.forEach { $0.resume(returning: []) }
        waiters = []
    }
}
