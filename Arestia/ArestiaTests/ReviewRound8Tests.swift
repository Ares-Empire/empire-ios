import Foundation
import Testing
@testable import Arestia

// The final review, round 8 (Codex gpt-6.2-astra, 2026-11-20): commands for one device reach flatd in the order they
// were given, from the 3D page and Home alike (one line per device); a movement superseded while flatd is being found
// is never sent; a confirmed start clears Cooking's trouble; a saved choice the flat does not have stays a choice (so
// it fails cleanly instead of meaning every fan); the Cooking card says how far a blind is and when a device is offline.

private func posts(_ transport: FakeTransport, to id: String) -> [[String: Any]] {
    transport.bodies(for: "POST /api/devices/\(id)")
}

private func blindCommands(_ transport: FakeTransport) -> [String] {
    posts(transport, to: "rollo:blind_2").map { body in
        (body["command"] as? String) ?? "position \(body["position"] ?? "?")"
    }
}

@MainActor
struct OneLinePerDeviceTests {
    func liveStore() async throws -> (FlatStore, FakeTransport) {
        let (store, transport, events, _) = Flat.store()
        transport.answer("GET /api/scenes", body: ["scenes": []])
        store.start()
        #expect(await eventually { events.isOpen })
        events.send(try Flat.snapshot())
        #expect(await eventually { store.link == .live })
        return (store, transport)
    }

