import Foundation
import Observation
import os

/// The flat as the app shows it: flatd's devices, modes and scenes, kept live by its event stream, and every command
/// the screens send. One store for the home screen and the 3D tab, so both show the same state.
///
/// - Live: the stream's snapshot replaces everything, then each state or mode event is merged in (whoever made the
///   change: this app, Claude, a wall button, a timer). The stream reconnects by itself, quietly, with growing pauses;
///   when the Mac's address changed it finds flatd again over Bonjour.
/// - Commands go over HTTP; flatd answers once the device confirmed, and that answer is shown at once (the stream
///   brings the same a moment later). Nothing is shown as done before flatd said so, except a blind's target while it
///   is dragged.
/// - Not reachable (the Mac asleep, away from home): the last state stays on screen, marked as not live; no alerts.
/// - The key and every request go only to a server that proved flatd's key (`FlatdPin`, checked by the transport on
///   every connection); Bonjour and the saved address only say where to look.
///
/// One loop follows flatd at a time: each has its own generation and failure count, and after every wait it checks it
/// is still the store's loop before it changes anything (Codex's review, 2026-11-19: a Try again during a Bonjour
/// lookup used to leave the old loop running on a reset count).
///
/// **One pairing at a time** (`pairingID`, the pairing's identity in the Keychain): everything the store does or hears
/// is tagged with it: the loop, every command, the 3D page and its listener. Whatever carries another identity is
/// dropped, never acted on, however late it gets its turn. When the saved pairing is another one than the store's (a
/// Disconnect, a pairing made elsewhere), the store leaves its pairing completely (`adopt`): its tasks cancelled, the
/// stream and the page's listener gone, its state cleared; only then does it follow the saved one. Pairing with another
/// flatd goes only that way (`connect`); a fresh code of the same flatd keeps the identity and only renews key and
/// address.
@MainActor @Observable
final class FlatStore {
    enum Link: Equatable {
        /// No key yet: the connect screen.
        case notSetUp
        /// Asking flatd (first time this launch, or after the stream dropped).
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
    /// A blind's position while a finger drags it, until flatd has it.
    private(set) var dragging: [String: Int] = [:]
    /// The pairing the store works for (`FlatdPairing.id`); nil without one. The 3D page has a web view of its own per
    /// identity, and everything sent or heard for another is dropped.
    private(set) var pairingID: UUID?
    /// Counts the times the store left a pairing (`adopt`), so a connect that started before knows it is too late.
    private var resets = 0
    /// Work under way for `pairingID` (commands): cancelled when the store leaves that pairing.
    private var tasks: [UUID: Task<Void, Never>] = [:]
    /// The line at the bottom: what could not be done, or "Cooking ended · Undo".
    var offer: UndoOffer?

    let connection: FlatdConnection
    /// Nil: the real transport, which accepts only a server holding the pairing's key (the tests pass a fake).
    private let transport: (any HTTPTransport & Sendable)?
    private let eventSource: any FlatEventSource
    private let rediscover: @Sendable () async -> [URL]
    private let reloadControls: @MainActor () -> Void
    private var loop: Task<Void, Never>?
    /// Which loop may change the store (`run`); a stopped or replaced loop finds it changed and ends.
    private var loopGeneration = 0
    /// The address the live loop reached flatd at: commands go there while live; otherwise they check the saved address
    /// first, as the loop does. (Who answers is settled on every connection by the pin, `FlatdTransport`.)
    private var liveBase: URL?
    /// How often each device or mode changed in the stream, and how many snapshots came: a command's answer is shown
    /// only when nothing newer came from the stream meanwhile (Codex's review, round 2).
    private var revisions: [String: Int] = [:]
    private var snapshots = 0
    /// Who hears every change as flatd describes it (the 3D page, `FlatScreen`'s bridge), each for one pairing.
    private var listeners: [UUID: (pairing: UUID, hear: @MainActor (FlatEvent) -> Void)] = [:]
    private static let log = Logger(subsystem: "de.ares-empire.arestia", category: "store")
    /// Pauses between attempts to reach flatd again (the last one repeats).
    static let backoff: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(15), .seconds(30)]

