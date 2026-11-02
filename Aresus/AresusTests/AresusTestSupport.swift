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

/// Runs the real request/status/decode path against a fake transport; production always uses the background driver.
@MainActor
final class ImmediateDropUploads: DropUploading {
    let identifier = "test-background-upload"
    var completed: ((DropUploadID, Result<Drop, Error>, String?) async -> Void)?
    let transport: any HTTPTransport
    init(_ transport: any HTTPTransport) { self.transport = transport }
    func activeIDs() async -> Set<UUID> { [] }
    func cancel(_ id: UUID) async {}
    func submit(_ id: DropUploadID, request: URLRequest, file: URL, earliestBeginDate: Date?) async throws {
        let result: Result<Drop, Error>
        do {
            let (data, response) = try await transport.upload(request, fromFile: file)
            result = DropBackgroundUploads.result(data: data, response: response, error: nil)
        } catch { result = .failure(error) }
        let token = request.value(forHTTPHeaderField: "Authorization").map { String($0.dropFirst(7)) }
        await completed?(id, result, token)
    }
}

extension AresusAPI {
    /// An API test's upload goes through the background driver's response parser, without making a URLSession.
    func testedUpload(_ id: Int, fileURL: URL, token: String) async throws -> Drop {
        let request = try uploadRequest(id, token: token)
        let (data, response) = try await transport.upload(request, fromFile: fileURL)
        return try DropBackgroundUploads.result(data: data, response: response, error: nil).get()
    }
}
