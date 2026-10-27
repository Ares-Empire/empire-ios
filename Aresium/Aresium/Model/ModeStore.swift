import Foundation
import Observation
import os

extension APIClient {
    /// `GET /api/mode` (aresium/docs/API-DATA.md → Mode): which mode this account uses. The only route a phone-mode
    /// account may call; it stores and logs nothing about the account.
    func mode(token: String, onUnauthorized: () -> Void) async throws -> AresiumMode {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/mode"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let (data, response) = try await transport.send(request)
        try checkResponse(response, data: data, onUnauthorized: onUnauthorized)
        return try decodeAnswer(ModeAnswer.self, from: data, answer: "GET /api/mode").mode
    }
}

private nonisolated struct ModeAnswer: Decodable { let mode: AresiumMode }

/// Which mode the app is in, and the backend that goes with it.
///
/// After a login (and at every session start: a launch, a login picked up from another app) the app asks
/// `GET /api/mode` once and remembers the answer per account id in the app's defaults. A remembered mode is used at once,
/// so phone mode works without a connection; the answer then only updates it. Unknown and offline: a calm line with Try
/// again. Phone mode opens the account's own store (`PhoneStorage`); logging out closes it (nothing is shown, nothing
/// deleted), the same account logging in opens it again, another account gets its own. The data is deleted only by
/// `deleteLocalData` (Leave Aresium, Delete Ares account, Settings → Delete Aresium data on this iPhone).
@MainActor @Observable
final class ModeStore {
    enum State: Equatable {
        /// No session: the login (or the no-access panel) shows.
        case signedOut
        /// Asking `GET /api/mode` for an account whose mode is not known yet.
        case asking
        /// The mode is not known and the server could not be asked: "Aresium needs a connection the first time".
        case needsConnection
        /// Phone mode's store could not be opened.
        case failed(String)
        case server
        /// Phone mode, with the account's own store.
        case phone(String)
    }

    private(set) var state: State = .signedOut
    /// The open phone store's backend (phone mode only).
    private(set) var phone: PhoneBackend?
    /// Phone mode on the saved login while the account server could not be asked at launch (offline): the login's
    /// account comes from the shared marker, and the store closes when the marker names someone else.
    private(set) var isOffline = false

