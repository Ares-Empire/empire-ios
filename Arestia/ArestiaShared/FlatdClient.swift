import Foundation
import os

#if DEBUG && ARESTIA_GATE
nonisolated enum FlatdRequestTimeout {
    static let gate: TimeInterval = 120
    static let duration = Duration.seconds(gate)
}
#endif
/// Why a request to flatd failed, in the terms the app shows (never a raw error).
nonisolated enum FlatdError: Error, Equatable, Sendable {
    /// No connection at all: the Mac is asleep, flatd is not running, or the phone is not on the home network.
    case unreachable
    case awayNeedsUnlock(needsPasscode: Bool)
    case partialFans(needsUnlock: Bool)
    /// Connected, but no answer in time: flatd may still have done it, so a command is never sent again elsewhere.
    case noAnswer
    /// 401: flatd has a new key (the app pairs again).
    case refused
    /// 404: flatd does not know this device, mode or scene (any more).
    case unknown
    /// 504: the device did not confirm in time. It may still have switched (a plug can switch and then not answer the
    /// reading back), so nothing is claimed: the next state flatd reads tells.
    case deviceDidNotAnswer
    /// 409: not possible now (a blind without a favourite spot asked to go there).
    case notPossible
    /// Any other refusal, with flatd's own sentence when it sent one.
    case failed(status: Int, message: String?)
    /// An answer this app cannot read.
    case invalidAnswer
    /// Arestia is not paired with a flat (never, or the flat was forgotten).
    case notPaired
    /// The pairing could not be read just now (the iPhone not unlocked since it started, a Keychain hiccup).
    case pairingUnreadable
    /// A pairing code of another flat while one is paired: one flat per install, so Forget comes first.
    case anotherFlat
    /// A flatd before contract v1.3 has no renaming (it answers 405).
    case renameNotSupported

    /// One short line for the person, in the app's language.
    func message(language: AppLanguage = .current) -> String {
        switch self {
        case .unreachable:
            language.string(LocalizedStringResource("Can't reach the flat. You may not be at home, or the flat service isn't answering.",
                                                    table: "ArestiaShared"))
        case .awayNeedsUnlock(needsPasscode: true):
            language.string(LocalizedStringResource("Set a passcode on your iPhone to control the flat from away.",
                                                    table: "ArestiaShared"))
        case .awayNeedsUnlock(needsPasscode: false):
            language.string(LocalizedStringResource("Unlock your iPhone to control the flat from away.",
                                                    table: "ArestiaShared"))
        case .partialFans(needsUnlock: true):
            language.string(LocalizedStringResource("Some fans changed. Unlock your iPhone to change the rest.",
                                                    table: "ArestiaShared"))
        case .partialFans(needsUnlock: false):
            language.string(LocalizedStringResource("Some fans changed; the others didn't confirm.",
                                                    table: "ArestiaShared"))
        case .noAnswer:
            language.string(LocalizedStringResource("The flat service didn't answer in time. It may still have done it.",
                                                    table: "ArestiaShared"))
        case .refused:
            language.string(LocalizedStringResource("The flat service refused the key. Pair again in Settings.",
                                                    table: "ArestiaShared"))
        case .unknown:
            language.string(LocalizedStringResource("The flat service doesn't know this any more.", table: "ArestiaShared"))
        case .deviceDidNotAnswer:
            language.string(LocalizedStringResource("The device didn't confirm it. Its state shows once flatd reads it again.",
                                                    table: "ArestiaShared"))
        case .notPossible:
            language.string(LocalizedStringResource("That isn't possible right now.", table: "ArestiaShared"))
        case let .failed(status, message):
            message ?? language.string(LocalizedStringResource("The flat service couldn't do it (\(status)).",
                                                               table: "ArestiaShared"))
        case .invalidAnswer:
            language.string(LocalizedStringResource("The flat service sent an answer this app can't read.",
                                                    table: "ArestiaShared"))
        case .notPaired:
            language.string(LocalizedStringResource("Arestia isn't paired with a flat. Open Arestia to pair it.",
                                                    table: "ArestiaShared"))
        case .pairingUnreadable:
            language.string(LocalizedStringResource("Arestia couldn't read its pairing just now. Unlock the iPhone and try again.",
                                                    table: "ArestiaShared"))
        case .anotherFlat:
            language.string(LocalizedStringResource("This is a different flat. Forget the current one first: Settings → Forget this flat.",
                                                    table: "ArestiaShared"))
        case .renameNotSupported:
            language.string(LocalizedStringResource("This flat service can't rename yet. Update flatd, then try again.",
                                                    table: "ArestiaShared"))
        }
    }
}

