import Foundation
import Testing
@testable import Arestia

/// flatd's answers and events as contract v1.1 describes them, read leniently.
struct ContractTests {
    @Test func aFanAndItsTimer() throws {
        let fan = try Flat.decode(Device.self, Flat.fan(1, on: true, offAt: "2026-11-19T18:30:00.123456Z"))
        #expect(fan.kind == .fan)
        #expect(fan.label == "Fan 1")
        #expect(fan.state.on == true)
        #expect(fan.state.online)
        #expect(fan.state.offAt == FlatdDate.parse("2026-11-19T18:30:00.123Z"))
        #expect(fan.controls == ["on", "for_s"])
    }

    @Test func flatdsTimesInEveryForm() throws {
        let expected = try #require(FlatdDate.parse("2026-11-19T18:02:11Z"))
        #expect(FlatdDate.parse("2026-11-19T18:02:11+00:00") == expected)
        #expect(FlatdDate.parse("2026-11-19T19:02:11+01:00") == expected)
        let micro = try #require(FlatdDate.parse("2026-11-19T18:02:11.123456Z"))
        #expect(abs(micro.timeIntervalSince(expected) - 0.123) < 0.001)
        #expect(FlatdDate.parse("2026-11-19T18:02:11.5+00:00") != nil)
        #expect(FlatdDate.parse("yesterday") == nil)
        #expect(FlatdDate.parse("2026-11-19T18:02:11.Z") == nil)
    }

    @Test func aRolloWithAndWithoutFavourite() throws {
        let withFavourite = try Flat.decode(Device.self, Flat.rollo(1, position: 48, moving: "down", target: 100, favourite: 48))
        #expect(withFavourite.kind == .rollo)
        #expect(withFavourite.state.position == 48)
        #expect(withFavourite.state.moving == .down)
        #expect(withFavourite.state.target == 100)
        #expect(withFavourite.hasFavourite)
        let withoutFavourite = try Flat.decode(Device.self, Flat.rollo(2))
        #expect(!withoutFavourite.hasFavourite)
        #expect(withoutFavourite.state.moving == nil)
    }

    @Test func positionIsReadWithinItsRange() throws {
        var object = Flat.rollo(1)
        object["state"] = ["position": 104.6, "online": true]
        #expect(try Flat.decode(Device.self, object).state.position == 100)
        object["state"] = ["position": NSNull()]
        #expect(try Flat.decode(Device.self, object).state.position == nil)
    }

    @Test func unknownKindsAndFieldsAreKept() throws {
        let device = try Flat.decode(Device.self, ["id": "heater:bath", "kind": "heater", "label": "", "new": [1, 2],
                                                   "state": ["on": true, "watts": 900, "mode": "eco"]])
        #expect(device.kind == .other("heater"))
        #expect(device.label == "heater:bath")         // no name: its id
        #expect(device.controls.isEmpty)
        #expect(device.state.fields["mode"] == .string("eco"))
        #expect(try Flat.decode(Device.self, ["id": "x"]).state == DeviceState())
    }

    @Test func aStatePatchKeepsTheRest() throws {
        let fan = try Flat.decode(Device.self, Flat.fan(1, on: true, offAt: "2026-11-19T18:30:00Z"))
        let patch = try Flat.decode(DeviceState.self, ["off_at": NSNull()])
        let merged = fan.state.merging(patch)
        #expect(merged.on == true)
        #expect(merged.offAt == nil)
        #expect(merged.powerW == 38)
    }

    @Test func modesAndScenes() throws {
        let mode = try Flat.decode(FlatMode.self, ["id": "cooking", "label": "Cooking", "active": true,
                                                   "since": "2026-11-19T18:02:11.123456Z",
                                                   "devices": ["fan:fan_1", "rollo:blind_1"], "failed": [:]])
        #expect(mode.active)
        #expect(mode.since != nil)
        #expect(mode.devices == ["fan:fan_1", "rollo:blind_1"])
        let bare = try Flat.decode(FlatMode.self, ["id": "party"])
        #expect(bare.label == "party" && !bare.active && bare.devices.isEmpty)
        let scene = try Flat.decode(FlatScene.self, ["id": "all_down", "label": "All blinds down",
                                                     "devices": ["rollo:blind_1", "rollo:blind_2"]])
        #expect(scene.devices.count == 2)
    }

    @Test func failuresOfAModeOrScene() throws {
        #expect(try Flat.decode(CommandFailures.self, ["failed": ["fan:fan_2": "timeout"]]).ids == ["fan:fan_2"])
        #expect(try Flat.decode(CommandFailures.self, ["failed": [:]]).ids.isEmpty)
        #expect(try Flat.decode(CommandFailures.self, ["failed": ["rollo:blind_1"]]).ids == ["rollo:blind_1"])
        #expect(try Flat.decode(CommandFailures.self, ["id": "cooking"]).ids.isEmpty)
    }