    /// Two taps on one fan in 3D (on, then off while the first is on its way): flatd gets them in that order, the
    /// second only once the first was answered, and the page gets one result for each.
    @Test func thePagesTapsOnOneDeviceReachFlatdInTheOrderMade() async throws {
        let (store, transport) = try await liveStore()
        transport.answer("POST /api/devices/fan:fan_1", body: Flat.fan(1, on: true), delay: .milliseconds(600))
        let first = store.pageRequest("fan:fan_1", body: Data(#"{"on":true}"#.utf8))
        let second = store.pageRequest("fan:fan_1", body: Data(#"{"on":false}"#.utf8))
        try await Task.sleep(for: .milliseconds(80))
        #expect(posts(transport, to: "fan:fan_1").map { $0["on"] as? Bool } == [true])
        #expect(await first.value == nil)
        #expect(await second.value == nil)
        #expect(posts(transport, to: "fan:fan_1").map { $0["on"] as? Bool } == [true, false])
        store.stop()
    }

    /// A blind sent down from the 3D page, then stopped on Home: Stop waits for the page's command, never overtakes it.
    @Test func thePageAndHomeShareOneLinePerDevice() async throws {
        let (store, transport) = try await liveStore()
        transport.answer("POST /api/devices/rollo:blind_2", body: Flat.rollo(2, moving: "down", target: 100),
                         delay: .milliseconds(600))
        let fromPage = store.pageRequest("rollo:blind_2", body: Data(#"{"command":"down"}"#.utf8))
        store.moveRollo("rollo:blind_2", .stop)
        try await Task.sleep(for: .milliseconds(80))
        #expect(blindCommands(transport) == ["down"])
        #expect(await fromPage.value == nil)
        #expect(await eventually({ blindCommands(transport).count == 2 }, timeout: .seconds(5)))
        #expect(blindCommands(transport) == ["down", "stop"])
        store.stop()
    }

    /// A page command and a mode change from the page after the store retired: each still gets its one result.
    @Test func aRetiredStoreAnswersEveryPageCommand() async throws {
        let (store, _) = try await liveStore()
        store.retire()
        #expect(await store.pageRequest("fan:fan_1", body: Data(#"{"on":true}"#.utf8)).value == .notPossible)
        #expect(await store.pageMode("cooking", body: Data(#"{"active":false}"#.utf8)).value == .notPossible)
    }

    /// Not live (reconnecting), a command first asks flatd's health: a position given and then Stop while that health
    /// check is out sends only Stop.
    @Test func aMovementSupersededWhileFlatdIsFoundIsNeverSent() async throws {
        let (store, transport, _, _) = Flat.store()                // not started: no live address
        transport.answer("GET /api/health", body: ["ok": true, "version": "1.2.0-test"], delay: .milliseconds(600))
        transport.answer("POST /api/devices/rollo:blind_2", body: Flat.rollo(2))
        store.setRollo("rollo:blind_2", position: 40)
        try await Task.sleep(for: .milliseconds(80))              // its turn came: flatd is being found
        store.moveRollo("rollo:blind_2", .stop)
        #expect(await eventually({ !blindCommands(transport).isEmpty }, timeout: .seconds(5)))
        try await Task.sleep(for: .milliseconds(300))
        #expect(blindCommands(transport) == ["stop"])
        #expect(store.pending["rollo:blind_2"] == nil)
        store.retire()
    }
}

struct RoundEightTroubleTests {
    let transport = FakeTransport()

    /// Started with a fan that did not follow, then started again with every device following (flatd sends every
    /// device its command again): the trouble is gone. A repeated End still keeps an end's trouble (round 7's test).
    @Test func aConfirmedStartClearsTheTrouble() async throws {
        let connection = Flat.connection()
        connection.note(ModeTrouble(pairing: Flat.id, mode: "cooking", active: true, names: ["Fan 2"], at: .now))
        var active = Flat.cooking
        active["active"] = true
        transport.answer("POST /api/modes/cooking", body: active.merging(["failed": [:]]) { $1 })
        let reach = FlatdReach(connection: connection, transport: transport, rediscover: { [] })
        _ = try await FlatActions(reach: reach).setCooking(true)
        #expect(connection.trouble(mode: "cooking", active: true, pairing: Flat.id) == nil)
    }
}

struct SavedChoiceTests {
    let transport = FakeTransport()

    /// iOS asks the query for a Shortcut's saved fan: one the flat does not have (chosen before Forget) comes back as
    /// "Not in your flat" instead of being dropped (which would leave the optional fan empty: every fan), and running
    /// with it switches nothing.
    @Test func aChoiceTheFlatDoesNotHaveStaysAChoiceAndActsOnNothing() async throws {
        let connection = Flat.connection()
        connection.remember(try Flat.devices([Flat.fan(1), Flat.fan(2)]), for: Flat.id)
        let known = DeviceChoices.choices(kind: .fan, from: connection.known)
        let fromBeforeForget = SavedDevice.id(for: "fan:fan_1", of: UUID())
        let resolved = DeviceChoices.resolve([known[1].id, fromBeforeForget], among: known, language: .english)
        #expect(resolved.map(\.id) == [known[1].id, fromBeforeForget])
        #expect(resolved.map(\.label) == ["Fan 2", "Not in your flat"])

        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1), Flat.fan(2)]])
        transport.answer("POST /api/devices/fan:fan_1", body: Flat.fan(1, on: true))
        transport.answer("POST /api/devices/fan:fan_2", body: Flat.fan(2, on: true))
        let reach = FlatdReach(connection: connection, transport: transport, rediscover: { [] })
        await #expect(throws: ChosenDeviceGone.fan) {
            try await FlatActions(reach: reach).setFans(on: true, only: [resolved[1].id])
        }
        #expect(transport.sent.allSatisfy { $0.httpMethod == "GET" })
    }
}

struct CookingCardWordsTests {
    @Test func aBlindPartWayAndAnOfflineDeviceAreSaidAsTheyAre() throws {
        let devices = try Flat.devices([Flat.fan(1, on: true), Flat.fan(2, on: true, online: false),
                                        Flat.rollo(1, position: 60), Flat.rollo(2, position: 100)])
        #expect(FlatWords.devicesNow(devices, language: .english)
                == "Fan 1 on · Fan 2 offline · Blind 1 60\u{202F}% closed · Blind 2 closed")
        #expect(FlatWords.devicesNow(devices, language: .german)
                == "Fan 1 an · Fan 2 offline · Blind 1 60\u{202F}% zu · Blind 2 zu")
    }
}
