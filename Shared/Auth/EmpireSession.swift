import Foundation
import Observation
import os

/// Which Empire app this is: the service its account must have, and its name for messages.
struct EmpireAppIdentity: Equatable, Sendable {
    let service: String
    let name: String
    /// The app works without an Ares account (Aresium, Patrik 2026-10-27): it never shows a login screen, any login
    /// (or none) opens it, and its service matters only to the app itself (Aresium's server mode for the owner). Every
    /// other app needs a login with its service.
    var accountOptional = false
    /// Contact & support always goes as a contact message without the login (the account server's open `contact`
    /// collection, the website's form's: an email to answer to, an optional name), also while an Ares login exists
    /// (Aresium, Patrik 2026-10-27: the privacy policy handles its messages like the website's contact form, without
    /// accounts). Every other app sends the account-linked `feedback` record with its login.
    var supportWithoutLogin = false
    static let aresium = EmpireAppIdentity(service: "aresium", name: "Aresium", accountOptional: true,
                                           supportWithoutLogin: true)
    static let empire = EmpireAppIdentity(service: "empire", name: "Ares Empire")
    static let arestemis = EmpireAppIdentity(service: "arestemis", name: "Arestemis")
    static let aresus = EmpireAppIdentity(service: "aresus", name: "Aresus")
    static let arestoteles = EmpireAppIdentity(service: "arestoteles", name: "Arestoteles")

    /// Every Ares app, in the order the account server lists its services.
    static let all: [EmpireAppIdentity] = [.empire, .aresium, .arestemis, .aresus, .arestoteles]

    /// The app's name for a service id ("arestemis" → "Arestemis"); the id itself for one this build does not know.
    static func name(of service: String) -> String {
        all.first { $0.service == service }?.name ?? service
    }
}

/// The account as the account server sends it to the account itself (a login answer, `GET`/`PATCH` of its record).
struct EmpireRecord: Decodable, Equatable {
    let id: String
    let approved: Bool
    let services: [String]
    /// The apps the account asked for and does not have yet (ares-empire docs/ACCOUNTS.md → Accounts in every app).
    var requested: [String] = []
    var email: String? = nil        // the account server sends it to the account itself

    init(id: String, approved: Bool, services: [String], requested: [String] = [], email: String? = nil) {
        self.id = id
        self.approved = approved
        self.services = services
        self.requested = requested
        self.email = email
    }

    private enum CodingKeys: String, CodingKey { case id, approved, services, requested, email }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        approved = try container.decode(Bool.self, forKey: .approved)
        services = try container.decode([String].self, forKey: .services)
        // Missing before the field existed on the server, and PocketBase sends "" for an empty multi-select.
        requested = (try? container.decodeIfPresent([String].self, forKey: .requested)) ?? []
        email = try container.decodeIfPresent(String.self, forKey: .email)
    }
}

struct AuthResponse: Decodable {
    let token: String
    let record: EmpireRecord
}

struct EmpireAuthClient {
    var transport: any HTTPTransport = URLSessionTransport()
    private let baseURL = URL(string: "https://auth.ares-empire.de/api/collections/users")!

    func login(email: String, password: String) async throws -> AuthResponse {
        do {
            return try await post("auth-with-password", body: ["identity": email, "password": password])
        } catch HTTPError.server(400, _) {
            // The account server's own words ("Failed to authenticate.") are English only. It cannot tell a wrong
            // password from an account that is not confirmed or approved yet, so the line names both.
            throw HTTPError.server(400, Self.refusedLogin)
        }
    }

    static var refusedLogin: String {
        String(localized: LocalizedStringResource("Wrong email or password, or the account is not confirmed or approved yet.",
                                                  table: "Shared", locale: .appLanguage))
    }

    func refresh(token: String) async throws -> AuthResponse {
        try await post("auth-refresh", body: [:], token: token)
    }

    private func post(_ path: String, body: [String: String], token: String? = nil) async throws -> AuthResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 30
        let (data, response) = try await transport.send(request)
        try checkResponse(response, data: data, onUnauthorized: {})
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }
}

