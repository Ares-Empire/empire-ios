import Foundation
import Testing
import UIKit
@testable import Arestia

// The pairing's identity (`FlatdPairing.id`) as the one value every piece of work carries (the trust review's round 4
// and the design that ends its class): the store, the 3D page, a command, a picker's choices. Work tagged with another
// identity is dropped, never acted on; pairing with another flatd goes only through a full Disconnect.

/// Two made-up flats on the fake transport, told apart by their addresses: A (the test flat) and B (another flatd).
private enum Flats {
    static let hostA = "192.0.2.10"
    static let hostB = "192.0.2.77"
    static let baseB = URL(string: "https://192.0.2.77:8788")!
    static let keyB = "other-key-0123456789abcdef"
    static let health: [String: Any] = ["ok": true, "version": "1.2.0-test"]

    /// B's devices: the same ids as A's (flatd's ids are only names inside one flatd), other names.
    static func devicesB() -> [[String: Any]] {
        var fan = Flat.fan(1), blind = Flat.rollo(1)
        fan["label"] = "Other fan"
        blind["label"] = "Other blind"
        return [fan, blind]
    }

    static func answerB(_ transport: FakeTransport) {
        transport.answer("GET \(hostB)/api/devices", body: ["devices": devicesB()])
        transport.answer("GET \(hostB)/api/scenes", body: ["scenes": []])
    }

    /// Everything that reached flat B.
    static func reachedB(_ transport: FakeTransport) -> [URLRequest] { transport.requests(to: hostB) }
}

@MainActor
struct PairingIdentityTests {
    let on = Data(#"{"on":true}"#.utf8)

    /// The regression the design is for: one pairing's work in flight (the 3D page loaded and listening, a command
    /// queued, a Shortcuts picker open) while the phone pairs with another flatd. Nothing of the old session reaches the
    /// new flat, the old page hears nothing of it, and the old picker's choices act on nothing there.
    @Test func rePairingMidFlightReachesNothingOfTheNewFlatFromTheOldSession() async throws {
        let connection = Flat.connection()
        let (store, transport, events, _) = Flat.store(connection: connection)
        // Flat A answers slowly, so its work is still on its way when the pairing changes.
        transport.answer("GET \(Flats.hostA)/api/health", body: Flats.health, delay: .milliseconds(400))
        transport.answer("GET \(Flats.hostA)/api/devices", body: ["devices": [Flat.fan(1), Flat.rollo(1)]],
                         delay: .milliseconds(400))
        transport.answer("POST /api/devices/fan:fan_1", body: Flat.fan(1, on: true))
        transport.answer("POST /api/modes/cooking", body: Flat.cooking)
        Flats.answerB(transport)
        let idA = try #require(store.pairingID)
        connection.remember(try Flat.devices([Flat.fan(1), Flat.rollo(1)]), for: idA)
        let choiceA = try #require(DeviceChoices.choices(kind: .rollo, from: connection.known).first)

        // The page of flat A, loaded and listening.
        var heardByPageA: [FlatEvent] = []
        let listener = try #require(store.listen(for: idA) { heardByPageA.append($0) })
        // A command queued (its address is still being checked), the page's own request and a picker, all for A.
        store.setFan("fan:fan_1", on: true)
        let pageRequest = Task { await store.pageRequest("fan:fan_1", body: on, pairing: idA) }
        let pageMode = Task { await store.pageMode("cooking", body: Data(#"{"active":false}"#.utf8), pairing: idA) }
        let reach = FlatdReach(connection: connection, transport: transport, rediscover: { [] })
        let picker = Task.detached { await DeviceChoices.load(kind: .rollo, connection: connection, reach: reach) }
        try await Task.sleep(for: .milliseconds(50))

        // Paired with another flatd, confirmed: a full Disconnect first, then the new pairing.
        #expect(await store.connect(to: Flats.baseB, token: Flats.keyB, pin: MadeUpCertificates.pinB,
                                    replacing: true) == nil)
        let idB = try #require(store.pairingID)
        #expect(idB != idA && connection.pairing?.id == idB && connection.pairing?.pin == MadeUpCertificates.pinB)
        let heardBefore = heardByPageA.count

        // Everything of A's session gets its turn now.
        #expect(await pageRequest.value == .notPossible)
        #expect(await pageMode.value == .notPossible)
        let choices = await picker.value
        try await Task.sleep(for: .milliseconds(600))
        #expect(await eventually { events.isOpen })
        events.send(.snapshot(devices: try Flat.devices(Flats.devicesB()), modes: []))
        #expect(await eventually { store.link == .live })

        // Nothing of A's session reached flat B: no command, and no key of A's.
        #expect(Flats.reachedB(transport).allSatisfy { $0.httpMethod == "GET" })
        #expect(Flats.reachedB(transport).allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization").map { $0 == "Bearer \(Flats.keyB)" } ?? true
        })
        // The queued command was dropped with A's pairing: it reached no flat at all.
        #expect(transport.bodies(for: "POST /api/devices/fan:fan_1").isEmpty)
        #expect(transport.bodies(for: "POST /api/modes/cooking").isEmpty)
        // A's page hears nothing of B, and can no longer listen, read or speak.
        #expect(heardByPageA.count == heardBefore)
        #expect(store.listen(for: idA) { _ in } == nil && store.snapshot(for: idA) == nil && !store.speaks(for: idA))
        store.unlisten(listener)
        // The picker's choices are labelled with the pairing their names belong to (B's names, B's identity).
        #expect(choices.allSatisfy { $0.id.hasPrefix(idB.uuidString.lowercased() + "/") })
        #expect(choices.map(\.label) == ["Other blind"])
        // A choice made in A's pairing acts on nothing in B's, though B has a device with that id.
        let actions = FlatActions(reach: reach)
        await #expect(throws: FlatdError.unknown) { try await actions.move(rollo: choiceA.id, .up) }
        await #expect(throws: FlatdError.unknown) { try await actions.setFans(on: true, only: [choiceA.id]) }
        #expect(try await actions.rollo(choiceA.id) == nil)
        #expect(Flats.reachedB(transport).allSatisfy { $0.httpMethod == "GET" })
        // A's names went with A's pairing.
        #expect(connection.known?.pairing == idB)
        store.stop()
    }

