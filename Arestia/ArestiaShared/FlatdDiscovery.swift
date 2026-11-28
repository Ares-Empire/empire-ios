import Foundation
import Network
import os

/// Finding flatd on the home network: it advertises its HTTPS listener over Bonjour as `_flatd._tcp`, so the app needs
/// no address. iOS asks once for the local network ("Arestia would like to find devices on your local network").
///
/// Bonjour is only a hint. Anyone on the Wi-Fi can advertise `_flatd._tcp` under any name, so what it finds are
/// *candidates*: an address counts as flatd's only once the server there proved the pinned key (`FlatdPin`). That is
/// also why no name is remembered: flatd is found again under whatever name it has, on whatever machine.
nonisolated struct FlatdBonjour: Sendable {
    static let type = "_flatd._tcp"
    static let domain = "local."
    static let log = Logger(subsystem: "de.ares-empire.arestia", category: "bonjour")

    var browse: @Sendable () async -> [String] = { await serviceNames(within: .seconds(2)) }
    var resolve: @Sendable (String) async -> URL? = { await resolve(name: $0) }

    /// Each service is probed as soon as its address resolves. A winning probe cancels the other resolutions.
    func firstReachable<T: Sendable>(_ probe: @escaping @Sendable (URL) async -> T?) async -> T? {
        let names = await browse().shuffled().prefix(Self.maxCandidates)
        return await withTaskGroup(of: T?.self) { group in
            for name in names {
                group.addTask {
                    guard !Task.isCancelled, let url = await resolve(name), !Task.isCancelled else { return nil }
                    return await probe(url)
                }
            }
            for await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

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
        #if DEBUG && ARESTIA_GATE
        let timeout = FlatdRequestTimeout.duration
        #endif
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let connection = NWConnection(to: .service(name: name, type: type, domain: domain, interface: nil),
                                      using: parameters)
        let (addresses, result) = AsyncStream<URL>.makeStream(bufferingPolicy: .bufferingNewest(1))
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let url = connection.currentPath?.remoteEndpoint.flatMap(serviceURL) {
                    result.yield(url)
                }
                result.finish()
            case .failed, .cancelled:
                result.finish()
            case .waiting:
                log.notice("Bonjour resolution is waiting")
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        defer {
            connection.stateUpdateHandler = nil
            connection.cancel()
            result.finish()
        }
        return try? await Deadline(after: timeout).run { () -> URL? in
            for await address in addresses { return address }
            return nil
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

/// Selects a route for an intent or control, then runs the action once through the selected client.
nonisolated struct FlatdReach: Sendable {
    let connection: FlatdConnection
    var transport: (any HTTPTransport & Sendable)?
    var rediscover: (@Sendable () async -> [URL])?
    var path: (@Sendable () async -> HomeRoute.Path)?
    var allowsRemote: @Sendable () -> Bool = RemoteUnlock.allowsRemote
    var needsPasscode: @Sendable () -> Bool = RemoteUnlock.needsPasscode
    var bonjour = FlatdBonjour()

    @TaskLocal static var intentBudget: Deadline?

    static func intentDeadline() -> Deadline {
        #if DEBUG && ARESTIA_GATE
        // Leave room for the 120-second request measurements in the gate build.
        Deadline(after: .seconds(600))
        #else
        Deadline(after: .seconds(15))
        #endif
    }

    func run<T: Sendable>(deadline: Deadline = intentBudget ?? intentDeadline(),
                          _ work: @Sendable (FlatdClient) async throws -> T) async throws -> T {
        let pairing = try connection.current()
        let dispatch = FlatdActionDispatch()
        func execute(_ selected: FlatdClient) async throws -> T {
            var client = selected.gated(by: connection, allowsRemote: allowsRemote, needsPasscode: needsPasscode)
            client.deadline = deadline
            client.action = dispatch
            guard try connection.current().id == pairing.id else { throw FlatdError.notPaired }
            let outcome: Result<T, Error>
            do { outcome = .success(try await work(client)) } catch { outcome = .failure(error) }
            try Task.checkCancellation()
            // A response received after Forget belongs to the forgotten flat.
            guard try connection.current().id == pairing.id else { throw FlatdError.notPaired }
            let result = try outcome.get()
            connection.move(pairing, to: client)
            return result
        }

        switch try await select(pairing, deadline: deadline, homeOnly: false) {
        case .remoteDenied:
            let passcode = (try? await deadline.read(needsPasscode)) ?? false
            try Task.checkCancellation()
            throw FlatdError.awayNeedsUnlock(needsPasscode: passcode)
        case .unreachable: throw FlatdError.unreachable
        case let .reached(client):
            do {
                return try await execute(client)
            } catch let error as FlatdError {
                guard case .awayNeedsUnlock = error, client.route == .remote, !dispatch.writeStarted else { throw error }
                guard case let .reached(home) = try await select(pairing, deadline: deadline, homeOnly: true) else {
                    throw error
                }
                return try await execute(home)
            }
        }
    }

    private func select(_ pairing: FlatdPairing, deadline: Deadline, homeOnly: Bool) async throws
        -> HomeRoute.Selection<FlatdClient> {
        let remote = FlatdClient(remoteOf: pairing, transport: transport)
        let remoteProbe: (@Sendable (Deadline) async -> FlatdClient?)? = remote.map { client in
            { @Sendable cap in await Self.probe(client, within: cap, deadline: deadline) }
        }
        let home: @Sendable (Deadline) async -> FlatdClient? = { cap in
            await Self.probe(FlatdClient(pairing, transport: transport), within: cap, deadline: deadline)
        }
        let discovery: @Sendable (Deadline) async -> FlatdClient? = { cap in
            if let rediscover {
                let candidates = await rediscover().filter { $0 != pairing.baseURL }
                return await Self.find(pairing, among: candidates, transport: transport, within: cap, deadline: deadline)
            }
            return await bonjour.firstReachable { url in
                guard url != pairing.baseURL, url.scheme == "https" else { return nil }
                let client = FlatdClient(pairing, at: url, transport: transport)
                return await Self.probe(client, within: cap, deadline: deadline)
            }
        }
        let readPath: @Sendable () async -> HomeRoute.Path = path ?? {
            #if DEBUG && ARESTIA_GATE
            // The timing probe can be entered as a home pairing and reached over cellular.
            if remote == nil { return .unknown }
            #endif
            if transport != nil { return .unknown }
            return await HomeRoute.currentPath()
        }
        return try await HomeRoute.select(deadline: deadline, homeOnly: homeOnly, path: readPath,
                                          home: home, discover: discovery, remote: remoteProbe,
                                          allowsRemote: allowsRemote)
    }

    private static func probe(_ client: FlatdClient, within cap: Deadline?, deadline: Deadline?) async -> FlatdClient? {
        var client = client
        client.deadline = deadline
        return (try? await client.verify(within: cap)) != nil ? client : nil
    }

    /// A candidate address where flatd answers (its key proved, by the transport). The candidates are asked side by
    /// side and the first that answers wins, so addresses that answer slowly or not at all (forged Bonjour records)
    /// cannot use up the time before the real one is asked.
    static func find(_ pairing: FlatdPairing, among candidates: [URL],
                     transport: (any HTTPTransport & Sendable)?, within cap: Deadline? = nil,
                     deadline: Deadline? = nil) async -> FlatdClient? {
        await find(among: candidates, within: cap, deadline: deadline) {
            FlatdClient(pairing, at: $0, transport: transport)
        }
    }

    static func find(among candidates: [URL], within cap: Deadline? = nil, deadline: Deadline? = nil,
                     client: @escaping @Sendable (URL) -> FlatdClient) async -> FlatdClient? {
        await withTaskGroup(of: FlatdClient?.self) { group in
            for url in candidates.prefix(FlatdBonjour.maxCandidates) where url.scheme == "https" {
                group.addTask {
                    await probe(client(url), within: cap, deadline: deadline)
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
