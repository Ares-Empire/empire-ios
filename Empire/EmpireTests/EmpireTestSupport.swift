import Foundation
@testable import Empire

@MainActor
final class EmpireFakeTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var status = 200
    var data = Data()
    var responses: [(Int, Data)] = []
    var failure: Error?
    var nextGate: EmpireRequestGate?

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
        return (response.1, HTTPURLResponse(url: request.url!, statusCode: response.0,
                                          httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor
final class EmpireRequestGate {
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
final class EmpireMemoryTokens: TokenStorage {
    var token: String?
    func read() throws -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func delete() throws { token = nil }
}

@MainActor
func empireAuthResponse(token: String = "fictional-empire-token") -> Data {
    Data("""
    {"token":"\(token)","record":{"id":"fictional-account","approved":true,"services":["empire","aresium"]}}
    """.utf8)
}

@MainActor
func empireSession(storage: EmpireMemoryTokens = EmpireMemoryTokens(),
                   auth: EmpireFakeTransport? = nil) async -> EmpireSession {
    let session = EmpireSession(app: .empire, storage: storage,
                                client: EmpireAuthClient(transport: auth ?? EmpireFakeTransport(data: empireAuthResponse())),
                                restoreOnLaunch: false)
    await session.login(email: "member@example.invalid", password: "fictional-password")
    return session
}

@MainActor
func empireJSON(user: Bool = false) throws -> Data {
    try JSONEncoder().encode(EmpireSamples.load(user: user))
}

@MainActor
func empireWithPending(_ count: Int) throws -> EmpireData {
    let original = try EmpireSamples.load(user: false)
    return EmpireData(version: original.version, me: original.me, projects: original.projects,
                      addable: original.addable, chronicle: original.chronicle, ideas: original.ideas, pending: count)
}
