import Foundation
import os

/// flatd's event stream (`/api/events`): a snapshot on connect, then one message per change. Behind a protocol, so the
/// store's tests feed it made-up events.
protocol FlatEventSource: Sendable {
    /// The events until the connection ends: the stream finishes with `FlatdError.refused` on a 401 and
    /// `FlatdError.unreachable` on anything else (the store then tries again).
    func events(from url: URL) -> AsyncThrowingStream<FlatEvent, Error>
}

/// The real stream over a WebSocket. A sleeping Mac leaves a socket open without answering, so a ping goes every
/// 20 s and a missing pong ends the stream.
nonisolated struct WebSocketEvents: FlatEventSource {
    static let pingEvery: Duration = .seconds(20)
    private static let log = Logger(subsystem: "de.ares-empire.arestia", category: "events")

    func events(from url: URL) -> AsyncThrowingStream<FlatEvent, Error> {
        AsyncThrowingStream { continuation in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 3600      // idle: liveness comes from the pings
            configuration.waitsForConnectivity = false
            let session = URLSession(configuration: configuration)
            var request = URLRequest(url: url, timeoutInterval: 8)
            request.setValue(AppLanguage.current.code, forHTTPHeaderField: "Accept-Language")
            let task = session.webSocketTask(with: request)
            task.resume()
            Self.log.notice("events: connecting")

            let reader = Task {
                do {
                    while !Task.isCancelled {
                        let message = try await task.receive()
                        Self.log.debug("events: a message")
                        let data: Data? = switch message {
                        case let .data(data): data
                        case let .string(text): Data(text.utf8)
                        @unknown default: nil
                        }
                        if let data, let event = FlatEvent.decode(data) {
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
                try? await Task.sleep(for: .seconds(8))
                finish(false)
            }
        }
    }
}
