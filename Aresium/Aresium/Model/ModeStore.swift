import Foundation
import Observation
import os

extension APIClient {
    /// `GET /api/mode` (aresium/docs/API-DATA.md → Mode): which mode this account uses. The only route a phone-mode
    /// account may call; it stores and logs nothing about the account.
    func mode(token: String) async throws -> AresiumMode {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/mode"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let (data, response) = try await transport.send(request)
        try checkResponse(response, data: data, onUnauthorized: {})
        return try decodeAnswer(ModeAnswer.self, from: data, answer: "GET /api/mode").mode
    }
}

private nonisolated struct ModeAnswer: Decodable { let mode: AresiumMode }

/// Which mode the app is in, and the backend that goes with it (Patrik, 2026-10-27: Aresium needs no account).
///
/// - **Phone mode** is Aresium: the phone's one store (`PhoneStorage`), opened at launch without asking anyone. No login
///   is needed, and none changes it: logging in or out, here or in another Ares app, never closes or deletes it.
/// - **Server mode** is for the owner list only, through the shared Ares login: while a login whose account has the
///   Aresium service exists, the app asks `GET /api/mode` once per session and remembers the answer per account id in
///   the app's defaults. `server` → today's server dashboard; anything else (`phone`, 401, 403, an error, offline without
///   a remembered answer) → phone mode. A remembered `server` works offline, also at launch before the login is renewed.
///   When that login ends (a logout here or in another app, the central logout's marker, the server's 403), the app goes
///   back to phone mode: the server's dashboard and its widget numbers go (`DashboardStore`), the phone's store is
///   untouched.
///
/// The phone's data is deleted only by `deleteLocalData` (Settings → "Delete Aresium data on this iPhone", the lock's
/// "Forgot the code?").
@MainActor @Observable
final class ModeStore {
    enum State: Equatable {
        /// The phone's store is opening (at launch, and after its data was deleted).
        case opening
        /// The phone's store did not open.
        case failed(String)
        /// Phone mode, on the phone's own store.
        case phone
        /// Server mode, on the owner's login.
        case server
    }

    private(set) var state: State
    /// The phone's own store, once opened. It stays open in server mode, so going back is instant.
    private(set) var local: PhoneBackend?

    let session: EmpireSession
    let dashboard: DashboardStore
    @ObservationIgnored private let client: APIClient
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let markerDefaults: UserDefaults?
    @ObservationIgnored private(set) var storage: PhoneStorage
    @ObservationIgnored private let makeEngine: () throws -> AresiumEngine
    @ObservationIgnored private var engine: AresiumEngine?
    /// The opening of the phone's store under way, so every caller waits for the same one.
    @ObservationIgnored private var opening: Task<PhoneBackend, Error>?
    /// Counts deletions of the phone's store, so an opening that started before one is not used.
    @ObservationIgnored private var storeGeneration = 0
    /// The account server mode shows; before the login is renewed (offline at launch) it comes from the shared marker.
    @ObservationIgnored private var serverAccount: String?
    /// The session generation whose mode was asked (once per session).
    @ObservationIgnored private var askedGeneration: Int?
    /// Counts switches, so a slow opening of the phone's store does not undo a later switch to the server.
    @ObservationIgnored private var switchID = 0
    @ObservationIgnored private var fixed = false
    private static let log = Logger(subsystem: "de.ares-empire.aresium", category: "mode")

    /// - Parameters:
    ///   - defaults: the app's own defaults, where the mode is remembered per account.
    ///   - markerDefaults: the shared App Group's defaults with the login marker (nil in samples and tests).
    init(session: EmpireSession, dashboard: DashboardStore, client: APIClient = APIClient(),
         defaults: UserDefaults = .standard, markerDefaults: UserDefaults?, storage: PhoneStorage = .standard,
         makeEngine: @escaping () throws -> AresiumEngine = { try AresiumEngine.bundled() }) {
        self.session = session
        self.dashboard = dashboard
        self.client = client
        self.defaults = defaults
        self.markerDefaults = markerDefaults
        self.storage = storage
        self.makeEngine = makeEngine
        // The saved login's account was in server mode: start there, so the phone's screens never show in between.
        if let account = LoginMarker.account(in: markerDefaults), defaults.string(forKey: Self.key(for: account)) == AresiumMode.server.rawValue {
            state = .server
            serverAccount = account
            dashboard.use(ServerBackend(client: client))
        } else {
            state = .opening
        }
        // The login ended or the server refused it: back to the phone's store.
        session.onAppDataReset { [weak self] in self?.loginEnded() }
    }