/// One Empire login for every Empire app on the device (docs/EMPIRE-APP.md in ares-empire → "One login for all").
/// The token lives in a Keychain item the apps share, so logging in or out in one app does it in all of them.
/// - The login itself is invalid (401, or the account server refuses the refresh: expired, unapproved): log out,
///   everywhere.
/// - The account is fine but may not use THIS app (its `services` lack this app's service, or the app's server
///   answers 403): `access = .denied` in this app only; this app forgets its own data (`onAppDataReset`), the shared
///   login stays for the other apps. An app that works without an account (`accountOptional`, Aresium) is denied only
///   by its server's 403; a login without its service opens it all the same.
/// - The account's own actions (Settings → Account, the login's sheets, "Ask for access") are in `AccountForms.swift`;
///   they change the session only through `updateAccess`, `takeOverLogin`, `accountDeleted` and the password-change
///   guard below.
@MainActor @Observable
final class EmpireSession {
    enum Access: Equatable { case unknown, granted, denied(String) }

    /// Passed only in memory to cleanup handlers, after the generation has moved on.
    struct EndedLogin {
        let token: String?
        let deletedSavedLogin: Bool
        let wasRefused: Bool
    }

    let app: EmpireAppIdentity
    private(set) var token: String?
    /// The account's email from the last login answer, for Settings → Account. Never logged; forgotten on logout.
    private(set) var email: String?
    /// The account's id and access from the last answer about it (a login, a refresh, leaving or asking for an app).
    private(set) var accountID: String?
    private(set) var services: [String] = []
    private(set) var requested: [String] = []
    /// A calm line for the login screen after a logout the person caused ("Your Ares account is deleted."); never an
    /// error. Cleared by the next login.
    private(set) var notice: String?
    /// Between a password change and the login with the new password: the old token is refused by now, so a 401 from
    /// a request still made with it must not log out (`ChangePasswordForm` ends it either way).
    private(set) var isChangingPassword = false
    private(set) var access: Access = .unknown
    private(set) var isRestoring = true
    private(set) var isBusy = false
    private(set) var error: String?
    private(set) var needsRestoreRetry = false
    private(set) var loginUnavailable = false
    private let storage: any TokenStorage
    /// The account server, through one transport (tests and `SampleAccount` hand in theirs): logins here,
    /// the account's own actions in `accountClient`.
    let authClient: EmpireAuthClient
    var accountClient: EmpireAccountClient { EmpireAccountClient(transport: authClient.transport) }
    private let sharedDefaults: UserDefaults?
    private(set) var generation = 0
    private(set) var lastRenewedAt: Date?
    /// When the no-access screen last asked the account server again (`followSharedLogin`).
    private var lastAccessRecheck: Date?
    private var signInHandlers: [() -> Void] = []
    private var logoutHandlers: [(EndedLogin) -> Void] = []
    private var appDataResetHandlers: [() -> Void] = []
    private static let log = Logger(subsystem: "de.ares-empire.shared", category: "login")

    /// This app may not be used with the current login.
    var isDenied: Bool { if case .denied = access { true } else { false } }
    /// Logged in AND allowed into this app.
    var isSignedIn: Bool { token != nil && !isDenied }
    /// No access because the account lacks this app's service (not because this app's server refused it): asking for
    /// access can help.
    var canAskForAccess: Bool { isDenied && accountID != nil && !services.contains(app.service) }
    /// The account asked for this app and waits for approval.
    var hasAskedForAccess: Bool { requested.contains(app.service) }

    /// Called when a session starts in this app: a new login, the saved login restored at launch, or a login picked
    /// up from another app (not when the same account's token is renewed). Access may still be denied: check `isSignedIn`.
    func onSignIn(_ action: @escaping () -> Void) { signInHandlers.append(action) }
    /// Called after this app ends its session, with the login needed to remove its push devices.
    func onLogout(_ action: @escaping (EndedLogin) -> Void) { logoutHandlers.append(action) }
    /// Called whenever this app must forget its own data: on logout and when access to this app is denied.
    func onAppDataReset(_ action: @escaping () -> Void) { appDataResetHandlers.append(action) }

