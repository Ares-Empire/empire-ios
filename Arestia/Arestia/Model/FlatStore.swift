import Foundation
import Observation
import os

/// The flat as the app shows it: flatd's devices, modes and scenes, kept live by its event stream, and every command
/// the screens send. One store for the home screen and the 3D tab, so both show the same state.
///
/// - Live: the stream's snapshot replaces everything, then each state or mode event is merged in (whoever made the
///   change: this app, Claude, a wall button, a timer). The stream reconnects by itself, quietly, with growing pauses;
///   when the Mac's address changed it finds flatd again over Bonjour.
/// - Commands go over HTTPS; flatd answers once the device confirmed, and that answer is shown at once (the stream
///   brings the same a moment later). Nothing is shown as done before flatd said so: a blind's position while a finger
///   drags it is the finger's, and once let go it shows as asked for ("Sending") until flatd answers.
/// - Not reachable (the Mac asleep, away from home): the last state stays on screen, marked as not live; no alerts.
/// - The key and every request go only to a server that proved flatd's key (`FlatdPin`, checked by the transport on
///   every connection); Bonjour and the saved address only say where to look.
///
/// **One pairing for its whole life** (one flat per install, docs/ARESTIA-APP.md): a store is made for the saved
/// pairing (`pairingID`), or for none (the connect screen), and never changes flat. Forget and a first pairing make a
/// new one (`FlatSession`); the old store is retired (`retire`): its loop and every command are cancelled, its
/// listeners dropped, and whatever of it is still on its way finds it retired and changes nothing. A fresh code of the
/// same flat only renews key and address (`connect`).
///
/// One loop follows flatd at a time: each has its own generation, and after every wait it checks it is still the
/// store's loop before it changes anything.
@MainActor @Observable
final class FlatStore {
    enum Link: Equatable {
        /// No pairing: the connect screen.
        case notSetUp
        /// Asking flatd (first time this launch, back from the background, or after the stream dropped: then the
        /// screens say "Reconnecting" over the last state).
        case connecting
        case live
        /// flatd does not answer.
        case offline
        /// flatd refused the key (401): the app has to pair again.
        case refused
    }

    private(set) var link: Link
    private(set) var devices: [Device] = []
    private(set) var modes: [FlatMode] = []
    private(set) var scenes: [FlatScene] = []
    /// When the stream last delivered something (for "last seen 18:40" while not live).
    private(set) var lastSeen: Date?
    /// Requests on their way, by what they change ("power:fan:…", "mode:cooking", "scene:air_out").
    private(set) var working: Set<String> = []
    /// A blind's position while a finger drags it.
    private(set) var dragging: [String: Int] = [:]
    /// A blind's position sent when the finger let go, until flatd answered or the stream brought the blind's state:
    /// shown as asked for, never as done (Codex's review, round 5).
    private(set) var pending: [String: Int] = [:]
    /// Counts the times a fresh code of this flat renewed its key or address: the 3D page loads again with it, so a
    /// page fetched with the old key never reports that key's refusal.
    private(set) var credentials = 0
    /// The line at the bottom: what could not be done, or "Cooking ended · Undo".
    var offer: UndoOffer?

    /// The pairing this store is for (`FlatdPairing.id`), for its whole life; nil: none (the connect screen).
    let pairingID: UUID?
    /// That pairing's flat (its pin): a code of another flat is refused, never paired in place.
    let pin: FlatdPin?
    /// The store's part is over (Forget, a first pairing made, the app rebuilt): nothing it started or still hears
    /// changes anything.
    private(set) var isRetired = false