    /// Phone mode's store, nil in server mode (Settings' and the first screen's phone screens).
    var phone: PhoneBackend? { state == .phone ? local : nil }

    // MARK: remembered modes

    static func key(for account: String) -> String { "aresium.mode." + account }

    func remembered(for account: String) -> AresiumMode? {
        defaults.string(forKey: Self.key(for: account)).flatMap(AresiumMode.init(rawValue:))
    }

    private func remember(_ mode: AresiumMode, for account: String) {
        defaults.set(mode.rawValue, forKey: Self.key(for: account))
    }

    // MARK: following the session

    /// At launch: opens the phone's store at once (unless the saved login starts in server mode). Nothing waits for a
    /// login or the network.
    func start() async {
        guard !fixed, state == .opening else { return }
        await showPhone()
    }

    /// Brings the mode in line with the session: call at launch (after the saved login was restored), whenever the
    /// session or the account's services change, and on coming to the foreground. Asks `GET /api/mode` once per
    /// session for a login whose account has Aresium.
    func update() async {
        guard !fixed, !session.isRestoring else { return }
        if let account = wantedServerAccount() { await showServer(account) } else { await showPhone() }
        guard session.token != nil, let account = session.accountID, hasAresium,
              askedGeneration != session.generation else { return }
        askedGeneration = session.generation
        await ask(account: account, generation: session.generation)
    }

    /// "Try again" when the phone's store did not open.
    func retry() async {
        guard case .failed = state else { return }
        state = .opening
        await showPhone()
    }

    /// On coming to the foreground, before anything async: server mode on a saved login that could not be renewed yet
    /// (offline at launch) ends when another app logged out or another account logged in meanwhile.
    func followMarker() {
        guard !fixed, state == .server, session.token == nil, let serverAccount,
              LoginMarker.account(in: markerDefaults) != serverAccount else { return }
        Self.log.notice("server mode ends: the saved login changed in another app")
        dashboard.clear()
        Task { await showPhone() }
    }

    /// The login's account may use Aresium's server at all (its service; it is never asked otherwise).
    private var hasAresium: Bool { !session.isDenied && session.services.contains(session.app.service) }

    /// The account server mode should show now, or nil for phone mode.
    private func wantedServerAccount() -> String? {
        if session.token != nil, let account = session.accountID {
            return hasAresium && remembered(for: account) == .server ? account : nil
        }
        // Offline at launch with a saved login of a server-mode account: its server mode, until the login is renewed.
        if session.needsRestoreRetry, let account = LoginMarker.account(in: markerDefaults),
           remembered(for: account) == .server {
            return account
        }
        return nil
    }

    private func ask(account: String, generation: Int) async {
        guard let token = session.token else { return }
        let answer: AresiumMode
        do {
            answer = try await client.mode(token: token)
        } catch HTTPError.unauthorized {
            // The login itself is refused: it ends everywhere (the session's rule), and phone mode follows.
            session.handleAuthFailure(HTTPError.unauthorized, generation: generation, token: token)
            return
        } catch {
            if Self.refusesAccount(error) {
                answer = .phone                     // the server keeps no data for this account
            } else {
                // Offline or the server is down: the remembered mode stays (none: phone mode); the next foreground asks
                // again.
                if generation == session.generation { askedGeneration = nil }
                return
            }
        }
        guard generation == session.generation, session.accountID == account else { return }
        remember(answer, for: account)
        await update()
    }