    /// Finding (a): two windows, each with its own store, on one Keychain. One pairs with another flatd; the other's old
    /// page neither commands the new flat nor hears it, also after that store reconnects.
    @Test func aSecondStoreLeavesItsPairingWhenAnotherOneWasMadeElsewhere() async throws {
        let connection = Flat.connection()
        let transport = FakeTransport()
        Flats.answerB(transport)
        transport.answer("GET /api/scenes", body: ["scenes": []])
        transport.answer("POST /api/devices/fan:fan_1", body: Flat.fan(1, on: true))
        let (first, _, eventsA, _) = Flat.store(transport: transport, connection: connection)
        let (second, _, _, _) = Flat.store(transport: transport, connection: connection)
        first.start()
        #expect(await eventually { eventsA.isOpen })
        eventsA.send(try Flat.snapshot())
        #expect(await eventually { first.link == .live })
        let idA = try #require(first.pairingID)
        var heardByPageA: [FlatEvent] = []
        _ = try #require(first.listen(for: idA) { heardByPageA.append($0) })

        // The other window pairs with flat B.
        #expect(await second.connect(to: Flats.baseB, token: Flats.keyB, pin: MadeUpCertificates.pinB,
                                     replacing: true) == nil)
        let idB = try #require(second.pairingID)
        let heardBefore = heardByPageA.count

        // The first window's page asks to switch a fan: the Keychain has another pairing, so nothing is sent.
        #expect(await first.pageRequest("fan:fan_1", body: on, pairing: idA) == .notPossible)
        #expect(transport.sent.allSatisfy { $0.httpMethod != "POST" })
        // The first store left A completely and follows B now; A's page is told nothing of B.
        #expect(await eventually { first.pairingID == idB })
        #expect(await eventually { eventsA.requests.last?.url?.host() == Flats.hostB })
        eventsA.send(.snapshot(devices: try Flat.devices(Flats.devicesB()), modes: []))
        #expect(await eventually { first.device("fan:fan_1")?.label == "Other fan" })
        #expect(heardByPageA.count == heardBefore)
        #expect(!first.speaks(for: idA))
        first.stop()
        second.stop()
    }

    /// Finding (a), the stream's side: a store whose stream reconnects after the pairing changed elsewhere never shows the
    /// new flat's snapshot to the old pairing's page.
    @Test func aReconnectAfterAPairingElsewhereStartsFromNothing() async throws {
        let connection = Flat.connection()
        let (store, transport, events, _) = Flat.store(connection: connection)
        transport.answer("GET /api/scenes", body: ["scenes": []])
        Flats.answerB(transport)
        store.start()
        #expect(await eventually { events.isOpen })
        events.send(try Flat.snapshot())
        #expect(await eventually { store.link == .live })
        let idA = try #require(store.pairingID)
        var heard: [FlatEvent] = []
        _ = try #require(store.listen(for: idA) { heard.append($0) })
        let heardBefore = heard.count
        // Another process pairs with B (as Debug or a second window would), then A's stream drops.
        let other = FlatdPairing(baseURL: Flats.baseB, token: Flats.keyB, pin: MadeUpCertificates.pinB)
        try connection.save(other)
        events.end(FlatdError.unreachable)
        #expect(await eventually({ store.pairingID == other.id }, timeout: .seconds(4)))
        #expect(store.devices.isEmpty || store.device("fan:fan_1")?.label != "Fan 1")
        #expect(await eventually({ events.requests.last?.url?.host() == Flats.hostB }, timeout: .seconds(4)))
        events.send(.snapshot(devices: try Flat.devices(Flats.devicesB()), modes: []))
        #expect(await eventually { store.link == .live })
        #expect(heard.count == heardBefore)
        store.stop()
    }

    /// Finding (b): the picker reads the names and the pairing they belong to in one reading. Another process pairing
    /// between two Keychain readings can no longer lend its identity to the old pairing's names.
    @Test func aPickerLabelsNamesWithTheirOwnPairingEvenWhenThePairingChangesBetweenReadings() async throws {
        let keys = MemoryKeys()
        let defaults = UserDefaults(suiteName: "arestia-tests-" + UUID().uuidString)!
        let connection = FlatdConnection(defaults: defaults, keychain: keys)
        try connection.save(Flat.pairing())
        connection.remember(try Flat.devices([Flat.rollo(1)]), for: Flat.id)
        // Right after the next Keychain reading, another process pairs with flat B.
        let other = FlatdPairing(baseURL: Flats.baseB, token: Flats.keyB, pin: MadeUpCertificates.pinB)
        let otherText = String(decoding: try JSONEncoder().encode(other), as: UTF8.self)
        let fired = Fired()
        keys.afterRead = {
            guard fired.once() else { return }
            try? keys.save(otherText, label: other.revision.uuidString)
        }
        let choices = DeviceChoices.choices(kind: .rollo, from: connection.known)
        #expect(connection.pairing?.id == other.id)                       // the pairing did change meanwhile
        #expect(choices.map(\.id) == [SavedDevice.id(for: "rollo:blind_1", of: Flat.id)])   // still A's own label
        // Used under B, that choice moves nothing.
        let transport = FakeTransport()
        transport.answer("GET /api/devices", body: ["devices": Flats.devicesB()])
        transport.answer("POST /api/devices/rollo:blind_1", body: Flat.rollo(1))
        let actions = FlatActions(reach: FlatdReach(connection: connection, transport: transport, rediscover: { [] }))
        await #expect(throws: FlatdError.unknown) { try await actions.move(rollo: choices[0].id, .down) }
        #expect(transport.sent.allSatisfy { $0.httpMethod != "POST" })
    }

    /// Finding (c): an attempt connects exactly the code it was started with. A second code scanned meanwhile (another
    /// flatd's) is never connected by it; it waits for its own Connect.
    @Test func anAttemptConnectsOnlyTheCodeItWasStartedWith() async throws {
        let connection = Flat.connection()
        let (store, transport, _, _) = Flat.store(connection: connection)
        let hint = URL(string: "https://192.0.2.20:8788")!
        transport.answer("GET 192.0.2.20/api/health", body: Flats.health, delay: .milliseconds(300))
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1)]])
        transport.answer("GET /api/scenes", body: ["scenes": []])
        Flats.answerB(transport)
        let model = ConnectModel(candidates: { [] })
        // A fresh code of the paired flatd (a new key): it connects at once, without a question.
        let renewedKey = "renewed-key-0123456789abcdef"
        let fresh = try #require(model.take(#"{"url":"\#(hint)","token":"\#(renewedKey)","spki_sha256":"\#(Flat.pin.hex)"}"#))
        #expect(!ConnectModel.needsConfirmation(fresh, saved: connection.saved))
        let attempt = Task { await model.connect(fresh, replacing: false, store: store) }
        try await Task.sleep(for: .milliseconds(50))
        // Meanwhile another flatd's code is scanned: it is shown, and needs its own Connect.
        let foreign = try #require(model.take(
            #"{"url":"\#(Flats.baseB)","token":"\#(Flats.keyB)","spki_sha256":"\#(MadeUpCertificates.pinB.hex)"}"#))
        #expect(ConnectModel.needsConfirmation(foreign, saved: connection.saved))
        #expect(await attempt.value)
        // The attempt kept the code it started with: the same flatd, renewed in place, its identity kept.
        #expect(connection.pairing?.pin == Flat.pin && connection.token == renewedKey)
        #expect(connection.pairing?.id == Flat.id && store.pairingID == Flat.id)
        #expect(Flats.reachedB(transport).isEmpty)
        #expect(model.code == foreign)                                    // still on screen, waiting for Connect
        // And the store itself refuses the foreign code without that Connect.
        #expect(await store.connect(to: Flats.baseB, token: Flats.keyB, pin: MadeUpCertificates.pinB) == .notPossible)
        #expect(connection.pairing?.pin == Flat.pin)
        store.stop()
    }

    /// A fresh code of the paired flatd keeps the pairing's identity, so its page, choices and work go on; the stream
    /// starts again with the new key.
    @Test func aFreshCodeOfTheSameFlatdIsALightUpdate() async throws {
        let connection = Flat.connection()
        let (store, transport, events, _) = Flat.store(connection: connection)
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1)]])
        transport.answer("GET /api/scenes", body: ["scenes": []])
        store.start()
        #expect(await eventually { events.isOpen })
        events.send(try Flat.snapshot())
        #expect(await eventually { store.link == .live })
        var heard: [FlatEvent] = []
        _ = try #require(store.listen(for: Flat.id) { heard.append($0) })
        let moved = URL(string: "https://192.0.2.30:8788")!
        #expect(await store.connect(to: moved, token: "renewed-key-0123456789abcdef", pin: Flat.pin) == nil)
        #expect(store.pairingID == Flat.id && connection.pairing?.id == Flat.id)
        #expect(connection.pairing?.baseURL == moved && connection.token == "renewed-key-0123456789abcdef")
        #expect(await eventually { events.requests.last?.url?.host() == "192.0.2.30" })
        #expect(events.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer renewed-key-0123456789abcdef")
        let before = heard.count
        events.send(try Flat.snapshot(fans: 1))
        #expect(await eventually { heard.count > before })
        guard case .snapshot = heard.last else {
            Issue.record("the page did not hear the new stream's snapshot")
            return
        }
        store.stop()
    }

    /// A refusal counts only for the key it was sent with: a command still under the old key of a renewed pairing does
    /// not send the app back to the connect screen.
    @Test func aRefusalOfAnOldKeyAfterARenewalIsNotARefusal() async throws {
        let connection = Flat.connection()
        let (store, transport, _, _) = Flat.store(connection: connection)
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1)]])
        transport.answer("GET /api/scenes", body: ["scenes": []])
        transport.answer("POST /api/devices/fan:fan_1", status: 401, body: ["error": "wrong token"],
                         delay: .milliseconds(300))
        store.setFan("fan:fan_1", on: true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(await store.connect(to: Flat.base, token: "renewed-key-0123456789abcdef", pin: Flat.pin) == nil)
        #expect(await eventually { !store.isWorking("power:fan:fan_1") })
        try await Task.sleep(for: .milliseconds(300))
        #expect(store.link != .refused)
        store.stop()
    }

    /// A late address update (its lookup started before a renewal) never puts the old key back: the Keychain item is
    /// written only over the version it was read as.
    @Test func aLateMoveNeverBringsBackAnOldKey() throws {
        let connection = Flat.connection()
        let read = try #require(connection.pairing)
        let renewed = FlatdPairing(baseURL: Flat.base, token: "renewed-key-0123456789abcdef", pin: Flat.pin, id: read.id)
        #expect(connection.renew(read, with: renewed))
        connection.move(read, to: URL(string: "https://192.0.2.77:8788")!)       // from before the renewal
        #expect(connection.token == "renewed-key-0123456789abcdef" && connection.pairing?.baseURL == Flat.base)
        // A renewal never changes the identity or the flatd.
        let other = FlatdPairing(baseURL: Flat.base, token: Flat.key, pin: MadeUpCertificates.pinB, id: read.id)
        #expect(!connection.renew(renewed, with: other))
        #expect(!connection.renew(renewed, with: Flat.pairing(id: UUID())))
        // A new pairing never overwrites one that is there.
        #expect(try connection.pairNew(Flat.pairing(id: UUID())) == false)
        #expect(connection.pairing?.id == read.id)
    }

    /// Disconnect forgets everything of the pairing: the item, the names kept for it, and the store's state, tasks and
    /// listeners; work of it that is still on its way changes nothing.
    @Test func disconnectLeavesNothingOfThePairing() async throws {
        let connection = Flat.connection()
        let (store, transport, events, _) = Flat.store(connection: connection)
        transport.answer("GET /api/scenes", body: ["scenes": []])
        transport.answer("POST /api/devices/fan:fan_1", body: Flat.fan(1, on: true), delay: .milliseconds(300))
        store.start()
        #expect(await eventually { events.isOpen })
        events.send(try Flat.snapshot())
        #expect(await eventually { store.link == .live })
        var heard = 0
        _ = try #require(store.listen(for: Flat.id) { _ in heard += 1 })
        store.setFan("fan:fan_1", on: true)
        try await Task.sleep(for: .milliseconds(50))
        store.disconnect()
        #expect(store.pairingID == nil && store.link == .notSetUp && store.devices.isEmpty && store.working.isEmpty)
        #expect(connection.pairing == nil && connection.knownDevices.isEmpty)
        let heardAfter = heard
        try await Task.sleep(for: .milliseconds(400))
        #expect(heard == heardAfter && store.devices.isEmpty)
        #expect(store.listen(for: Flat.id) { _ in } == nil)
    }
}

