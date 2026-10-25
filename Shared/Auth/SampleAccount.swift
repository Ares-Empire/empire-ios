#if DEBUG
import Foundation

/// Screenshots of the login and the no-access screen without the real login or any server (DEBUG launch arguments,
/// the same in every app):
/// - `-sampleLogin`: the login screen (its sheets reach `SampleAccountServer`, never the account server);
/// - `-sampleNoAccess`: logged in with an account that lacks this app (the no-access screen; "Ask for access" works);
/// - `-sampleAccessAsked`: the same account after it asked for this app.
/// The login lives in memory only, never in the shared Keychain.
enum SampleAccount {
    enum Start: Equatable { case login, noAccess, asked }

    static func start(_ arguments: [String]) -> Start? {
        if arguments.contains("-sampleAccessAsked") { return .asked }
        if arguments.contains("-sampleNoAccess") { return .noAccess }
        if arguments.contains("-sampleLogin") { return .login }
        return nil
    }

    /// The session for a screenshot start, and whether the app should restore it at launch (it should for the
    /// no-access screens: the restore asks `SampleAccountServer` and denies this app as the real one would).
    static func session(app: EmpireAppIdentity, arguments: [String]) -> (session: EmpireSession, restores: Bool)? {
        guard let start = start(arguments) else { return nil }
        let server = SampleAccountServer(app: app, asked: start == .asked)
        let storage = MemoryTokens(token: start == .login ? nil : SampleAccountServer.token)
        let session = EmpireSession(app: app, storage: storage, client: EmpireAuthClient(transport: server),
                                    restoreOnLaunch: start != .login)
        return (session, start != .login)
    }

    private final class MemoryTokens: TokenStorage {
        private var token: String?
        init(token: String?) { self.token = token }
        func read() throws -> String? { token }
        func save(_ token: String) throws { self.token = token }
        func delete() throws { token = nil }
    }
}

/// Answers like the account server for one made-up account (`sample@example.com`) that has the other apps but not this
/// one. Each answer comes after a short pause, so the screens' progress shows.
final class SampleAccountServer: HTTPTransport, @unchecked Sendable {
    /// A made-up, unsigned token in PocketBase's shape (only its account id is ever read on the phone).
    static let token = "eyJhbGciOiJIUzI1NiJ9.eyJpZCI6InNhbXBsZWFjY291bnQwMSJ9.sample-signature"
    static let accountID = "sampleaccount01"

    private let app: EmpireAppIdentity
    private let lock = NSLock()
    private var requested: [String]

    init(app: EmpireAppIdentity, asked: Bool) {
        self.app = app
        requested = asked ? [app.service] : []
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(for: .milliseconds(900))
        let path = request.url?.path ?? ""
        let (status, body): (Int, Any?)
        switch (request.httpMethod ?? "GET", path) {
        case ("POST", let path) where path.hasSuffix("/auth-refresh") || path.hasSuffix("/auth-with-password"):
            (status, body) = (200, ["token": Self.token, "record": record()])
        case ("GET", let path) where path.hasSuffix("/records/\(Self.accountID)"):
            (status, body) = (200, record())
        case ("PATCH", let path) where path.hasSuffix("/records/\(Self.accountID)"):
            if let data = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let asked = json["requested"] as? [String] {
                lock.withLock { requested = asked }
            }
            (status, body) = (200, record())
        case ("POST", let path) where path.hasSuffix("/records"):
            (status, body) = (200, ["id": "samplenew000001"])
        case ("POST", "/api/empire/leave"):
            (status, body) = (200, ["services": services, "requested": lock.withLock { requested }])
        default:
            (status, body) = (204, nil)
        }
        let data = try body.map { try JSONSerialization.data(withJSONObject: $0) } ?? Data()
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    /// Every other app, never this one.
    private var services: [String] { EmpireAppIdentity.all.map(\.service).filter { $0 != app.service } }

    private func record() -> [String: Any] {
        ["id": Self.accountID, "email": "sample@example.com", "approved": true, "services": services,
         "requested": lock.withLock { requested }]
    }
}
#endif
