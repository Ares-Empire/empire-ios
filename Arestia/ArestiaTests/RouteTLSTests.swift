import Foundation
import Testing
@testable import Arestia

struct RouteTLSTests {
    private struct Arrival: Decodable {
        let event: String
        let method: String?
        let path: String?
        let authorized: Bool?
    }

    /// Replace only DNS resolution in the fixture. Both routes still use a real URLSession and its pin delegate.
    private struct LoopbackRemote: GatedTransport {
        let listener: URL
        let pinned: FlatdTransport

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            try await send(request, gate: nil, dispatch: nil)
        }

        func send(_ request: URLRequest, gate: FlatdGate?, dispatch: FlatdRequestDispatch?) async throws
            -> (Data, HTTPURLResponse) {
            var request = request
            var url = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            url.host = listener.host()
            url.port = listener.port
            request.url = url.url
            return try await pinned.send(request, gate: gate, dispatch: dispatch)
        }
    }

    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["ARESTIA_ARRIVALS"] != nil))
    func routePinsRejectOppositeKeyBeforeAnyRequest() async throws {
        let environment = ProcessInfo.processInfo.environment
        let h = try #require(PairingCode.parse(environment["ARESTIA_HOME_FLATD"] ?? ""))
        let a = try #require(PairingCode.parse(environment["ARESTIA_REMOTE_FLATD"] ?? ""))
        let homeURL = try #require(h.baseURL)
        let aLoopback = try #require(a.baseURL)
        let directory = URL(filePath: try #require(environment["ARESTIA_ARRIVALS"]))
        #expect(h.pin != a.pin)
        let connection = Flat.connection(linked: false)
        let initial = FlatdPairing(baseURL: homeURL, token: h.token, pin: h.pin)
        try connection.save(initial)
        let home = FlatdClient(initial).gated(by: connection)
        await FlatStore.enrollRemote(from: home, read: initial, connection: connection)
        let paired = try connection.current()
        #expect(paired.remote?.pin == a.pin)
        #expect(paired.remote?.url.port == aLoopback.port)
        let positiveRemote = try #require(FlatdClient(remoteOf: paired, transport: LoopbackRemote(
            listener: aLoopback, pinned: FlatdTransport(pin: a.pin)
        ))).gated(by: connection, allowsRemote: { true })
        #expect(try await !positiveRemote.devices().isEmpty)

        func arrivals(_ listener: String) throws -> [Arrival] {
            let data = try String(contentsOf: directory.appending(path: listener + ".arrivals"), encoding: .utf8)
            return try data.split(separator: "\n").map { try JSONDecoder().decode(Arrival.self, from: Data($0.utf8)) }
        }
        let beforeA = try arrivals("remote")
        let beforeH = try arrivals("home")
        #expect(beforeA.contains { $0.method == "GET" && $0.path == "/api/devices" && $0.authorized == true })
        #expect(beforeH.contains { $0.method == "GET" && $0.path == "/api/remote" && $0.authorized == true })

        // The wrong key is at the saved home address.
        var wrong = paired
        wrong.baseURL = aLoopback
        let wrongHome = FlatdClient(wrong).gated(by: connection)
        await #expect(throws: FlatdError.unreachable) { try await wrongHome.devices() }

        // The only Bonjour candidate is the genuine remote listener. A locked action cannot use either route.
        var offline = paired
        offline.baseURL = URL(string: "https://127.0.0.1:0")!
        try connection.save(offline)
        let reach = FlatdReach(connection: connection, rediscover: { [aLoopback] }, path: { .localPossible },
                               allowsRemote: { false }, needsPasscode: { false })
        await #expect(throws: FlatdError.awayNeedsUnlock(needsPasscode: false)) {
            try await reach.run { try await $0.devices() }
        }

        let wrongRemote = try #require(FlatdClient(remoteOf: paired, transport: LoopbackRemote(
            listener: homeURL, pinned: FlatdTransport(pin: a.pin)
        ))).gated(by: connection, allowsRemote: { true })
        await #expect(throws: FlatdError.unreachable) { try await wrongRemote.devices() }

        try #require(await eventually {
            let rejectedA = (try? arrivals("remote").dropFirst(beforeA.count).filter { $0.event == "tls_failed" }.count) ?? 0
            let rejectedH = (try? arrivals("home").dropFirst(beforeH.count).filter { $0.event == "tls_failed" }.count) ?? 0
            return rejectedA >= 2 && rejectedH >= 1
        })
        let newA = try arrivals("remote").dropFirst(beforeA.count)
        let newH = try arrivals("home").dropFirst(beforeH.count)
        #expect(newA.filter { $0.event == "tls_accept" }.count >= 2)
        #expect(newH.contains { $0.event == "tls_accept" })
        #expect(newA.allSatisfy { $0.event != "request" })
        #expect(newH.allSatisfy { $0.event != "request" })
    }
}
