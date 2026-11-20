import Foundation
import Testing
@testable import Arestia

/// The store: live state from the stream, commands, connecting, and what it tells the 3D page.
@MainActor
struct StoreTests {
    /// A store following a fake flatd, its first snapshot taken.
    func liveStore(cookingActive: Bool = false) async throws -> (FlatStore, FakeTransport, FakeEvents, Counter) {
        let (store, transport, events, reloads) = Flat.store()
        transport.answer("GET /api/scenes", body: ["scenes": [["id": "air_out", "label": "Air out"],
                                                              ["id": "all_down", "label": "All blinds down"]]])
        store.start()
        #expect(await eventually { events.isOpen })
        events.send(try Flat.snapshot(cookingActive: cookingActive))
        #expect(await eventually { store.link == .live })
        return (store, transport, events, reloads)
    }

    @Test func withoutAKeyTheConnectScreen() {
        let (store, _, _, _) = Flat.store(connection: Flat.connection(linked: false))
        #expect(store.link == .notSetUp)
        store.start()
        #expect(store.link == .notSetUp)
    }

    @Test func theSnapshotMakesItLive() async throws {
        let (store, transport, events, _) = try await liveStore()
        #expect(store.fans.map(\.label) == ["Fan 1", "Fan 2"])
        #expect(store.rollos.map(\.label) == ["Blind 1", "Blind 2"])
        #expect(store.scenes.map(\.id) == ["air_out", "all_down"])
        #expect(store.cooking?.active == false)
        #expect(store.hasSnapshot)
        // The stream carries the key in its header, never in the URL.
        #expect(events.requests.first?.url?.query == nil)
        #expect(events.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer \(Flat.key)")
        // First the keyless health check, then the key.
        #expect(transport.sent.first?.url?.path() == "/api/health")
        #expect(transport.sent.first?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(transport.sent.dropFirst().first?.value(forHTTPHeaderField: "Authorization") == "Bearer \(Flat.key)")
        #expect(store.connection.knownDevices.count == 4)
        store.stop()
    }

