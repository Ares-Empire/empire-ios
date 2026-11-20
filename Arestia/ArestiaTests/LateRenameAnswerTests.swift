import Foundation
import Testing
@testable import Arestia

// Codex's review of the renaming, round 3, finding 3: a rename's late answer never puts its name over a newer one kept
// for the same device meanwhile; flatd is asked again instead.

/// A device as flatd v1.3 sends it after a rename: its own name, the config's as `default_label`.
private func named(_ object: [String: Any], _ label: String) -> [String: Any] {
    var object = object
    object["default_label"] = object["label"]
    object["label"] = label
    return object
}

@MainActor
struct LateRenameAnswerTests {
    func liveStore() async throws -> (FlatStore, FakeTransport, FakeEvents) {
        let (store, transport, events, _) = Flat.store()
        transport.answer("GET /api/scenes", body: ["scenes": []])
        store.start()
        #expect(await eventually { events.isOpen })
        events.send(try Flat.snapshot())
        #expect(await eventually { store.link == .live })
        return (store, transport, events)
    }

    func asked(_ transport: FakeTransport, _ route: String) -> Int {
        transport.sent.filter { ($0.httpMethod ?? "GET") + " " + ($0.url?.path(percentEncoded: true) ?? "") == route }
            .count
    }

    /// The app's rename to "Desk" succeeds while its stream is quiet (down); its answer is slow. Meanwhile another
    /// client renamed the same blind and a picker read flatd's list and kept "Kitchen". The late "Desk" is not kept over
    /// it: flatd is asked once more, and its answer is what the app shows and what is kept, whichever it is.
    @Test(arguments: ["Kitchen", "Desk"])
    func aLateAnswerNeverOverwritesANewerNameOfTheSameDevice(now: String) async throws {
        let (store, transport, _) = try await liveStore()
        let connection = store.connection
        let kept = { connection.knownDevices.first { $0.id == "rollo:blind_1" }?.label }
        // Without names kept meanwhile, an answer is kept as it is and flatd is not asked again.
        transport.answer("PATCH /api/devices/fan:fan_1", body: named(Flat.fan(1), "Desk fan"))
        store.rename("fan:fan_1", to: "Desk fan")
        #expect(await eventually { connection.knownDevices.first?.label == "Desk fan" && !store.isRenaming("fan:fan_1") })
        #expect(asked(transport, "GET /api/devices/fan:fan_1") == 0)

        transport.answer("PATCH /api/devices/rollo:blind_1", body: named(Flat.rollo(1), "Desk"), delay: .milliseconds(400))
        store.rename("rollo:blind_1", to: "Desk")
        try await Task.sleep(for: .milliseconds(100))
        transport.answer("GET /api/devices", body: ["devices": [
            named(Flat.fan(1), "Desk fan"), Flat.fan(2), named(Flat.rollo(1), "Kitchen"), Flat.rollo(2)]])
        let reach = FlatdReach(connection: connection, transport: transport, rediscover: { [] })
        #expect(await DeviceChoices.load(kind: .rollo, connection: connection, reach: reach).map(\.label)
                == ["Kitchen", "Blind 2"])
        #expect(kept() == "Kitchen")
        transport.answer("GET /api/devices/rollo:blind_1", body: named(Flat.rollo(1), now))

        #expect(await eventually { asked(transport, "GET /api/devices/rollo:blind_1") == 1 })
        #expect(await eventually { store.device("rollo:blind_1")?.label == now && kept() == now })
        #expect(!store.isRenaming("rollo:blind_1"))
        #expect(connection.knownDevices.first?.label == "Desk fan")       // the other names as kept
        store.stop()
    }
}