// The callers share one constructor signature across builds. Release can only pass nil.
#if DEBUG
typealias FlatdTransportOverride = any PreparingTransport
#else
typealias FlatdTransportOverride = Never
#endif

/// Talks to flatd over HTTPS (contract v1.2: on the home network flatd speaks HTTPS only and proves its identity with
/// the key the pairing pinned, `FlatdPin`; every endpoint but `/api/health` needs `Authorization: Bearer <token>`).
/// The app, its intents and its Control Center controls all go through this one client, so nothing else builds a
/// request, and every request goes through the pinned transport (`FlatdTransport`).
nonisolated struct FlatdClient: Sendable {
    let baseURL: URL
    let token: String
    let pin: FlatdPin
    /// The pairing this client speaks for (`FlatdPairing.id`); nil for a pairing code being tried, which belongs to no
    /// pairing yet. What it reads or does counts only while that pairing is the saved one (`FlatdConnection.isCurrent`).
    let pairingID: UUID?
    let route: HomeRoute?
    var deadline: Deadline?
    var action: FlatdActionDispatch?
    private let transport: any PreparingTransport
    private(set) var remoteGeneration: UUID?
    /// Where a request with the key is started only while this client's pairing is still the saved one (`gated(by:)`);
    /// nil for a pairing code being tried, which belongs to no pairing yet.
    private(set) var gate: FlatdGate?
    /// Reads answer quickly or not at all (the service is on the home network).
    #if DEBUG && ARESTIA_GATE
    var readTimeout = FlatdRequestTimeout.gate
    #else
    var readTimeout: TimeInterval = 6
    #endif
    /// A command waits for the device to confirm (a Rollo's board, a plug), so it may take longer.
    #if DEBUG && ARESTIA_GATE
    var commandTimeout = FlatdRequestTimeout.gate
    #else
    var commandTimeout: TimeInterval = 12
    #endif

    /// A pairing code being tried. Its identity is supplied by the code itself.
    init(baseURL: URL, token: String, pin: FlatdPin, transport: FlatdTransportOverride? = nil) {
        self.baseURL = baseURL
        self.token = token
        self.pin = pin
        pairingID = nil
        route = nil
        self.transport = Self.makeTransport(pin: pin, override: transport)
    }

    /// Home, at the saved address or a Bonjour candidate, always using the home pin.
    init(_ pairing: FlatdPairing, at baseURL: URL? = nil, transport: FlatdTransportOverride? = nil) {
        self.baseURL = baseURL ?? pairing.baseURL
        token = pairing.token
        pin = pairing.pin
        pairingID = pairing.id
        route = .home
        self.transport = Self.makeTransport(pin: pairing.pin, override: transport)
    }

    init?(remoteOf pairing: FlatdPairing, transport: FlatdTransportOverride? = nil) {
        guard let remote = pairing.remote, remote.pin != pairing.pin else { return nil }
        baseURL = remote.url
        token = pairing.token
        pin = remote.pin
        pairingID = pairing.id
        route = .remote
        remoteGeneration = remote.generation
        self.transport = Self.makeTransport(pin: remote.pin, override: transport)
    }

    private static func makeTransport(pin: FlatdPin, override: FlatdTransportOverride?) -> any PreparingTransport {
        #if DEBUG
        if let override { return override }
        #endif
        return FlatdTransport(pin: pin)
    }

    /// Verifies a fresh code with GET /api/devices, while the pairing it would renew is still saved.
    static func verifyRenewal(of saved: FlatdPairing, at baseURL: URL, token: String, connection: FlatdConnection,
                              transport: FlatdTransportOverride?) async throws -> [Device] {
        var verifier = FlatdClient(FlatdPairing(baseURL: baseURL, token: token, pin: saved.pin, id: saved.id),
                                   transport: transport)
        verifier.gate = FlatdGate(connection: connection, pairing: saved.id, route: .home, pin: saved.pin,
                                  baseURL: baseURL, savedToken: saved.token, remoteGeneration: nil,
                                  marker: .live)
        return try await verifier.devices()
    }

    /// The same client, with each authenticated request started under the lock that Forget takes.
    func gated(by connection: FlatdConnection,
               marker: RemoteMarker = .live) -> FlatdClient {
        guard let pairingID, let route else { return self }
        var client = self
        client.gate = FlatdGate(connection: connection, pairing: pairingID, route: route, pin: pin,
                               baseURL: baseURL, savedToken: token, remoteGeneration: remoteGeneration,
                               marker: marker)
        return client
    }

    // MARK: reads

    /// `GET /api/health`, without the key: whether flatd answers at this address (`{"ok": true, "version": …}`).
    func health(within cap: Deadline? = nil) async throws -> Bool {
        let data: Data
        do {
            data = try await send(request("api/health", timeout: readTimeout, authorized: false), within: cap)
        } catch let error as FlatdError where error != .unreachable && error != .noAnswer {
            return false                         // something answered, but not flatd's health
        }
        struct Health: Decodable { let ok: Bool?; let version: String? }
        guard let health = try? JSONDecoder().decode(Health.self, from: data) else { return false }
        return health.ok == true && health.version != nil
    }

    /// Whether flatd is at this address, asked before any work is sent there: the transport has then checked the
    /// server's key against the pin (anything else at the address ends as `.unreachable`, having received nothing), and
    /// flatd answered. This settles *where* flatd is, so a command is sent once, to the right address; *who* answers is
    /// settled by the pin on every connection, also without this call. Throws `.unreachable` otherwise.
    func verify(within cap: Deadline? = nil) async throws {
        guard try await health(within: cap) else { throw FlatdError.unreachable }
    }

    enum RemoteEnrollment {
        case unchanged
        case replace(RemoteListener?)
    }

    func remoteEnrollment() async throws -> RemoteEnrollment {
        guard route == .home else { return .unchanged }
        struct Answer: Decodable {
            let url: String?
            let pin: String?

            init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: Keys.self)
                url = try values.decode(String?.self, forKey: .url)
                pin = try values.decode(String?.self, forKey: .pin)
            }

            enum Keys: String, CodingKey { case url, pin = "spki_sha256" }
        }
        let data: Data
        do { data = try await send(request("api/remote", timeout: readTimeout)) }
        catch FlatdError.unknown { return .unchanged }
        let answer = try decode(Answer.self, data)
        if answer.url == nil && answer.pin == nil { return .replace(nil) }
        guard let remote = RemoteListener.parse(url: answer.url, pin: answer.pin, homePin: pin) else {
            return .unchanged
        }
        return .replace(remote)
    }

    func devices() async throws -> [Device] {
        struct Answer: Decodable { let devices: [Device] }
        return try decode(Answer.self, try await send(request("api/devices", timeout: readTimeout))).devices
    }

    /// One device as flatd has it now (`GET /api/devices/{id}`).
    func device(_ id: String) async throws -> Device {
        try decode(Device.self, try await send(request("api/devices/" + Self.pathID(id), timeout: readTimeout)))
    }

    func modes() async throws -> [FlatMode] {
        try await readModes(FlatMode.self)
    }

    /// The Cooking control and Toggle cooking need an explicit state to act on.
    func cookingActive() async throws -> Bool {
        struct ModeState: Decodable {
            let id: String
            let active: JSONValue?
        }
        let modes = try await readModes(ModeState.self)
        guard case let .bool(active)? = modes.first(where: { $0.id == FlatMode.cookingID })?.active else {
            throw FlatdError.invalidAnswer
        }
        return active
    }

    private struct ModeList<Mode: Decodable>: Decodable { let modes: [Mode] }

    private func readModes<Mode: Decodable>(_ type: Mode.Type) async throws -> [Mode] {
        try decode(ModeList<Mode>.self, try await send(request("api/modes", timeout: readTimeout))).modes
    }

    func scenes() async throws -> [FlatScene] {
        struct Answer: Decodable { let scenes: [FlatScene] }
        return try decode(Answer.self, try await send(request("api/scenes", timeout: readTimeout))).scenes
    }

    // MARK: commands

    /// Sends a command and returns the device as flatd confirmed it.
    func send(_ command: DeviceCommand, to id: String) async throws -> Device {
        try await send(body: JSONEncoder().encode(command.body), to: id)
    }

    /// flatd steps the lamp and waits for its confirmation before replying.
    func setLevel(id: String, level: String) async throws -> Device {
        try await sendDevice(body: JSONEncoder().encode(["level": level]), to: id, timeout: 40)
    }

    /// Turns a mode on or off. flatd changes the mode even when a device fails; those come back in `failed`.
    func setMode(_ id: String, active: Bool) async throws -> (mode: FlatMode, failed: [String]) {
        try await setMode(id, body: try JSONEncoder().encode(["active": active]))
    }

    /// The same with a body as the 3D page sent it (BRIDGE.md: forwarded unchanged).
    func setMode(_ id: String, body: Data) async throws -> (mode: FlatMode, failed: [String]) {
        let data = try await send(request("api/modes/" + Self.pathID(id), method: "POST", body: body,
                                          timeout: commandTimeout))
        return (try decode(FlatMode.self, data), (try? JSONDecoder().decode(CommandFailures.self, from: data))?.ids ?? [])
    }

    /// Runs a scene; returns the devices that did not follow.
    @discardableResult
    func runScene(_ id: String) async throws -> [String] {
        let data = try await send(request("api/scenes/" + Self.pathID(id), method: "POST", body: Data("{}".utf8),
                                          timeout: commandTimeout))
        return (try? JSONDecoder().decode(CommandFailures.self, from: data))?.ids ?? []
    }

    /// Renames a device (contract v1.3, `PATCH /api/devices/{id}`): its own name, or nil for flatd's config name again.
    /// Returns the device as flatd now names it; `.renameNotSupported` from a flatd before v1.3 (405).
    func rename(_ id: String, to label: String?) async throws -> Device {
        let body = try JSONEncoder().encode(["label": label.map(JSONValue.string) ?? .null])
        do {
            let data = try await send(request("api/devices/" + Self.pathID(id), method: "PATCH", body: body,
                                              timeout: readTimeout))
            return try decode(Device.self, data)
        } catch FlatdError.failed(status: 405, _) {
            throw FlatdError.renameNotSupported
        }
    }

    /// A device command with a body as the 3D page sent it (BRIDGE.md: `request.body` is exactly flatd's body).
    func send(body: Data, to id: String) async throws -> Device {
        try await sendDevice(body: body, to: id, timeout: commandTimeout)
    }

    private func sendDevice(body: Data, to id: String, timeout: TimeInterval) async throws -> Device {
        let data = try await send(request("api/devices/" + Self.pathID(id), method: "POST", body: body,
                                          timeout: timeout))
        return try decode(Device.self, data)
    }

    // MARK: the event stream and the 3D page

    /// The event stream's request: `wss://<host>/api/events` with the key in the header (the contract takes the
    /// header or `?token=`; the header keeps the key out of every URL a log might keep). Always `wss`: the stream is
    /// opened in a session that accepts only flatd's key (`WebSocketEvents`).
    var eventsRequest: URLRequest {
        var components = URLComponents(url: baseURL.appending(path: "api/events"), resolvingAgainstBaseURL: false)!
        components.scheme = "wss"
        #if DEBUG && ARESTIA_GATE
        var request = URLRequest(url: components.url!, timeoutInterval: FlatdRequestTimeout.gate)
        #else
        var request = URLRequest(url: components.url!, timeoutInterval: 8)
        #endif
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        return request
    }

    enum ViewerPage: Equatable, Sendable {
        case unchanged
        case page(Data, etag: String?)
    }

    /// The phone viewer page (`GET /viewer`, private: flatd serves it only with the key; `.unknown` when flatd has none
    /// set up). The app fetches it here, through the pinned transport, and hands it to the web view, which itself
    /// never talks to the network: one place checks flatd's identity, and the key never enters the web view. The page
    /// is never bundled. The app keeps one copy per pairing and checks its ETag here (see docs/ARESTIA-APP.md).
    func viewerPage(ifNoneMatch: String?) async throws -> ViewerPage {
        var request = request("viewer", timeout: 30)
        if let ifNoneMatch { request.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await response(to: request)
        switch response.statusCode {
        case 304: return .unchanged
        case 200: return .page(data, etag: response.value(forHTTPHeaderField: "ETag"))
        default: throw Self.rejection(response.statusCode, data: data)
        }
    }

    func viewerPage() async throws -> Data {
        guard case let .page(data, _) = try await viewerPage(ifNoneMatch: nil) else {
            throw FlatdError.failed(status: 304, message: nil)
        }
        return data
    }

    // MARK: plumbing

    /// A device id in a path: each part encoded, the colon kept (`fan:kitchen` stays readable).
    static func pathID(_ id: String) -> String {
        id.split(separator: ":", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/", "?", "#"])) ?? "" }
            .joined(separator: ":")
    }

    func request(_ path: String, method: String = "GET", body: Data? = nil, timeout: TimeInterval,
                 authorized: Bool = true) -> URLRequest {
        #if DEBUG && ARESTIA_GATE
        let timeout = FlatdRequestTimeout.gate
        #endif
        // The path is appended as written, so an encoded id is not encoded twice.
        let base = baseURL.absoluteString.hasSuffix("/") ? baseURL.absoluteString : baseURL.absoluteString + "/"
        var request = URLRequest(url: URL(string: base + path)!, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: timeout)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if authorized { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        return request
    }

    private func send(_ request: URLRequest, within limit: Deadline? = nil) async throws -> Data {
        let (data, response) = try await response(to: request, within: limit)
        guard (200..<300).contains(response.statusCode) else { throw Self.rejection(response.statusCode, data: data) }
        return data
    }

    private func response(to request: URLRequest, within limit: Deadline? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = request
        let usual = Duration.seconds(request.timeoutInterval)
        let budget = limit ?? deadline
        let cap = budget?.capped(by: usual) ?? Deadline(after: usual)
        if let budget {
            request.timeoutInterval = max(0.001, min(request.timeoutInterval, budget.remainingSeconds))
        }
        let authorized = request.value(forHTTPHeaderField: "Authorization") != nil
        let admission: FlatdAdmission
        if authorized, pairingID != nil {
            guard let gate else { throw FlatdError.unreachable }
            admission = .gated(gate)
        } else {
            admission = .open
        }
        let rule = WriteRule(cap: cap, deadline: deadline, isWrite: request.httpMethod != "GET", action: action)
        let boundedRequest = request.withLanguage()
        let preparing: any PreparingTransport
        if let pinned = transport as? FlatdTransport {
            guard pinned.pin == pin else { throw FlatdError.unreachable }
            preparing = pinned.capturingFixturesAndTiming(for: request)
        } else {
            preparing = transport
        }
        let outcome = await FlatdLaunch.run(admission: admission, rule: rule, prepare: { reply in
            .init(request: try preparing.prepare(boundedRequest, reply: reply))
        }, didResume: {
            #if DEBUG
            Self.logDispatch(boundedRequest, route: route, deadline: deadline)
            #endif
        })
        return try Self.classify(outcome, isWrite: rule.isWrite, inAction: action != nil)
    }

    static func classify(_ outcome: Attempt<HTTPReply>.Outcome, isWrite: Bool, inAction: Bool) throws -> HTTPReply {
        switch outcome.result {
        case let .success(reply): return reply
        case let .failure(error):
            if error is CancellationError { throw error }
            if !outcome.committed {
                if let admission = error as? FlatdError { throw admission }
                if error is FlatdGate.RemoteDenied { throw error }
                throw FlatdError.unreachable
            }
            if error is Deadline.Expired || (error as? URLError)?.code == .timedOut || (isWrite && inAction) {
                throw FlatdError.noAnswer
            }
            throw FlatdError.unreachable
        }
    }

    private static func rejection(_ status: Int, data: Data) -> FlatdError {
        switch status {
        case 401: return .refused
        case 404: return .unknown
        case 409: return .notPossible
        case 504: return .deviceDidNotAnswer
        default:
            let sentence = (try? JSONDecoder().decode(ServerMessage.self, from: data))?.sentence
            return .failed(status: status, message: sentence)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            Self.log.error("flatd's answer did not decode (\(String(describing: T.self), privacy: .public))")
            throw FlatdError.invalidAnswer
        }
    }

    private static let log = Logger(subsystem: "de.ares-empire.arestia", category: "flatd")
}

/// All clients built for one action share this record, including concurrent writes in a fan batch.
nonisolated final class FlatdActionDispatch: Sendable {
    private let written = OSAllocatedUnfairLock(initialState: false)
    var writeStarted: Bool { written.withLock { $0 } }
    func startingWrite() { written.withLock { $0 = true } }
}

nonisolated extension FlatdClient {
    #if DEBUG
    private static let logger = Logger(subsystem: "de.ares-empire.arestia", category: "route")

    static func logDispatch(_ request: URLRequest, route: HomeRoute?, deadline: Deadline?) {
        let routeName = route.map { String(describing: $0) } ?? "pairing-code"
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path() ?? ""
        let time = deadline.map { String(format: "%.3f s", max(0, $0.remainingSeconds)) } ?? "no action deadline"
        logger.notice("\(routeName, privacy: .public) \(method, privacy: .public) \(path, privacy: .public) \(time, privacy: .public)")
    }
    #endif
}