    /// A request failed; `generation` and `token` are the session's and the login's it was made with. Only an answer
    /// about the login this app uses now counts: a late answer about an older one (the same account's renewed token,
    /// taken over from another app after a password change there, say) changes nothing. A 401 ends the login (the
    /// saved one only while it is still that token); a 403 "no access" closes this app; anything else is the
    /// caller's to show.
    func handleAuthFailure(_ failure: Error, generation: Int, token refused: String?) {
        // Both: a login made again can bring back the same token (PocketBase's tokens of one second are identical).
        guard generation == self.generation, let refused, refused == token else { return }
        switch failure {
        case HTTPError.unauthorized:
            // During a password change the old token is refused on purpose; the change logs in again or out itself.
            guard !isChangingPassword else {
                Self.log.notice("\(self.app.service, privacy: .public): a 401 during the password change is not a logout")
                return
            }
            // Another app saved a newer login of the same account meanwhile: this answer is about the old one.
            if let saved = try? storage.read(), saved != refused, isSameAccount(refused, saved) {
                Self.log.notice("\(self.app.service, privacy: .public): a 401 for an outdated token; takes over the saved one")
                token = saved
                lastRenewedAt = .now
                return
            }
            logOut(refusedToken: refused)
        case HTTPError.server(403, let message): deny(message ?? noAccessMessage)
        default: break
        }
    }

    init(app: EmpireAppIdentity, storage: any TokenStorage = TokenKeychain(), client: EmpireAuthClient = EmpireAuthClient(),
         restoreOnLaunch: Bool = true, sharedDefaults: UserDefaults? = nil) {
        self.app = app
        self.sharedDefaults = sharedDefaults
        self.storage = storage
        authClient = client
        isRestoring = restoreOnLaunch
        if let sharedDefaults {
            do { try FirstLaunchTokenReset.run(storage: storage, defaults: sharedDefaults) }
            catch { self.error = error.localizedDescription }
        }
    }

    private var noAccessMessage: String { String(localized: LocalizedStringResource("This account has no access to \(app.name).",
                                                                                    table: "Shared",
                                                                                    locale: .appLanguage)) }

    /// Renews the saved login with the account server (at launch, picking up another app's login, every 12 hours).
    /// - Parameter quietly: a check in the background (the no-access re-check, a refused login of the delete form): no
    ///   loading state, and a failure that may pass (offline) leaves everything as it was. A refused login still ends.
    func restore(quietly: Bool = false) async {
        guard !isBusy, !isChangingPassword else { return }
        isBusy = true
        if !quietly {
            isRestoring = true
            error = nil
            needsRestoreRetry = false
        }
        let generation = generation
        var saved: String?
        defer {
            if !quietly { isRestoring = false }
            isBusy = false
        }
        do {
            if let sharedDefaults { try FirstLaunchTokenReset.run(storage: storage, defaults: sharedDefaults) }
            saved = try storage.read()
            guard let saved else { return }
            let response = try await authClient.refresh(token: saved)
            guard generation == self.generation else { return }
            let startsSession = token == nil
            let wasDenied = isDenied
            try accept(response)
            // Access granted after a denial (approved meanwhile) starts this app's session as a login would.
            if startsSession || (wasDenied && !isDenied) {
                self.generation += 1
                signInHandlers.forEach { $0() }
            }
        } catch HTTPError.unauthorized {
            guard generation == self.generation else { return }
            logOut(refusedToken: saved)
        } catch HTTPError.server(let status, let message) where status == 400 || status == 401 || status == 403 {
            // The account server refused the refresh itself (expired, unapproved): the login is gone everywhere.
            guard generation == self.generation else { return }
            logOut(reason: message, refusedToken: saved)
        } catch {
            guard generation == self.generation, !quietly else { return }
            self.error = error.localizedDescription
            needsRestoreRetry = true
        }
    }

