import Foundation
@testable import Arestia

// Made-up flat for the tests: generic devices only ("Fan 1", "Blind 1"), never the real flat's.

/// flatd's answers to requests, by method and path; records what was asked.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    struct Answer {
        var status = 200
        var body: Any = [String: Any]()
        var fails = false            // no answer at all (flatd out of reach)
    }

    private let lock = NSLock()
    private var answers: [String: Answer] = [:]
    private(set) var requests: [URLRequest] = []

    /// `"POST /api/devices/fan:fan_1"` → answer.
    func answer(_ route: String, status: Int = 200, body: Any = [String: Any](), fails: Bool = false) {
        lock.withLock { answers[route] = Answer(status: status, body: body, fails: fails) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let route = (request.httpMethod ?? "GET") + " " + (request.url?.path(percentEncoded: true) ?? "")
        let answer = lock.withLock {
            requests.append(request)
            return answers[route]
        }
        guard let answer, !answer.fails else { throw URLError(.cannotConnectToHost) }
        let data = try JSONSerialization.data(withJSONObject: answer.body)
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }

    var sent: [URLRequest] { lock.withLock { requests } }

    func bodies(for route: String) -> [[String: Any]] {
        sent.filter { ($0.httpMethod ?? "GET") + " " + ($0.url?.path(percentEncoded: true) ?? "") == route }
            .compactMap { $0.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
    }
}

/// The event stream, fed by the test.
final class FakeEvents: FlatEventSource, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<FlatEvent, Error>.Continuation?
    private(set) var urls: [URL] = []

    func events(from url: URL) -> AsyncThrowingStream<FlatEvent, Error> {
        AsyncThrowingStream { continuation in
            lock.withLock {
                urls.append(url)
                self.continuation = continuation
            }
        }
    }

    var isOpen: Bool { lock.withLock { continuation != nil } }

    func send(_ event: FlatEvent) { _ = lock.withLock { continuation }?.yield(event) }

    func end(_ error: Error) {
        let continuation = lock.withLock { () -> AsyncThrowingStream<FlatEvent, Error>.Continuation? in
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.finish(throwing: error)
    }
}

/// The key in memory.
final class MemoryKeys: FlatdKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?
    init(_ key: String? = nil) { self.key = key }
    func read() throws -> String? { lock.withLock { key } }
    func save(_ key: String) throws { lock.withLock { self.key = key } }
    func delete() throws { lock.withLock { key = nil } }
}

enum Flat {
    static let base = URL(string: "http://192.0.2.10:8787")!
    static let key = "test-key-0123456789abcdef"

    /// A connection in a defaults suite of its own and an in-memory key.
    static func connection(linked: Bool = true) -> FlatdConnection {
        let defaults = UserDefaults(suiteName: "arestia-tests-" + UUID().uuidString)!
        let connection = FlatdConnection(defaults: defaults, keychain: MemoryKeys(linked ? key : nil))
        if linked { connection.save(link: FlatdLink(baseURL: base, serviceName: "flatd")) }
        return connection
    }

    static func fan(_ number: Int, on: Bool = false, offAt: String? = nil, online: Bool = true) -> [String: Any] {
        ["id": "fan:fan_\(number)", "kind": "fan", "label": "Fan \(number)", "room": "living",
         "controls": ["on", "for_s"],
         "state": ["on": on, "off_at": offAt as Any? ?? NSNull(), "online": online, "power_w": on ? 38.0 : 0.0]]
    }

    static func rollo(_ number: Int, position: Int = 0, moving: String? = nil, target: Int? = nil,
                      favourite: Int? = nil) -> [String: Any] {
        ["id": "rollo:blind_\(number)", "kind": "rollo", "label": "Blind \(number)", "controls": ["command", "position"],
         "state": ["position": position, "moving": moving as Any? ?? NSNull(), "target": target as Any? ?? NSNull(),
                   "favourite": favourite as Any? ?? NSNull(), "online": true]]
    }

    static let cooking: [String: Any] = ["id": "cooking", "label": "Cooking", "active": false, "since": NSNull(),
                                         "devices": ["fan:fan_1", "fan:fan_2", "rollo:blind_1"]]

    static func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }

    static func devices(_ objects: [[String: Any]]) throws -> [Device] { try decode([Device].self, objects) }

    static func snapshot(fans: Int = 2, rollos: Bool = true, cookingActive: Bool = false) throws -> FlatEvent {
        var objects = (1...max(1, fans)).map { fan($0) }
        if rollos { objects += [rollo(1, position: 60, favourite: 60), rollo(2)] }
        var mode = cooking
        mode["active"] = cookingActive
        return .snapshot(devices: try devices(objects), modes: [try decode(FlatMode.self, mode)])
    }

    /// A store on the fakes, with its controls' reloads counted.
    @MainActor
    static func store(transport: FakeTransport = FakeTransport(), events: FakeEvents = FakeEvents(),
                      connection: FlatdConnection = connection()) -> (FlatStore, FakeTransport, FakeEvents, Counter) {
        let reloads = Counter()
        let store = FlatStore(connection: connection, transport: transport, eventSource: events,
                              rediscover: { _ in nil }, reloadControls: { reloads.count += 1 })
        return (store, transport, events, reloads)
    }
}

@MainActor
final class Counter {
    var count = 0
}

/// Waits (briefly) until a condition holds: the store's work runs in tasks.
@MainActor
func eventually(_ condition: () -> Bool, timeout: Duration = .seconds(2)) async -> Bool {
    let clock = ContinuousClock(), end = clock.now + timeout
    while clock.now < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