    @Test func theEventStream() throws {
        let snapshot = try JSONSerialization.data(withJSONObject: [
            "type": "snapshot", "devices": [Flat.fan(1), Flat.rollo(1)], "modes": [Flat.cooking]])
        guard case let .snapshot(devices, modes)? = FlatEvent.decode(snapshot) else {
            Issue.record("no snapshot")
            return
        }
        #expect(devices.map(\.id) == ["fan:fan_1", "rollo:blind_1"])
        #expect(modes?.first?.id == "cooking")

        let state = Data(#"{"type":"state","id":"fan:fan_1","state":{"on":true},"source":"mode:cooking"}"#.utf8)
        guard case let .state(id, patch, source)? = FlatEvent.decode(state) else {
            Issue.record("no state")
            return
        }
        #expect(id == "fan:fan_1" && patch.on == true && source == "mode:cooking")

        let mode = Data(#"{"type":"mode","mode":{"id":"cooking","active":true},"source":"api"}"#.utf8)
        #expect(FlatEvent.decode(mode) == .mode(FlatMode(id: "cooking", label: "cooking", active: true)))
        #expect(FlatEvent.decode(Data(#"{"type":"history"}"#.utf8)) == .other)
        #expect(FlatEvent.decode(Data(#"{"type":"state"}"#.utf8)) == nil)
        #expect(FlatEvent.decode(Data("not json".utf8)) == nil)
    }

    @Test func aSnapshotWithoutModesLeavesThemAlone() throws {
        let data = try JSONSerialization.data(withJSONObject: ["type": "snapshot", "devices": [Flat.fan(1)]])
        guard case let .snapshot(_, modes)? = FlatEvent.decode(data) else {
            Issue.record("no snapshot")
            return
        }
        #expect(modes == nil)
    }

    @Test func commandsAreFlatdsBodies() {
        #expect(DeviceCommand.power(on: true).body == ["on": .bool(true)])
        #expect(DeviceCommand.power(on: true, seconds: 900).body == ["on": .bool(true), "for_s": .number(900)])
        #expect(DeviceCommand.power(on: false, seconds: 900).body == ["on": .bool(false)])   // off has no timer
        #expect(DeviceCommand.rollo(.favourite).body == ["command": .string("favourite")])
        #expect(DeviceCommand.position(140).body == ["position": .number(100)])
    }

    @Test func eventsGoBackOutAsFlatdWroteThem() throws {
        let event = try Flat.snapshot()
        let json = try #require(event.json)
        #expect(FlatEvent.decode(json) == event)
        let state = FlatEvent.state(id: "fan:fan_1", state: DeviceState(fields: ["on": .bool(true)]), source: "api")
        let stateJSON = try #require(state.json)
        #expect(FlatEvent.decode(stateJSON) == state)
        let object = try #require(try JSONSerialization.jsonObject(with: stateJSON) as? [String: Any])
        #expect(object["type"] as? String == "state")
        #expect((object["state"] as? [String: Any])?["on"] as? Bool == true)
    }

    @Test func aBlindCountsAsOpenWhileMoreUpThanDown() throws {
        #expect(RolloOpenness.isOpen(try Flat.decode(Device.self, Flat.rollo(1, position: 0)).state))
        #expect(!RolloOpenness.isOpen(try Flat.decode(Device.self, Flat.rollo(1, position: 100)).state))
        #expect(!RolloOpenness.isOpen(try Flat.decode(Device.self, Flat.rollo(1, position: 10, moving: "down",
                                                                               target: 100)).state))
    }
}

/// The QR code or pasted text that connects the app once.
struct PairingCodeTests {
    let key = "Xq3v-A_9bc0dEf1gHi2jKl3mNo4pQr5s"

    @Test func neverAnAppLinkWithTheKey() {
        // Another app may claim the arestia:// scheme: a key is never taken from such a link.
        #expect(PairingCode.parse("arestia://connect?url=http://192.168.1.20:8787&token=\(key)") == nil)
    }

    @Test func flatdsOwnAddressWithTheKey() {
        #expect(PairingCode.parse("http://mac.local:8787/viewer?token=\(key)")
                == PairingCode(token: key, baseURL: URL(string: "http://mac.local:8787")))
        #expect(PairingCode.parse("http://192.168.1.20:8787/?flatd_token=\(key)")?.token == key)
    }

    @Test func json() {
        #expect(PairingCode.parse(#"{"url": "http://192.168.1.20:8787/", "token": "\#(key)"}"#)
                == PairingCode(token: key, baseURL: URL(string: "http://192.168.1.20:8787")))
    }

    @Test func theKeyAlone() {
        #expect(PairingCode.parse("  \(key)\n") == PairingCode(token: key, baseURL: nil))
    }

    @Test func notAKey() {
        #expect(PairingCode.parse("") == nil)
        #expect(PairingCode.parse("short") == nil)
        #expect(PairingCode.parse("two words that are long enough") == nil)
        #expect(PairingCode.parse("https://example.com/page") == nil)        // no key in it
        #expect(PairingCode.parse("arestia://flat") == nil)
        #expect(PairingCode.parse("ftp://host?token=\(key)") == nil)
    }

    @Test func anAddressAsTyped() {
        #expect(PairingCode.serviceURL("http://192.168.1.20:8787/api/devices?x=1") == URL(string: "http://192.168.1.20:8787"))
        #expect(PairingCode.serviceURL("HTTP://Mac.local:8787") == URL(string: "http://Mac.local:8787"))
        #expect(PairingCode.serviceURL("192.168.1.20:8787") == nil)       // the screen adds http:// itself
        #expect(PairingCode.serviceURL("http://") == nil)
    }
}
