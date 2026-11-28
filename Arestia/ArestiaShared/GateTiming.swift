#if DEBUG && ARESTIA_GATE
import Foundation
import os

/// One action's timestamps. Only fixed action names and error cases reach either log.
nonisolated final class GateAction: Sendable {
    @TaskLocal static var current: GateAction?

    let id = UUID()
    private let name: String
    private let dispatched = OSAllocatedUnfairLock(initialState: false)
    let isFanBatch: Bool

    init(_ name: String, isFanBatch: Bool = false) {
        self.name = name
        self.isFanBatch = isFanBatch
        record("intent entry")
    }

    func claimDispatch() -> Bool {
        dispatched.withLock { didDispatch in
            guard !didDispatch else { return false }
            didDispatch = true
            return true
        }
    }

    func dispatch(at time: Date) { record("dispatch", at: time) }
    func completion(_ outcome: GateOutcome, at time: Date = .now) {
        record("completion", outcome: outcome, at: time)
    }
    func fansSettled(_ outcome: GateOutcome) {
        guard isFanBatch, dispatched.withLock({ $0 }) else { return }
        completion(outcome)
    }
    func resultReturned(_ outcome: GateOutcome) { record("result returned", outcome: outcome) }
    func ended(_ outcome: GateOutcome) { record("action ended", outcome: outcome) }

    static func cooking(_ id: String?) -> GateAction? {
        id == FlatMode.cookingID ? GateAction("InAppCooking") : nil
    }

    private func record(_ stamp: String, outcome: GateOutcome? = nil, at time: Date = .now) {
        let utc = time.ISO8601Format(.iso8601(timeZone: .gmt, includingFractionalSeconds: true)
            .timeZone(separator: .colon))
        var fields = [utc, id.uuidString, name, stamp]
        if let outcome { fields.append(outcome.rawValue) }
        GateTimingLog.append(fields.joined(separator: "\t"))
    }
}

nonisolated enum GateOutcome: String, Sendable {
    case ok, cancelled, unreachable, noAnswer, refused, unknown, deviceDidNotAnswer, notPossible, failed
    case invalidAnswer, notPaired, pairingUnreadable, anotherFlat, renameNotSupported, chosenDeviceGone
    case awayNeedsUnlock, partialFans, unexpectedError

    // The transport records the HTTP result before the caller decodes it or updates its UI.
    init(_ result: Result<(Data, HTTPURLResponse), Error>, cancelled: Bool) {
        switch result {
        case let .success((_, response)):
            self = switch response.statusCode {
            case 200..<300: .ok
            case 401: .refused
            case 404: .unknown
            case 409: .notPossible
            case 504: .deviceDidNotAnswer
            default: .failed
            }
        case let .failure(error):
            switch (error as? URLError)?.code {
            case .timedOut: self = .noAnswer
            case .cancelled: self = cancelled ? .cancelled : .unreachable
            default: self = .unreachable
            }
        }
    }

    init(_ error: Error) {
        if error is CancellationError {
            self = .cancelled
        } else if error is ChosenDeviceGone {
            self = .chosenDeviceGone
        } else if let error = error as? FlatdError {
            self = switch error {
            case .unreachable: .unreachable
            case .awayNeedsUnlock: .awayNeedsUnlock
            case .partialFans: .partialFans
            case .noAnswer: .noAnswer
            case .refused: .refused
            case .unknown: .unknown
            case .deviceDidNotAnswer: .deviceDidNotAnswer
            case .notPossible: .notPossible
            case .failed: .failed
            case .invalidAnswer: .invalidAnswer
            case .notPaired: .notPaired
            case .pairingUnreadable: .pairingUnreadable
            case .anotherFlat: .anotherFlat
            case .renameNotSupported: .renameNotSupported
            }
        } else {
            self = .unexpectedError
        }
    }
}

nonisolated enum GateTimingLog {
    private static let logger = Logger(subsystem: "de.ares-empire.arestia", category: "gate-timing")
    static let file = ArestiaGroup.folder?.appending(path: "arestia-gate-timing.txt")
    // The app and the extension use the same lock for append, read and clear. Each stamp is written synchronously.
    private static let lock = ArestiaGroup.folder.map {
        FlatdDispatchLock(path: $0.appending(path: "arestia-gate-timing.lock").path(percentEncoded: false))
    }

    private static let queue = DispatchQueue(label: "de.ares-empire.arestia.gate-timing")

    static func append(_ line: String) {
        logger.notice("\(line, privacy: .public)")
        let cap = Deadline(after: .seconds(6))
        queue.async {
            let hold = Attempt<Void>(until: cap)
            do {
                try access(hold) { file in
                    try hold.commit {}
                    if !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                        try Data().write(to: file, options: .completeFileProtectionUntilFirstUserAuthentication)
                    }
                    let handle = try FileHandle(forWritingTo: file)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: Data((line + "\n").utf8))
                }
            } catch {
                logger.error("Could not append to the gate timing file")
            }
        }
    }

    static func newestFirst() async throws -> [String] {
        try await Deadline(after: .seconds(6)).blocking { hold in
            try queue.sync {
                try access(hold) { file in
                    do {
                        return try String(contentsOf: file, encoding: .utf8)
                            .split(separator: "\n").reversed().map(String.init)
                            .sorted { $0.prefix(24) > $1.prefix(24) }
                    } catch CocoaError.fileReadNoSuchFile {
                        return []
                    }
                }
            }
        }
    }

    static func clear() async throws {
        try await Deadline(after: .seconds(6)).blocking { hold in
            try queue.sync {
                try access(hold) { file in
                    try hold.commit {}
                    do { try FileManager.default.removeItem(at: file) } catch CocoaError.fileNoSuchFile {}
                }
            }
        }
    }

    private static func access<T>(_ hold: Hold, _ work: (URL) throws -> T) throws -> T {
        guard let file, let lock else { throw CocoaError(.fileNoSuchFile) }
        return try lock.withLock(until: hold.deadline, hold: hold) { try work(file) }
    }
}
#endif