/// Finding (e): only the load the app handed over, once WebKit put *that* navigation in place, may speak.
@MainActor
struct PageHandoverTests {
    @Test func aLateCommitOfAnEarlierLoadDoesNotLetTheNextDocumentSpeak() {
        var handover = PageHandover()
        let first = NSObject(), second = NSObject()
        let one = handover.begin()
        let firstStarted = handover.loading(one, as: first)
        #expect(firstStarted && !handover.maySpeak)
        // A second load overlaps the first.
        let two = handover.begin()
        let earlierAgain = handover.loading(one, as: first)              // the earlier document is no longer awaited
        let secondStarted = handover.loading(two, as: second)
        #expect(!earlierAgain && secondStarted)
        handover.committed(first)                                         // the first load's late commit
        #expect(!handover.maySpeak)
        #expect(!handover.concerns(first))
        handover.committed(nil)
        #expect(!handover.maySpeak)
        handover.committed(second)
        #expect(handover.maySpeak && handover.document == two)
        #expect(handover.concerns(second) && !handover.concerns(first))
        // A new load silences the page at once.
        _ = handover.begin()
        #expect(!handover.maySpeak)
    }

    @Test func aLoadWebKitDidNotStartIsNotAwaited() {
        var handover = PageHandover()
        let one = handover.begin()
        let started = handover.loading(one, as: nil)
        #expect(!started)
        handover.committed(NSObject())
        #expect(!handover.maySpeak)
    }
}

/// Finding (a): the app has one window, so there is one store.
@MainActor
struct OneWindowTests {
    @Test func theAppDeclaresASingleScene() throws {
        let manifest = try #require(Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest")
                                    as? [String: Any])
        #expect(manifest["UIApplicationSupportsMultipleScenes"] as? Bool == false)
        #expect(UIApplication.shared.supportsMultipleScenes == false)
    }
}

/// Fires once, from any thread.
private nonisolated final class Fired: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func once() -> Bool {
        lock.withLock {
            defer { done = true }
            return !done
        }
    }
}
