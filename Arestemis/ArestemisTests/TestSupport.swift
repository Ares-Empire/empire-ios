import Foundation
@testable import Arestemis

/// A server in memory: answers by "METHOD /path" (the path below /api/arestemis), records every request, and can hold
/// one request of a route until the test lets it go.
@MainActor
final class FakeTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var routes: [String: (status: Int, data: Data)] = [:]
    var fallback: (status: Int, data: Data) = (404, Data(#"{"error":"Not found"}"#.utf8))
    var failure: Error?
    var gates: [String: RequestGate] = [:]

    init(fallback: (status: Int, data: Data)? = nil) {
        if let fallback { self.fallback = fallback }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let key = Self.key(request)
        let answer = routes[key] ?? fallback
        if let gate = gates.removeValue(forKey: key) { await gate.pause() }
        if let failure { throw failure }
        return (answer.data, HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: nil, headerFields: nil)!)
    }

    /// "POST /matches/41/state"
    static func key(_ request: URLRequest) -> String {
        let path = request.url?.path(percentEncoded: false) ?? ""
        return "\(request.httpMethod ?? "GET") \(path.replacingOccurrences(of: "/api/arestemis", with: ""))"
    }

    func requests(_ key: String) -> [URLRequest] { requests.filter { Self.key($0) == key } }

    func answer(_ key: String, _ status: Int = 200, json: Data) { routes[key] = (status, json) }

    func answer(_ key: String, sample name: String) throws {
        routes[key] = (200, try ArestemisSamples.data(name))
    }

    func answer<T: Encodable>(_ key: String, _ status: Int = 200, encoding value: T) throws {
        routes[key] = (status, try JSONEncoder().encode(value))
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
    func read() throws -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func delete() throws { token = nil }
}

/// A logged-in session with a made-up token, for an account with the `arestemis` service.
@MainActor
func signedInSession(storage: MemoryTokens = MemoryTokens()) async -> EmpireSession {
    let auth = FakeTransport(fallback: (200, Data("""
        {"token":"fictional-token","record":{"id":"fictional-account","approved":true,"services":["arestemis"]}}
        """.utf8)))
    let session = EmpireSession(app: .arestemis, storage: storage, client: EmpireAuthClient(transport: auth),
                                restoreOnLaunch: false)
    await session.login(email: "member@example.invalid", password: "fictional-password")
    return session
}

/// A store on a fake server that already answers the overview with the sample.
@MainActor
func makeStore(session: EmpireSession? = nil, transport: FakeTransport = FakeTransport()) async throws
    -> (ArestemisStore, FakeTransport, EmpireSession) {
    var signedIn = session
    if signedIn == nil { signedIn = await signedInSession() }
    let session = signedIn!
    if transport.routes["GET /overview"] == nil { try transport.answer("GET /overview", sample: "overview") }
    let api = ArestemisAPI(transport: transport, token: { session.token })
    return (ArestemisStore(session: session, backend: api, placeDelay: .milliseconds(30)), transport, session)
}

@MainActor
func sample<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
    try JSONDecoder().decode(type, from: ArestemisSamples.data(name))
}

/// The body of a request as JSON.
func body(_ request: URLRequest?) throws -> [String: Any]? {
    guard let data = request?.httpBody else { return nil }
    return try JSONSerialization.jsonObject(with: data) as? [String: Any]
}

/// A fixed clock and calendar for formatting tests: Saturday 24 Oct 2026, 12:02:40 in Berlin.
enum Clock {
    static let now = Timestamp.parse("2026-10-24T10:02:40Z")!
    static var berlin: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }
}

extension Array {
    var only: Element? { count == 1 ? first : nil }
}