    /// A 403 of any kind: this account's data is not on the server.
    private static func refusesAccount(_ error: Error) -> Bool {
        switch error {
        case HTTPError.server(403, _), HTTPError.forbidden: true
        default: false
        }
    }

    /// The session ended its login here (a logout anywhere, the marker, a refused login) or the server refused this
    /// account: server mode ends; phone mode goes on as it is.
    private func loginEnded() {
        askedGeneration = nil
        guard !fixed, state == .server else { return }
        if session.isDenied, let serverAccount { remember(.phone, for: serverAccount) }
        Self.log.notice("server mode ends with its login")
        Task { await showPhone() }
    }

    // MARK: switching

    private func showServer(_ account: String) async {
        switchID += 1
        serverAccount = account
        state = .server
        if !(dashboard.backend is ServerBackend) { dashboard.use(ServerBackend(client: client)) }
        if dashboard.dashboard == nil { await dashboard.reload() }
    }

    private func showPhone() async {
        serverAccount = nil
        if state == .phone, let local, dashboard.backend === local { return }
        switchID += 1
        let id = switchID
        if dashboard.backend is ServerBackend {
            dashboard.clear()                       // the server's dashboard and its widget numbers
            dashboard.use(nil)
        }
        if local == nil { state = .opening }
        do {
            let backend = try await openLocal()
            guard id == switchID else { return }
            state = .phone
            dashboard.use(backend)
            await dashboard.reload()
        } catch {
            guard id == switchID else { return }
            Self.log.error("the phone's store did not open: \(String(describing: error), privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    /// The phone's store, opened once (off the main actor, so the store's work runs on its own).
    private func openLocal() async throws -> PhoneBackend {
        if let local { return local }
        if let opening { return try await opening.value }
        let storage = storage
        let generation = storeGeneration
        let task = Task { () throws -> PhoneBackend in
            let engine = try self.engine ?? self.makeEngine()
            self.engine = engine
            let ledger = try await Task.detached { try storage.open() }.value
            let backend = PhoneBackend(ledger: ledger, engine: engine)
            try await backend.load()
            return backend
        }
        opening = task
        let backend: PhoneBackend
        do { backend = try await task.value } catch {
            if generation == storeGeneration { opening = nil }
            throw error
        }
        // The store was deleted while it opened: this one is gone.
        guard generation == storeGeneration else { throw CancellationError() }
        opening = nil
        local = backend
        return backend
    }

    // MARK: deleting the phone's data

    /// Deletes the phone's store, and the widget's numbers when they are the phone's; an empty store opens in its place.
    /// Settings → "Delete Aresium data on this iPhone" and the lock's "Forgot the code?" run it; nothing else does.
    func deleteLocalData() async throws {
        let shown = state != .server
        switchID += 1
        storeGeneration += 1
        opening = nil
        local = nil
        if dashboard.backend is PhoneBackend { dashboard.use(nil) }
        if shown { state = .opening }
        try storage.delete()
        Self.log.notice("the phone's store was deleted")
        if shown {
            do { try dashboard.widgetPublisher.clear() }
            catch { Self.log.error("the widget snapshot was not deleted: \(String(describing: error), privacy: .public)") }
            await showPhone()
        }
    }

    // MARK: samples

    #if DEBUG
    /// Screenshots and the samples: shows a state as it is.
    func debugShow(_ state: State) { self.state = state }

    /// DEBUG samples: held as they are from the start, so following the session never opens the phone's real store
    /// (`-sampleData`: the server's bundled sample; `-samplePhone`: its made-up store comes with `showFixed`).
    func holdForSample(server: Bool) {
        fixed = true
        state = server ? .server : .opening
    }
    #endif

    /// DEBUG `-samplePhone`: phone mode without a login or network, on a made-up store in a folder of its own (deleting
    /// its data deletes only that).
    func showFixed(_ backend: PhoneBackend, storage: PhoneStorage) async {
        fixed = true
        self.storage = storage
        local = backend
        dashboard.use(backend)
        state = .phone
        await dashboard.reload()
    }
}
