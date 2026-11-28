import Foundation
import os

/// One active worker per saved pairing, shared by every store that follows it.
nonisolated final class RemoteEnrollment: Sendable {
    private struct Key: Hashable, Sendable {
        let lock: ObjectIdentifier
        let pairing: UUID
    }

    private struct Signal: Sendable {
        let pin: FlatdPin
        let revision: UUID
        let address: URL
        let transport: FlatdTransportOverride?
    }

    private struct Work: Sendable {
        let loop: Task<Void, Never>
        var pending: Signal?
        var fetch: Task<FlatdClient.RemoteEnrollment, Error>?
        var stopped = false
    }

    private struct Answer: Sendable {
        let remote: RemoteListener?
        let saved: FlatdPairing
        let timeout: TimeInterval
    }

    private enum Next: Sendable { case done, retry, refetch }

    private static let active = OSAllocatedUnfairLock(initialState: [Key: Work]())
    private static let retryPause: Duration = .milliseconds(100)

    private let key: Key
    private let connection: FlatdConnection

    private init(key: Key, connection: FlatdConnection) {
        self.key = key
        self.connection = connection
    }

    @discardableResult
    static func signal(snapshot: FlatdPairing, at address: URL, connection: FlatdConnection,
                       transport: FlatdTransportOverride? = nil) -> Task<Void, Never> {
        let key = Key(lock: ObjectIdentifier(connection.lock), pairing: snapshot.id)
        let signal = Signal(pin: snapshot.pin, revision: snapshot.revision, address: address, transport: transport)
        return active.withLock { active in
            if var work = active[key] {
                if !work.stopped {
                    work.pending = signal
                    cancelFetch(&work)
                    active[key] = work
                }
                return work.loop
            }
            let owner = RemoteEnrollment(key: key, connection: connection)
            let loop = Task.detached(priority: .userInitiated) { await owner.run() }
            active[key] = Work(loop: loop, pending: signal)
            return loop
        }
    }

    /// A store may retire while the pairing is still saved. Only a confirmed identity change stops its worker.
    static func stop(for connection: FlatdConnection, except pairing: UUID?) {
        let lock = ObjectIdentifier(connection.lock)
        active.withLock { active in
            for key in active.keys where key.lock == lock && key.pairing != pairing {
                guard var work = active[key] else { continue }
                work.stopped = true
                work.pending = nil
                cancelFetch(&work)
                active[key] = work
            }
        }
    }

    private static func cancelFetch(_ work: inout Work) {
        guard let fetch = work.fetch else { return }
        work.fetch = nil
        Task.detached { fetch.cancel() }
    }

    private func run() async {
        var refetch: Signal?
        while let signal = nextSignal(or: refetch) {
            refetch = nil
            guard let answer = await refresh(signal) else { continue }
            // Finish the validated answer before a replacement refresh can stall in a read.
            committing: while isRunning {
                switch await commit(answer) {
                case .done: break committing
                case .refetch:
                    refetch = signal
                    break committing
                case .retry:
                    try? await Task.sleep(for: Self.retryPause)
                }
            }
        }
    }

    private func nextSignal(or refetch: Signal?) -> Signal? {
        Self.active.withLock { active in
            guard let work = active[key], !work.stopped, let signal = work.pending ?? refetch else {
                active.removeValue(forKey: key)
                return nil
            }
            active[key]?.pending = nil
            return signal
        }
    }

    private var isLatest: Bool {
        Self.active.withLock { $0[key]?.stopped == false && $0[key]?.pending == nil }
    }

    private var isRunning: Bool {
        Self.active.withLock { $0[key]?.stopped == false }
    }

    private func refresh(_ signal: Signal) async -> Answer? {
        while isLatest {
            switch await onWorker({ self.connection.saved }) {
            case .unreadable:
                try? await Task.sleep(for: Self.retryPause)
            case let .paired(saved) where saved.id == key.pairing && saved.pin == signal.pin:
                if saved.revision == signal.revision, saved.baseURL != signal.address {
                    if !(await move(saved, using: signal)) {
                        try? await Task.sleep(for: Self.retryPause)
                    }
                    // Re-read before the GET. Retry an unchanged revision and honor a newer saved address.
                    continue
                }
                let address = saved.revision == signal.revision ? signal.address : saved.baseURL
                let client = FlatdClient(saved, at: address, transport: signal.transport)
                    .gated(by: connection, revision: saved.revision)
                guard let fetch = startFetch(client) else { return nil }
                let answer = await fetch.result
                Self.active.withLock { $0[key]?.fetch = nil }
                switch answer {
                case let .success(.replace(remote)):
                    return Answer(remote: remote, saved: saved, timeout: client.readTimeout)
                case .failure(is FlatdGate.RevisionChanged): break
                case .failure(FlatdError.pairingUnreadable), .failure(is Deadline.Expired):
                    try? await Task.sleep(for: Self.retryPause)
                default: return nil
                }
            default: return nil // Forgotten or replaced.
            }
        }
        return nil
    }

    private func startFetch(_ client: FlatdClient) -> Task<FlatdClient.RemoteEnrollment, Error>? {
        Self.active.withLock { active in
            guard active[key]?.stopped == false, active[key]?.pending == nil else { return nil }
            let fetch = Task { try await client.remoteEnrollment() }
            active[key]?.fetch = fetch
            return fetch
        }
    }

    private func move(_ saved: FlatdPairing, using signal: Signal) async -> Bool {
        let client = FlatdClient(saved, at: signal.address, transport: signal.transport)
        return await onWorker { [self] in
            guard isLatest else { return false }
            let hold = Attempt<Void>(until: Deadline(after: .seconds(client.readTimeout)))
            return (try? connection.move(saved, to: client, hold: hold)) ?? false
        }
    }

    private func commit(_ answer: Answer) async -> Next {
        let saved = answer.saved
        let remote = answer.remote
        var updated = saved
        updated.remote = remote
        updated.revision = UUID()
        let renewed = updated
        let changed = remote?.url != saved.remote?.url || remote?.pin != saved.remote?.pin
        return await onWorker { [self] in
            guard isRunning else { return .done }
            // The Keychain CAS checks the saved revision under the dispatch lock.
            if changed {
                let hold = Attempt<Void>(until: Deadline(after: .seconds(answer.timeout)))
                do {
                    if try connection.renew(saved, with: renewed, hold: hold, isLatest: { isRunning }) { return .done }
                } catch {
                    return .retry
                }
            }
            // A rejected CAS can mean a transient Keychain failure or a newer revision.
            switch connection.saved {
            case .unreadable: return .retry
            case let .paired(current) where current.id == saved.id:
                guard current.revision == saved.revision else { return .refetch }
                return changed ? .retry : .done
            default: return .done
            }
        }
    }

    /// Wait for Security itself to return, even if a system call takes longer than the lock budget.
    private func onWorker<Value: Sendable>(_ operation: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: operation()) }
        }
    }
}
