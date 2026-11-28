import Foundation
import Testing
@testable import Arestia

// Renaming a device (flatd contract v1.3 (owner, 2026-11-20): "can we make the names of things changable so I can name
// rename things?"), and the lights' own section (owner, 2026-11-20) ("put the lamp under 'Lighting' in Arestia").

/// A device as flatd v1.3 sends it: its shown name and the config's.
private func named(_ object: [String: Any], _ label: String, default original: String) -> [String: Any] {
    var object = object
    object["label"] = label
    object["default_label"] = original
    return object
}

/// The rename's body as flatd received it.
private func label(_ transport: FakeTransport, _ id: String) -> Any? {
    transport.bodies(for: "PATCH /api/devices/" + id).last?["label"]
}

/// The contract's new parts, read leniently.
struct RenameContractTests {
    @Test func aDeviceCarriesItsOwnAndItsConfigName() throws {
        let renamed = try Flat.decode(Device.self, named(Flat.fan(1), "Desk fan", default: "Fan 1"))
        #expect(renamed.label == "Desk fan")
        #expect(renamed.defaultLabel == "Fan 1")
        #expect(renamed.hasOwnName)
        let plain = try Flat.decode(Device.self, named(Flat.fan(1), "Fan 1", default: "Fan 1"))
        #expect(!plain.hasOwnName)
        // A flatd before v1.3 sends no default_label: nothing counts as renamed.
        let older = try Flat.decode(Device.self, Flat.fan(1))
        #expect(older.defaultLabel == nil)
        #expect(!older.hasOwnName)
        // Sent on to the 3D page as flatd sent it.
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(renamed)) as? [String: Any]
        #expect(json?["default_label"] as? String == "Fan 1")
        #expect(json?["label"] as? String == "Desk fan")
    }

    @Test func theDeviceEvent() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "type": "device", "source": "mcp", "device": named(Flat.rollo(1), "Kitchen blind", default: "Blind 1")])
        guard case let .device(device, source)? = FlatEvent.decode(data) else {
            Issue.record("not read as a device event")
            return
        }
        #expect(device.id == "rollo:blind_1")
        #expect(device.label == "Kitchen blind")
        #expect(source == "mcp")
        // To the page as is (BRIDGE.md: unknown types are ignored there), who renamed it included.
        let out = try #require(FlatEvent.device(device, source: source).json)
        let json = try JSONSerialization.jsonObject(with: out) as? [String: Any]
        #expect(json?["type"] as? String == "device")
        #expect(json?["source"] as? String == "mcp")
        #expect((json?["device"] as? [String: Any])?["label"] as? String == "Kitchen blind")
        #expect(FlatEvent.decode(out) == .device(device, source: "mcp"))       // the round trip keeps it all
        // A device event without its device is not taken.
        #expect(FlatEvent.decode(Data(#"{"type": "device"}"#.utf8)) == nil)
    }

    @Test func aNewNameKeepsTheStateAsItIs() throws {
        let shown = try Flat.decode(Device.self, Flat.rollo(1, position: 60))
        let answer = try Flat.decode(Device.self, named(Flat.rollo(1, position: 0), "Kitchen blind", default: "Blind 1"))
        let device = shown.named(like: answer)
        #expect(device.label == "Kitchen blind")
        #expect(device.defaultLabel == "Blind 1")
        #expect(device.state.position == 60)
    }
}

/// `PATCH /api/devices/{id}` and how a refusal reads.
struct RenameClientTests {
    let transport = FakeTransport()
    let connection = Flat.connection()
    var client: FlatdClient { FlatdClient(Flat.pairing(), transport: transport).gated(by: connection) }

    @Test func aNameAndTheConfigNameAgain() async throws {
        transport.answer("PATCH /api/devices/fan:fan_1", body: named(Flat.fan(1), "Desk fan", default: "Fan 1"))
        #expect(try await client.rename("fan:fan_1", to: "Desk fan").label == "Desk fan")
        #expect(label(transport, "fan:fan_1") as? String == "Desk fan")
        let request = try #require(transport.sent.last)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Flat.key)")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        _ = try await client.rename("fan:fan_1", to: nil)
        #expect(label(transport, "fan:fan_1") is NSNull)                 // {"label": null}
    }

