import Foundation
import os

/// flatd's event stream (`/api/events`): a snapshot on connect, then one message per change. Behind a protocol, so the
/// store's tests feed it made-up events.
nonisolated protocol FlatEventSource: Sendable {
    /// The events until the connection ends: the stream finishes with `FlatdError.refused` on a 401 and
    /// `FlatdError.unreachable` on anything else (the store then tries again), a server without flatd's key included.
    func events(from request: URLRequest, pin: FlatdPin, starting: (() -> Void) throws -> Void)
        throws -> AsyncThrowingStream<FlatEvent, Error>
}

/// The real stream over a WebSocket. A sleeping Mac leaves a socket open without answering, so a ping goes every
/// 20 s and a missing pong ends the stream.
nonisolated struct WebSocketEvents: FlatEventSource {
    static let pingEvery: Duration = .seconds(20)
    /// flatd sends its snapshot at once; a stream without one this long is not flatd's (or flatd is stuck): it ends.
    #if DEBUG && ARESTIA_GATE
    static let snapshotWithin = FlatdRequestTimeout.duration
    #else
    static let snapshotWithin: Duration = .seconds(10)
    #endif
    private static let log = Logger(subsystem: "de.ares-empire.arestia", category: "events")

    #if DEBUG
    func events(from request: URLRequest, pin: FlatdPin) -> AsyncThrowingStream<FlatEvent, Error> {
        do { return try events(from: request.withLanguage(), pin: pin, starting: { $0() }) }
        catch { return AsyncThrowingStream { $0.finish(throwing: error) } }
    }
    #endif

    func events(from request: URLRequest, pin: FlatdPin, starting: (() -> Void) throws -> Void)
        throws -> AsyncThrowingStream<FlatEvent, Error> {
        // The key is in the header. The session accepts only a server holding flatd's key.
        guard request.url?.scheme?.lowercased() == "wss" else { throw FlatdError.unreachable }
        let session = FlatdSession.events(pin: pin)
        let task = session.webSocketTask(with: request)
        do { try starting { task.resume() } }
        catch {
            session.invalidateAndCancel()
            throw error
        }
        Self.log.notice("events: connecting")

        return AsyncThrowingStream { continuation in
            let snapshotSeen = OSAllocatedUnfairLock(initialState: false)
            let reader = Task {
                do {
                    while !Task.isCancelled {
                        let message = try await task.receive()
                        let data: Data? = switch message {
                        case let .data(data): data
                        case let .string(text): Data(text.utf8)
                        @unknown default: nil
                        }
                        if let data, let event = FlatEvent.decode(data) {
                            if case .snapshot = event { snapshotSeen.withLock { $0 = true } }
                            continuation.yield(event)
                        } else {
                            Self.log.error("an event did not decode (\(data?.count ?? 0, privacy: .public) bytes)")
                        }
                    }
                } catch {
                    let status = (task.response as? HTTPURLResponse)?.statusCode
                    Self.log.notice("events ended (\(status ?? 0, privacy: .public))")
                    continuation.finish(throwing: status == 401 ? FlatdError.refused : FlatdError.unreachable)
                }
            }
            let deadline = Task {
                try? await Task.sleep(for: Self.snapshotWithin)
                guard !Task.isCancelled, !snapshotSeen.withLock({ $0 }) else { return }
                Self.log.notice("no snapshot in time: the stream ends")
                task.cancel(with: .goingAway, reason: nil)
                continuation.finish(throwing: FlatdError.unreachable)
            }
            let pinger = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.pingEvery)
                    guard !Task.isCancelled else { return }
                    let answered = await Self.ping(task)
                    if !answered {
                        Self.log.notice("no pong: the stream is gone")
                        task.cancel(with: .goingAway, reason: nil)
                        continuation.finish(throwing: FlatdError.unreachable)
                        return
                    }
                }
            }
            continuation.onTermination = { _ in
                reader.cancel()
                deadline.cancel()
                pinger.cancel()
                task.cancel(with: .normalClosure, reason: nil)
                session.invalidateAndCancel()
            }
        }
    }

    /// A ping that counts as lost after 8 s.
    private static func ping(_ task: URLSessionWebSocketTask) async -> Bool {
        let answered = OSAllocatedUnfairLock<Bool?>(initialState: nil)
        return await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            let finish: @Sendable (Bool) -> Void = { value in
                let first = answered.withLock { state -> Bool in
                    guard state == nil else { return false }
                    state = value
                    return true
                }
                if first { done.resume(returning: value) }
            }
            task.sendPing { error in finish(error == nil) }
            Task {
                #if DEBUG && ARESTIA_GATE
                try? await Task.sleep(for: FlatdRequestTimeout.duration)
                #else
                try? await Task.sleep(for: .seconds(8))
                #endif
                finish(false)
            }
        }
    }
}
