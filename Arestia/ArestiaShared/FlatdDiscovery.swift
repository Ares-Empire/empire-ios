import Foundation
import Network
import os

/// Finding flatd on the home network: it advertises itself over Bonjour as `_flatd._tcp` (contract v1.1), so the app
/// needs no address. iOS asks once for the local network ("Arestia would like to find devices on your local network").
nonisolated enum FlatdBonjour {
    static let type = "_flatd._tcp"
    static let domain = "local."
    static let log = Logger(subsystem: "de.ares-empire.arestia", category: "bonjour")

    /// The address of the service with this name, `http://<IPv4>:<port>`, or nil when it does not answer in time.
    /// IPv4 only: an IPv6 link-local address needs its interface in the URL, which URLSession and WebKit read poorly.
    static func resolve(name: String, timeout: Duration = .seconds(4)) async -> URL? {
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let connection = NWConnection(to: .service(name: name, type: type, domain: domain, interface: nil),
                                      using: parameters)
        let result = OSAllocatedUnfairLock<URL??>(initialState: nil)   // nil: not yet; .some(nil): failed
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (done: CheckedContinuation<URL?, Never>) in
                let finish: @Sendable (URL?) -> Void = { url in
                    let first = result.withLock { state -> Bool in
                        guard state == nil else { return false }
                        state = .some(url)
                        return true
                    }
                    guard first else { return }
                    connection.cancel()
                    done.resume(returning: url)
                }
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        finish(connection.currentPath?.remoteEndpoint.flatMap(httpURL))
                    case .failed, .cancelled:
                        finish(nil)
                    case let .waiting(error):
                        log.notice("resolve waits: \(String(describing: error), privacy: .public)")
                    default:
                        break
                    }
                }
                connection.start(queue: .global(qos: .userInitiated))
                Task {
                    try? await Task.sleep(for: timeout)
                    finish(nil)
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }

    /// `http://192.168.1.20:8787` from a resolved endpoint.
    static func httpURL(_ endpoint: NWEndpoint) -> URL? {
        guard case let .hostPort(host, port) = endpoint else { return nil }
        let address: String
        switch host {
        case let .ipv4(ip):
            address = ip.rawValue.map(String.init).joined(separator: ".")
        case let .name(name, _):
            address = name
        default:
            return nil
        }
        return URL(string: "http://\(address):\(port.rawValue)")
    }
}

/// The client to use, for the intents and the controls (which run without the app): the saved pairing's address, once
/// it answered like flatd; when it cannot be reached at all and the pairing came from Bonjour, flatd is looked up again
/// under its name (the Mac's address may have changed), checked the same way, and the new address is kept once the
/// work succeeded there. A timeout is never retried elsewhere: flatd may have done it already.
nonisolated struct FlatdReach: Sendable {
    let connection: FlatdConnection
    var transport: any HTTPTransport & Sendable = URLSessionTransport()
    var resolve: @Sendable (String) async -> URL? = { await FlatdBonjour.resolve(name: $0) }

    /// Throws `FlatdError.refused` without a pairing, `.unreachable` when flatd cannot be found.
    func run<T: Sendable>(_ work: @Sendable (FlatdClient) async throws -> T) async throws -> T {
        guard let pairing = connection.pairing, !pairing.token.isEmpty else { throw FlatdError.refused }
        let saved = FlatdClient(baseURL: pairing.link.baseURL, token: pairing.token, transport: transport)
        do {
            try await saved.verify()
            return try await work(saved)
        } catch FlatdError.unreachable {
            guard let name = pairing.link.serviceName, let found = await resolve(name),
                  found != pairing.link.baseURL else { throw FlatdError.unreachable }
            let moved = FlatdClient(baseURL: found, token: pairing.token, transport: transport)
            try await moved.verify()
            let result = try await work(moved)
            connection.move(to: found, keyedBy: pairing.token)
            return result
        }
    }
}