    @Test func anOlderFlatdCannotRename() async {
        transport.answer("PATCH /api/devices/fan:fan_1", status: 405, body: ["error": "Method Not Allowed"])
        await #expect(throws: FlatdError.renameNotSupported) { try await client.rename("fan:fan_1", to: "Desk fan") }
        transport.answer("PATCH /api/devices/fan:fan_1", status: 400, body: ["error": "label must be at most 40 characters"])
        await #expect(throws: FlatdError.failed(status: 400, message: "label must be at most 40 characters")) {
            try await client.rename("fan:fan_1", to: "Desk fan")
        }
        transport.answer("PATCH /api/devices/fan:gone", status: 404, body: ["error": "Unknown device id"])
        await #expect(throws: FlatdError.unknown) { try await client.rename("fan:gone", to: "Desk fan") }
    }

    @Test func theCalmLineInBothLanguages() {
        #expect(FlatdError.renameNotSupported.message(language: .english)
                == "This flat service can't rename yet. Update flatd, then try again.")
        #expect(FlatdError.renameNotSupported.message(language: .german).hasPrefix("Dieser Wohnungsdienst"))
        #expect(PageScript.errorWord(.renameNotSupported) == "failed")
    }
}

/// flatd's rules for a name, as the field applies them.
struct DeviceNamesTests {
    @Test func whatTheFieldKeeps() {
        #expect(DeviceNames.typed("Fan\t1") == "Fan1")
        #expect(DeviceNames.typed("Desk\nfan") == "Desk fan")                 // a pasted line break: a space
        #expect(DeviceNames.typed("Fan\u{7F}\u{0}") == "Fan")
        #expect(DeviceNames.typed("Fan\u{2028}1") == "Fan 1")                // a line separator: a space too
        #expect(DeviceNames.typed(String(repeating: "x", count: 45)) == String(repeating: "x", count: 40))
        // Leading and trailing spaces do not count, as flatd trims them; typing "Desk " keeps its space.
        #expect(DeviceNames.typed("Desk ") == "Desk ")
        #expect(DeviceNames.typed("  " + String(repeating: "x", count: 40)) == "  " + String(repeating: "x", count: 40))
        // flatd counts code points: an emoji with a skin tone is two, and is dropped whole, never cut.
        let thumb = "\u{1F44D}\u{1F3FD}"
        let full = String(repeating: "x", count: 38) + thumb
        #expect(DeviceNames.typed(full) == full)
        #expect(DeviceNames.typed(full + thumb) == full)
        #expect(DeviceNames.typed(String(repeating: "x", count: 39) + thumb) == String(repeating: "x", count: 39))
    }

    @Test func aLongPasteIsCutInOnePass() {
        // Once each character dropped normalized the whole rest again, on the main thread (Codex's review, finding 6).
        let pasted = String(repeating: "Desk fan ", count: 12_000)               // 108,000 characters
        #expect(DeviceNames.typed(pasted) == String(pasted.prefix(41)))          // 40 that count, and a space
        #expect(DeviceNames.typed("   " + String(repeating: "x", count: 50_000))
                == "   " + String(repeating: "x", count: 40))
        // Counted as flatd counts them, in NFC: an e with a combining accent is one, and stays whole.
        let accented = DeviceNames.typed(String(repeating: "e\u{301}", count: 50_000))
        #expect(accented.count == 40)
        #expect(accented.unicodeScalars.count == 80)                             // as typed, not normalized
        #expect(DeviceNames.cleaned(accented).unicodeScalars.count == 40)
        let thumbs = DeviceNames.typed(String(repeating: "\u{1F44D}\u{1F3FD}", count: 30_000))
        #expect(thumbs == String(repeating: "\u{1F44D}\u{1F3FD}", count: 20))
    }

    @Test func theNameAsFlatdKeepsIt() {
        #expect(DeviceNames.cleaned("  Cafe\u{301} fan ") == "Caf\u{E9} fan")
        #expect(DeviceNames.cleaned(" \n ") == "")
    }

    @Test func whatSavingChanges() throws {
        let fan = try Flat.decode(Device.self, named(Flat.fan(1), "Fan 1", default: "Fan 1"))
        #expect(DeviceNames.change("Fan 1", for: fan) == nil)
        #expect(DeviceNames.change("  Fan 1 ", for: fan) == nil)
        #expect(DeviceNames.change("", for: fan) == nil)                     // no own name to clear
        #expect(DeviceNames.change(" Desk fan ", for: fan) == .own("Desk fan"))
        #expect(DeviceNames.change("Desk fan", for: fan)?.label == "Desk fan")
        let renamed = try Flat.decode(Device.self, named(Flat.fan(1), "Desk fan", default: "Fan 1"))
        #expect(DeviceNames.change("Desk fan", for: renamed) == nil)
        #expect(DeviceNames.change("", for: renamed) == .original)
        #expect(DeviceNames.change("   ", for: renamed) == .original)
        #expect(DeviceNames.change("Fan 1", for: renamed) == .original)      // the config's name: the own one cleared
        #expect(DeviceNames.Change.original.label == nil)
        #expect(DeviceNames.shown(.original, for: renamed) == "Fan 1")
        #expect(DeviceNames.shown(.own("Balcony"), for: renamed) == "Balcony")
        // A flatd before v1.3: a new name is still sent (flatd then says it can't), an empty field changes nothing.
        let older = try Flat.decode(Device.self, Flat.fan(1))
        #expect(DeviceNames.change("", for: older) == nil)
        #expect(DeviceNames.change("Desk fan", for: older) == .own("Desk fan"))
    }
}