    let session: EmpireSession
    let dashboard: DashboardStore
    @ObservationIgnored private let client: APIClient
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let markerDefaults: UserDefaults?
    @ObservationIgnored let storage: PhoneStorage
    @ObservationIgnored private let makeEngine: () throws -> AresiumEngine
    @ObservationIgnored private var engine: AresiumEngine?
    /// The session generation whose mode was asked (once per session).
    @ObservationIgnored private var askedGeneration: Int?
    /// Counts opening attempts, so a store that opens after a logout is not used.
    @ObservationIgnored private var openID = 0
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
        // Logout or no access: the phone's store closes; its data stays.
        session.onAppDataReset { [weak self] in self?.close() }
    }

    /// The app shows Aresium's screens (not the login): a mode is known, being asked, or missing a connection.
    var showsApp: Bool { state != .signedOut }

    // MARK: remembered modes

    static func key(for account: String) -> String { "aresium.mode." + account }

    func remembered(for account: String) -> AresiumMode? {
        defaults.string(forKey: Self.key(for: account)).flatMap(AresiumMode.init(rawValue:))
    }

    private func remember(_ mode: AresiumMode, for account: String) {
        defaults.set(mode.rawValue, forKey: Self.key(for: account))
    }

    // MARK: following the session

    /// Brings the mode in line with the session: call at launch (after the saved login was restored), whenever the
    /// session changes, and on coming to the foreground.
    func update() async {
        guard !fixed else { return }
        if session.isSignedIn, let account = session.accountID {
            isOffline = false
            let generation = session.generation
            if let mode = remembered(for: account) { await apply(mode, account: account) }
            else if state != .asking { close(); state = .asking }
            guard askedGeneration != generation else { return }
            askedGeneration = generation
            await ask(account: account, generation: generation)
        } else if session.token == nil, session.needsRestoreRetry, let account = LoginMarker.account(in: markerDefaults),
                  remembered(for: account) == .phone {
            // Offline at launch with a saved login of a phone-mode account: its data is on this iPhone.
            isOffline = true
            await apply(.phone, account: account)
        } else if state != .signedOut {
            close()
        }
    }

    /// "Try again" after "Aresium needs a connection the first time" (or a store that did not open).
    func retry() async {
        askedGeneration = nil
        if case .failed = state { state = .asking }
        await update()
    }

    /// On coming to the foreground, before anything async: phone mode on the saved login (offline) closes when another
    /// app logged out or another account logged in meanwhile.
    func followMarker() {
        guard isOffline, case .phone(let account) = state, LoginMarker.account(in: markerDefaults) != account else { return }
        Self.log.notice("the offline phone store closes: the saved login changed")
        close()
    }

    private func ask(account: String, generation: Int) async {
        guard let token = session.token else { return }
        do {
            let mode = try await client.mode(token: token) {
                self.session.handleAuthFailure(HTTPError.unauthorized, generation: generation, token: token)
            }
            // Only for the session that asked, while it may still use Aresium (a stale remembered mode can have closed
            // the app meanwhile: a 403 from the server's data).
            guard generation == session.generation, session.isSignedIn, session.accountID == account else { return }
            remember(mode, for: account)
            await apply(mode, account: account)
        } catch {
            guard generation == session.generation else { return }
            session.handleAuthFailure(error, generation: generation, token: token)    // 401 logs out, 403 closes the app
            guard generation == session.generation, session.isSignedIn else { return }
            // Known: the remembered mode stays. Unknown: say a connection is needed, and ask again on Try again.
            if remembered(for: account) == nil {
                askedGeneration = nil
                state = .needsConnection
            }
        }
    }

    private func apply(_ mode: AresiumMode, account: String) async {
        switch mode {
        case .server:
            closePhone()
            if !(dashboard.backend is ServerBackend) { dashboard.use(ServerBackend(client: client)) }
            if state != .server {
                state = .server
                await dashboard.reload()
            }
        case .phone:
            if let phone, phone.account == account {
                state = .phone(account)
                return
            }
            closePhone()
            openID += 1
            let id = openID
            if state != .asking, state != .needsConnection { state = .asking }
            do {
                let backend = try await open(account: account)
                guard id == openID else { return }
                phone = backend
                dashboard.use(backend)
                state = .phone(account)
                await dashboard.reload()
            } catch {
                guard id == openID else { return }
                Self.log.error("the phone store did not open: \(String(describing: error), privacy: .public)")
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func open(account: String) async throws -> PhoneBackend {
        let engine = try self.engine ?? makeEngine()
        self.engine = engine
        let storage = storage
        // Off the main actor, so the store's work runs on its own.
        let ledger = try await Task.detached { try storage.open(account: account) }.value
        let backend = PhoneBackend(account: account, ledger: ledger, engine: engine)
        try await backend.load()
        return backend
    }

    /// Closes the phone store (if one is open) and goes back to no mode. Nothing is deleted.
    func close() {
        closePhone()
        openID += 1
        isOffline = false
        dashboard.use(nil)
        state = .signedOut
    }

    private func closePhone() {
        guard phone != nil else { return }
        phone = nil
        if dashboard.backend is PhoneBackend { dashboard.use(nil) }
    }

    // MARK: deleting the phone's data

    /// Deletes the phone store of the account in use, and the widget's numbers with it. Leave Aresium and Delete Ares
    /// account run it after the server said yes (`SettingsApp.localData`, `reopen: false`: the app closes right after);
    /// Settings → "Delete Aresium data on this iPhone" with `reopen: true`, and the same account starts again with an
    /// empty store.
    func deleteLocalData(reopen: Bool) async throws {
        let account: String?
        if case .phone(let open) = state { account = open } else { account = session.accountID }
        let wasOpen = phone != nil
        closePhone()
        openID += 1
        if let account {
            try storage.delete(account: account)
            Self.log.notice("the phone store was deleted")
        }
        do { try dashboard.widgetPublisher.clear() }
        catch { Self.log.error("the widget snapshot was not deleted: \(String(describing: error), privacy: .public)") }
        guard reopen, wasOpen, let account else { return }
        if fixed { await showFixed(try await open(account: account)) }
        else { await apply(.phone, account: account) }
    }

    // MARK: samples

    #if DEBUG
    /// Screenshots: shows a state as it is (`-sampleModeOffline`).
    func debugShow(_ state: State) { self.state = state }
    #endif

    /// DEBUG `-samplePhone`: phone mode without a login or network, on a store of its own.
    func showFixed(_ backend: PhoneBackend) async {
        fixed = true
        phone = backend
        dashboard.use(backend)
        state = .phone(backend.account ?? "")
        await dashboard.reload()
    }

}
