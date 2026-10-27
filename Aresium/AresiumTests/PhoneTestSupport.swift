import Foundation
import Testing
@testable import Aresium

// Helpers for the phone-mode tests: a fake network answering by route, a signed-in session, a store in a temporary
// folder, the app's engine, the made-up bank files in Engine/. Everything here is made up.

/// Answers requests by "METHOD /path" from queued answers (the last one repeats); unknown routes get 404. `offline`
/// fails every request as without a connection.
@MainActor
final class RoutedTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var routes: [String: [(Int, Data)]] = [:]
    var offline = false

    func answer(_ route: String, _ status: Int = 200, _ body: Any) {
        let data = body as? Data ?? (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        routes[route, default: []].append((status, data))
    }

    func requests(to route: String) -> [URLRequest] { requests.filter { Self.route($0) == route } }

    static func route(_ request: URLRequest) -> String { "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")" }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if offline { throw URLError(.notConnectedToInternet) }
        let route = Self.route(request)
        var queue = routes[route] ?? []
        let answer = queue.first ?? (404, Data(#"{"error":"Not found"}"#.utf8))
        if queue.count > 1 { queue.removeFirst(); routes[route] = queue }
        return (answer.1, HTTPURLResponse(url: request.url!, statusCode: answer.0, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor
final class PhoneTokens: TokenStorage {
    var token: String?
    func read() throws -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func delete() throws { token = nil }
}

@MainActor
enum PhoneTest {
    static let login = "/api/collections/users/auth-with-password"
    static let refresh = "/api/collections/users/auth-refresh"

    /// A PocketBase-like token naming the account (so renewals of one account are recognised).
    static func token(_ account: String) -> String {
        let payload = Data(#"{"id":"\#(account)","type":"auth"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        return "eyJhbGciOiJIUzI1NiJ9.\(payload).fictional-signature"
    }

    static func loginAnswer(_ account: String, services: [String] = ["empire", "aresium"]) -> [String: Any] {
        ["token": token(account),
         "record": ["id": account, "approved": true, "services": services, "email": "\(account)@example.invalid"]]
    }

    /// A session logged in as `account` through `transport` (the account server's answers are queued there).
    static func session(_ account: String = "fictionalA", transport: RoutedTransport, tokens: PhoneTokens = PhoneTokens(),
                        markerDefaults: UserDefaults? = nil) async -> EmpireSession {
        transport.answer("POST " + login, 200, loginAnswer(account))
        let session = EmpireSession(app: .aresium, storage: tokens, client: EmpireAuthClient(transport: transport),
                                    restoreOnLaunch: false, sharedDefaults: markerDefaults)
        await session.login(email: "\(account)@example.invalid", password: "fictional-password")
        transport.routes["POST " + login] = nil
        return session
    }

    static func login(_ session: EmpireSession, as account: String, transport: RoutedTransport) async {
        transport.routes["POST " + login] = [(200, try! JSONSerialization.data(withJSONObject: loginAnswer(account)))]
        await session.login(email: "\(account)@example.invalid", password: "fictional-password")
    }

    static func defaults() -> UserDefaults {
        let name = "aresium-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    static func storage() -> PhoneStorage {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "build/15-test-stores/\(UUID().uuidString)", directoryHint: .isDirectory)
        return PhoneStorage(root: root)
    }

    static func engine() throws -> AresiumEngine { try AresiumEngine.bundled() }

    /// A phone backend on a new store of its own, with these categories ticked.
    static func backend(account: String = "fictionalA", storage: PhoneStorage = storage(),
                        chosen: [String] = []) async throws -> PhoneBackend {
        let ledger = try await Task.detached { try storage.open(account: account) }.value
        let backend = PhoneBackend(account: account, ledger: ledger, engine: try engine())
        backend.today = { "2026-10-27" }
        try await backend.load()
        for id in chosen { try await ledger.choose(id) }
        try await backend.refresh()
        return backend
    }

    /// A made-up bank file from the tests' Engine/ folder.
    static func fixture(_ name: String) throws -> ImportFile {
        let bundle = Bundle(for: FixtureAnchor.self)
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        let url = bundle.url(forResource: parts[0], withExtension: parts[1], subdirectory: "Engine")
            ?? bundle.url(forResource: parts[0], withExtension: parts[1])
        return ImportFile(name: name, data: try Data(contentsOf: #require(url, "Missing fixture \(name)")))
    }

    /// A VR Bank CSV (its known layout) with these made-up rows: (day, counterparty, text, amount in cents).
    static func vrBank(_ rows: [(String, String, String, Int)], name: String = "vr.csv") -> ImportFile {
        var lines = ["IBAN Auftragskonto;Buchungstag;Valutadatum;Name Zahlungsbeteiligter;Buchungstext;Verwendungszweck;Betrag;Währung;Soll/Haben;Saldo nach Buchung"]
        for (day, who, text, cents) in rows {
            let amount = String(format: "%d,%02d", abs(cents) / 100, abs(cents) % 100)
            lines.append(";\(day);\(day);\(who);Kartenzahlung;\(text);\(amount);EUR;\(cents < 0 ? "S" : "H");")
        }
        return ImportFile(name: name, data: Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    static func phoneResults(_ results: [ImportFileResult]) -> [PhoneImportResult] {
        results.compactMap { if case let .phone(result) = $0 { result } else { nil } }
    }
}

private final class FixtureAnchor: NSObject {}
