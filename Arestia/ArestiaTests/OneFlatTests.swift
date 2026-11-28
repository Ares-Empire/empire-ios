import Foundation
import Testing
import UIKit
@testable import Arestia

// One flat per install (docs/ARESTIA-APP.md): the app is paired with one flatd identity at a time. Another flat is
// paired only after Forget, which ends every piece of work of the old one (its store retired, a new store for the next
// pairing); a code of another flat while one is paired is refused; a fresh code of the same flat renews key and address.

/// Two made-up flats on the fake transport, told apart by their addresses: A (the test flat) and B (another flatd).
private enum Flats {
    static let hostA = "192.0.2.10"
    static let hostB = "192.0.2.77"
    static let baseB = URL(string: "https://192.0.2.77:8788")!
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

    /// B's pairing code, as scanned.
    static var codeB: String {
        #"{"url":"\#(baseB)","token":"\#(Flat.otherKey)","spki_sha256":"\#(MadeUpCertificates.pinB.hex)"}"#
    }
}

@MainActor
struct OneFlatTests {
    let on = Data(#"{"on":true}"#.utf8)

    /// The regression the design is for: one flat's work in flight (the 3D page listening, a command queued, the page's
    /// own requests, a Shortcut) when the flat is forgotten and another one paired. Nothing of the old flat's session
    /// reaches the new flat or acts after Forget, the old page hears nothing, and the old choices act on nothing.
    @Test func forgetEndsEverythingOfTheFlatAndNothingOfItReachesTheNextOne() async throws {
        let connection = Flat.connection()
        let (session, transport, events, _) = Flat.session(connection: connection)
        let old = try #require(session.store)
        // Flat A answers slowly, so its work is still on its way when the flat is forgotten.
        transport.answer("GET \(Flats.hostA)/api/health", body: Flats.health, delay: .milliseconds(400))
        transport.answer("POST /api/devices/fan:fan_1", body: Flat.fan(1, on: true))
        transport.answer("POST /api/modes/cooking", body: Flat.cooking)
        transport.answer("GET /api/modes", body: ["modes": [Flat.cooking]])
        Flats.answerB(transport)
        connection.remember(try Flat.devices([Flat.fan(1), Flat.rollo(1)]), for: Flat.id)
        let blindOfA = try #require(DeviceChoices.choices(kind: .rollo, from: connection.known).first)
        let fanOfA = try #require(DeviceChoices.choices(kind: .fan, from: connection.known).first)

        // The old page listening, a command queued (its address still being checked), the page's own requests, a
        // Shortcut starting cooking: all for A.
        var heardByOldPage: [FlatEvent] = []
        _ = try #require(old.listen { heardByOldPage.append($0) })
        old.setFan("fan:fan_1", on: true)
        let pageRequest = old.pageRequest("fan:fan_1", body: on)
        let pageMode = old.pageMode("cooking", body: Data(#"{"active":false}"#.utf8))
        let reach = FlatdReach(connection: connection, transport: transport, rediscover: { [] })
        // The Shortcut has a transport of its own, so the test sees it started on A (it asked A's health) before
        // Forget: a detached task can start late on a busy machine, and one that starts after Forget acts, by design,
        // on the flat paired then (it failed on a GitHub runner that way, not in the app).
        let shortcutTransport = FakeTransport()
        shortcutTransport.answer("GET \(Flats.hostA)/api/health", body: Flats.health, delay: .seconds(2))
        shortcutTransport.answer("POST /api/modes/cooking", body: Flat.cooking)
        let shortcutReach = FlatdReach(connection: connection, transport: shortcutTransport, rediscover: { [] })
        let shortcut = Task.detached { try await FlatActions(reach: shortcutReach).setCooking(true) }
        #expect(await eventually { !shortcutTransport.requests(to: Flats.hostA).isEmpty })
        try await Task.sleep(for: .milliseconds(50))

        // Forget: the old store is retired at once and a new one without a pairing takes its place.
        #expect(session.forget())
        #expect(old.isRetired && old.working.isEmpty && old.devices.isEmpty && old.offer == nil)
        #expect(connection.saved == .none && connection.knownDevices.isEmpty)
        let unpaired = try #require(session.store)
        #expect(unpaired !== old && unpaired.pairingID == nil && unpaired.link == .notSetUp)

        // Flat B is paired: a store of its own again.
        #expect(await unpaired.connect(to: Flats.baseB, token: Flat.otherKey, pin: MadeUpCertificates.pinB) == nil)
        let storeB = try #require(session.store)
        let idB = try #require(storeB.pairingID)
        #expect(storeB !== unpaired && unpaired.isRetired)
        #expect(idB != Flat.id && connection.pairing?.id == idB && connection.pairing?.pin == MadeUpCertificates.pinB)
        storeB.start()

        // Everything of A's session gets its turn now: nothing goes through.
        #expect(await pageRequest.value == .notPossible)
        #expect(await pageMode.value == .notPossible)
        await #expect(throws: FlatdError.notPaired) { try await shortcut.value }
        try await Task.sleep(for: .milliseconds(500))
        #expect(await eventually { events.isOpen })
        events.send(.snapshot(devices: try Flat.devices(Flats.devicesB()), modes: []))
        #expect(await eventually { storeB.link == .live })

        // No command went anywhere (the queued one, the page's, the Shortcut's), and no key of A's reached B.
        #expect(transport.sent.allSatisfy { $0.httpMethod == "GET" })
        #expect(shortcutTransport.sent.allSatisfy { $0.httpMethod == "GET" && $0.url?.host() == Flats.hostA })
        #expect(transport.requests(to: Flats.hostB).allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization").map { $0 == "Bearer \(Flat.otherKey)" } ?? true
        })
        // The old page hears nothing of B, and can no longer listen or read.
        #expect(heardByOldPage.isEmpty)
        #expect(old.listen { _ in } == nil && old.snapshot == nil)
        // A choice made for A acts on nothing in B, though B has devices with those ids.
        let actions = FlatActions(reach: reach)
        await #expect(throws: ChosenDeviceGone.blind) { try await actions.move(rollo: blindOfA.id, .up) }
        await #expect(throws: ChosenDeviceGone.fan) { try await actions.setFans(on: true, only: [fanOfA.id]) }
        #expect(try await actions.rolloControl(blindOfA.id) == .gone)
        #expect(transport.sent.allSatisfy { $0.httpMethod == "GET" })
        #expect(connection.known?.pairing == idB)
        storeB.stop()
    }

    /// One flat per install: another flat's code while one is paired is refused with its line, before anything is
    /// asked anywhere; the paired flat stays as it was.
    @Test func aCodeOfAnotherFlatIsRefusedWhileOneIsPaired() async throws {
        let connection = Flat.connection()
        let (store, transport, _, _) = Flat.store(connection: connection)
        Flats.answerB(transport)
        let baseB = Flats.baseB
        let model = ConnectModel(candidates: { [baseB] })
        let code = try #require(model.take(Flats.codeB))
        #expect(await model.connect(code, store: store) == false)
        #expect(model.problem == FlatdError.anotherFlat.message())
        #expect(model.problem?.contains("Forget this flat") == true)
        #expect(!model.isConnecting)
        // And the store refuses it itself.
        #expect(await store.connect(to: Flats.baseB, token: Flat.otherKey, pin: MadeUpCertificates.pinB) == .anotherFlat)
        #expect(transport.sent.isEmpty)
        #expect(connection.pairing?.id == Flat.id && connection.pairing?.pin == Flat.pin && connection.token == Flat.key)
        #expect(!store.isRetired && store.pairingID == Flat.id)
    }

    /// Another flat's code refused while an attempt for the paired flat is still out: Connect is usable afterwards.
    @Test func aRefusalDuringASlowAttemptLeavesConnectUsable() async throws {
        let connection = Flat.connection()
        let (store, transport, _, _) = Flat.store(connection: connection)
        transport.answer("GET /api/health", body: Flats.health, delay: .milliseconds(300))
        let model = ConnectModel(candidates: { [] })
        let fresh = try #require(model.take(#"{"url":"\#(Flat.base)","token":"\#(Flat.renewedKey)","spki_sha256":"\#(Flat.pin.hex)"}"#))
        let slow = Task { await model.connect(fresh, store: store) }
        try await Task.sleep(for: .milliseconds(50))
        slow.cancel()                                                   // what scanning another code does
        let foreign = try #require(model.take(Flats.codeB))
        #expect(await model.connect(foreign, store: store) == false)
        _ = await slow.value
        #expect(!model.isConnecting && model.canConnect)
        #expect(model.problem == FlatdError.anotherFlat.message())
        store.stop()
    }

    /// An attempt connects exactly the code it was started with: another flat's code scanned meanwhile is refused and
    /// never connected by it.
    @Test func anAttemptConnectsOnlyTheCodeItWasStartedWith() async throws {
        let connection = Flat.connection()
        let (store, transport, _, _) = Flat.store(connection: connection)
        let hint = URL(string: "https://192.0.2.20:8788")!
        transport.answer("GET 192.0.2.20/api/health", body: Flats.health, delay: .milliseconds(300))
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1)]])
        transport.answer("GET /api/scenes", body: ["scenes": []])
        Flats.answerB(transport)
        let model = ConnectModel(candidates: { [] })
        // A fresh code of the paired flatd (a new key): it connects at once.
        let fresh = try #require(model.take(#"{"url":"\#(hint)","token":"\#(Flat.renewedKey)","spki_sha256":"\#(Flat.pin.hex)"}"#))
        let attempt = Task { await model.connect(fresh, store: store) }
        try await Task.sleep(for: .milliseconds(50))
        // Meanwhile another flat's code is scanned: shown, and refused when it is tried.
        let foreign = try #require(model.take(Flats.codeB))
        #expect(await attempt.value)
        #expect(connection.pairing?.pin == Flat.pin && connection.token == Flat.renewedKey)
        #expect(connection.pairing?.id == Flat.id && store.pairingID == Flat.id)
        #expect(transport.requests(to: Flats.hostB).isEmpty)
        #expect(model.code == foreign)
        #expect(await model.connect(foreign, store: store) == false)
        #expect(transport.requests(to: Flats.hostB).isEmpty && connection.pairing?.pin == Flat.pin)
        store.stop()
    }

    /// A first pairing gets a store of its own: the store without a pairing retires, and a late attempt of it keeps
    /// nothing.
    @Test func aFirstPairingGetsAStoreOfItsOwn() async throws {
        let connection = Flat.connection(linked: false)
        let (session, transport, events, _) = Flat.session(connection: connection)
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1)]])
        transport.answer("GET /api/scenes", body: ["scenes": []])
        let unpaired = try #require(session.store)
        let generation = session.generation
        #expect(unpaired.pairingID == nil && unpaired.link == .notSetUp)
        #expect(await unpaired.connect(to: Flat.base, token: Flat.key, pin: Flat.pin) == nil)
        let paired = try #require(session.store)
        #expect(paired !== unpaired && unpaired.isRetired && session.generation == generation + 1)
        #expect(paired.pairingID == connection.pairing?.id && paired.pin == Flat.pin)
        #expect(connection.knownDevices.map(\.id) == ["fan:fan_1"])
        // The retired store keeps nothing more.
        #expect(await unpaired.connect(to: Flat.base, token: Flat.otherKey, pin: Flat.pin) == .notPossible)
        #expect(connection.token == Flat.key)
        paired.start()
        #expect(await eventually { events.isOpen })
        #expect(events.pins == [Flat.pin])
        paired.stop()
    }

    /// An item a build before flatd's identity saved (no pin) counts as no pairing, and a first pairing replaces it.
    @Test func anOldItemThatIsNoPairingIsReplacedByAFirstPairing() async throws {
        let keys = MemoryKeys()
        let connection = FlatdConnection(defaults: UserDefaults(suiteName: "arestia-tests-" + UUID().uuidString)!,
                                         names: Flat.nameFile(), keychain: keys, lock: .processOnly)
        try keys.save(#"{"link":{"baseURL":"http://192.0.2.10:8787"},"token":"\#(Flat.key)"}"#, label: "old")
        #expect(connection.saved == .invalid)
        let (session, transport, _, _) = Flat.session(connection: connection)
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1)]])
        let unpaired = try #require(session.store)
        #expect(unpaired.pairingID == nil)
        #expect(await unpaired.connect(to: Flat.base, token: Flat.key, pin: Flat.pin) == nil)
        #expect(connection.pairing?.pin == Flat.pin && session.store?.pairingID == connection.pairing?.id)
    }

    /// Forget that the Keychain refuses changes nothing: the store goes on, the pairing stays.
    @Test func aForgetTheKeychainRefusesChangesNothing() throws {
        let keys = MemoryKeys()
        let connection = FlatdConnection(defaults: UserDefaults(suiteName: "arestia-tests-" + UUID().uuidString)!,
                                         names: Flat.nameFile(), keychain: keys, lock: .processOnly)
        try connection.save(Flat.pairing())
        let (session, _, _, _) = Flat.session(connection: connection)
        let store = try #require(session.store)
        keys.failsToDelete = true
        #expect(!session.forget())
        #expect(session.store === store && !store.isRetired && connection.pairing?.id == Flat.id)
    }

    /// A store never takes on another pairing it finds saved (only a Debug launch argument could put one there): it
    /// retires and the session builds a new store, whose page starts from nothing.
    @Test func aStoreThatFindsAnotherPairingSavedRetires() async throws {
        let connection = Flat.connection()
        let (session, transport, events, _) = Flat.session(connection: connection)
        transport.answer("GET /api/scenes", body: ["scenes": []])
        Flats.answerB(transport)
        let old = try #require(session.store)
        old.start()
        #expect(await eventually { events.isOpen })
        events.send(try Flat.snapshot())
        #expect(await eventually { old.link == .live })
        var heard: [FlatEvent] = []
        _ = try #require(old.listen { heard.append($0) })
        let other = FlatdPairing(baseURL: Flats.baseB, token: Flat.otherKey, pin: MadeUpCertificates.pinB)
        try connection.save(other)
        events.end(FlatdError.unreachable)
        #expect(await eventually({ old.isRetired }, timeout: .seconds(4)))
        let next = try #require(session.store)
        #expect(next !== old && next.pairingID == other.id && next.devices.isEmpty)
        #expect(heard.isEmpty)
    }

    /// A fresh code of the paired flatd keeps the pairing's identity, so its choices go on; the stream starts again with
    /// the new key, and the 3D page is told to load again (`credentials`).
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
        _ = try #require(store.listen { heard.append($0) })
        let moved = URL(string: "https://192.0.2.30:8788")!
        #expect(await store.connect(to: moved, token: Flat.renewedKey, pin: Flat.pin) == nil)
        #expect(store.pairingID == Flat.id && connection.pairing?.id == Flat.id && store.credentials == 1)
        #expect(connection.pairing?.baseURL == moved && connection.token == Flat.renewedKey)
        #expect(await eventually { events.requests.last?.url?.host() == "192.0.2.30" })
        #expect(events.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer \(Flat.renewedKey)")
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
    /// not send the app back to the connect card.
    @Test func aRefusalOfAnOldKeyAfterARenewalIsNotARefusal() async throws {
        let connection = Flat.connection()
        let (store, transport, _, _) = Flat.store(connection: connection)
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1)]])
        transport.answer("GET /api/scenes", body: ["scenes": []])
        transport.answer("POST /api/devices/fan:fan_1", status: 401, body: ["error": "wrong token"],
                         delay: .milliseconds(300))
        store.setFan("fan:fan_1", on: true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(await store.connect(to: Flat.base, token: Flat.renewedKey, pin: Flat.pin) == nil)
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
        let renewed = FlatdPairing(baseURL: Flat.base, token: Flat.renewedKey, pin: Flat.pin, id: read.id)
        #expect(connection.renew(read, with: renewed))
        connection.move(read, to: FlatdClient(read, at: URL(string: "https://192.0.2.77:8788")!))       // from before the renewal
        #expect(connection.token == Flat.renewedKey && connection.pairing?.baseURL == Flat.base)
        // A renewal never changes the identity or the flatd.
        let other = FlatdPairing(baseURL: Flat.base, token: Flat.key, pin: MadeUpCertificates.pinB, id: read.id)
        #expect(!connection.renew(renewed, with: other))
        #expect(!connection.renew(renewed, with: Flat.pairing(id: UUID())))
        // A first pairing never overwrites one that is there.
        #expect(try connection.pairNew(Flat.pairing(id: UUID())) == false)
        #expect(connection.pairing?.id == read.id)
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

/// The app has one window, so there is one session and one store at a time.
@MainActor
struct OneWindowTests {
    @Test func theAppDeclaresASingleScene() throws {
        let manifest = try #require(Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest")
                                    as? [String: Any])
        #expect(manifest["UIApplicationSupportsMultipleScenes"] as? Bool == false)
        #expect(UIApplication.shared.supportsMultipleScenes == false)
    }
}
