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
/// - The key goes only to an address that answered like flatd (`FlatdClient.verify`).
///
/// One loop follows flatd at a time: each has its own generation and failure count, and after every wait it checks it
/// is still the store's loop before it changes anything (Codex's review, 2026-11-19: a Try again during a Bonjour
/// lookup used to leave the old loop running on a reset count). Every command remembers the pairing it was sent with,
/// so a late answer after connecting again changes nothing.
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
        /// flatd refused the key (401): it has to be entered again.
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
    /// Counts up whenever the pairing changes (connect, disconnect): the 3D page loads again, late answers are dropped.
    private(set) var pairingGeneration = 0
    /// The line at the bottom: what could not be done, or "Cooking ended · Undo".
    var offer: UndoOffer?

    let connection: FlatdConnection
    private let transport: any HTTPTransport & Sendable
    private let eventSource: any FlatEventSource
    private let rediscover: @Sendable (String) async -> URL?
    private let reloadControls: @MainActor () -> Void
    private var loop: Task<Void, Never>?
    /// Which loop may change the store (`run`); a stopped or replaced loop finds it changed and ends.
    private var loopGeneration = 0
    /// Who hears every change as flatd describes it (the 3D page, `FlatScreen`'s bridge).
    private var listeners: [UUID: @MainActor (FlatEvent) -> Void] = [:]
    private static let log = Logger(subsystem: "de.ares-empire.arestia", category: "store")
    /// Pauses between attempts to reach flatd again (the last one repeats).
    static let backoff: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(15), .seconds(30)]

    static func pause(after failures: Int) -> Duration {
        backoff[min(max(failures, 1), backoff.count) - 1]
    }

    init(connection: FlatdConnection, transport: any HTTPTransport & Sendable = URLSessionTransport(),
         eventSource: any FlatEventSource = WebSocketEvents(),
         rediscover: @escaping @Sendable (String) async -> URL? = { await FlatdBonjour.resolve(name: $0) },
         reloadControls: @escaping @MainActor () -> Void = { ArestiaControlKind.reloadAll() }) {
        self.connection = connection
        self.transport = transport
        self.eventSource = eventSource
        self.rediscover = rediscover
        self.reloadControls = reloadControls
        link = connection.client == nil ? .notSetUp : .connecting
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

    /// Starts following flatd (at launch and back in the foreground). Does nothing while it already does or without a key.
    func start() {
        guard loop == nil else { return }
        guard let pairing = connection.pairing else {
            link = .notSetUp
            return
        }
        if link != .live, !hasSnapshot { link = .connecting }
        loopGeneration += 1
        let generation = loopGeneration
        loop = Task { [weak self] in await self?.run(generation: generation, pairing: pairing) }
    }

    /// Stops following (the app went to the background, the screen went away, the pairing changed).
    func stop() {
        loopGeneration += 1
        loop?.cancel()
        loop = nil
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
        var base = pairing.link.baseURL
        while owns(generation) {
            let client = FlatdClient(baseURL: base, token: pairing.token, transport: transport)
            do {
                try await follow(client, generation: generation) { failures = 0 }
            } catch FlatdError.refused {
                guard owns(generation) else { return }
                Self.log.notice("flatd refused the key")
                link = .refused
                stop()
                return
            } catch {}
            guard owns(generation) else { return }
            failures += 1
            // The Mac's address may have changed: after the second miss, look for flatd again under its Bonjour name.
            if failures >= 2, let name = pairing.link.serviceName {
                let found = await rediscover(name)
                guard owns(generation) else { return }
                if let found, found != base {
                    Self.log.notice("flatd may be at a new address")
                    base = found                     // kept in the pairing only once it answered (in `follow`)
                    continue
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
        try await client.verify()
        let answered: [FlatScene]
        do { answered = try await client.scenes() } catch FlatdError.unknown { answered = [] }   // a flatd without scenes
        guard owns(generation) else { return }
        scenes = answered
        for try await event in eventSource.events(from: client.eventsURL) {
            guard owns(generation) else { return }
            apply(event)
            if case .snapshot = event {
                live()
                link = .live
                connection.move(to: client.baseURL, keyedBy: client.token)
            }
        }
        throw FlatdError.unreachable            // the stream ended: reconnect
    }

    /// Hears every change from now on, in flatd's own form: the stream's events, and the state a command's answer
    /// brought. Keep the token; `unlisten` ends it.
    func listen(_ listener: @escaping @MainActor (FlatEvent) -> Void) -> UUID {
        let token = UUID()
        listeners[token] = listener
        return token
    }

    func unlisten(_ token: UUID) { listeners[token] = nil }

    private func tell(_ event: FlatEvent) {
        for listener in listeners.values { listener(event) }
    }

    /// The whole state now, as a snapshot event (for a listener that starts, or the page after it loaded).
    var snapshot: FlatEvent { .snapshot(devices: devices, modes: modes) }

    /// One event of the stream (also called by the tests). Listeners hear it once; a snapshot as the whole state (a
    /// snapshot without modes keeps the modes known).
    func apply(_ event: FlatEvent, at now: Date = .now) {
        let before = controlState
        switch event {
        case let .snapshot(devices, modes):
            self.devices = devices
            if let modes { self.modes = modes }
            dragging = [:]
            connection.remember(devices)
            lastSeen = now
            tell(snapshot)
        case let .state(id, patch, _):
            guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
            devices[index].state = devices[index].state.merging(patch)
            if dragging[id] != nil, patch.fields["target"] != nil || patch.fields["moving"] != nil
                || patch.fields["position"] != nil { dragging[id] = nil }
            lastSeen = now
            tell(event)
        case let .mode(mode):
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

    /// A device as a command's answer brought it. An answer older than what the stream already brought is left out.
    private func take(_ device: Device) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        if let incoming = device.state.updatedAt, let current = devices[index].state.updatedAt, incoming < current {
            return
        }
        let before = controlState
        devices[index].state = devices[index].state.merging(device.state)
        tell(.state(id: device.id, state: device.state, source: "api"))
        if controlState != before { reloadControls() }
    }

    /// A mode as a command's answer brought it.
    private func take(_ mode: FlatMode) {
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

    /// Checks the address and key with flatd (`GET /api/devices`, once it answered like flatd) and keeps them when it
    /// answers. Returns why not.
    func connect(to baseURL: URL, serviceName: String?, token: String) async -> FlatdError? {
        let candidate = FlatdClient(baseURL: baseURL, token: token, transport: transport)
        do {
            try await candidate.verify()
            let found = try await candidate.devices()
            try connection.save(FlatdPairing(link: FlatdLink(baseURL: baseURL, serviceName: serviceName), token: token))
            stop()
            pairingGeneration += 1
            devices = found
            modes = []
            scenes = []
            dragging = [:]
            working = []
            connection.remember(found)
            link = .connecting
            start()
            reloadControls()
            return nil
        } catch let error as FlatdError {
            return error
        } catch {
            return .invalidAnswer     // the Keychain refused to save
        }
    }

    /// Forgets the address and the key (Settings → Disconnect).
    func disconnect() {
        stop()
        pairingGeneration += 1
        connection.forget()
        devices = []
        modes = []
        scenes = []
        dragging = [:]
        working = []
        lastSeen = nil
        link = .notSetUp
        reloadControls()
    }

    // MARK: commands

    /// A fan on (for `minutes`, nil: until off) or off.
    func setFan(_ id: String, on: Bool, minutes: Int? = nil) {
        send("power:" + id) { client in
            try await client.send(.power(on: on, seconds: minutes.map { $0 * 60 }), to: id)
        } done: { device in
            self.take(device)
        }
    }

    func moveRollo(_ id: String, _ command: RolloCommand) {
        dragging[id] = nil
        send("rollo:" + id, blocking: false) { client in
            try await client.send(.rollo(command), to: id)
        } done: { device in
            self.take(device)
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
        send("rollo:" + id, blocking: false) { client in
            try await client.send(.position(position), to: id)
        } done: { device in
            self.take(device)
            if self.dragging[id] == position { self.dragging[id] = nil }   // flatd has it now (moving, target)
        } failed: {
            if self.dragging[id] == position { self.dragging[id] = nil }
        }
    }

    /// Cooking on or off (any mode). Ending cooking offers Undo, which starts it again. Devices that did not follow
    /// are named (flatd changes the mode anyway).
    func setMode(_ id: String, active: Bool) {
        send("mode:" + id) { client in
            try await client.setMode(id, active: active)
        } done: { answer in
            let (mode, failed) = answer
            self.take(mode)
            if let line = self.failureLine(failed) {
                self.offer = UndoOffer(message: line)
            } else if id == FlatMode.cookingID, !active {
                self.offer = UndoOffer(message: FlatWords.cookingEnded()) { [weak self] in
                    self?.setMode(id, active: true)
                }
            }
        }
    }

    func runScene(_ id: String, title: String) {
        send("scene:" + id) { client in
            try await client.runScene(id)
        } done: { failed in
            self.offer = UndoOffer(message: [FlatWords.sceneDone(title), self.failureLine(failed)]
                .compactMap { $0 }.joined(separator: " "))
        }
    }

    func isWorking(_ key: String) -> Bool { working.contains(key) }

    /// Runs a command: one at a time per thing (`blocking`), the failure as a calm line, a refused key back to the
    /// connect screen, a lost flatd as a reason to reconnect. An answer that comes after the pairing changed is dropped.
    private func send<Answer: Sendable>(_ key: String, blocking: Bool = true,
                                        _ work: @escaping @Sendable (FlatdClient) async throws -> Answer,
                                        done: @escaping @MainActor (Answer) -> Void,
                                        failed: @escaping @MainActor () -> Void = {}) {
        guard let client = currentClient() else { return }
        if blocking, working.contains(key) { return }
        let pairing = pairingGeneration
        working.insert(key)
        Task {
            defer { if pairing == pairingGeneration { working.remove(key) } }
            do {
                let answer = try await work(client)
                guard pairing == pairingGeneration else { return }
                done(answer)
                reloadControls()
            } catch let error as FlatdError {
                guard pairing == pairingGeneration else { return }
                failed()
                handle(error)
            } catch {
                guard pairing == pairingGeneration else { return }
                failed()
            }
        }
    }

    /// What a failed command does to the store: a refused key stops it, a lost flatd reconnects, the rest is a line.
    private func handle(_ error: FlatdError) {
        switch error {
        case .refused:
            link = .refused
            stop()
        case .unreachable:
            offer = UndoOffer(message: error.message())
            if link == .live { retry() }
        default:
            offer = UndoOffer(message: error.message())
        }
    }

    // MARK: the 3D page's requests (BRIDGE.md: bodies forwarded unchanged, one result each)

    /// A device command from the 3D page. The answer's state reaches the page through the listeners.
    func pageRequest(_ id: String, body: Data) async -> FlatdError? {
        guard let client = currentClient() else { return .refused }
        let pairing = pairingGeneration
        do {
            let device = try await client.send(body: body, to: id)
            guard pairing == pairingGeneration else { return nil }
            take(device)
            reloadControls()
            return nil
        } catch {
            return pageFailure(error, pairing: pairing)
        }
    }

    /// A mode change from the 3D page (it only ever ends cooking).
    func pageMode(_ id: String, body: Data) async -> FlatdError? {
        guard let client = currentClient() else { return .refused }
        let pairing = pairingGeneration
        do {
            let (mode, failed) = try await client.setMode(id, body: body)
            guard pairing == pairingGeneration else { return nil }
            take(mode)
            if let line = failureLine(failed) { offer = UndoOffer(message: line) }
            reloadControls()
            return nil
        } catch {
            return pageFailure(error, pairing: pairing)
        }
    }

    private func currentClient() -> FlatdClient? {
        connection.client.map { FlatdClient(baseURL: $0.baseURL, token: $0.token, transport: transport) }
    }

    /// A page's failed command: the bridge's error, and the store's reaction while the pairing is still the same.
    private func pageFailure(_ error: Error, pairing: Int) -> FlatdError {
        let error = error as? FlatdError ?? .unreachable
        guard pairing == pairingGeneration else { return error }
        if error == .refused {
            link = .refused
            stop()
        } else if error == .unreachable, link == .live {
            retry()
        }
        return error
    }
}
