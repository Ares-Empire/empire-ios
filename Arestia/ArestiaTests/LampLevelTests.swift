import Foundation
import Testing
@testable import Arestia

@MainActor
struct LampLevelTests {
    private let id = "light:sample"
    private var path: String { "/api/devices/" + id }
    private var route: String { "POST " + path }
    private var readRoute: String { "GET " + path }
    private let failure = "The requested level was not reached."

    private var levelEvent: FlatEvent { levelEvent() }

    private func levelEvent(_ level: String = "low", at updatedAt: String? = nil) -> FlatEvent {
        var fields: [String: JSONValue] = ["on": .bool(true), "level": .string(level)]
        if let updatedAt { fields["updated_at"] = .string(updatedAt) }
        return .state(id: id, state: DeviceState(fields: fields), source: "api")
    }

    private func deviceReads(_ transport: FakeTransport) -> [URLRequest] {
        transport.sent.filter { $0.httpMethod == "GET" && $0.url?.path() == path }
    }

    private func lamp(on: Bool = true, level: String? = "mid", levels: [String]? = ["low", "mid", "high"],
                      controls: [String] = ["on", "level"]) -> [String: Any] {
        var lamp: [String: Any] = [
            "id": id, "kind": "light", "label": "Sample light", "controls": controls,
            "state": ["on": on, "level": level as Any? ?? NSNull(), "future_field": true],
            "future_field": 1,
        ]
        lamp["levels"] = levels
        return lamp
    }

    @Test func levelFieldsDecodeInServiceOrderAndRoundTrip() throws {
        let light = try Flat.decode(Device.self, lamp(levels: ["mid", "high", "low"]))
        #expect(light.levels == ["mid", "high", "low"])
        #expect(light.state.level == "mid")
        #expect(light.state.fields["future_field"] == .bool(true))
        #expect(try JSONDecoder().decode(Device.self, from: JSONEncoder().encode(light)) == light)
    }

    @Test func absentAndNullLevelFieldsAreOptional() throws {
        let legacy = try Flat.decode(Device.self, ["id": id, "kind": "light", "state": ["on": true]])
        #expect(legacy.levels == nil)
        #expect(legacy.state.level == nil)
        #expect(!legacy.hasLevels)
        let off = try Flat.decode(Device.self, lamp(on: false, level: nil))
        #expect(off.state.level == nil)
        #expect(off.hasLevels)
    }

    @Test func aLevelControlNeedsAtLeastTwoAdvertisedNames() throws {
        #expect(try Flat.decode(Device.self, lamp(levels: ["mid", "high"])).hasLevels)
        #expect(try !Flat.decode(Device.self, lamp(levels: ["mid"])).hasLevels)
        #expect(try !Flat.decode(Device.self, lamp(levels: nil)).hasLevels)
        #expect(try !Flat.decode(Device.self, lamp(controls: ["on"])).hasLevels)
    }

    @Test func levelStatusAndSelection() throws {
        let mid = try Flat.decode(Device.self, lamp())
        let unknown = try Flat.decode(Device.self, lamp(level: "unknown"))
        let off = try Flat.decode(Device.self, lamp(on: false, level: nil))
        let legacy = try Flat.decode(Device.self, lamp(level: nil, levels: nil, controls: ["on"]))
        let now = Date()
        #expect(mid.selectedLevel == "mid")
        #expect(unknown.selectedLevel == nil)
        #expect(off.selectedLevel == nil)
        #expect(FlatWords.switchStatus(mid, settingLevel: nil, now: now, language: .english) == "On · Mid")
        #expect(FlatWords.switchStatus(unknown, settingLevel: nil, now: now, language: .english) == "On · Level unknown")
        #expect(FlatWords.switchStatus(off, settingLevel: "high", now: now, language: .english) == "Setting to High…")
        #expect(FlatWords.switchStatus(off, settingLevel: nil, now: now, language: .english) == "Off")
        #expect(FlatWords.switchStatus(legacy, settingLevel: nil, now: now, language: .english) == "On")
        #expect(FlatWords.switchStatus(mid, settingLevel: nil, now: now, language: .german) == "An · Mittel")
        #expect(FlatWords.switchStatus(unknown, settingLevel: nil, now: now, language: .german) == "An · Stufe unbekannt")
        #expect(FlatWords.switchStatus(off, settingLevel: "high", now: now, language: .german) == "Stelle auf Hoch…")
        #expect(FlatWords.levelName("low", language: .german) == "Niedrig")
        #expect(FlatWords.levelName("extra dim", language: .english) == "Extra dim")
    }