/// The store: a rename shown quietly until flatd confirms it, a rename from elsewhere arriving live, and every place
/// that keeps names (Shortcuts' choices, the Blind control, the 3D page) hearing it.
@MainActor
struct RenameStoreTests {
    func liveStore() async throws -> (FlatStore, FakeTransport, FakeEvents, Counter) {
        let (store, transport, events, reloads) = Flat.store()
        transport.answer("GET /api/scenes", body: ["scenes": []])
        store.start()
        #expect(await eventually { events.isOpen })
        events.send(try Flat.snapshot())
        #expect(await eventually { store.link == .live })
        return (store, transport, events, reloads)
    }

    @Test func aRenameShowsQuietlyUntilFlatdConfirmsIt() async throws {
        let (store, transport, _, reloads) = try await liveStore()
        // flatd's answer carries the blind's state as flatd has it; the stream's stays (the answer names it only).
        transport.answer("PATCH /api/devices/rollo:blind_1",
                         body: named(Flat.rollo(1, position: 0), "Kitchen blind", default: "Blind 1"),
                         delay: .milliseconds(150))
        let before = reloads.count
        store.rename("rollo:blind_1", to: "  Kitchen blind ")
        #expect(store.renaming["rollo:blind_1"] == "Kitchen blind")
        #expect(store.isWorking("label:rollo:blind_1"))
        #expect(store.device("rollo:blind_1")?.label == "Blind 1")         // never shown as done before flatd says so
        #expect(await eventually { store.device("rollo:blind_1")?.label == "Kitchen blind" })
        #expect(store.renaming["rollo:blind_1"] == nil)
        #expect(store.device("rollo:blind_1")?.state.position == 60)
        #expect(store.device("rollo:blind_1")?.hasOwnName == true)
        #expect(label(transport, "rollo:blind_1") as? String == "Kitchen blind")
        // Shortcuts' choices read the new name, and Control Center reads its Blind control again.
        #expect(await eventually {
            store.connection.knownDevices.first { $0.id == "rollo:blind_1" }?.label == "Kitchen blind"
        })
        #expect(reloads.count > before)
        store.stop()
    }

    @Test func theSameNameSendsNothing() async throws {
        let (store, transport, _, _) = try await liveStore()
        store.rename("fan:fan_1", to: " Fan 1 ")
        store.rename("fan:fan_1", to: "")                                   // no own name to clear
        store.rename("fan:unknown", to: "Desk fan")
        #expect(store.renaming.isEmpty)
        #expect(!store.isWorking("label:fan:fan_1"))
        #expect(transport.sent.allSatisfy { $0.httpMethod != "PATCH" })
        store.stop()
    }

    @Test func aRenameFromElsewhereArrivesLive() async throws {
        let (store, transport, events, reloads) = try await liveStore()
        var heard: [String] = []
        _ = store.listen { event in
            if case let .device(device, source) = event { heard.append(device.label + " · " + (source ?? "none")) }
        }
        let before = reloads.count
        events.send(.device(try Flat.decode(Device.self, named(Flat.rollo(1, position: 0), "Kitchen blind",
                                                               default: "Blind 1")), source: "mcp"))
        #expect(await eventually { store.device("rollo:blind_1")?.label == "Kitchen blind" })
        #expect(store.device("rollo:blind_1")?.state.position == 60)
        #expect(heard == ["Kitchen blind · mcp"])                           // the 3D page hears it, and who did it
        #expect(await eventually {
            store.connection.knownDevices.first { $0.id == "rollo:blind_1" }?.label == "Kitchen blind"
        })
        #expect(reloads.count == before + 1)                                // the Blind control shows the name
        // A device flatd does not list here is no news.
        events.send(.device(Device(id: "fan:elsewhere", kind: .fan, label: "Somewhere"), source: "api"))
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.device("fan:elsewhere") == nil)
        // Clearing the own name asks flatd for its config name again ({"label": null}).
        transport.answer("PATCH /api/devices/rollo:blind_1", body: named(Flat.rollo(1), "Blind 1", default: "Blind 1"))
        store.rename("rollo:blind_1", to: "   ")
        #expect(store.renaming["rollo:blind_1"] == "Blind 1")
        #expect(await eventually { store.device("rollo:blind_1")?.label == "Blind 1" })
        #expect(label(transport, "rollo:blind_1") is NSNull)
        store.stop()
    }

    @Test func anOlderFlatdSaysItCalmly() async throws {
        let (store, transport, _, _) = try await liveStore()
        transport.answer("PATCH /api/devices/fan:fan_1", status: 405, body: ["error": "Method Not Allowed"])
        store.rename("fan:fan_1", to: "Desk fan")
        #expect(await eventually { store.offer != nil })
        #expect(store.offer?.message == FlatdError.renameNotSupported.message())
        #expect(store.offer?.undo == nil)
        #expect(store.renaming.isEmpty)
        #expect(store.device("fan:fan_1")?.label == "Fan 1")                 // the name as it was
        #expect(store.link == .live)
        store.stop()
    }

    /// The field opened, a rename from elsewhere arriving, the field losing the keyboard untouched (a scroll): nothing
    /// is sent, so the other rename stands (Codex's review of the renaming, finding 1).
    @Test func anUntouchedFieldSendsNothing() async throws {
        let (store, transport, events, _) = try await liveStore()
        let editor = RenameEditor()
        editor.begin(try #require(store.device("fan:fan_1")), in: store)
        #expect(editor.isEditing("fan:fan_1"))
        #expect(editor.text == "Fan 1")
        events.send(.device(try Flat.decode(Device.self, named(Flat.fan(1), "Kitchen fan", default: "Fan 1")),
                            source: "mcp"))
        #expect(await eventually { store.device("fan:fan_1")?.label == "Kitchen fan" })
        editor.save(in: store)                                              // what losing the keyboard does
        #expect(!editor.isEditing("fan:fan_1"))
        // A config name longer than an own name may be, opened and left: never cut to 40 and sent.
        let long = String(repeating: "x", count: 45)
        events.send(.device(try Flat.decode(Device.self, named(Flat.fan(2), long, default: long)), source: "api"))
        #expect(await eventually { store.device("fan:fan_2")?.label == long })
        editor.begin(try #require(store.device("fan:fan_2")), in: store)
        editor.save(in: store)
        // Edited back to the name it opened with (spaces at the ends do not count): nothing either.
        editor.begin(try #require(store.device("fan:fan_1")), in: store)
        editor.text = DeviceNames.typed("Desk")
        editor.text = DeviceNames.typed(" Kitchen fan ")
        editor.save(in: store)
        try await Task.sleep(for: .milliseconds(100))
        #expect(transport.sent.allSatisfy { $0.httpMethod != "PATCH" })
        #expect(store.device("fan:fan_1")?.label == "Kitchen fan")
        #expect(store.device("fan:fan_2")?.label == long)
        // Edited, it is sent; emptied, the own name is cleared.
        transport.answer("PATCH /api/devices/fan:fan_1", body: named(Flat.fan(1), "Desk fan", default: "Fan 1"))
        editor.begin(try #require(store.device("fan:fan_1")), in: store)
        editor.text = DeviceNames.typed("Desk fan")
        editor.save(in: store)
        #expect(await eventually { store.device("fan:fan_1")?.label == "Desk fan" })
        #expect(label(transport, "fan:fan_1") as? String == "Desk fan")
        transport.answer("PATCH /api/devices/fan:fan_1", body: named(Flat.fan(1), "Fan 1", default: "Fan 1"))
        #expect(await eventually { !store.isRenaming("fan:fan_1") })
        editor.begin(try #require(store.device("fan:fan_1")), in: store)
        editor.text = ""
        editor.save(in: store)
        #expect(await eventually { store.device("fan:fan_1")?.label == "Fan 1" })
        #expect(label(transport, "fan:fan_1") is NSNull)
        #expect(transport.bodies(for: "PATCH /api/devices/fan:fan_1").count == 2)
        store.stop()
    }

    /// The stream confirms a name while flatd's answer is still on its way: the name shows as done, but renaming waits
    /// for the answer (the menu, the field and VoiceOver's action alike), so no second name is dropped unseen (Codex's
    /// review of the renaming, finding 2).
    @Test func renamingWaitsForFlatdsAnswerAfterTheStreamConfirmedIt() async throws {
        let (store, transport, events, _) = try await liveStore()
        let desk = try Flat.decode(Device.self, named(Flat.fan(1), "Desk fan", default: "Fan 1"))
        transport.answer("PATCH /api/devices/fan:fan_1", body: named(Flat.fan(1), "Desk fan", default: "Fan 1"),
                         delay: .milliseconds(400))
        store.rename("fan:fan_1", to: "Desk fan")
        events.send(.device(desk, source: "api"))
        #expect(await eventually { store.renaming.isEmpty && store.device("fan:fan_1")?.label == "Desk fan" })
        #expect(store.isRenaming("fan:fan_1"))                              // shown as done, the request still out
        let editor = RenameEditor()
        editor.begin(try #require(store.device("fan:fan_1")), in: store)
        #expect(!editor.isEditing("fan:fan_1"))
        store.rename("fan:fan_1", to: "Balcony fan")                        // the Original name item's way: not taken
        #expect(store.renaming.isEmpty)
        #expect(await eventually { !store.isRenaming("fan:fan_1") })
        editor.begin(try #require(store.device("fan:fan_1")), in: store)
        #expect(editor.isEditing("fan:fan_1"))
        #expect(editor.text == "Desk fan")
        editor.cancel()
        #expect(transport.bodies(for: "PATCH /api/devices/fan:fan_1").count == 1)
        store.stop()
    }

    /// A picker or the Blind control reads flatd's list; a rename reaches the app before that list's answer: the older
    /// list never replaces the newer name in what Shortcuts and the controls show offline (Codex's review, finding 3).
    @Test func anOlderListNeverReplacesANameHeardSince() async throws {
        let (store, transport, events, _) = try await liveStore()
        let connection = store.connection
        let kept = { connection.knownDevices.first { $0.id == "rollo:blind_1" }?.label }
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1), Flat.fan(2), Flat.rollo(1), Flat.rollo(2)]],
                         delay: .milliseconds(300))
        let reach = FlatdReach(connection: connection, transport: transport, rediscover: { [] })
        let reading = Task { try await FlatActions(reach: reach).rollo(SavedDevice.id(for: "rollo:blind_1", of: Flat.id)) }
        try await Task.sleep(for: .milliseconds(100))
        events.send(.device(try Flat.decode(Device.self, named(Flat.rollo(1), "Kitchen blind", default: "Blind 1")),
                            source: "mcp"))
        #expect(await eventually { kept() == "Kitchen blind" })
        #expect(try await reading.value?.label == "Kitchen blind")         // never the late answer's older name
        #expect(kept() == "Kitchen blind")
        // A list read after it is kept, from a picker too.
        transport.answer("GET /api/devices",
                         body: ["devices": [named(Flat.rollo(1), "Bedroom blind", default: "Blind 1"), Flat.rollo(2)]])
        let choices = await DeviceChoices.load(kind: .rollo, connection: connection, reach: reach)
        #expect(choices.map(\.label) == ["Bedroom blind", "Blind 2"])
        #expect(kept() == "Bedroom blind")
        store.stop()
    }

    @Test func aReadingKeepsItsListOnlyWhileNothingNewerWasKept() async throws {
        let connection = Flat.connection()
        let first = connection.devicesVersion
        #expect(first == nil)                                               // nothing kept yet
        await connection.remember(try Flat.devices([Flat.fan(1)]), for: Flat.id, readSince: first)
        #expect(connection.knownDevices.map(\.label) == ["Fan 1"])
        let begun = connection.devicesVersion
        #expect(begun != nil)
        await connection.remember(try Flat.devices([named(Flat.fan(1), "Desk fan", default: "Fan 1")]), for: Flat.id)
        await connection.remember(try Flat.devices([Flat.fan(1)]), for: Flat.id, readSince: begun)
        #expect(connection.knownDevices.map(\.label) == ["Desk fan"])
        // The stream's names are always the newest, even the same names again (a list read before them is older).
        let again = connection.devicesVersion
        await connection.remember(try Flat.devices([named(Flat.fan(1), "Desk fan", default: "Fan 1")]), for: Flat.id)
        #expect(connection.devicesVersion != again)
        await connection.remember(try Flat.devices([Flat.fan(1)]), for: Flat.id, readSince: again)
        #expect(connection.knownDevices.map(\.label) == ["Desk fan"])
    }

    /// The Blind control's gallery preview names the chosen blind only as the paired flat calls it now (Codex's
    /// review, finding 5): never a forgotten flat's name kept in the control's configuration.
    @Test func theBlindPreviewNamesOnlyThePairedFlatsBlind() async throws {
        let connection = Flat.connection()
        await connection.remember(try Flat.devices([Flat.fan(1), named(Flat.rollo(1), "Kitchen blind", default: "Blind 1")]),
                            for: Flat.id)
        let chosen = SavedDevice.id(for: "rollo:blind_1", of: Flat.id)
        #expect(DeviceChoices.name(of: chosen, kind: .rollo, from: connection.known) == "Kitchen blind")
        #expect(DeviceChoices.name(of: nil, kind: .rollo, from: connection.known) == nil)
        #expect(DeviceChoices.name(of: SavedDevice.id(for: "rollo:blind_1", of: UUID()), kind: .rollo,
                                   from: connection.known) == nil)          // chosen for another pairing
        #expect(DeviceChoices.name(of: SavedDevice.id(for: "fan:fan_1", of: Flat.id), kind: .rollo,
                                   from: connection.known) == nil)
        try await connection.forgetSavedPairing()
        #expect(DeviceChoices.name(of: chosen, kind: .rollo, from: connection.known) == nil)
    }

    @Test func aRetiredStoreForgetsWhatWasOnItsWay() async throws {
        let (store, transport, _, _) = try await liveStore()
        transport.answer("PATCH /api/devices/fan:fan_1", body: named(Flat.fan(1), "Desk fan", default: "Fan 1"),
                         delay: .milliseconds(150))
        store.rename("fan:fan_1", to: "Desk fan")
        store.retire()
        #expect(store.renaming.isEmpty)
        try await Task.sleep(for: .milliseconds(250))
        #expect(store.devices.isEmpty)
    }

    @Test func lightsHaveTheirOwnSection() throws {
        let (store, _, _, _) = Flat.store()
        var lamp = Flat.fan(9)
        lamp["id"] = "light:desk_lamp"
        lamp["kind"] = "light"
        lamp["label"] = "Desk lamp"
        var plug = Flat.fan(8)
        plug["id"] = "plug:plug_1"
        plug["kind"] = "plug"
        store.apply(.snapshot(devices: try Flat.devices([Flat.fan(1), lamp, plug, Flat.rollo(1),
                                                         ["id": "heater:bath", "kind": "heater"]]), modes: []))
        #expect(store.fans.map(\.id) == ["fan:fan_1"])
        #expect(store.lights.map(\.id) == ["light:desk_lamp"])
        #expect(store.rollos.map(\.id) == ["rollo:blind_1"])
        #expect(store.others.map(\.id) == ["plug:plug_1", "heater:bath"])   // More: plugs and kinds of a newer flatd
    }
}