    let connection: FlatdConnection
    /// Nil: the real transport, which accepts only a server holding the pairing's key (the tests pass a fake).
    private let transport: (any HTTPTransport & Sendable)?
    private let eventSource: any FlatEventSource
    private let rediscover: @Sendable () async -> [URL]
    private let reloadControls: @MainActor () -> Void
    /// Tells the session that the saved pairing is no longer this store's (a first pairing was made, or the pairing
    /// went): it builds the store anew from what is saved.
    private let pairingChanged: @MainActor () -> Void
    private var loop: Task<Void, Never>?
    /// Which loop may change the store (`run`); a stopped or replaced loop finds it changed and ends.
    private var loopGeneration = 0
    /// Commands under way, cancelled when the store retires.
    private var tasks: [UUID: Task<Void, Never>] = [:]
    /// The address the live loop reached flatd at: commands go there while live; otherwise they check the saved address
    /// first, as the loop does. (Who answers is settled on every connection by the pin, `FlatdTransport`.)
    private var liveBase: URL?
    /// How often each device or mode changed in the stream, and how many snapshots came: a command's answer is shown
    /// only when nothing newer came from the stream meanwhile (Codex's review, round 2).
    private var revisions: [String: Int] = [:]
    private var snapshots = 0
    /// Who hears every change as flatd describes it (the 3D page, `FlatScreen`'s bridge).
    private var listeners: [UUID: @MainActor (FlatEvent) -> Void] = [:]
    private static let log = Logger(subsystem: "de.ares-empire.arestia", category: "store")
    /// Pauses between attempts to reach flatd again (the last one repeats).
    static let backoff: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(15), .seconds(30)]

    static func pause(after failures: Int) -> Duration {
        backoff[min(max(failures, 1), backoff.count) - 1]
    }

    init(pairing: FlatdPairing?, connection: FlatdConnection, transport: (any HTTPTransport & Sendable)? = nil,
         eventSource: any FlatEventSource = WebSocketEvents(),
         rediscover: @escaping @Sendable () async -> [URL] = { await FlatdBonjour.candidates() },
         reloadControls: @escaping @MainActor () -> Void = { ArestiaControlKind.reloadAll() },
         pairingChanged: @escaping @MainActor () -> Void = {}) {
        self.pairingID = pairing?.id
        self.pin = pairing?.pin
        self.connection = connection
        self.transport = transport
        self.eventSource = eventSource
        self.rediscover = rediscover
        self.reloadControls = reloadControls
        self.pairingChanged = pairingChanged
        link = pairing == nil ? .notSetUp : .connecting
    }

    // MARK: what the screens read

    var fans: [Device] { devices.filter { $0.kind == .fan } }
    var rollos: [Device] { devices.filter { $0.kind == .rollo } }
    /// Devices the home screen has no card for yet (lights, plugs): listed quietly.
    var others: [Device] { devices.filter { $0.kind != .fan && $0.kind != .rollo } }
    var cooking: FlatMode? { modes.first { $0.id == FlatMode.cookingID } }
    var isCooking: Bool { cooking?.active == true }
    var hasSnapshot: Bool { lastSeen != nil }
    /// Not live any more, the last state still shown, a new connection being made: "Reconnecting".
    var isReconnecting: Bool { link == .connecting && hasSnapshot }

    func device(_ id: String) -> Device? { devices.first { $0.id == id } }

    /// A blind's position as shown: the finger's while it drags, the one asked for until flatd answered, else flatd's.
    func shownPosition(of rollo: Device) -> Int? { dragging[rollo.id] ?? pending[rollo.id] ?? rollo.state.position }

    // MARK: following flatd

    /// Starts following flatd (at launch and back in the foreground). Does nothing while it already does, without a
    /// pairing, or once retired.
    func start() {
        guard !isRetired, pairingID != nil, loop == nil else { return }
        if link != .live, !hasSnapshot { link = .connecting }
        loopGeneration += 1
        let generation = loopGeneration
        loop = Task { [weak self] in await self?.run(generation: generation) }
    }

    /// Stops following (the app went to the background, the screen went away). Whatever was live is only the last state
    /// seen now: back in the foreground the stream is checked again before "Live" shows (Codex's review, round 5).
    func stop() {
        loopGeneration += 1
        loop?.cancel()
        loop = nil
        liveBase = nil
        if link == .live { link = .connecting }
    }

    /// Try again now (pull to refresh, the offline card's button).
    func retry() {
        stop()
        if link == .offline || link == .refused { link = .connecting }
        start()
    }

    /// Ends the store's part for good (`FlatSession`: Forget, a first pairing, a rebuilt app): its loop and every
    /// command under way are cancelled, its listeners dropped, its state cleared; what of it is still on its way finds
    /// it retired and changes nothing.
    func retire() {
        guard !isRetired else { return }
        isRetired = true
        stop()
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        listeners = [:]
        devices = []
        modes = []
        scenes = []
        working = []
        dragging = [:]
        pending = [:]
        offer = nil
        lastSeen = nil
        link = .notSetUp
    }

    /// The saved pairing is no longer this store's: it retires, and the session builds the store for what is saved.
    private func handOver() {
        guard !isRetired else { return }
        retire()
        pairingChanged()
    }

    /// What the Keychain says of this store's pairing: here (with its newest key and address), unreadable just now
    /// (try again), or gone (nil, after `handOver`).
    private enum Reading {
        case here(FlatdPairing)
        case unreadable
        case gone
    }

    private func readPairing() -> Reading {
        switch connection.saved {
        case let .paired(saved) where saved.id == pairingID: return .here(saved)
        case .unreadable: return .unreadable
        default:
            handOver()
            return .gone
        }
    }

    /// Whether the loop of `generation` may still change the store.
    private func owns(_ generation: Int) -> Bool { generation == loopGeneration && !Task.isCancelled && !isRetired }

    private func run(generation: Int) async {
        // However this loop ends, it never stays in `loop` as a finished task that `start` would take for a running one.
        defer { if generation == loopGeneration { loop = nil } }
        var failures = 0
        /// Where rediscovery found flatd, until the pairing keeps that address.
        var foundAt: URL?
        var movedSinceLive = false
        while owns(generation) {
            let pairing: FlatdPairing
            switch readPairing() {
            case let .here(saved):
                pairing = saved
            case .unreadable:
                // A Keychain hiccup is not the end of the pairing: try again with the same growing pauses.
                Self.log.error("the pairing could not be read; trying again")
                failures += 1
                markNotLive(failures)
                try? await Task.sleep(for: Self.pause(after: failures))
                continue
            case .gone:
                return
            }
            let client = FlatdClient(pairing, at: foundAt, transport: transport)
            do {
                try await follow(client, generation: generation) {
                    failures = 0
                    movedSinceLive = false
                }
            } catch FlatdError.refused {
                guard owns(generation) else { return }
                // A refusal counts only for the key it was sent with: a fresh code of the same flatd brought another
                // one meanwhile, which the next round uses.
                if connection.pairing?.token == pairing.token {
                    Self.log.notice("flatd refused the key")
                    stop()
                    link = .refused
                    return
                }
            } catch {}
            guard owns(generation) else { return }
            failures += 1
            if link == .live { link = .connecting }
            // flatd's address may have changed: after the second miss, look over Bonjour. What it offers are only
            // candidates; one counts when the server there proved flatd's key and answered.
            if failures >= 2 {
                let candidates = await rediscover().filter { $0 != client.baseURL }
                guard owns(generation) else { return }
                let found = await FlatdReach.find(pairing, among: candidates, transport: transport)
                guard owns(generation) else { return }
                if let found {
                    Self.log.notice("flatd is at a new address")
                    foundAt = found.baseURL               // kept in the pairing only once it answered (in `follow`)
                    // At once the first time; a second move without a live stream in between waits like any retry
                    // (flatd reachable at two addresses with a failing stream must not spin).
                    if !movedSinceLive {
                        movedSinceLive = true
                        continue
                    }
                }
            }
            markNotLive(failures)
            try? await Task.sleep(for: Self.pause(after: failures))
        }
    }

    /// One quick retry says "Reconnecting" over the last state; after that, or without any state, "Not reachable".
    private func markNotLive(_ failures: Int) {
        if failures >= 2 || !hasSnapshot { link = .offline } else if link == .live { link = .connecting }
    }

    /// The address checked, scenes over HTTPS (also telling a refused key apart at once), then the event stream until
    /// it ends. A first snapshot resets the failures and, at a new address, keeps it in the pairing.
    private func follow(_ client: FlatdClient, generation: Int, live: () -> Void) async throws {
        // However the stream ends, its checked address stops counting at once: a command in the retry's pause checks
        // the address again (Codex's review, round 3).
        defer { liveBase = nil }
        try await client.verify()
        let answered: [FlatScene]
        do { answered = try await client.scenes() } catch FlatdError.unknown { answered = [] }   // a flatd without scenes
        guard owns(generation) else { return }
        scenes = answered
        for try await event in eventSource.events(from: client.eventsRequest, pin: client.pin) {
            guard owns(generation) else { return }
            if case .snapshot = event {
                // Each connection's first word: still this store's pairing? (Forget retires the store before anything
                // else, so this only guards a pairing changed outside the app's own flow.)
                let saved: FlatdPairing?
                switch readPairing() {
                case let .here(pairing): saved = pairing
                case .unreadable: saved = nil
                case .gone: return
                }
                apply(event)
                live()
                link = .live
                liveBase = client.baseURL
                if let saved, saved.token == client.token { connection.move(saved, to: client.baseURL) }
                sayTroubleFromOutside()
            } else {
                apply(event)
            }
        }
        throw FlatdError.unreachable            // the stream ended: reconnect
    }

    /// Cooking changed outside the app (a control, a Shortcut) while devices did not follow, and it still describes
    /// cooking as it is: said once here, then forgotten (the control shows it until then).
    private func sayTroubleFromOutside() {
        guard let pairingID, let cooking,
              let trouble = connection.trouble(mode: cooking.id, active: cooking.active, pairing: pairingID) else { return }
        connection.note(nil, mode: cooking.id)
        offer = UndoOffer(message: FlatWords.troubleFromOutside(trouble))
        reloadControls()
    }

    /// Hears every change of the flat from now on, in flatd's own form: the stream's events, and the state a command's
    /// answer brought. Nil (nothing is heard) once the store is retired, which drops every listener. Keep the token;
    /// `unlisten` ends it.
    func listen(_ listener: @escaping @MainActor (FlatEvent) -> Void) -> UUID? {
        guard !isRetired else { return nil }
        let token = UUID()
        listeners[token] = listener
        return token
    }

    func unlisten(_ token: UUID) { listeners[token] = nil }

    private func tell(_ event: FlatEvent) {
        for listener in listeners.values { listener(event) }
    }

    /// The whole state now, as a snapshot event (for a listener that starts, or the page after it loaded); nil once
    /// the store is retired.
    var snapshot: FlatEvent? { isRetired ? nil : .snapshot(devices: devices, modes: modes) }

    /// One event of the stream (also called by the tests). Listeners hear it once; a snapshot as the whole state (a
    /// snapshot without modes keeps the modes known).
    func apply(_ event: FlatEvent, at now: Date = .now) {
        guard !isRetired else { return }
        let before = controlState
        switch event {
        case let .snapshot(devices, modes):
            snapshots += 1
            self.devices = devices
            if let modes { self.modes = modes }
            pending = [:]
            if let pairingID { connection.remember(devices, for: pairingID) }
            lastSeen = now
            tell(.snapshot(devices: self.devices, modes: self.modes))
        case let .state(id, patch, _):
            guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
            revisions[id, default: 0] += 1
            devices[index].state = devices[index].state.merging(patch)
            // flatd's word on the blind: from now on its state is shown, not the position asked for.
            if pending[id] != nil, patch.fields["target"] != nil || patch.fields["moving"] != nil
                || patch.fields["position"] != nil { pending[id] = nil }
            lastSeen = now
            tell(event)
        case let .mode(mode):
            revisions["mode:" + mode.id, default: 0] += 1
            store(mode)
            lastSeen = now
            tell(event)
        case .other:
            return
        }
        if controlState != before { reloadControls() }
    }

    /// What the Control Center controls show: when it changes here, they are asked to read again.
    private var controlState: [String] {
        [String(isCooking), String(fans.contains { $0.state.on == true })]
            + rollos.map { $0.id + String(RolloOpenness.isOpen($0.state)) }
    }

    /// Where the stream stood for a device or mode when a command was sent.
    struct Stamp: Equatable, Sendable {
        let snapshots: Int
        let revision: Int
    }

    func stamp(_ key: String) -> Stamp { Stamp(snapshots: snapshots, revision: revisions[key, default: 0]) }

    /// A device as a command's answer brought it, unless the stream brought newer news of it since the command was sent
    /// (`stamp`), or the answer is older than what is shown.
    private func take(_ device: Device, since stamp: Stamp) {
        guard stamp == self.stamp(device.id), let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        if let incoming = device.state.updatedAt, let current = devices[index].state.updatedAt, incoming < current {
            return
        }
        let before = controlState
        devices[index].state = devices[index].state.merging(device.state)
        tell(.state(id: device.id, state: device.state, source: "api"))
        if controlState != before { reloadControls() }
    }

    /// A mode as a command's answer brought it, unless the stream brought newer news of it meanwhile.
    private func take(_ mode: FlatMode, since stamp: Stamp) {
        guard stamp == self.stamp("mode:" + mode.id) else { return }
        let before = controlState
        store(mode)
        tell(.mode(mode))
        if controlState != before { reloadControls() }
    }

    private func store(_ mode: FlatMode) {
        if let index = modes.firstIndex(where: { $0.id == mode.id }) { modes[index] = mode } else { modes.append(mode) }
    }

    /// "Didn't answer: Fan 2." for the devices a mode or scene could not reach; nil when all followed.
    func failureLine(_ ids: [String], language: AppLanguage = .current) -> String? {
        guard !ids.isEmpty else { return nil }
        let names = ids.map { id in device(id)?.label ?? id }.joined(separator: ", ")
        return language.string("Didn't answer: \(names).")
    }

    // MARK: pairing codes

    /// Where among these addresses the flatd of this pairing code answers (its identity proved by the transport, its
    /// health asked without the key); nil when nowhere.
    func locate(_ code: PairingCode, among candidates: [URL]) async -> URL? {
        guard let first = candidates.first else { return nil }
        let probe = FlatdPairing(baseURL: first, token: code.token, pin: code.pin)
        return await FlatdReach.find(probe, among: candidates, transport: transport)?.baseURL
    }

    /// Whether a code with this pin is another flat than this store's: then it is refused (one flat per install).
    func isAnotherFlat(_ pin: FlatdPin) -> Bool { self.pin.map { $0 != pin } ?? false }

    /// Checks a pairing code's key with flatd at this address (`GET /api/devices`; the transport accepts only a server
    /// holding the code's pin) and keeps it when flatd answers. Returns why not: `.unreachable` when flatd is not there
    /// (nothing, or something without its key), `.refused` when flatd itself does not know the key, `.anotherFlat` for
    /// a code of another flat while one is paired (nothing is asked), `.notPossible` when the store retired meanwhile.
    ///
    /// - A store with no pairing makes the first one, saved only while nothing usable is saved; the session then builds
    ///   the store for it (this one retires).
    /// - A code of this store's flat (the same identity) renews key and address in place; the stream starts again with
    ///   the new key, and the 3D page loads again.
    /// - Another flat is never paired in place: that takes Forget first (`FlatSession.forget`).
    func connect(to baseURL: URL, token: String, pin: FlatdPin) async -> FlatdError? {
        guard !isRetired else { return .notPossible }
        if isAnotherFlat(pin) { return .anotherFlat }
        let candidate = FlatdClient(baseURL: baseURL, token: token, pin: pin, transport: transport)
        do {
            try await candidate.verify()
            let found = try await candidate.devices()
            // The screen went away, or the store's part ended meanwhile: this attempt keeps nothing.
            guard !Task.isCancelled, !isRetired else { return .notPossible }
            if let pairingID {
                return renew(pairingID, baseURL: baseURL, token: token, pin: pin, found: found)
            }
            return try pairFirst(baseURL: baseURL, token: token, pin: pin, found: found)
        } catch let error as FlatdError {
            return error
        } catch is CancellationError {
            return .notPossible
        } catch {
            return .invalidAnswer     // the Keychain refused to save or to delete an unusable item
        }
    }

    /// A fresh code of this store's flat: written over the version read (a control that only moved the address
    /// meanwhile is written over too, after reading again).
    private func renew(_ id: UUID, baseURL: URL, token: String, pin: FlatdPin, found: [Device]) -> FlatdError? {
        let renewed = FlatdPairing(baseURL: baseURL, token: token, pin: pin, id: id)
        for _ in 0..<3 {
            let current: FlatdPairing
            switch readPairing() {
            case let .here(saved): current = saved
            case .unreadable: return .pairingUnreadable
            case .gone: return .notPossible
            }
            guard current.pin == pin else { return .anotherFlat }
            if connection.renew(current, with: renewed) {
                connection.remember(found, for: id)
                credentials += 1
                stop()                                  // the stream again, with the new key and address
                if link == .refused || !hasSnapshot { link = .connecting }
                start()
                reloadControls()
                return nil
            }
        }
        return .notPossible
    }

    /// The first pairing, from a store with none: saved only while nothing usable is saved (an item that is no pairing,
    /// from an old build, is replaced); then the session takes over with a store for it.
    private func pairFirst(baseURL: URL, token: String, pin: FlatdPin, found: [Device]) throws -> FlatdError? {
        switch connection.saved {
        case .none: break
        case .invalid: try connection.forget()
        case .unreadable: return .pairingUnreadable
        case .paired:
            handOver()                                  // paired meanwhile: the session follows that one
            return .notPossible
        }
        let fresh = FlatdPairing(baseURL: baseURL, token: token, pin: pin)
        guard try connection.pairNew(fresh) else {
            handOver()
            return .notPossible
        }
        connection.remember(found, for: fresh.id)
        Self.log.notice("paired with a flat")
        handOver()
        reloadControls()
        return nil
    }

    // MARK: commands

    /// A fan on (for `minutes`, nil: until off) or off.
    func setFan(_ id: String, on: Bool, minutes: Int? = nil) {
        send("power:" + id, affects: id) { client in
            try await client.send(.power(on: on, seconds: minutes.map { $0 * 60 }), to: id)
        } done: { device, stamp in
            self.take(device, since: stamp)
        }
    }

    func moveRollo(_ id: String, _ command: RolloCommand) {
        dragging[id] = nil
        pending[id] = nil
        send("rollo:" + id, affects: id, blocking: false) { client in
            try await client.send(.rollo(command), to: id)
        } done: { device, stamp in
            self.take(device, since: stamp)
        }
    }

    /// While a finger drags a blind: shown at once, sent when it lets go (`setRollo(_:position:)`).
    func drag(_ id: String, to position: Int) {
        dragging[id] = min(100, max(0, position))
    }

    /// The finger left without letting go on the blind (the gesture was cancelled): flatd's position again.
    func endDrag(_ id: String) {
        dragging[id] = nil
    }

    /// The finger let go (or VoiceOver adjusted it): sent, and shown as asked for until flatd answered; a failure puts
    /// flatd's position back, with the reason in the line at the bottom.
    func setRollo(_ id: String, position: Int) {
        let position = min(100, max(0, position))
        dragging[id] = nil
        let sent = send("rollo:" + id, affects: id, blocking: false) { client in
            try await client.send(.position(position), to: id)
        } done: { device, stamp in
            self.take(device, since: stamp)
            if self.pending[id] == position { self.pending[id] = nil }   // flatd has it now (moving, target)
        } failed: {
            if self.pending[id] == position { self.pending[id] = nil }
        }
        if sent { pending[id] = position }
    }

    /// Cooking on or off (any mode). Ending cooking offers Undo, which starts it again. Devices that did not follow are
    /// named (flatd changes the mode anyway).
    func setMode(_ id: String, active: Bool) {
        send("mode:" + id, affects: "mode:" + id) { client in
            try await client.setMode(id, active: active)
        } done: { answer, stamp in
            let (mode, failed) = answer
            self.take(mode, since: stamp)
            self.connection.note(nil, mode: id)            // the app says its own failures; an older one is moot
            if let line = self.failureLine(failed) {
                self.offer = UndoOffer(message: line)
            } else if id == FlatMode.cookingID, !active {
                self.offer = UndoOffer(message: FlatWords.cookingEnded()) { [weak self] in
                    guard let self, !self.isRetired else { return }
                    self.setMode(id, active: true)
                }
            }
        }
    }

    func runScene(_ id: String, title: String) {
        send("scene:" + id, affects: "scene:" + id) { client in
            try await client.runScene(id)
        } done: { failed, _ in
            self.offer = UndoOffer(message: [FlatWords.sceneDone(title), self.failureLine(failed)]
                .compactMap { $0 }.joined(separator: " "))
        }
    }

    func isWorking(_ key: String) -> Bool { working.contains(key) }

    /// The store's part ended under a command: it is dropped.
    private struct Retired: Error {}

    /// The client a command goes through, built from one reading of the saved pairing (its newest key and address): at
    /// the live loop's address, or at the saved one once flatd answered there. Throws `Retired` once the store's part
    /// ended, `.pairingUnreadable` while the Keychain cannot be read.
    private func readyClient() async throws -> FlatdClient {
        guard !isRetired else { throw Retired() }
        let pairing: FlatdPairing
        switch readPairing() {
        case let .here(saved): pairing = saved
        case .unreadable: throw FlatdError.pairingUnreadable
        case .gone: throw Retired()
        }
        if link == .live, let liveBase {
            return FlatdClient(pairing, at: liveBase, transport: transport)
        }
        let client = FlatdClient(pairing, transport: transport)
        try await client.verify()
        guard !isRetired else { throw Retired() }
        return client
    }

    /// Runs a command as a task the store cancels when it retires.
    private func perform(_ work: @escaping @MainActor () async -> Void) {
        let token = UUID()
        tasks[token] = Task { [weak self] in
            await work()
            self?.tasks[token] = nil
        }
    }

    /// Runs a command: one at a time per thing (`blocking`), the failure as a calm line, a refused key back to the
    /// connect card, a lost flatd as a reason to reconnect. Dropped, its answer too, once the store retired; `affects`
    /// names what the answer shows (a device id, "mode:<id>"), for `stamp`. False when it was not started.
    @discardableResult
    private func send<Answer: Sendable>(_ key: String, affects: String, blocking: Bool = true,
                                        _ work: @escaping @Sendable (FlatdClient) async throws -> Answer,
                                        done: @escaping @MainActor (Answer, Stamp) -> Void,
                                        failed: @escaping @MainActor () -> Void = {}) -> Bool {
        guard !isRetired, pairingID != nil else { return false }
        if blocking, working.contains(key) { return false }
        working.insert(key)
        perform { [weak self] in
            guard let self else { return }
            defer { if !isRetired { working.remove(key) } }
            var used: FlatdClient?
            do {
                let client = try await readyClient()
                used = client
                let stamp = stamp(affects)
                let answer = try await work(client)
                guard !isRetired else { return }
                done(answer, stamp)
                reloadControls()
            } catch is Retired {
                return
            } catch let error as FlatdError {
                guard !isRetired else { return }
                failed()
                handle(error, client: used)
            } catch {
                guard !isRetired else { return }
                failed()
            }
        }
        return true
    }

    /// What a failed command does to the store: a refused key stops it (only while that key is the saved one: a fresh
    /// code may have brought another meanwhile), a lost flatd reconnects (only while the store follows flatd at all),
    /// the rest is a line.
    private func handle(_ error: FlatdError, client: FlatdClient?) {
        switch error {
        case .refused:
            guard let client, client.token == connection.token else { return }
            stop()
            link = .refused
        case .unreachable:
            offer = UndoOffer(message: error.message())
            if link == .live, loop != nil { retry() }
        default:
            offer = UndoOffer(message: error.message())
        }
    }

    // MARK: the 3D page (BRIDGE.md: bodies forwarded unchanged, one result each)

    /// The client for fetching the 3D page, or why there is none (`.pairingUnreadable`: the Keychain could not be read
    /// just now, so the page offers Try again).
    func pageClient() -> Result<FlatdClient, FlatdError> {
        guard !isRetired, pairingID != nil else { return .failure(.notPaired) }
        switch readPairing() {
        case let .here(pairing):
            return .success(FlatdClient(pairing, at: link == .live ? liveBase : nil, transport: transport))
        case .unreadable:
            return .failure(.pairingUnreadable)
        case .gone:
            return .failure(.notPaired)
        }
    }

    /// A device command from the 3D page. The answer's state reaches the page through the listeners.
    func pageRequest(_ id: String, body: Data) async -> FlatdError? {
        var used: FlatdClient?
        do {
            let client = try await readyClient()
            used = client
            let stamp = stamp(id)
            let device = try await client.send(body: body, to: id)
            guard !isRetired else { return .notPossible }
            take(device, since: stamp)
            reloadControls()
            return nil
        } catch {
            return pageFailure(error, client: used)
        }
    }

    /// A mode change from the 3D page (it only ever ends cooking).
    func pageMode(_ id: String, body: Data) async -> FlatdError? {
        var used: FlatdClient?
        do {
            let client = try await readyClient()
            used = client
            let stamp = stamp("mode:" + id)
            let (mode, failed) = try await client.setMode(id, body: body)
            guard !isRetired else { return .notPossible }
            take(mode, since: stamp)
            connection.note(nil, mode: id)
            if let line = failureLine(failed) { offer = UndoOffer(message: line) }
            reloadControls()
            return nil
        } catch {
            return pageFailure(error, client: used)
        }
    }

    /// A page's failed command: the bridge's error, and the store's reaction while it has not retired.
    private func pageFailure(_ error: Error, client: FlatdClient?) -> FlatdError {
        if error is Retired || isRetired { return .notPossible }
        let error = error as? FlatdError ?? .unreachable
        if error == .refused {
            handle(.refused, client: client)
        } else if error == .unreachable, link == .live, loop != nil {
            retry()
        }
        return error
    }
}

