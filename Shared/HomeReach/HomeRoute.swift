import Dispatch
import Network
import os

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
        case timeUp
        case remoteTime
        case remote(Client?)
        case remoteDenied
    }

    @TaskLocal static var admission: Admission?

    /// A nested race can close independently, and its parent can close admission for all descendants.
    final class Admission: Sendable {
        private let parent = HomeRoute.admission
        private let closed = OSAllocatedUnfairLock(initialState: false)

        var isOpen: Bool { (try? start { true }) == true }

        func start<Value>(_ probe: () throws -> Value) throws -> Value {
            func admit() throws -> Value {
                try closed.withLockUnchecked { closed in
                    guard !closed else { throw Deadline.Abandoned() }
                    return try probe()
                }
            }
            if let parent { return try parent.start(admit) }
            return try admit()
        }

        func close() { closed.withLock { $0 = true } }
    }

    private static func cancel(_ task: Task<Void, Never>) {
        DispatchQueue.global(qos: .userInitiated).async { task.cancel() }
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
        let startTime = deadline.clock.now()
        let choice = deadline.capped(at: startTime + choiceLimit)
        let routePath = homeOnly ? .localPossible :
            (try? await choice.capped(at: startTime + .milliseconds(100)).run(path)) ?? .unknown
        try Task.checkCancellation()
        let admission = Admission()
        guard choice.remaining > .zero, admission.isOpen else { return .unreachable }
        let (mailbox, messages) = AsyncStream<Candidate<Client>>.makeStream()
        var probes: [Task<Void, Never>] = []
        var pending = 0
        var remotePending = !homeOnly && remote != nil
        // If choice and the policy lookup expire together, a remote probe whose policy
        // never allowed it counts as denied whichever mailbox message arrives first.
        let remoteAllowed = OSAllocatedUnfairLock<Bool?>(initialState: nil)

        func start(_ probe: @escaping @Sendable () async -> Candidate<Client>) {
            pending += 1
            probes.append(Task {
                await $admission.withValue(admission) {
                    guard admission.isOpen, !Task.isCancelled else {
                        messages.yield(.timeUp)
                        return
                    }
                    _ = messages.yield(await probe())
                }
            })
        }

        func startRemote() {
            guard remotePending, let remote else { return }
            remotePending = false
            remoteAllowed.withLock { $0 = false }
            start {
                let cap = choice.capped(by: .seconds(4))
                guard (try? await cap.blocking({ _ in allowsRemote() })) == true else { return .remoteDenied }
                guard cap.remaining > .zero, admission.isOpen else { return .remoteDenied }
                remoteAllowed.withLock { $0 = true }
                return .remote(try? await cap.run {
                    guard admission.isOpen else { return nil }
                    return await remote(cap)
                })
            }
        }

        let timer = Task {
            do {
                try await choice.clock.sleepUntil(choice.instant)
                messages.yield(.timeUp)
            } catch {}
        }
        defer {
            admission.close()
            messages.finish()
            cancel(timer)
            probes.forEach(cancel)
        }

        if routePath == .remoteOnly {
            startRemote()
        } else {
            start {
                let cap = choice.capped(by: .milliseconds(2500))
                return .home(try? await cap.run {
                    guard admission.isOpen else { return nil }
                    return await home(cap)
                })
            }
            start {
                try? await choice.clock.sleepUntil(min(choice.instant, startTime + .milliseconds(300)))
                guard admission.isOpen, !Task.isCancelled, choice.remaining > .zero else { return .discovery(nil) }
                return .discovery(await discover(choice))
            }
            if remotePending {
                probes.append(Task {
                    do {
                        try await choice.clock.sleepUntil(min(choice.instant, startTime + .milliseconds(500)))
                        messages.yield(.remoteTime)
                    } catch {}
                })
            }
        }

        return try await withTaskCancellationHandler {
            if pending > 0 {
                for await candidate in mailbox {
                    try Task.checkCancellation()
                    if case .timeUp = candidate { break }
                    guard choice.remaining > .zero else { break }
                    if case .remoteTime = candidate { startRemote(); continue }
                    pending -= 1
                    switch candidate {
                    case let .home(value?), let .discovery(value?), let .remote(value?):
                        return .reached(value)
                    case .home(nil):
                        startRemote()
                    default:
                        break
                    }
                    if pending == 0 { break }
                }
            }
            try Task.checkCancellation()
            return remoteAllowed.withLock { $0 } == false ? .remoteDenied : .unreachable
        } onCancel: {
            admission.close()
        }
    }

    /// First non-nil result wins. A cancelled or stalled operation is never awaited.
    static func first<Value: Sendable>(_ operations: [@Sendable () async -> Value?]) async -> Value? {
        let admission = Admission()
        guard admission.isOpen, !Task.isCancelled else { return nil }
        let (mailbox, messages) = AsyncStream<Value?>.makeStream()
        let tasks = operations.map { operation in
            Task {
                await $admission.withValue(admission) {
                    guard admission.isOpen, !Task.isCancelled else {
                        messages.yield(nil)
                        return
                    }
                    _ = messages.yield(await operation())
                }
            }
        }
        defer {
            admission.close()
            messages.finish()
            tasks.forEach(cancel)
        }
        return await withTaskCancellationHandler {
            var replies = mailbox.makeAsyncIterator()
            for _ in operations {
                guard !Task.isCancelled, let result = await replies.next(), !Task.isCancelled else { break }
                if let result { return result }
            }
            return nil
        } onCancel: {
            admission.close()
        }
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
