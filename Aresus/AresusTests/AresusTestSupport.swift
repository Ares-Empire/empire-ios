import Foundation
@testable import Aresus

@MainActor
final class FakeTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var status = 200
    var data = Data()
    var responses: [(Int, Data)] = []
    var failure: Error?
    var nextGate: RequestGate?

    init(data: Data = Data()) { self.data = data }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = responses.isEmpty ? (status, data) : responses.removeFirst()
        let failure = failure
        if let gate = nextGate {
            nextGate = nil
            await gate.pause()
        }
        if let failure { throw failure }
        return (response.1, HTTPURLResponse(url: request.url!, statusCode: response.0, httpVersion: nil, headerFields: nil)!)
    }
}

/// Holds a request until the test lets it go, to check what happens while it is on its way.
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

@MainActor
func authResponse(token: String = "fictional-empire-token", services: [String] = ["empire", "aresus"]) -> Data {
    let list = services.map { "\"\($0)\"" }.joined(separator: ",")
    return Data("""
    {"token":"\(token)","record":{"id":"fictional-account","approved":true,"services":[\(list)]}}
    """.utf8)
}

/// A signed-in session against fakes (no Keychain, no network).
@MainActor
func signedInSession(storage: MemoryTokens = MemoryTokens(), auth: FakeTransport? = nil) async -> EmpireSession {
    let session = EmpireSession(app: .aresus, storage: storage,
                                client: EmpireAuthClient(transport: auth ?? FakeTransport(data: authResponse())),
                                restoreOnLaunch: false)
    await session.login(email: "member@example.invalid", password: "fictional-password")
    return session
}

/// A bundled sample answer as the server would send it.
func sampleData(_ name: String) throws -> Data {
    guard let url = Bundle.main.url(forResource: name, withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
    return try Data(contentsOf: url)
}

func sample<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
    try AresusJSON.decoder().decode(T.self, from: sampleData(name))
}

/// A fixed place and time for formatting: Berlin, where Patrik reads the app.
nonisolated let berlin: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    calendar.locale = Locale(identifier: "en_GB")
    return calendar
}()

/// "2026-10-24T12:09:00Z" → Date.
nonisolated func at(_ text: String) -> Date { AresusJSON.date(text)! }

extension Array {
    var only: Element? { count == 1 ? first : nil }
}
