import Foundation
import Testing
@testable import Arestia

// Codex's review of the 3D page, finding 2: a device's own name reaches the page through the app, in the snapshot and
// live (a rename made elsewhere, the app's own rename and its reset), each with `default_label`, so the page shows the
// own name and its own words again after a reset. An older flatd sends no `default_label`: the page keeps its words.

/// A device as flatd v1.3 sends it: its shown name and the config's.
private func named(_ object: [String: Any], _ label: String, default original: String) -> [String: Any] {
    var object = object
    object["label"] = label
    object["default_label"] = original
    return object
}

/// What the page is handed for an event: the JSON inside `flat3d.receive(…)`, as the web view runs it.
@MainActor
private func handed(_ event: FlatEvent) throws -> [String: Any] {
    let script = PageScript.receive(try #require(event.json))
    let start = "window.flat3d && flat3d.receive && flat3d.receive(", end = ");"
    #expect(script.hasPrefix(start) && script.hasSuffix(end))
    let json = String(script.dropFirst(start.count).dropLast(end.count))
    return try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
}

/// A frame of flatd's event stream, read as the app reads it.
private func frame(_ object: [String: Any]) throws -> FlatEvent {
    try #require(FlatEvent.decode(JSONSerialization.data(withJSONObject: object)))
}

private func device(_ message: [String: Any], _ id: String) -> [String: Any]? {
    let devices = message["devices"] as? [[String: Any]] ?? [message["device"] as? [String: Any]].compactMap { $0 }
    return devices.first { $0["id"] as? String == id }
}

private func names(_ message: [String: Any]?) -> [String?] {
    [message?["label"] as? String, message?["default_label"] as? String]
}

@MainActor
struct ViewerNamesTests {
    @Test func renamesAndResetsReachThePage() async throws {
        let (store, transport, events, _) = Flat.store()
        transport.answer("GET /api/scenes", body: ["scenes": []])
        store.start()
        #expect(await eventually { events.isOpen })
        var page: [[String: Any]] = []
        _ = store.listen { event in if let message = try? handed(event) { page.append(message) } }

        // The snapshot: an own name and a device without one, both with the config's name.
        events.send(try frame(["type": "snapshot", "modes": [], "devices": [
            named(Flat.fan(1), "Desk fan", default: "Fan 1"), named(Flat.rollo(1), "Blind 1", default: "Blind 1")]]))
        #expect(await eventually { store.link == .live })
        let snapshot = try handed(try #require(store.snapshot))
        #expect(names(device(snapshot, "fan:fan_1")) == ["Desk fan", "Fan 1"])
        #expect(names(device(snapshot, "rollo:blind_1")) == ["Blind 1", "Blind 1"])

        // Renamed elsewhere (Claude, another phone): the device event, as flatd sent it.
        events.send(try frame(["type": "device", "source": "mcp",
                               "device": named(Flat.rollo(1), "Kitchen blind", default: "Blind 1")]))
        #expect(await eventually { page.last?["type"] as? String == "device" })
        #expect(names(device(try #require(page.last), "rollo:blind_1")) == ["Kitchen blind", "Blind 1"])
        #expect(page.last?["source"] as? String == "mcp")

        // The app's own rename, then its reset (Original name: {"label": null}).
        transport.answer("PATCH /api/devices/fan:fan_1", body: named(Flat.fan(1), "Bath fan", default: "Fan 1"))
        store.rename("fan:fan_1", to: "Bath fan")
        #expect(await eventually { names(device(page.last ?? [:], "fan:fan_1")) == ["Bath fan", "Fan 1"] })
        #expect(await eventually { !store.isRenaming("fan:fan_1") })
        transport.answer("PATCH /api/devices/fan:fan_1", body: named(Flat.fan(1), "Fan 1", default: "Fan 1"))
        store.rename("fan:fan_1", to: "")
        #expect(await eventually { names(device(page.last ?? [:], "fan:fan_1")) == ["Fan 1", "Fan 1"] })
        #expect(page.last?["type"] as? String == "device")

        // A page that loads now gets the names as they are.
        let later = try handed(try #require(store.snapshot))
        #expect(names(device(later, "fan:fan_1")) == ["Fan 1", "Fan 1"])
        #expect(names(device(later, "rollo:blind_1")) == ["Kitchen blind", "Blind 1"])
        store.stop()
    }

    /// flatd before 1.3: no `default_label`, so the page is handed none and keeps its own words.
    @Test func anOlderFlatdHandsNoConfigName() async throws {
        let (store, transport, events, _) = Flat.store()
        transport.answer("GET /api/scenes", body: ["scenes": []])
        store.start()
        #expect(await eventually { events.isOpen })
        events.send(try frame(["type": "snapshot", "modes": [], "devices": [Flat.fan(1), Flat.rollo(1)]]))
        #expect(await eventually { store.link == .live })
        let snapshot = try handed(try #require(store.snapshot))
        #expect(names(device(snapshot, "fan:fan_1")) == ["Fan 1", nil])
        #expect(device(snapshot, "fan:fan_1")?.keys.contains("default_label") == false)
        store.stop()
    }
}