/// The app's state for the one flat it is paired with (one flat per install, docs/ARESTIA-APP.md): the store for the
/// saved pairing, built anew whenever that changes (Forget, a first pairing). An old store is retired and released,
/// never reused, so nothing it started or still hears lands anywhere; the screens are built anew with the new store.
@MainActor @Observable
final class FlatSession {
    /// The store for the saved pairing (one without a pairing shows the connect screen); nil while the Keychain could
    /// not be read yet.
    private(set) var store: FlatStore?
    /// Counts the stores made: the screens' identity, so a new store gets new screens (and a new 3D page).
    private(set) var generation = 0
    let connection: FlatdConnection
    private let makeStore: @MainActor (FlatdPairing?, @escaping @MainActor () -> Void) -> FlatStore
    private let reloadControls: @MainActor () -> Void
    private var reading: Task<Void, Never>?
    private var readFailures = 0
    private static let log = Logger(subsystem: "de.ares-empire.arestia", category: "session")

    /// `makeStore`: the store for a pairing (nil: none) and what it calls when the saved pairing is no longer its own.
    init(connection: FlatdConnection,
         reloadControls: @escaping @MainActor () -> Void = { ArestiaControlKind.reloadAll() },
         makeStore: (@MainActor (FlatdPairing?, @escaping @MainActor () -> Void) -> FlatStore)? = nil) {
        self.connection = connection
        self.reloadControls = reloadControls
        self.makeStore = makeStore ?? { pairing, changed in
            FlatStore(pairing: pairing, connection: connection, pairingChanged: changed)
        }
        load()
    }

