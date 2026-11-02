import Foundation

/// Distinguishes a retried upload from a late completion for an older task of the same queued file.
nonisolated struct DropUploadID: Equatable, Sendable {
    let record: UUID
    let attempt: UUID
    var description: String { record.uuidString + ":" + attempt.uuidString }
    init(record: UUID, attempt: UUID = UUID()) { self.record = record; self.attempt = attempt }
    init?(_ description: String?) {
        guard let parts = description?.split(separator: ":"), parts.count == 2,
              let record = UUID(uuidString: String(parts[0])), let attempt = UUID(uuidString: String(parts[1])) else { return nil }
        self.record = record; self.attempt = attempt
    }
}

/// App-only background preparation time (copy/hash/POST). The extension supplies no application object.
@MainActor
protocol DropActivity: AnyObject {
    func observe(active: @escaping @MainActor () -> Void, expiring: @escaping @MainActor () -> Void)
    func begin()
    func end()
}

@MainActor
protocol DropUploading: AnyObject {
    var identifier: String { get }
    var supportsDeferredRetry: Bool { get }
    var completed: ((DropUploadID, Result<Drop, Error>, String?) async -> Void)? { get set }
    func submit(_ id: DropUploadID, request: URLRequest, file: URL, earliestBeginDate: Date?) async throws
    func cancel(_ id: UUID) async
    func activeIDs() async -> Set<UUID>
}

extension DropUploading {
    var supportsDeferredRetry: Bool { false }
}

/// The only production upload path. Both executables use it, with distinct identifiers because iOS permits only one
/// process to own a background session at a time. The app reconnects the exact identifier iOS hands its delegate.
/// Task descriptions contain only a local UUID; credentials stay in the authenticated request, never in our journal.
@MainActor
final class DropBackgroundUploads: NSObject, DropUploading, URLSessionDataDelegate {
    private static var liveDrivers: [String: DropBackgroundUploads] = [:]
    static func live() -> DropBackgroundUploads {
        driver(identifier: DropContainer.uploadSession)
    }
    static func driver(identifier id: String) -> DropBackgroundUploads {
        if let driver = liveDrivers[id] { return driver }
        let driver = DropBackgroundUploads(identifier: id)
        liveDrivers[id] = driver
        return driver
    }
    weak var outbox: DropOutbox?
    let identifier: String
    var supportsDeferredRetry: Bool { true }
    var completed: ((DropUploadID, Result<Drop, Error>, String?) async -> Void)?
    var finishedEvents: (() -> Void)?
    private var responses: [Int: Data] = [:]
    private var delivery: Task<Void, Never>?
    private var pending = Set<UUID>()
    private var urlSession: URLSession!

    static func configuration(identifier: String) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sharedContainerIdentifier = DropContainer.appGroup
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.waitsForConnectivity = true
        return configuration
    }

    init(identifier: String = DropContainer.uploadSession) {
        self.identifier = identifier
        super.init()
        urlSession = URLSession(configuration: Self.configuration(identifier: identifier), delegate: self, delegateQueue: .main)
    }

    func submit(_ id: DropUploadID, request: URLRequest, file: URL, earliestBeginDate: Date?) async throws {
        let task = urlSession.uploadTask(with: request.withLanguage(), fromFile: file)
        task.taskDescription = id.description
        task.earliestBeginDate = earliestBeginDate
        task.resume()
    }

    func activeIDs() async -> Set<UUID> {
        Set(await urlSession.allTasks.compactMap { DropUploadID($0.taskDescription)?.record }).union(pending)
    }

    func cancel(_ id: UUID) async {
        for task in await urlSession.allTasks where DropUploadID(task.taskDescription)?.record == id { task.cancel() }
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // delegateQueue is the main queue; recording data synchronously preserves the completion ordering.
        MainActor.assumeIsolated {
            // Drop responses are small JSON, never the uploaded file. Cap an invalid server's response too.
            if (responses[dataTask.taskIdentifier]?.count ?? 0) + data.count <= 1_048_576 {
                responses[dataTask.taskIdentifier, default: Data()].append(data)
            } else { dataTask.cancel() }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        MainActor.assumeIsolated {
            guard let id = DropUploadID(task.taskDescription) else { return }
            let data = responses.removeValue(forKey: task.taskIdentifier) ?? Data()
            let result = Self.result(data: data, response: task.response as? HTTPURLResponse, error: error)
            let token = task.originalRequest?.value(forHTTPHeaderField: "Authorization").flatMap {
                $0.hasPrefix("Bearer ") ? String($0.dropFirst(7)) : nil
            }
            deliver(id, result: result, token: token)
        }
    }

    /// Also exercised directly by tests, including a completion delivered to a newly opened process.
    func deliver(_ id: DropUploadID, result: Result<Drop, Error>, token: String?) {
        pending.insert(id.record)
        let previous = delivery
        delivery = Task { [self] in
            defer { pending.remove(id.record) }
            await previous?.value
            await completed?(id, result, token)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        MainActor.assumeIsolated { finishEvents() }
    }

    func invalidate() { urlSession.finishTasksAndInvalidate() }

    nonisolated func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        MainActor.assumeIsolated {
            completed = nil; outbox = nil
            if Self.liveDrivers[identifier] === self { Self.liveDrivers[identifier] = nil }
        }
    }

    func finishEvents() {
        let pending = delivery
        Task { [self] in
            await pending?.value
            let finish = finishedEvents
            finishedEvents = nil
            finish?()
        }
    }

    static func result(data: Data, response: HTTPURLResponse?, error: Error?) -> Result<Drop, Error> {
        Result {
            if let error { throw error }
            guard let response else { throw HTTPError.invalidResponse }
            try checkResponse(response, data: data, onUnauthorized: {})
            return try AresusJSON.decoder().decode(Drop.self, from: data)
        }
    }
}
