import CoreSpotlight
import Foundation
@testable import Arestoteles

/// A server in memory: answers by "METHOD /path" (the path below /api/arestoteles, still percent-encoded), records every
/// request, and can hold one request of a route until the test lets it go.
@MainActor
final class FakeTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var routes: [String: (status: Int, data: Data, headers: [String: String])] = [:]
    var fallback: (status: Int, data: Data) = (404, Data(#"{"error":"Not found"}"#.utf8))
    var failure: Error?
    var gates: [String: RequestGate] = [:]

    init(fallback: (status: Int, data: Data)? = nil) {
        if let fallback { self.fallback = fallback }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let key = Self.key(request)
        if let gate = gates.removeValue(forKey: key) { await gate.pause() }
        if let failure { throw failure }
        let answer = routes[key] ?? (fallback.status, fallback.data, [:])
        return (answer.data, HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: nil,
                                             headerFields: answer.headers)!)
    }

    /// "POST /edits", "GET /notes/Spread%20of%20print/source"
    static func key(_ request: URLRequest) -> String {
        let path = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath } ?? ""
        return "\(request.httpMethod ?? "GET") \(path.replacingOccurrences(of: "/api/arestoteles", with: ""))"
    }

    func requests(_ key: String) -> [URLRequest] { requests.filter { Self.key($0) == key } }

    func answer(_ key: String, _ status: Int = 200, json: Data, headers: [String: String] = [:]) {
        routes[key] = (status, json, headers)
    }

    func answer(_ key: String, sample name: String, headers: [String: String] = [:]) throws {
        routes[key] = (200, try ArestotelesSamples.data(name), headers)
    }

    func answer<T: Encodable>(_ key: String, _ status: Int = 200, encoding value: T) throws {
        routes[key] = (status, try JSONEncoder().encode(value), [:])
    }

    /// The bodies of the edits sent, as JSON objects.
    func edits() throws -> [[String: Any]] {
        try requests("POST /edits").map { request in
            guard let json = try body(request) else { throw CocoaError(.coderReadCorrupt) }
            return json
        }
    }
}

/// Holds one request until `resume()`.
@MainActor
final class RequestGate {
    private var pending: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?

    func pause() async {
        await withCheckedContinuation {
            pending = $0
            waiter?.resume()
            waiter = nil
        }
    }

    func waitUntilPaused() async {
        if pending != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func resume() {
        pending?.resume()
        pending = nil
    }
}

@MainActor
final class MemoryTokens: TokenStorage {
    var token: String?
    init(token: String? = nil) { self.token = token }
    func read() throws -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func delete() throws { token = nil }
}

/// Records what the store asks of Spotlight.
@MainActor
final class FakeSpotlight: SpotlightIndexing {
    enum Call: Equatable { case replace([String]), removeAll }
    var calls: [Call] = []
    func replace(with notes: [Note]) async throws { calls.append(.replace(notes.map(\.id))) }
    func removeAll() async throws { calls.append(.removeAll) }
}

/// A made-up login token shaped like PocketBase's (a JWT whose payload names the account), so the store can tell
/// accounts apart. Not signed: only the servers verify tokens.
func fakeToken(account: String) -> String {
    func base64url(_ text: String) -> String {
        Data(text.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    return base64url(#"{"alg":"none"}"#) + "." + base64url(#"{"id":"\#(account)"}"#) + ".fictional-signature"
}

/// The account server in memory: answers every login and renewal with a made-up token of `account`.
@MainActor
func authServer(account: String = "account-a", services: [String] = ["arestoteles"]) -> FakeTransport {
    let services = services.map { "\"\($0)\"" }.joined(separator: ",")
    return FakeTransport(fallback: (200, Data("""
        {"token":"\(fakeToken(account: account))","record":{"id":"\(account)","approved":true,"services":[\(services)]}}
        """.utf8)))
}

/// A logged-in session for an account with the `arestoteles` service.
@MainActor
func signedInSession(storage: MemoryTokens = MemoryTokens(), account: String = "account-a",
                     auth: FakeTransport? = nil) async -> EmpireSession {
    let session = EmpireSession(app: .arestoteles, storage: storage,
                                client: EmpireAuthClient(transport: auth ?? authServer(account: account)),
                                restoreOnLaunch: false)
    await session.login(email: "member@example.invalid", password: "fictional-password")
    return session
}

/// Everything a store test needs.
@MainActor
struct Harness {
    let store: VaultStore
    let transport: FakeTransport
    let session: EmpireSession
    let persistence: MemoryPersistence
    let spotlight: FakeSpotlight
}

/// A store on a fake server that answers `GET /vault` with the sample (ETag `"a1b2c3d"`).
@MainActor
func makeStore(session: EmpireSession? = nil, transport: FakeTransport = FakeTransport(),
               persistence: MemoryPersistence = MemoryPersistence(), savedAccount: String? = "account-a") async throws
    -> Harness {
    var signedIn = session
    if signedIn == nil { signedIn = await signedInSession() }
    let session = signedIn!
    if transport.routes["GET /vault"] == nil {
        try transport.answer("GET /vault", sample: "vault", headers: ["ETag": "\"a1b2c3d\""])
    }
    let spotlight = FakeSpotlight()
    let api = ArestotelesAPI(transport: transport, token: { session.token })
    let store = VaultStore(session: session, backend: api, persistence: persistence, spotlight: spotlight,
                           savedAccount: { savedAccount })
    return Harness(store: store, transport: transport, session: session, persistence: persistence, spotlight: spotlight)
}

@MainActor
func sample<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
    try JSONDecoder().decode(type, from: ArestotelesSamples.data(name))
}

@MainActor
func sampleVault() throws -> Vault { try sample(Vault.self, "vault") }

@MainActor
func sampleIndex() throws -> VaultIndex { VaultIndex(vault: try sampleVault()) }

/// The body of a request as JSON.
func body(_ request: URLRequest?) throws -> [String: Any]? {
    guard let data = request?.httpBody else { return nil }
    return try JSONSerialization.jsonObject(with: data) as? [String: Any]
}

extension Array {
    var only: Element? { count == 1 ? first : nil }
}