    static func pause(after failures: Int) -> Duration {
        backoff[min(max(failures, 1), backoff.count) - 1]
    }

    init(connection: FlatdConnection, transport: (any HTTPTransport & Sendable)? = nil,
         eventSource: any FlatEventSource = WebSocketEvents(),
         rediscover: @escaping @Sendable () async -> [URL] = { await FlatdBonjour.candidates() },
         reloadControls: @escaping @MainActor () -> Void = { ArestiaControlKind.reloadAll() }) {
        self.connection = connection
        self.transport = transport
        self.eventSource = eventSource
        self.rediscover = rediscover
        self.reloadControls = reloadControls
        let saved = connection.pairing?.id
        pairingID = saved
        link = saved == nil ? .notSetUp : .connecting
    }

    // MARK: what the screens read

    var fans: [Device] { devices.filter { $0.kind == .fan } }
    var rollos: [Device] { devices.filter { $0.kind == .rollo } }
    /// Devices the home screen has no card for yet (lights, plugs): listed quietly.
    var others: [Device] { devices.filter { $0.kind != .fan && $0.kind != .rollo } }
    var cooking: FlatMode? { modes.first { $0.id == FlatMode.cookingID } }
    var isCooking: Bool { cooking?.active == true }
    var hasSnapshot: Bool { lastSeen != nil }

    func device(_ id: String) -> Device? { devices.first { $0.id == id } }

    /// A blind's position as shown: the finger's while it drags, else flatd's.
    func shownPosition(of rollo: Device) -> Int? { dragging[rollo.id] ?? rollo.state.position }

    // MARK: following flatd

    /// Starts following flatd (at launch and back in the foreground). Does nothing while it already does or without a
    /// pairing. A saved pairing other than the store's (Disconnect or pairing elsewhere) is taken on only after the
    /// store left its own completely (`adopt`).
    func start() {
        guard loop == nil else { return }
        let saved = connection.pairing
        if saved?.id != pairingID { adopt(saved) }
        guard let pairing = saved else {
            link = .notSetUp
            return
        }
        if link != .live, !hasSnapshot { link = .connecting }
        loopGeneration += 1
        let generation = loopGeneration
        loop = Task { [weak self] in await self?.run(generation: generation, pairing: pairing) }
    }

    /// Leaves the store's pairing completely and takes on this one (nil: none): its loop and every command under way
    /// are cancelled, the page's listener is dropped (the page goes with its web view, which belongs to the old
    /// identity), and nothing of the old flat stays: devices, modes, scenes, the line at the bottom, the time last
    /// seen. Whatever of the old pairing is still on its way finds `pairingID` changed and is dropped.
    private func adopt(_ pairing: FlatdPairing?) {
        stop()
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        listeners = [:]
        resets += 1
        pairingID = pairing?.id
        devices = []
        modes = []
        scenes = []
        dragging = [:]
        working = []
        revisions = [:]
        snapshots = 0
        offer = nil
        lastSeen = nil
        link = pairing == nil ? .notSetUp : .connecting
        reloadControls()
    }

    /// The saved pairing changed under the store (seen by a command or the loop): it leaves its own and, if it was
    /// following flatd, follows the saved one.
    private func followSaved() {
        let following = loop != nil
        let saved = connection.pairing
        guard saved?.id != pairingID else { return }
        adopt(saved)
        if following { start() }
    }

    /// Stops following (the app went to the background, the screen went away, the pairing changed).
    func stop() {
        loopGeneration += 1
        loop?.cancel()
        loop = nil
        liveBase = nil
    }

    /// Try again now (pull to refresh, the offline card's button).
    func retry() {
        stop()
        if link == .offline || link == .refused { link = .connecting }
        start()
    }

