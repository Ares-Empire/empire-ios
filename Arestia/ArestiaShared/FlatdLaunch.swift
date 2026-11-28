import Foundation

nonisolated protocol SuspendedRequest: Sendable {
    func resume()
    func cancel()
    func afterResume()
}

nonisolated extension SuspendedRequest {
    func afterResume() {}
}

nonisolated protocol PreparingTransport: Sendable {
    func prepare(_ request: URLRequest, reply: Attempt<HTTPReply>) throws -> any SuspendedRequest
}

typealias HTTPReply = (Data, HTTPURLResponse)

nonisolated enum FlatdAdmission: Sendable {
    case open
    case gated(FlatdGate)
}

nonisolated struct WriteRule: Sendable {
    let cap: Deadline
    var deadline: Deadline? = nil
    var isWrite = false
    var action: FlatdActionDispatch? = nil

    fileprivate func check() throws {
        try cap.check()
        if isWrite, let deadline, deadline.remaining < .seconds(3) { throw FlatdError.unreachable }
    }

    fileprivate func start(_ request: any SuspendedRequest) {
        if isWrite { action?.startingWrite() }
        request.resume()
    }
}

nonisolated enum FlatdLaunch {
    /// The completion captures any typed value to hand off after dispatch, such as a prepared event stream.
    struct Prepared<Value: Sendable>: Sendable {
        let request: any SuspendedRequest
        var afterStart: @Sendable (Attempt<Value>) -> Void = { _ in }
    }

    static func run<Value: Sendable>(
        admission: FlatdAdmission, rule: WriteRule,
        prepare: @escaping @Sendable (Attempt<Value>) throws -> Prepared<Value>,
        didResume: @escaping @Sendable () -> Void = {}
    ) async -> Attempt<Value>.Outcome {
        let attempt = Attempt<Value>(until: rule.cap)
        return await rule.cap.wait(for: attempt) {
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    guard attempt.isLive else { return }
                    let prepared = try prepare(attempt)
                    let request = prepared.request
                    attempt.onFailure { request.cancel() }
                    switch admission {
                    case .open:
                        try attempt.commit {
                            try rule.check()
                            rule.start(request)
                        }
                    case let .gated(gate):
                        try gate.admit(attempt, rule: rule, request: request)
                    }
                    request.afterResume()
                    didResume()
                    prepared.afterStart(attempt)
                } catch {
                    attempt.end(.failure(error))
                }
            }
        }
    }
}

nonisolated struct RemoteMarker: Sendable {
    let read: @Sendable () -> Bool
    static let live = RemoteMarker(read: RemoteUnlock.allowsRemote)

    #if DEBUG
    init(read: @escaping @Sendable () -> Bool) { self.read = read }
    #else
    private init(read: @escaping @Sendable () -> Bool) { self.read = read }
    #endif
}

/// Admission shares the lock used to change or delete the saved pairing.
nonisolated struct FlatdGate: Sendable {
    struct RemoteDenied: Error {}
    private static let markerAge: Duration = .seconds(1)

    let connection: FlatdConnection
    let pairing: UUID
    let route: HomeRoute
    let pin: FlatdPin
    let baseURL: URL
    let savedToken: String
    let remoteGeneration: UUID?
    let marker: RemoteMarker

    fileprivate func admit<Value>(_ attempt: Attempt<Value>, rule: WriteRule, request: any SuspendedRequest) throws {
        do {
            try connection.lock.withLock(until: rule.cap, hold: attempt) {
                let saved = try connection.current()
                guard saved.id == pairing else { throw FlatdError.notPaired }
                guard saved.matches(route: route, pin: pin, url: baseURL, token: savedToken,
                                    remoteGeneration: remoteGeneration) else { throw FlatdError.unreachable }
                try attempt.check()
                if route == .remote {
                    let clock = rule.cap.clock
                    let freshUntil = clock.now() + Self.markerAge
                    let timer = Task {
                        do {
                            try await clock.sleepUntil(freshUntil)
                            attempt.endBeforeCommit(with: RemoteDenied())
                        } catch {}
                    }
                    defer { timer.cancel() }
                    guard marker.read() else { throw RemoteDenied() }
                    try attempt.commit {
                        try rule.check()
                        guard clock.now() < freshUntil else { throw RemoteDenied() }
                        rule.start(request)
                    }
                } else {
                    try attempt.commit {
                        try rule.check()
                        rule.start(request)
                    }
                }
            }
        } catch is FlatdDispatchLock.Unavailable {
            throw FlatdError.pairingUnreadable
        }
    }
}
