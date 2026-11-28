import Foundation
import os

nonisolated final class PinnedSession: Sendable {
    private let sessions = OSAllocatedUnfairLock<[SPKIPin: URLSession]>(initialState: [:])
    private let requestTimeout: TimeInterval?
    private let resourceTimeout: TimeInterval?

    init(requestTimeout: TimeInterval? = nil, resourceTimeout: TimeInterval? = nil) {
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
    }

    /// Reuse one HTTP session per pin. A connection authenticated with one pin cannot carry another pin's requests.
    func shared(pin: SPKIPin) -> URLSession {
        sessions.withLock { sessions in
            if let session = sessions[pin] { return session }
            let configuration = Self.configuration()
            if let requestTimeout { configuration.timeoutIntervalForRequest = requestTimeout }
            if let resourceTimeout { configuration.timeoutIntervalForResource = resourceTimeout }
            let session = URLSession(configuration: configuration, delegate: PinnedServer(pin: pin),
                                     delegateQueue: nil)
            sessions[pin] = session
            return session
        }
    }

    private static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        return configuration
    }

    /// The long-lived event stream has its own session and idle timeout.
    static func events(pin: SPKIPin, requestTimeout: TimeInterval) -> URLSession {
        let configuration = configuration()
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration, delegate: PinnedServer(pin: pin), delegateQueue: nil)
    }
}
