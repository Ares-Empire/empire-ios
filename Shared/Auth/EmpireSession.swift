import Foundation
import Observation

/// Which Empire app this is: the service its account must have, and its name for messages.
struct EmpireAppIdentity: Equatable, Sendable {
    let service: String
    let name: String
    static let aresium = EmpireAppIdentity(service: "aresium", name: "Aresium")
    static let empire = EmpireAppIdentity(service: "empire", name: "the Ares Empire")
}

struct EmpireRecord: Decodable {
    let id: String
    let approved: Bool
    let services: [String]
}

struct AuthResponse: Decodable {
    let token: String
    let record: EmpireRecord
}

struct EmpireAuthClient {
    var transport: any HTTPTransport = URLSessionTransport()
    private let baseURL = URL(string: "https://auth.ares-empire.de/api/collections/users")!

    func login(email: String, password: String) async throws -> AuthResponse {
        try await post("auth-with-password", body: ["identity": email, "password": password])
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
///   login stays for the other apps.
@MainActor @Observable
final class EmpireSession {
    enum Access: Equatable { case unknown, granted, denied(String) }

    let app: EmpireAppIdentity
    private(set) var token: String?
    private(set) var access: Access = .unknown
    private(set) var isRestoring = true
    private(set) var isBusy = false
    private(set) var error: String?
    private(set) var needsRestoreRetry = false
    private(set) var loginUnavailable = false
    private let storage: any TokenStorage
    private let client: EmpireAuthClient
    private let installDefaults: UserDefaults?
    private(set) var generation = 0
    private(set) var lastRenewedAt: Date?
    private var signInHandlers: [() -> Void] = []
    private var logoutHandlers: [() -> Void] = []
    private var appDataResetHandlers: [() -> Void] = []

    /// This app may not be used with the current login.
    var isDenied: Bool { if case .denied = access { true } else { false } }
    /// Logged in AND allowed into this app.
    var isSignedIn: Bool { token != nil && !isDenied }

    /// Called when a session starts in this app: a new login, the saved login restored at launch, or a login picked
    /// up from another app (not when the same account's token is renewed). Access may still be denied: check `isSignedIn`.
    func onSignIn(_ action: @escaping () -> Void) { signInHandlers.append(action) }
    /// Called on logout (the shared login ends).
    func onLogout(_ action: @escaping () -> Void) { logoutHandlers.append(action) }
    /// Called whenever this app must forget its own data: on logout and when access to this app is denied.
    func onAppDataReset(_ action: @escaping () -> Void) { appDataResetHandlers.append(action) }

    func handleAuthFailure(_ failure: Error, generation: Int) {
        guard generation == self.generation else { return }
        switch failure {
        case HTTPError.unauthorized: logOut()
        case HTTPError.server(403, let message): deny(message ?? noAccessMessage)
        default: break
        }
    }

    init(app: EmpireAppIdentity, storage: any TokenStorage = TokenKeychain(), client: EmpireAuthClient = EmpireAuthClient(),
         restoreOnLaunch: Bool = true, installDefaults: UserDefaults? = nil) {
        self.app = app
        self.installDefaults = installDefaults
        self.storage = storage
        self.client = client
        isRestoring = restoreOnLaunch
        if let installDefaults {
            do { try FirstLaunchTokenReset.run(storage: storage, defaults: installDefaults) }
            catch { self.error = error.localizedDescription }
        }
    }

    private var noAccessMessage: String { "This account has no access to \(app.name)." }

    func restore() async {
        guard !isBusy else { return }
        isBusy = true
        isRestoring = true
        error = nil
        needsRestoreRetry = false
        let generation = generation
        defer { isRestoring = false; isBusy = false }
        do {
            if let installDefaults { try FirstLaunchTokenReset.run(storage: storage, defaults: installDefaults) }
            guard let saved = try storage.read() else { return }
            let response = try await client.refresh(token: saved)
            guard generation == self.generation else { return }
            let startsSession = token == nil
            try accept(response)
            if startsSession {
                self.generation += 1
                signInHandlers.forEach { $0() }
            }
        } catch HTTPError.unauthorized {
            guard generation == self.generation else { return }
            logOut()
        } catch HTTPError.server(let status, let message) where status == 400 || status == 401 || status == 403 {
            // The account server refused the refresh itself (expired, unapproved): the login is gone everywhere.
            guard generation == self.generation else { return }
            logOut(reason: message)
        } catch {
            guard generation == self.generation else { return }
            self.error = error.localizedDescription
            needsRestoreRetry = true
        }
    }

    func login(email: String, password: String) async {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        loginUnavailable = false
        let generation = generation
        defer { isBusy = false }
        do {
            if let installDefaults { try FirstLaunchTokenReset.run(storage: storage, defaults: installDefaults) }
            let response = try await client.login(email: email, password: password)
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
            throw HTTPError.server(403, "This account is not approved yet.")
        }
        try storage.save(response.token)
        token = response.token
        lastRenewedAt = .now
        if response.record.services.contains(app.service) {
            access = .granted
        } else {
            deny(noAccessMessage)
        }
    }

    /// This app may not be used with this account: forget its data, keep the shared login.
    private func deny(_ message: String) {
        access = .denied(message)
        error = message
        appDataResetHandlers.forEach { $0() }
    }

    /// The apps share the saved login, so it can change while this app waits in the background. Call when the app
    /// comes to the foreground: it picks up a login made in another app, follows a logout made there, and switches
    /// when another account logged in. A newer token for the same account (another app renewed it) is taken over
    /// without asking the server, so the apps don't renew it in turn on every switch.
    func followSharedLogin() async {
        guard !isBusy, !isRestoring else { return }
        let saved: String?
        do { saved = try storage.read() } catch { return }
        switch (token, saved) {
        case (nil, .some):
            await restore()
        case (.some, nil):
            endSession(reason: nil)
        case let (.some(current), .some(saved)) where current != saved:
            if let account = EmpireToken.accountID(current), account == EmpireToken.accountID(saved) {
                token = saved
                lastRenewedAt = .now
            } else {
                endSession(reason: nil)
                await restore()
            }
        default:
            break
        }
    }

    /// Ends the login in every Empire app.
    func logOut(reason: String? = nil) {
        endSession(reason: reason)
        do { try storage.delete() } catch { self.error = self.error ?? error.localizedDescription }
    }

    /// Ends the login in this app only (the saved login is left as it is).
    private func endSession(reason: String?) {
        generation += 1
        token = nil
        access = .unknown
        lastRenewedAt = nil
        isRestoring = false
        needsRestoreRetry = false
        error = reason
        loginUnavailable = false
        logoutHandlers.forEach { $0() }
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
