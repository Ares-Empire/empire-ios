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
        guard (200..<300).contains(response.statusCode) else {
            throw HTTPError.server(response.statusCode, try? JSONDecoder().decode(ServerMessage.self, from: data).message)
        }
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
    private let storage: any TokenStorage
    private let client: EmpireAuthClient
    private var generation = 0

    init(storage: any TokenStorage = TokenKeychain(), client: EmpireAuthClient = EmpireAuthClient(), restoreOnLaunch: Bool = true) {
        self.storage = storage
        self.client = client
        isRestoring = restoreOnLaunch
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
            guard let saved = try storage.read() else { return }
            let response = try await client.refresh(token: saved)
            guard generation == self.generation else { return }
            try accept(response)
        } catch HTTPError.server(let status, let message) where status == 400 || status == 401 {
            guard generation == self.generation else { return }
            logOut()
            if error == nil { error = message }
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
        let generation = generation
        defer { isBusy = false }
        do {
            let response = try await client.login(email: email, password: password)
            guard generation == self.generation else { return }
            try accept(response)
            needsRestoreRetry = false
        } catch {
            guard generation == self.generation else { return }
            self.error = error.localizedDescription
        }
    }

    private func accept(_ response: AuthResponse) throws {
        guard !response.token.isEmpty, response.record.approved, response.record.services.contains("aresium") else {
            throw HTTPError.server(403, "This account has no access to Aresium.")
        }
        try storage.save(response.token)
        token = response.token
    }

    func logOut() {
        generation += 1
        token = nil
        isRestoring = false
        needsRestoreRetry = false
        error = nil
        do { try storage.delete() } catch { self.error = error.localizedDescription }
    }
}