    func login(email: String, password: String) async {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        notice = nil
        loginUnavailable = false
        let generation = generation
        defer { isBusy = false }
        do {
            if let sharedDefaults { try FirstLaunchTokenReset.run(storage: storage, defaults: sharedDefaults) }
            let response = try await authClient.login(email: email, password: password)
            guard generation == self.generation else { return }
            try accept(response)
            self.generation += 1
            needsRestoreRetry = false
            signInHandlers.forEach { $0() }
        } catch {
            // A failed login concerns only the credentials just typed: an existing login (used by the other Empire
            // apps) stays as it is.
            guard generation == self.generation else { return }
            if case HTTPError.server(503, _) = error { loginUnavailable = true }
            self.error = error.localizedDescription
        }
    }

    /// A valid login is saved for all apps even when this app is not allowed; access is decided per app.
    private func accept(_ response: AuthResponse) throws {
        guard !response.token.isEmpty, response.record.approved else {
            throw HTTPError.server(403, String(localized: LocalizedStringResource("This account is not approved yet.",
                                                                                  table: "Shared",
                                                                                  locale: .appLanguage)))
        }
        try storage.save(response.token)
        LoginMarker.save(response.record.id, in: sharedDefaults)
        token = response.token
        email = response.record.email
        accountID = response.record.id
        services = response.record.services
        requested = response.record.requested
        lastRenewedAt = .now
        if app.accountOptional || response.record.services.contains(app.service) {
            if isDenied { error = nil }             // the no-access line goes with the denial
            access = .granted
        } else {
            deny(noAccessMessage)
        }
    }

    /// This app may not be used with this account: forget its data, keep the shared login. Asked again while denied
    /// (the no-access re-check), only the line is renewed: the data went at the first denial.
    private func deny(_ message: String) {
        let wasDenied = isDenied
        access = .denied(message)
        error = message
        if !wasDenied { appDataResetHandlers.forEach { $0() } }
    }

    /// The apps share the saved login, so it can change while this app waits in the background. Call when the app
    /// comes to the foreground: it picks up a login made in another app, follows a logout made there, and switches
    /// when another account logged in. A newer token for the same account (another app renewed it) is taken over
    /// without asking the server, so the apps don't renew it in turn on every switch.
    /// While this app is closed because the account lacks its service (it may have asked for it), the account server is
    /// asked again, at most once a minute, so an approval opens the app by itself. A 403 from the app's own server is
    /// not asked again: the account server cannot tell anything new about it.
    func followSharedLogin(now: Date = .now) async {
        guard !isBusy, !isRestoring, !isChangingPassword else { return }
        let saved: String?
        do { saved = try storage.read() } catch { return }
        switch (token, saved) {
        case (nil, .some):
            await restore()
        case (.some, nil):
            Self.log.notice("\(self.app.service, privacy: .public): follows a logout made in another app")
            endSession(reason: nil)
        case let (.some(current), .some(saved)) where current != saved:
            if isSameAccount(current, saved) {
                token = saved
                lastRenewedAt = .now
            } else {
                endSession(reason: nil)
                await restore()
            }
        default:
            // The account server answered about this login at its last renewal (the login, say) and at the last check.
            guard canAskForAccess,
                  [lastRenewedAt, lastAccessRecheck].allSatisfy({ asked in
                      asked.map { now.timeIntervalSince($0) >= Self.accessRecheckInterval } ?? true
                  }) else { return }
            lastAccessRecheck = now
            await restore(quietly: true)
        }
    }

    /// Before the foreground's async work: forget this app's old data without waiting for the Keychain or server.
    /// Nil defaults are used by samples and isolated tests, which do not follow the device's real login.
    func followMarker() {
        guard token != nil, let sharedDefaults,
              LoginMarker.account(in: sharedDefaults) != accountID else { return }
        endSession(reason: nil)
    }

    /// How long the no-access screen waits before asking the account server again (`followSharedLogin`).
    static let accessRecheckInterval: TimeInterval = 60

    /// Two tokens of the same account (a renewed one, or one from a new login of that account).
    private func isSameAccount(_ one: String, _ other: String) -> Bool {
        guard let account = EmpireToken.accountID(one) else { return false }
        return account == EmpireToken.accountID(other)
    }