    /// Whether the loop of `generation` may still change the store.
    private func owns(_ generation: Int) -> Bool { generation == loopGeneration && !Task.isCancelled }

    private func run(generation: Int, pairing: FlatdPairing) async {
        var failures = 0
        var client = FlatdClient(pairing, transport: transport)
        var movedSinceLive = false
        while owns(generation) {
            // Paired anew or disconnected meanwhile (anywhere): this loop's pairing is over.
            guard connection.pairing?.id == pairing.id else {
                followSaved()
                return
            }
            do {
                try await follow(client, generation: generation) {
                    failures = 0
                    movedSinceLive = false
                }
            } catch FlatdError.refused {
                guard owns(generation) else { return }
                // A refusal counts only for the key it was sent with: a fresh code of the same flatd brought another
                // one meanwhile, which the next round uses.
                if connection.pairing?.id == pairing.id, connection.token == pairing.token {
                    Self.log.notice("flatd refused the key")
                    link = .refused
                    stop()
                    return
                }
            } catch {}
            guard owns(generation) else { return }
            failures += 1
            // flatd's address may have changed: after the second miss, look over Bonjour. What it offers are only
            // candidates; one counts when the server there proved flatd's key and answered.
            if failures >= 2 {
                let candidates = await rediscover().filter { $0 != client.baseURL }
                guard owns(generation) else { return }
                let found = await FlatdReach.find(pairing, among: candidates, transport: transport)
                guard owns(generation) else { return }
                if let found {
                    Self.log.notice("flatd is at a new address")
                    client = found                   // kept in the pairing only once it answered (in `follow`)
                    // At once the first time; a second move without a live stream in between waits like any retry
                    // (flatd reachable at two addresses with a failing stream must not spin).
                    if !movedSinceLive {
                        movedSinceLive = true
                        continue
                    }
                }
            }
            // One quick retry before the screen says so: a stream cut while the app was in the background, say.
            if failures >= 2 || !hasSnapshot { link = .offline }
            try? await Task.sleep(for: Self.pause(after: failures))
        }
    }

