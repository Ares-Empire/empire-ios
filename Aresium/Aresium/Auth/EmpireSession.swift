import Foundation
import Observation

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

@MainActor @Observable
final class EmpireSession {
    private(set) var token: String?
    private(set) var isRestoring = true
    private(set) var isBusy = false
    private(set) var error: String?
    private(set) var needsRestoreRetry = false
    private(set) var loginUnavailable = false
    private let storage: any TokenStorage
    private let client: EmpireAuthClient
    private let installDefaults: UserDefaults?
    let widgetPublisher: WidgetSnapshotPublisher
    private(set) var generation = 0
    private(set) var lastRenewedAt: Date?
    private var logoutHandlers: [() -> Void] = []

    func onLogout(_ action: @escaping () -> Void) { logoutHandlers.append(action) }

    func handleAuthFailure(_ failure: Error, generation: Int) {
        guard generation == self.generation else { return }
        switch failure {
        case HTTPError.unauthorized: logOut()
        case HTTPError.server(403, let message): logOut(reason: message ?? "This account has no access to Aresium.")
        default: break
        }
    }

    init(storage: any TokenStorage = TokenKeychain(), client: EmpireAuthClient = EmpireAuthClient(), restoreOnLaunch: Bool = true,
         widgetPublisher: WidgetSnapshotPublisher = .temporary(), installDefaults: UserDefaults? = nil) {
        self.installDefaults = installDefaults
        self.storage = storage
        self.client = client
        self.widgetPublisher = widgetPublisher
        isRestoring = restoreOnLaunch
        if let installDefaults {
            do { try FirstLaunchTokenReset.run(storage: storage, defaults: installDefaults) }
            catch { self.error = error.localizedDescription }
        }
    }

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
            if startsSession { self.generation += 1 }
        } catch HTTPError.unauthorized {
            guard generation == self.generation else { return }
            logOut()
        } catch HTTPError.server(let status, let message) where status == 400 || status == 401 || status == 403 {
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
        } catch {
            guard generation == self.generation else { return }
            if case HTTPError.server(503, _) = error { loginUnavailable = true }
            handleAuthFailure(error, generation: generation)
            self.error = error.localizedDescription
        }
    }

    private func accept(_ response: AuthResponse) throws {
        guard !response.token.isEmpty, response.record.approved, response.record.services.contains("aresium") else {
            throw HTTPError.server(403, "This account has no access to Aresium.")
        }
        try storage.save(response.token)
        token = response.token
        lastRenewedAt = .now
    }

    func logOut(reason: String? = nil) {
        generation += 1
        token = nil
        lastRenewedAt = nil
        isRestoring = false
        needsRestoreRetry = false
        error = reason
        loginUnavailable = false
        logoutHandlers.forEach { $0() }
        do { try storage.delete() } catch { self.error = self.error ?? error.localizedDescription }
        do { try widgetPublisher.clear() } catch { self.error = self.error ?? error.localizedDescription }
    }
}