    @Test func onlyLevelRequestsHaveFortySeconds() async throws {
        let transport = FakeTransport()
        let client = FlatdClient(Flat.pairing(), transport: transport)
        transport.answer(route, body: lamp(level: "high"))
        transport.answer("GET /api/devices/" + id, body: lamp())
        transport.answer("POST /api/modes/cooking", body: Flat.cooking)

        #expect(try await client.setLevel(id: id, level: "high").state.level == "high")
        _ = try await client.send(.power(on: true), to: id)
        _ = try await client.send(body: Data(#"{"on":true}"#.utf8), to: id)
        _ = try await client.setMode(FlatMode.cookingID, active: false)
        _ = try await client.device(id)

        let body = try #require(transport.bodies(for: route).first)
        #expect(body.keys.sorted() == ["level"])
        #expect(body["level"] as? String == "high")
        #expect(transport.sent.map(\.timeoutInterval) == [40, 12, 12, 12, 6])
    }

    @Test func theCurrentLevelSendsNothing() throws {
        let (store, transport, _, _) = Flat.store()
        store.apply(.snapshot(devices: [try Flat.decode(Device.self, lamp())], modes: nil))
        store.setLevel(id, level: "mid")
        #expect(!store.isWorking("level:" + id))
        #expect(transport.sent.isEmpty)
    }

    @Test func aLevelCanTurnTheLightOn() async throws {
        let (store, transport, _, _) = Flat.store()
        defer { store.retire() }
        store.apply(.snapshot(devices: [try Flat.decode(Device.self, lamp(on: false, level: nil))], modes: nil))
        transport.answer(route, body: lamp(level: "high"))

        store.setLevel(id, level: "high")
        #expect(store.isWorking("level:" + id))
        #expect(store.settingLevel[id] == "high")
        #expect(store.device(id)?.selectedLevel == nil)
        store.setFan(id, on: false)
        store.setLevel(id, level: "low")

        try #require(await eventually { !store.isWorking("level:" + id) })
        #expect(transport.bodies(for: route).count == 1)
        #expect(store.settingLevel[id] == nil)
        #expect(store.device(id)?.state.on == true)
        #expect(store.device(id)?.selectedLevel == "high")
    }

    @Test func a502ShowsItsErrorAndTheStreamSuppliesTheActualLevel() async throws {
        let (store, transport, events, _) = Flat.store()
        defer { store.retire() }
        transport.answer(route, status: 502, body: ["error": failure])
        transport.answer(readRoute, status: 503, body: ["error": "Readback unavailable"])
        transport.answer("GET /api/scenes", body: ["scenes": []])
        store.start()
        try #require(await eventually { events.isOpen })
        events.send(.snapshot(devices: [try Flat.decode(Device.self, lamp())], modes: nil))
        try #require(await eventually { store.link == .live })

        store.setLevel(id, level: "high")
        try #require(await eventually { !store.isWorking("level:" + id) })
        #expect(store.offer?.message == failure)
        #expect(store.settingLevel[id] == nil)
        #expect(deviceReads(transport).count == 1)
        events.send(levelEvent)
        try #require(await eventually { store.device(id)?.selectedLevel == "low" })
        #expect(store.offer?.message == failure)
    }

    @Test func a502ReadsTheActualLevelOnceWithoutAStreamEvent() async throws {
        let (store, transport, _, _) = Flat.store()
        defer { store.retire() }
        store.apply(.snapshot(devices: [try Flat.decode(Device.self, lamp(on: false, level: nil))], modes: nil))
        transport.answer(route, status: 502, body: ["error": failure])
        transport.answer(readRoute, body: lamp(level: "low"))

        store.setLevel(id, level: "high")
        try #require(await eventually { !store.isWorking("level:" + id) })

        #expect(store.offer?.message == failure)
        #expect(store.settingLevel[id] == nil)
        #expect(store.device(id)?.state.on == true)
        #expect(store.device(id)?.selectedLevel == "low")
        #expect(transport.sent.map(\.httpMethod) == ["GET", "POST", "GET"])
        let read = try #require(deviceReads(transport).first)
        let command = try #require(transport.sent.first { $0.httpMethod == "POST" })
        #expect(read.url == command.url)
        #expect(read.value(forHTTPHeaderField: "Authorization") == command.value(forHTTPHeaderField: "Authorization"))
    }

    private func lamp(level: String, at updatedAt: String) -> [String: Any] {
        var lamp = lamp(level: level)
        lamp["state"] = ["on": true, "level": level, "updated_at": updatedAt]
        return lamp
    }

    /// flatd publishes the final state before it answers 502: the read-back still happens, and an older read
    /// can't roll the event back.
    @Test func aNewerLevelEventBeforeThe502OutlivesAnOlderRead() async throws {
        let (store, transport, _, _) = Flat.store()
        defer { store.retire() }
        let event = levelEvent("low", at: "2026-11-26T18:00:20Z")
        store.apply(.snapshot(devices: [try Flat.decode(Device.self, lamp(level: "mid", at: "2026-11-26T18:00:00Z"))],
                              modes: nil))
        transport.answer(route, status: 502, body: ["error": failure], beforeReply: { [weak store] in
            await store?.apply(event)
        })
        transport.answer(readRoute, body: lamp(level: "mid", at: "2026-11-26T18:00:00Z"))

        store.setLevel(id, level: "high")
        try #require(await eventually { !store.isWorking("level:" + id) })

        #expect(store.offer?.message == failure)
        #expect(deviceReads(transport).count == 1)
        #expect(store.device(id)?.selectedLevel == "low")
    }

    @Test func aNewerLevelEventDuringReadbackWinsOverTheRead() async throws {
        let (store, transport, _, _) = Flat.store()
        defer { store.retire() }
        let event = levelEvent("low", at: "2026-11-26T18:00:30Z")
        store.apply(.snapshot(devices: [try Flat.decode(Device.self, lamp(level: "mid", at: "2026-11-26T18:00:00Z"))],
                              modes: nil))
        transport.answer(route, status: 502, body: ["error": failure])
        transport.answer(readRoute, body: lamp(level: "high", at: "2026-11-26T18:00:20Z"), beforeReply: { [weak store] in
            await store?.apply(event)
        })

        store.setLevel(id, level: "high")
        try #require(await eventually { !store.isWorking("level:" + id) })

        #expect(store.offer?.message == failure)
        #expect(store.device(id)?.selectedLevel == "low")
        #expect(deviceReads(transport).count == 1)
    }

    /// A reconnect snapshot taken while flatd was still stepping the lamp, and the final event never arrives: the
    /// read-back still brings the level the lamp reached.
    @Test func aStaleSnapshotDuringTheRunDoesNotSkipTheReadback() async throws {
        let (store, transport, _, _) = Flat.store()
        defer { store.retire() }
        let stale = FlatEvent.snapshot(devices: [try Flat.decode(Device.self, lamp(level: "mid", at: "2026-11-26T18:00:05Z"))],
                                       modes: nil)
        store.apply(.snapshot(devices: [try Flat.decode(Device.self, lamp(level: "mid", at: "2026-11-26T18:00:00Z"))],
                              modes: nil))
        transport.answer(route, status: 502, body: ["error": failure], beforeReply: { [weak store] in
            await store?.apply(stale)
        })
        transport.answer(readRoute, body: lamp(level: "low", at: "2026-11-26T18:00:20Z"))

        store.setLevel(id, level: "high")
        try #require(await eventually { !store.isWorking("level:" + id) })

        #expect(store.offer?.message == failure)
        #expect(deviceReads(transport).count == 1)
        #expect(store.device(id)?.selectedLevel == "low")
    }
}
