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
    /// Requests on their way, by what they change ("fan:…", "mode:cooking", "scene:air_out").
    private(set) var working: Set<String> = []
    /// A blind's position while a finger drags it, before flatd has it.
    private(set) var dragging: [String: Int] = [:]
    /// The line at the bottom: what could not be done, or "Cooking ended · Undo".
    var offer: UndoOffer?

    let connection: FlatdConnection
    private let transport: any HTTPTransport & Sendable
    private let eventSource: any FlatEventSource
    private let rediscover: @Sendable (String) async -> URL?
    private let reloadControls: @MainActor () -> Void
    private var loop: Task<Void, Never>?
    private var failures = 0
    /// Who hears every change as flatd describes it (the 3D page, `FlatViewerBridge`).
    private var listeners: [UUID: @MainActor (FlatEvent) -> Void] = [:]
    private static let log = Logger(subsystem: "de.ares-empire.arestia", category: "store")
    /// Pauses between attempts to reach flatd again (the last one repeats).
    static let backoff: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(15), .seconds(30)]

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
        guard connection.client != nil else {
            link = .notSetUp
            return
        }
        if link != .live { link = hasSnapshot ? link : .connecting }
        loop = Task { [weak self] in await self?.run() }
    }

    /// Stops following (the app went to the background; the stream would be cut anyway).
    func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Try again now (pull to refresh, the offline card's button).
    func retry() {
        stop()
        failures = 0
        if link == .offline || link == .refused { link = .connecting }
        start()
    }

    private func client() -> FlatdClient? {
        guard let link = connection.link, let token = connection.token, !token.isEmpty else { return nil }
        return FlatdClient(baseURL: link.baseURL, token: token, transport: transport)
    }

    private func run() async {
        while !Task.isCancelled {
            guard let client = client() else {
                link = .notSetUp
                loop = nil
                return
            }
            do {
                try await follow(client)
            } catch FlatdError.refused {
                Self.log.notice("flatd refused the key")
                link = .refused
                loop = nil
                return
            } catch is CancellationError {
                return
            } catch {}
            guard !Task.isCancelled else { return }
            failures += 1
            // The Mac's address may have changed: after the first miss, look for flatd again under its Bonjour name.
            if failures >= 2, let name = connection.link?.serviceName, let found = await rediscover(name),
               found != connection.link?.baseURL {
                Self.log.notice("flatd found again at a new address")
                connection.save(link: FlatdLink(baseURL: found, serviceName: name))
                continue
            }
            // One quick retry before the screen says so: a stream cut while the app was in the background, say.
            if failures >= 2 || !hasSnapshot { link = .offline }
            let pause = Self.backoff[min(failures - 1, Self.backoff.count - 1)]
            try? await Task.sleep(for: pause)
        }
    }

    /// Scenes over HTTP (also telling a refused key apart at once), then the event stream until it ends.
    private func follow(_ client: FlatdClient) async throws {
        do {
            scenes = try await client.scenes()
        } catch FlatdError.unknown {
            scenes = []                         // a flatd without scenes
        }
        for try await event in eventSource.events(from: client.eventsURL) {
            Self.log.debug("store: an event")
            apply(event)
            if case .snapshot = event {
                failures = 0
                link = .live
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

    /// One event of the stream (also called by the tests).
    func apply(_ event: FlatEvent, at now: Date = .now) {
        let before = controlState
        switch event {
        case let .snapshot(devices, modes):
            self.devices = devices
            if let modes { self.modes = modes }
            connection.remember(devices)
        case let .state(id, patch, _):
            guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
            devices[index].state = devices[index].state.merging(patch)
            if dragging[id] != nil, patch.fields["target"] != nil || patch.fields["moving"] != nil { dragging[id] = nil }
        case let .mode(mode):
            take(mode)
        case .other:
            return
        }
        lastSeen = now
        tell(event)
        if controlState != before { reloadControls() }
    }

    /// What the Control Center controls show: when it changes here, they are asked to read again.
    private var controlState: [String] {
        [String(isCooking), String(fans.contains { $0.state.on == true })]
            + rollos.map { $0.id + String(RolloOpenness.isOpen($0.state)) }
    }

    /// A device as a command's answer brought it (the stream brings the same a moment later).
    private func take(_ device: Device) {
        let before = controlState
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[index].state = devices[index].state.merging(device.state)
        tell(.state(id: device.id, state: device.state, source: "api"))
        if controlState != before { reloadControls() }
    }

    private func take(_ mode: FlatMode) {
        let before = controlState
        if let index = modes.firstIndex(where: { $0.id == mode.id }) { modes[index] = mode } else { modes.append(mode) }
        tell(.mode(mode))
        if controlState != before { reloadControls() }
    }

    /// "Didn't answer: Fan 2." for the devices a mode or scene could not reach; nil when all followed.
    func failureLine(_ ids: [String], language: AppLanguage = .current) -> String? {
        guard !ids.isEmpty else { return nil }
        let names = ids.map { id in device(id)?.label ?? id }.joined(separator: ", ")
        return language.string("Didn't answer: \(names).")
    }

    // MARK: connecting

    /// Checks the address and key with flatd (`GET /api/devices`) and keeps them when it answers. Returns why not.
    func connect(to baseURL: URL, serviceName: String?, token: String) async -> FlatdError? {
        let candidate = FlatdClient(baseURL: baseURL, token: token, transport: transport)
        do {
            let found = try await candidate.devices()
            try connection.save(token: token)
            connection.save(link: FlatdLink(baseURL: baseURL, serviceName: serviceName))
            stop()
            devices = found
            connection.remember(found)
            failures = 0
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
        connection.forget()
        devices = []
        modes = []
        scenes = []
        lastSeen = nil
        link = .notSetUp
        reloadControls()
    }

    // MARK: commands

    /// A fan on (for `minutes`, nil: until off) or off.
    func setFan(_ id: String, on: Bool, minutes: Int? = nil) {
        send("power:" + id) { client in
            let device = try await client.send(.power(on: on, seconds: minutes.map { $0 * 60 }), to: id)
            self.take(device)
        }
    }

    func moveRollo(_ id: String, _ command: RolloCommand) {
        dragging[id] = nil
        send("rollo:" + id, blocking: false) { client in
            self.take(try await client.send(.rollo(command), to: id))
        }
    }

    /// While a finger drags a blind: shown at once, sent when it lets go (`setRollo(_:position:)`).
    func drag(_ id: String, to position: Int) {
        dragging[id] = min(100, max(0, position))
    }

    func setRollo(_ id: String, position: Int) {
        let position = min(100, max(0, position))
        dragging[id] = position
        send("rollo:" + id, blocking: false) { client in
            self.take(try await client.send(.position(position), to: id))
        } failed: {
            self.dragging[id] = nil
        }
    }

    /// Cooking on or off (any mode). Ending cooking offers Undo, which starts it again. Devices that did not follow
    /// are named (flatd changes the mode anyway).
    func setMode(_ id: String, active: Bool) {
        send("mode:" + id) { client in
            let (mode, failed) = try await client.setMode(id, active: active)
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
            let failed = try await client.runScene(id)
            self.offer = UndoOffer(message: [FlatWords.sceneDone(title), self.failureLine(failed)]
                .compactMap { $0 }.joined(separator: " "))
        }
    }

    // MARK: the 3D page's requests (BRIDGE.md: bodies forwarded unchanged, one result each)

    /// A device command from the 3D page. The answer's state reaches the page through the listeners.
    func pageRequest(_ id: String, body: Data) async -> FlatdError? {
        await pageCommand { client in self.take(try await client.send(body: body, to: id)) }
    }

    /// A mode change from the 3D page (it only ever ends cooking).
    func pageMode(_ id: String, body: Data) async -> FlatdError? {
        await pageCommand { client in
            let (mode, failed) = try await client.setMode(id, body: body)
            self.take(mode)
            if let line = self.failureLine(failed) { self.offer = UndoOffer(message: line) }
        }
    }

    private func pageCommand(_ work: @MainActor (FlatdClient) async throws -> Void) async -> FlatdError? {
        guard let client = client() else { return .refused }
        do {
            try await work(client)
            reloadControls()
            return nil
        } catch let error as FlatdError {
            if error == .refused {
                link = .refused
                stop()
            } else if error == .unreachable, link == .live {
                retry()
            }
            return error
        } catch {
            return .unreachable
        }
    }

    func isWorking(_ key: String) -> Bool { working.contains(key) }

    /// Runs a command: one at a time per thing (`blocking`), the failure as a calm line, a refused key back to the
    /// connect screen, a missed flatd as a reason to reconnect.
    private func send(_ key: String, blocking: Bool = true,
                      _ work: @escaping @MainActor (FlatdClient) async throws -> Void,
                      failed: @escaping @MainActor () -> Void = {}) {
        guard let client = client() else { return }
        if blocking, working.contains(key) { return }
        working.insert(key)
        Task {
            defer { working.remove(key) }
            do {
                try await work(client)
                reloadControls()
            } catch let error as FlatdError {
                failed()
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
            } catch {
                failed()
            }
        }
    }
}