    /// Ends the login in every Empire app. Each logout is written to the device's log with the line that asked for it,
    /// so an unexpected one can be traced: `log show --predicate 'subsystem == "de.ares-empire.shared"'`.
    /// - Parameters:
    ///   - reason: a problem to show on the login screen; `notice`: a calm line instead (an action the person took).
    ///   - refusedToken: when a server refused this login: the saved login is deleted only while it is still that
    ///     token, so a newer one another app saved meanwhile stays for the apps (this one picks it up when it next
    ///     comes to the foreground). Nil (the person logs out): it is deleted.
    func logOut(reason: String? = nil, notice: String? = nil, refusedToken: String? = nil,
                file: StaticString = #fileID, line: UInt = #line) {
        var deletedSavedLogin = false
        var deletionError: String?
        do {
            if let refusedToken, try storage.read() != refusedToken {
                Self.log.notice("\(self.app.service, privacy: .public): login ended here by \(file, privacy: .public):\(line); the saved login is another one (or none) and stays")
            } else {
                Self.log.notice("\(self.app.service, privacy: .public): login ended everywhere by \(file, privacy: .public):\(line)")
                try storage.delete()
                LoginMarker.clear(in: sharedDefaults)
                deletedSavedLogin = true
            }
        } catch {
            Self.log.error("\(self.app.service, privacy: .public): login ended here by \(file, privacy: .public):\(line); the saved login could not be read or deleted")
            deletionError = error.localizedDescription
        }
        endSession(reason: reason ?? deletionError, notice: notice, deletedSavedLogin: deletedSavedLogin,
                   refusedToken: refusedToken)
    }

    // MARK: the account's own actions (AccountForms.swift)

    /// The account's access changed on the server (it left this app, or asked for one): take over its services and
    /// requests. Without this app's service this app closes and forgets its data, as when access is denied; the shared
    /// login stays for the other apps.
    func updateAccess(services: [String], requested: [String]) {
        guard token != nil else { return }
        self.services = services
        self.requested = requested
        if !app.accountOptional, !services.contains(app.service), !isDenied { deny(noAccessMessage) }
    }

    /// After a password change: the login with the new password replaces the refused token here and, through the
    /// shared Keychain item, in every app. The same account only; no new session starts, so the app keeps its data.
    func takeOverLogin(_ response: AuthResponse) throws {
        guard token != nil, let accountID, response.record.id == accountID else { throw HTTPError.invalidResponse }
        try accept(response)
    }

    /// Starts and ends the password change's guard (see `isChangingPassword`). Any logout ends it as well.
    func beginPasswordChange() { isChangingPassword = true }
    func endPasswordChange() { isChangingPassword = false }

    /// The account is deleted on the server: the login ends in every app, with a calm line on the login screen.
    func accountDeleted(file: StaticString = #fileID, line: UInt = #line) {
        logOut(notice: String(localized: LocalizedStringResource("Your Ares account is deleted.", table: "Shared",
                                                                 locale: .appLanguage)), file: file, line: line)
    }

    /// Ends the login in this app only (the saved login is left as it is).
    private func endSession(reason: String?, notice: String? = nil, deletedSavedLogin: Bool = false,
                            refusedToken: String? = nil) {
        let ended = EndedLogin(token: token ?? refusedToken, deletedSavedLogin: deletedSavedLogin,
                               wasRefused: refusedToken != nil)
        generation += 1
        token = nil
        email = nil
        accountID = nil
        services = []
        requested = []
        self.notice = notice
        isChangingPassword = false
        access = .unknown
        lastRenewedAt = nil
        lastAccessRecheck = nil
        isRestoring = false
        needsRestoreRetry = false
        error = reason
        loginUnavailable = false
        logoutHandlers.forEach { $0(ended) }
        appDataResetHandlers.forEach { $0() }
    }
}

/// Reading a PocketBase login token (a JWT) without verifying it: only to tell a renewed token of the same account
/// from another account's. The servers verify every token they receive.
enum EmpireToken {
    static func accountID(_ token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = payload["id"] as? String, !id.isEmpty else { return nil }
        return id
    }
}