    /// Reads the saved pairing and makes sure the store is for it: kept when it already is, else a new one. While the
    /// Keychain cannot be read, there is no store and it is read again with growing pauses (never taken as no pairing).
    func load() {
        reading?.cancel()
        reading = nil
        switch connection.saved {
        case .unreadable:
            store?.retire()
            store = nil
            readFailures += 1
            Self.log.error("the pairing could not be read; trying again")
            let pause = FlatStore.pause(after: readFailures)
            reading = Task { [weak self] in
                try? await Task.sleep(for: pause)
                guard !Task.isCancelled else { return }
                self?.load()
            }
        case let .paired(pairing):
            readFailures = 0
            if let store, !store.isRetired, store.pairingID == pairing.id { return }
            replace(with: pairing)
        case .none, .invalid:
            readFailures = 0
            if let store, !store.isRetired, store.pairingID == nil { return }
            replace(with: nil)
        }
    }

    private func replace(with pairing: FlatdPairing?) {
        store?.retire()
        generation += 1
        store = makeStore(pairing) { [weak self] in self?.load() }
    }

    /// Settings → Forget this flat: the pairing and everything kept for it go (`FlatdConnection.forget`), the store
    /// retires (its work cancelled, its stream and 3D page gone) and a new one without a pairing takes its place; the
    /// controls read again. A choice made in a Shortcut or a control before acts on nothing afterwards (`SavedDevice`).
    /// False, and nothing changed, when the Keychain kept the item.
    func forget() -> Bool {
        do {
            try connection.forget()
        } catch {
            Self.log.error("the pairing could not be forgotten")
            return false
        }
        // Nothing runs between the delete and this on the main actor: no work of the old store starts after it.
        store?.retire()
        load()
        reloadControls()
        return true
    }
}
