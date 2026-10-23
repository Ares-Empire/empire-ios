#if DEBUG
import Foundation

@MainActor
enum DebugLaunch {
    static var isTesting: Bool {
        NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
    static func testingSession() -> EmpireSession {
        let tokens = Tokens()
        tokens.token = nil
        return EmpireSession(app: .aresium, storage: tokens, restoreOnLaunch: false)
    }
    static func unavailableSession() -> EmpireSession {
        EmpireSession(app: .aresium, storage: Tokens(), client: EmpireAuthClient(transport: Unavailable()))
    }
    private final class Tokens: TokenStorage {
        var token: String? = "fictional-screenshot-token"
        func read() throws -> String? { token }
        func save(_ token: String) throws { self.token = token }
        func delete() throws { token = nil }
    }
    private struct Unavailable: HTTPTransport {
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            (Data(#"{"error":"Login service unavailable"}"#.utf8),
             HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!)
        }
    }
}
#endif