    @Test func eventsAreMergedWhoeverMadeThem() async throws {
        let (store, _, events, reloads) = try await liveStore()
        let before = reloads.count
        events.send(.state(id: "fan:fan_2", state: DeviceState(fields: ["on": .bool(true)]), source: "device"))
        #expect(await eventually { store.device("fan:fan_2")?.state.on == true })
        #expect(store.device("fan:fan_2")?.state.online == true)            // the rest of its state stays
        #expect(reloads.count == before + 1)                                // a fan on: the controls read again
        events.send(.mode(FlatMode(id: "cooking", label: "Cooking", active: true, since: .now)))
        #expect(await eventually { store.isCooking })
        events.send(.state(id: "fan:unknown", state: DeviceState(fields: ["on": .bool(true)]), source: "api"))
        events.send(.other)
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.devices.count == 4)
        store.stop()
    }

    @Test func aFanTimerIsSentAndItsAnswerShown() async throws {
        let (store, transport, _, _) = try await liveStore()
        transport.answer("POST /api/devices/fan:fan_1", body: Flat.fan(1, on: true, offAt: "2026-11-19T18:30:00Z"))
        store.setFan("fan:fan_1", on: true, minutes: 15)
        #expect(store.isWorking("power:fan:fan_1"))
        #expect(await eventually { store.device("fan:fan_1")?.state.offAt != nil })
        #expect(!store.isWorking("power:fan:fan_1"))
        #expect(transport.bodies(for: "POST /api/devices/fan:fan_1").first?["for_s"] as? Double == 900)
        store.stop()
    }

    @Test func aRefusedCommandSaysSoQuietly() async throws {
        let (store, transport, _, _) = try await liveStore()
        transport.answer("POST /api/devices/fan:fan_2", status: 504, body: ["error": "timeout"])
        store.setFan("fan:fan_2", on: true)
        #expect(await eventually { store.offer != nil })
        #expect(store.offer?.message == FlatdError.deviceDidNotAnswer.message())
        #expect(store.offer?.undo == nil)
        #expect(store.link == .live)
        store.stop()
    }

    @Test func aRefusedKeyGoesBackToConnecting() async throws {
        let (store, transport, _, _) = try await liveStore()
        transport.answer("POST /api/devices/fan:fan_1", status: 401, body: ["error": "missing or wrong token"])
        store.setFan("fan:fan_1", on: true)
        #expect(await eventually { store.link == .refused })
    }

    @Test func endingCookingOffersUndo() async throws {
        let (store, transport, _, _) = try await liveStore(cookingActive: true)
        transport.answer("POST /api/modes/cooking", body: Flat.cooking.merging(["failed": [:]]) { $1 })
        store.setMode("cooking", active: false)
        #expect(await eventually { !store.isCooking })
        #expect(store.offer?.message == FlatWords.cookingEnded())
        #expect(store.offer?.undo != nil)
        store.stop()
    }

    @Test func devicesThatDidNotFollowAreNamed() async throws {
        let (store, transport, _, _) = try await liveStore()
        var active = Flat.cooking
        active["active"] = true
        active["failed"] = ["fan:fan_2": "did not answer"]
        transport.answer("POST /api/modes/cooking", body: active)
        store.setMode("cooking", active: true)
        #expect(await eventually { store.offer != nil })
        #expect(store.isCooking)
        #expect(store.offer?.message == "Didn't answer: Fan 2.")
        store.stop()
    }

    @Test func aDraggedBlindShowsWhereItGoesUntilFlatdHasIt() async throws {
        let (store, transport, events, _) = try await liveStore()
        let blind = try #require(store.device("rollo:blind_1"))
        store.drag("rollo:blind_1", to: 85)
        #expect(store.shownPosition(of: blind) == 85)
        transport.answer("POST /api/devices/rollo:blind_1", body: Flat.rollo(1, position: 60, moving: "down",
                                                                             target: 85, favourite: 60))
        store.setRollo("rollo:blind_1", position: 85)
        #expect(await eventually { transport.bodies(for: "POST /api/devices/rollo:blind_1").count == 1 })
        #expect(transport.bodies(for: "POST /api/devices/rollo:blind_1").first?["position"] as? Double == 85)
        events.send(.state(id: "rollo:blind_1", state: DeviceState(fields: ["moving": .string("down"),
                                                                            "target": .number(85)]), source: "device"))
        #expect(await eventually { store.pending["rollo:blind_1"] == nil && store.dragging["rollo:blind_1"] == nil })
        store.stop()
    }

    @Test func connectingChecksTheKeyBeforeKeepingIt() async throws {
        let connection = Flat.connection(linked: false)
        let (session, transport, events, _) = Flat.session(connection: connection)
        let unpaired = try #require(session.store)
        transport.answer("GET /api/devices", status: 401, body: ["error": "missing or wrong token"])
        #expect(await unpaired.connect(to: Flat.base, token: Flat.otherKey, pin: Flat.pin) == .refused)
        #expect(connection.pairing == nil && connection.token == nil)
        #expect(session.store === unpaired && unpaired.link == .notSetUp)

        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1)]])
        transport.answer("GET /api/scenes", body: ["scenes": []])
        #expect(await unpaired.connect(to: Flat.base, token: Flat.key, pin: Flat.pin) == nil)
        #expect(connection.pairing?.baseURL == Flat.base && connection.pairing?.pin == Flat.pin)
        #expect(connection.token == Flat.key)
        let store = try #require(session.store)
        store.start()
        #expect(await eventually { events.isOpen })
        #expect(events.pins == [Flat.pin])                 // the stream is opened for the pairing's identity
        #expect(session.forget())
        #expect(connection.pairing == nil && connection.token == nil && store.isRetired && store.devices.isEmpty)
        #expect(session.store?.link == .notSetUp)
    }

    @Test func theStreamEndingIsNotLiveAnyMore() async throws {
        let (store, transport, events, _) = try await liveStore()
        transport.answer("GET /api/scenes", fails: true)
        events.end(FlatdError.unreachable)
        #expect(await eventually({ store.link == .offline }, timeout: .seconds(5)))
        #expect(store.devices.count == 4)                 // the last state stays on screen
        transport.answer("GET /api/scenes", body: ["scenes": []])
        store.retry()
        #expect(await eventually { events.isOpen })
        events.send(try Flat.snapshot())
        #expect(await eventually { store.link == .live })
        store.stop()
    }

    @Test func aRefusedStreamNeedsTheKeyAgain() async throws {
        let (store, _, events, _) = try await liveStore()
        events.end(FlatdError.refused)
        #expect(await eventually { store.link == .refused })
    }

    @Test func listenersHearEveryChangeAsFlatdWroteIt() async throws {
        let (store, transport, events, _) = try await liveStore()
        var heard: [FlatEvent] = []
        let token = try #require(store.listen { heard.append($0) })
        events.send(.state(id: "fan:fan_1", state: DeviceState(fields: ["on": .bool(true)]), source: "device"))
        #expect(await eventually { heard.count == 1 })
        // A command's answer too, as a state event (the page shows it before the stream repeats it).
        transport.answer("POST /api/devices/rollo:blind_2", body: Flat.rollo(2, moving: "down", target: 100))
        #expect(await store.pageRequest("rollo:blind_2", body: Data(#"{"command":"down"}"#.utf8)).value == nil)
        #expect(heard.count == 2)
        if case let .state(id, state, _) = heard[1] { #expect(id == "rollo:blind_2" && state.moving == .down) }
        #expect(transport.bodies(for: "POST /api/devices/rollo:blind_2").first?["command"] as? String == "down")
        store.unlisten(token)
        events.send(.state(id: "fan:fan_1", state: DeviceState(fields: ["on": .bool(false)]), source: "device"))
        try await Task.sleep(for: .milliseconds(50))
        #expect(heard.count == 2)
        store.stop()
    }

    @Test func thePagesRequestsGetTheBridgesErrors() async throws {
        let (store, transport, _, _) = try await liveStore()
        transport.answer("POST /api/devices/fan:fan_2", status: 504, body: ["error": "timeout"])
        #expect(await store.pageRequest("fan:fan_2", body: Data(#"{"on":true}"#.utf8)).value == .deviceDidNotAnswer)
        transport.answer("POST /api/modes/cooking", body: Flat.cooking.merging(["failed": [:]]) { $1 })
        #expect(await store.pageMode("cooking", body: Data(#"{"active":false}"#.utf8)).value == nil)
        store.stop()
    }
}
