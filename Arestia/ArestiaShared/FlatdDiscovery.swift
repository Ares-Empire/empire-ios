import Foundation
import Network
import os

/// Finding flatd on the home network: it advertises its HTTPS listener over Bonjour as `_flatd._tcp`, so the app needs
/// no address. iOS asks once for the local network ("Arestia would like to find devices on your local network").
///
/// Bonjour is only a hint. Anyone on the Wi-Fi can advertise `_flatd._tcp` under any name, so what it finds are
/// *candidates*: an address counts as flatd's only once the server there proved the pinned key (`FlatdPin`). That is
/// also why no name is remembered: flatd is found again under whatever name it has, on whatever machine.
nonisolated enum FlatdBonjour {
    static let type = "_flatd._tcp"
    static let domain = "local."
    static let log = Logger(subsystem: "de.ares-empire.arestia", category: "bonjour")

    /// Every address a `_flatd._tcp` service is advertised at right now, in no particular order: the services seen
    /// within `browse` (none seen: empty), each resolved. Candidates only, see above.
    static func candidates(browse: Duration = .seconds(2)) async -> [URL] {
        // Anyone on the Wi-Fi can advertise any number of services: a handful is looked at, never all of them.
        // Which handful changes from one look to the next, so no set of forged names can keep the real one out.
        let names = await serviceNames(within: browse).shuffled().prefix(maxCandidates)
        return await withTaskGroup(of: URL?.self) { group in
            for name in names { group.addTask { await resolve(name: name) } }
            var found: [URL] = []
            for await url in group {
                if let url, !found.contains(url) { found.append(url) }
            }
            return found
        }
    }

    /// How many advertised services are resolved and tried at most (a home has one flatd, two during a move).
    static let maxCandidates = 8

    /// The names of the services advertised now. Ends early once some were seen and nothing new came for a moment.
    static func serviceNames(within limit: Duration) async -> [String] {
        let browser = NWBrowser(for: .bonjour(type: type, domain: domain), using: .tcp)
        let names = OSAllocatedUnfairLock<Set<String>>(initialState: [])
        browser.browseResultsChangedHandler = { results, _ in
            let found = results.compactMap { result -> String? in
                if case let .service(name, _, _, _) = result.endpoint { name } else { nil }
            }
            names.withLock { $0 = Set(found) }
        }
        browser.start(queue: .global(qos: .userInitiated))
        defer { browser.cancel() }
        let clock = ContinuousClock(), end = clock.now + limit
        var seen = 0
        while clock.now < end, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(300))
            let count = names.withLock { $0.count }
            if count > 0, count == seen { break }
            seen = count
        }
        return names.withLock { $0.sorted() }
    }

    /// The address of the service with this name, `https://<IPv4>:<port>`, or nil when it does not answer in time.
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
                        finish(connection.currentPath?.remoteEndpoint.flatMap(serviceURL))
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

    /// `https://192.168.1.20:8788` from a resolved endpoint.
    static func serviceURL(_ endpoint: NWEndpoint) -> URL? {
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
        return URL(string: "https://\(address):\(port.rawValue)")
    }
}

/// The client to use, for the intents and the controls (which run without the app), always for the flat paired when
/// they run (one flat per install). The address is settled first: the saved one if flatd answers there, else (nothing
/// answers, or what answers does not hold flatd's key) every address Bonjour offers is tried the same way, and only one
/// where the server proved flatd's key counts. Then the work runs once, there: a command is never sent twice (a
/// connection lost after flatd took it would otherwise repeat it). The new address is kept once the work succeeded.
nonisolated struct FlatdReach: Sendable {
    let connection: FlatdConnection
    /// Nil: the real, pinned transport (the tests pass a fake).
    var transport: (any HTTPTransport & Sendable)?
    var rediscover: @Sendable () async -> [URL] = { await FlatdBonjour.candidates() }

    /// Throws `.notPaired` without a pairing, `.pairingUnreadable` while it cannot be read, `.unreachable` when flatd
    /// cannot be found.
    func run<T: Sendable>(_ work: @Sendable (FlatdClient) async throws -> T) async throws -> T {
        let pairing = try connection.current()
        var client = FlatdClient(pairing, transport: transport)
        do {
            try await client.verify()
        } catch let error as FlatdError where error == .unreachable || error == .noAnswer {
            let candidates = await rediscover().filter { $0 != pairing.baseURL }
            guard let found = await Self.find(pairing, among: candidates, transport: transport) else {
                throw FlatdError.unreachable
            }
            client = found
        }
        // Forgotten while the address was looked up: this run sends nothing.
        guard try connection.current().id == pairing.id else { throw FlatdError.notPaired }
        let result = try await work(client)
        connection.move(pairing, to: client.baseURL)
        return result
    }

    /// A candidate address where flatd answers (its key proved, by the transport). The candidates are asked side by
    /// side and the first that answers wins, so addresses that answer slowly or not at all (forged Bonjour records)
    /// cannot use up the time before the real one is asked.
    static func find(_ pairing: FlatdPairing, among candidates: [URL],
                     transport: (any HTTPTransport & Sendable)?) async -> FlatdClient? {
        await withTaskGroup(of: FlatdClient?.self) { group in
            for url in candidates.prefix(FlatdBonjour.maxCandidates) where url.scheme == "https" {
                group.addTask {
                    let client = FlatdClient(pairing, at: url, transport: transport)
                    return (try? await client.verify()) != nil ? client : nil
                }
            }
            for await found in group {
                if let found {
                    group.cancelAll()
                    return found
                }
            }
            return nil
        }
    }
}
