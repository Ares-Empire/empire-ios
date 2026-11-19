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

/// The client to use: the saved address first; when it does not answer and the service was found over Bonjour, its
/// address is looked up again (the Mac's address may have changed) and saved. For the intents and the controls, which
/// run without the app.
nonisolated struct FlatdReach: Sendable {
    let connection: FlatdConnection
    var transport: any HTTPTransport & Sendable = URLSessionTransport()
    var resolve: @Sendable (String) async -> URL? = { await FlatdBonjour.resolve(name: $0) }

    /// Runs `work` with the saved client; when flatd cannot be reached there, finds it again over Bonjour and runs it
    /// once more. Throws `FlatdError.refused` without a key, `.unreachable` when it cannot be found.
    func run<T: Sendable>(_ work: @Sendable (FlatdClient) async throws -> T) async throws -> T {
        guard let link = connection.link, let token = connection.token, !token.isEmpty else { throw FlatdError.refused }
        do {
            return try await work(FlatdClient(baseURL: link.baseURL, token: token, transport: transport))
        } catch FlatdError.unreachable {
            guard let name = link.serviceName, let found = await resolve(name), found != link.baseURL else {
                throw FlatdError.unreachable
            }
            connection.save(link: FlatdLink(baseURL: found, serviceName: name))
            return try await work(FlatdClient(baseURL: found, token: token, transport: transport))
        }
    }
}
