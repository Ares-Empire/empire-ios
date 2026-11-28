import Network

nonisolated enum HomeRoute: Sendable {
    case home, remote

    enum Path: Sendable, Equatable { case localPossible, remoteOnly, unknown }

    enum Selection<Client: Sendable>: Sendable {
        case reached(Client)
        case remoteDenied
        case unreachable
    }

    private enum Candidate<Client: Sendable>: Sendable {
        case home(Client?)
        case discovery(Client?)
        case remoteTime
        case remote(Client?)
        case remoteDenied
    }

    /// Only health probes race. The caller sends work to the one client that wins.
    static func select<Client: Sendable>(
        deadline: Deadline, choiceLimit: Duration = .seconds(5), homeOnly: Bool = false,
        path: @escaping @Sendable () async -> Path = { await currentPath() },
        home: @escaping @Sendable (Deadline) async -> Client?,
        discover: @escaping @Sendable (Deadline) async -> Client?,
        remote: (@Sendable (Deadline) async -> Client?)?,
        allowsRemote: @escaping @Sendable () -> Bool = { true }
    ) async throws -> Selection<Client> {
        let start = deadline.clock.now()
        let choice = deadline.capped(at: start + choiceLimit)
        let routePath = homeOnly ? .localPossible :
            (try? await choice.capped(at: start + .milliseconds(100)).run(path)) ?? .unknown
        try Task.checkCancellation()
        guard choice.remaining > .zero else { return .unreachable }
        let selection: Selection<Client> = await withTaskGroup(of: Candidate<Client>.self) { group in
            var remotePending = !homeOnly && remote != nil
            var remoteDenied = false
            func startRemote() {
                guard remotePending, let remote else { return }
                remotePending = false
                group.addTask {
                    let cap = choice.capped(by: .seconds(4))
                    guard let allowed = try? await cap.read(allowsRemote) else { return .remoteDenied }
                    guard allowed else { return .remoteDenied }
                    return .remote(try? await cap.run { await remote(cap) })
                }
            }

            if routePath == .remoteOnly {
                startRemote()
            } else {
                group.addTask {
                    let cap = choice.capped(by: .milliseconds(2500))
                    return .home(try? await cap.run { await home(cap) })
                }
                group.addTask {
                    try? await choice.clock.sleepUntil(min(choice.instant, start + .milliseconds(300)))
                    return .discovery(try? await choice.run { await discover(choice) })
                }
                if remotePending {
                    group.addTask {
                        try? await choice.clock.sleepUntil(min(choice.instant, start + .milliseconds(500)))
                        return .remoteTime
                    }
                }
            }

            for await candidate in group {
                guard !Task.isCancelled else { break }
                switch candidate {
                case let .home(value?), let .discovery(value?), let .remote(value?):
                    group.cancelAll()
                    return .reached(value)
                case .home(nil), .remoteTime:
                    if choice.remaining > .zero { startRemote() }
                case .remoteDenied:
                    remoteDenied = true
                default:
                    break
                }
            }
            return remoteDenied ? .remoteDenied : .unreachable
        }
        try Task.checkCancellation()
        if case .reached = selection, choice.remaining <= .zero { return .unreachable }
        return selection
    }

    static func currentPath() async -> Path {
        let monitor = NWPathMonitor()
        let (updates, continuation) = AsyncStream<Path>.makeStream(bufferingPolicy: .bufferingNewest(1))
        monitor.pathUpdateHandler = { path in
            continuation.yield(path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
                               ? .localPossible : .remoteOnly)
        }
        monitor.start(queue: .global(qos: .userInitiated))
        defer {
            monitor.cancel()
            continuation.finish()
        }
        for await path in updates { return path }
        return .unknown
    }
}
