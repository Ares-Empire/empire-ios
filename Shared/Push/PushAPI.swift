import Foundation

/// Debug builds get their device tokens from Apple's sandbox, release builds (TestFlight) from production.
enum PushEnvironment: String, Sendable {
    case sandbox, production

    static var current: PushEnvironment {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }
}

/// The Empire push service's device API (ares-empire/docs/PUSH.md → Public API).
struct PushAPI {
    var transport: any HTTPTransport = URLSessionTransport()
    private let url = URL(string: "https://www.ares-empire.de/api/push/devices")!

    /// 204 on success; the newest account wins, so this also moves the device to a new account. The language picks the
    /// text of each notification (a phone that changes its language moves over at the app's next launch).
    func register(app: String, deviceToken: String, environment: PushEnvironment, language: AppLanguage = .current,
                  token: String) async throws {
        try await send("POST", ["app": app, "token": deviceToken, "environment": environment.rawValue,
                                "language": language.code], token: token)
    }

    /// 204 also when the server does not know the device.
    func unregister(app: String, deviceToken: String, token: String) async throws {
        try await send("DELETE", ["app": app, "token": deviceToken], token: token)
    }

    private func send(_ method: String, _ body: [String: String], token: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 30
        let (data, response) = try await transport.send(request)
        try checkResponse(response, data: data, onUnauthorized: {})
        guard response.statusCode == 204 else { throw HTTPError.invalidResponse }
    }
}