    /// The address checked, scenes over HTTP (also telling a refused key apart at once), then the event stream until it
    /// ends. A first snapshot resets the failures and, at a new address, keeps it in the pairing.
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
            guard owns(generation), client.pairingID == pairingID else { return }
            if case .snapshot = event {
                // Each connection's first word: still the saved pairing? Otherwise nothing of it is shown.
                guard let saved = connection.pairing, saved.id == client.pairingID else {
                    followSaved()
                    return
                }
                apply(event)
                live()
                link = .live
                liveBase = client.baseURL
                if saved.token == client.token { connection.move(saved, to: client.baseURL) }
            } else {
                apply(event)
            }
        }
        throw FlatdError.unreachable            // the stream ended: reconnect
    }

    /// Hears every change of this pairing's flat from now on, in flatd's own form: the stream's events, and the state a
    /// command's answer brought. Nil (nothing is heard) when the store works for another pairing; the store drops the
    /// listener when it leaves the pairing. Keep the token; `unlisten` ends it.
    func listen(for pairing: UUID, _ listener: @escaping @MainActor (FlatEvent) -> Void) -> UUID? {
        guard pairing == pairingID else { return nil }
        let token = UUID()
        listeners[token] = (pairing, listener)
        return token
    }

    func unlisten(_ token: UUID) { listeners[token] = nil }

    private func tell(_ event: FlatEvent) {
        for listener in listeners.values where listener.pairing == pairingID { listener.hear(event) }
    }

    /// The whole state now, as a snapshot event (for a listener that starts, or the page after it loaded).
    var snapshot: FlatEvent { .snapshot(devices: devices, modes: modes) }

    /// The same for a page of this pairing; nil for one of another.
    func snapshot(for pairing: UUID) -> FlatEvent? { pairing == pairingID ? snapshot : nil }

    /// One event of the stream (also called by the tests). Listeners hear it once; a snapshot as the whole state (a
    /// snapshot without modes keeps the modes known).
    func apply(_ event: FlatEvent, at now: Date = .now) {
        let before = controlState
        switch event {
        case let .snapshot(devices, modes):
            snapshots += 1
            self.devices = devices
            if let modes { self.modes = modes }
            dragging = [:]
            if let pairingID { connection.remember(devices, for: pairingID) }
            lastSeen = now
            tell(snapshot)
        case let .state(id, patch, _):
            guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
            revisions[id, default: 0] += 1
            devices[index].state = devices[index].state.merging(patch)
            if dragging[id] != nil, patch.fields["target"] != nil || patch.fields["moving"] != nil
                || patch.fields["position"] != nil { dragging[id] = nil }
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

    // MARK: connecting

    /// Where among these addresses the flatd of this pairing code answers (its identity proved by the transport, its
    /// health asked without the key); nil when nowhere.
    func locate(_ code: PairingCode, among candidates: [URL]) async -> URL? {
        guard let first = candidates.first else { return nil }
        let probe = FlatdPairing(baseURL: first, token: code.token, pin: code.pin)
        return await FlatdReach.find(probe, among: candidates, transport: transport)?.baseURL
    }

    /// Checks a pairing code's key with flatd at this address (`GET /api/devices`; the transport accepts only a server
    /// holding the code's pin) and keeps the pairing when flatd answers. Returns why not: `.unreachable` when flatd is
    /// not there (nothing, or something without its key), `.refused` when flatd itself does not know the key,
    /// `.notPossible` when the pairing changed meanwhile, or the code would replace who the app trusts without
    /// `replacing`.
    ///
    /// - A code of the flatd paired now (the same identity) renews key and address in place: the pairing keeps its
    ///   identity, so its page, choices and work go on; the stream starts again with the new key.
    /// - Any other code (another flatd, or when what is saved cannot be told) replaces who the app trusts, so only with
    ///   `replacing` (the person tapped Connect for exactly this code), and only through a full Disconnect: the old
    ///   pairing forgotten with its choices, the store's tasks, stream, page and state gone (`adopt`), then the new
    ///   pairing saved fresh with an identity of its own. Its flatd is checked first, so an unreachable one leaves the old
    ///   pairing as it was.
    /// - A first pairing is saved only while nothing is saved (`pairNew`).
    func connect(to baseURL: URL, token: String, pin: FlatdPin, replacing: Bool = false) async -> FlatdError? {
        let decided = connection.saved
        let sameFlatd: FlatdPairing? = if case let .paired(saved) = decided, saved.pin == pin { saved } else { nil }
        let replaces = decided != .none && sameFlatd == nil
        guard !replaces || replacing else { return .notPossible }
        let candidate = FlatdClient(baseURL: baseURL, token: token, pin: pin, transport: transport)
        let startedAt = resets
        do {
            try await candidate.verify()
            let found = try await candidate.devices()
            // The screen went away, the store left its pairing, or the saved pairing is no longer what this attempt was
            // decided against: this attempt keeps nothing.
            guard !Task.isCancelled, startedAt == resets, connection.saved.isSamePairing(as: decided) else {
                return .notPossible
            }
            if let sameFlatd {
                let renewed = FlatdPairing(baseURL: baseURL, token: token, pin: pin, id: sameFlatd.id)
                // Over the version read; a control that only moved the address meanwhile is written over too.
                var current = sameFlatd, written = false
                for _ in 0..<3 where !written {
                    written = connection.renew(current, with: renewed)
                    if !written {
                        guard case let .paired(now) = connection.saved, now.id == sameFlatd.id, now.pin == pin,
                              now.token == sameFlatd.token else { return .notPossible }
                        current = now
                    }
                }
                guard written else { return .notPossible }
                if pairingID != renewed.id { adopt(renewed) }
                stop()                                  // the stream again, with the new key and address
                connection.remember(found, for: renewed.id)
                if link == .refused || !hasSnapshot { link = .connecting }
                start()
                reloadControls()
                return nil
            }
            if replaces { try connection.forget() }
            adopt(nil)
            let fresh = FlatdPairing(baseURL: baseURL, token: token, pin: pin)
            guard try connection.pairNew(fresh) else {
                start()                                 // someone paired meanwhile: follow that one
                return .notPossible
            }
            adopt(fresh)
            devices = found
            connection.remember(found, for: fresh.id)
            start()
            return nil
        } catch let error as FlatdError {
            return error
        } catch is CancellationError {
            return .notPossible
        } catch {
            return .invalidAnswer     // the Keychain refused to save or to forget
        }
    }

    /// Forgets the pairing and everything of it (Settings → Disconnect): the Keychain item and the device names, the
    /// store's tasks, stream, page and state. If the Keychain keeps the item, says so and stays.
    func disconnect() {
        do {
            try connection.forget()
        } catch {
            offer = UndoOffer(message: String(localized: "Arestia couldn't forget the key. Try again."))
            return
        }
        adopt(nil)
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

    func setRollo(_ id: String, position: Int) {
        let position = min(100, max(0, position))
        dragging[id] = position
        send("rollo:" + id, affects: id, blocking: false) { client in
            try await client.send(.position(position), to: id)
        } done: { device, stamp in
            self.take(device, since: stamp)
            if self.dragging[id] == position { self.dragging[id] = nil }   // flatd has it now (moving, target)
        } failed: {
            if self.dragging[id] == position { self.dragging[id] = nil }
        }
    }

    /// Cooking on or off (any mode). Ending cooking offers Undo, which starts it again (only on the same pairing).
    /// Devices that did not follow are named (flatd changes the mode anyway).
    func setMode(_ id: String, active: Bool) {
        send("mode:" + id, affects: "mode:" + id) { client in
            try await client.setMode(id, active: active)
        } done: { answer, stamp in
            let (mode, failed) = answer
            self.take(mode, since: stamp)
            if let line = self.failureLine(failed) {
                self.offer = UndoOffer(message: line)
            } else if id == FlatMode.cookingID, !active {
                let pairing = self.pairingID
                self.offer = UndoOffer(message: FlatWords.cookingEnded()) { [weak self] in
                    guard let self, pairing == self.pairingID else { return }
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

    /// The pairing changed under a command: it is dropped (and the store follows the saved pairing).
    private struct PairingChanged: Error {}

    /// The client a command for this pairing goes through, built from one reading of the saved pairing (so the identity
    /// checked and the key and pin used are the same pairing's): at the live loop's address, or at the saved one once
    /// flatd answered there. Throws `PairingChanged` when the store or the Keychain has another pairing now.
    private func readyClient(for id: UUID) async throws -> FlatdClient {
        guard id == pairingID, let pairing = connection.pairing, pairing.id == id else { throw PairingChanged() }
        if link == .live, let liveBase {
            return FlatdClient(pairing, at: liveBase, transport: transport)
        }
        let client = FlatdClient(pairing, transport: transport)
        try await client.verify()
        guard id == pairingID else { throw PairingChanged() }
        return client
    }

    /// Runs work for the store's pairing as a task the store can cancel when it leaves that pairing.
    private func perform(_ work: @escaping @MainActor () async -> Void) {
        let token = UUID()
        tasks[token] = Task { [weak self] in
            await work()
            self?.tasks[token] = nil
        }
    }

    /// Runs a command: one at a time per thing (`blocking`), the failure as a calm line, a refused key back to the
    /// connect screen, a lost flatd as a reason to reconnect. Tagged with the store's pairing: dropped, its answer too,
    /// once the store works for another (or the Keychain holds another); `affects` names what the answer shows (a
    /// device id, "mode:<id>"), for `stamp`.
    private func send<Answer: Sendable>(_ key: String, affects: String, blocking: Bool = true,
                                        _ work: @escaping @Sendable (FlatdClient) async throws -> Answer,
                                        done: @escaping @MainActor (Answer, Stamp) -> Void,
                                        failed: @escaping @MainActor () -> Void = {}) {
        guard let pairing = pairingID else { return }
        if blocking, working.contains(key) { return }
        working.insert(key)
        perform { [weak self] in
            guard let self else { return }
            defer { if pairing == pairingID { working.remove(key) } }
            var used: FlatdClient?
            do {
                let client = try await readyClient(for: pairing)
                used = client
                let stamp = stamp(affects)
                let answer = try await work(client)
                guard pairing == pairingID else { return }
                done(answer, stamp)
                reloadControls()
            } catch is PairingChanged {
                followSaved()
            } catch let error as FlatdError {
                guard pairing == pairingID else { return }
                failed()
                handle(error, client: used)
            } catch {
                guard pairing == pairingID else { return }
                failed()
            }
        }
    }

    /// What a failed command does to the store: a refused key stops it (only while that key is the saved one: a fresh
    /// code may have brought another meanwhile), a lost flatd reconnects (only while the store follows flatd at all),
    /// the rest is a line.
    private func handle(_ error: FlatdError, client: FlatdClient?) {
        switch error {
        case .refused:
            guard client == nil || client?.token == connection.token else { return }
            link = .refused
            stop()
        case .unreachable:
            offer = UndoOffer(message: error.message())
            if link == .live, loop != nil { retry() }
        default:
            offer = UndoOffer(message: error.message())
        }
    }

    // MARK: the 3D page's requests (BRIDGE.md: bodies forwarded unchanged, one result each)

    /// Whether a page of this pairing may still speak: the store works for it and it is the saved one.
    func speaks(for pairing: UUID) -> Bool { pairing == pairingID && connection.pairing?.id == pairing }

    /// The client for fetching this pairing's page: nil once the store or the Keychain has another pairing.
    func client(for pairing: UUID) -> FlatdClient? {
        guard pairing == pairingID else { return nil }
        return connection.client(for: pairing, transport: transport)
    }

    /// A device command from the 3D page. The answer's state reaches the page through the listeners. `pairing` is the
    /// identity of the pairing whose flatd gave the page that asks: a page of another pairing commands nothing, however
    /// late its message is worked off, and its client is that pairing's own (`readyClient`).
    func pageRequest(_ id: String, body: Data, pairing: UUID) async -> FlatdError? {
        var used: FlatdClient?
        do {
            let client = try await readyClient(for: pairing)
            used = client
            let stamp = stamp(id)
            let device = try await client.send(body: body, to: id)
            guard pairing == pairingID else { return nil }
            take(device, since: stamp)
            reloadControls()
            return nil
        } catch {
            return pageFailure(error, pairing: pairing, client: used)
        }
    }

    /// A mode change from the 3D page (it only ever ends cooking); `pairing` as for `pageRequest`.
    func pageMode(_ id: String, body: Data, pairing: UUID) async -> FlatdError? {
        var used: FlatdClient?
        do {
            let client = try await readyClient(for: pairing)
            used = client
            let stamp = stamp("mode:" + id)
            let (mode, failed) = try await client.setMode(id, body: body)
            guard pairing == pairingID else { return nil }
            take(mode, since: stamp)
            if let line = failureLine(failed) { offer = UndoOffer(message: line) }
            reloadControls()
            return nil
        } catch {
            return pageFailure(error, pairing: pairing, client: used)
        }
    }

    /// A page's failed command: the bridge's error, and the store's reaction while the pairing is still the same.
    private func pageFailure(_ error: Error, pairing: UUID, client: FlatdClient?) -> FlatdError {
        if error is PairingChanged {
            if pairing == pairingID { followSaved() }
            return .notPossible
        }
        let error = error as? FlatdError ?? .unreachable
        guard pairing == pairingID else { return error }
        if error == .refused {
            handle(.refused, client: client)
        } else if error == .unreachable, link == .live, loop != nil {
            retry()
        }
        return error
    }
}
