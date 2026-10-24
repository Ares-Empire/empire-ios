import Foundation
import Observation

/// The app's data: the overview, province details cached by slug, the sync overview and run details. Each part loads on
/// its own, keeps its last good answer when a refresh fails, and is forgotten on logout or when access is denied.
/// The screens on view refresh every `interval` and when the app comes to the foreground (`AresusTabs`).
@MainActor @Observable
final class AresusStore {
    enum Part: Hashable, Sendable {
        case overview, province(String), sync, run(Int)
    }

    /// How often the visible data refreshes while the app is open.
    static let interval: TimeInterval = 60

    private(set) var overview: Overview?
    private(set) var provinces: [String: ProvinceDetail] = [:]
    private(set) var sync: SyncOverview?
    private(set) var runs: [Int: RunDetail] = [:]
    private(set) var loading: Set<Part> = []
    private(set) var errors: [Part: String] = [:]
    private(set) var loadedAt: [Part: Date] = [:]
    let session: EmpireSession
    /// The app's "now": the real clock, or the samples' moment (plus the time since launch) in sample mode.
    let clock: AresusClock
    private(set) var samples: AresusSamples?
    private let client: AresusAPI
    private var resetGeneration = 0
    private var foregroundRefreshing = false

    var isSample: Bool { samples != nil }

    init(session: EmpireSession, client: AresusAPI = AresusAPI(), samples: AresusSamples? = nil, launched: Date = .now) {
        self.session = session
        self.client = client
        #if DEBUG
        let samples = samples
        #else
        let samples: AresusSamples? = nil
        #endif
        self.samples = samples
        if let sampleNow = try? samples?.now() {
            clock = AresusClock(offset: sampleNow.timeIntervalSince(launched))
        } else {
            clock = AresusClock()
        }
        session.onAppDataReset { [weak self] in self?.clear() }
    }

    func isLoading(_ part: Part) -> Bool { loading.contains(part) }
    func error(_ part: Part) -> String? { errors[part] }

    /// Loads one part now (one request per part at a time).
    func load(_ part: Part) async {
        guard !loading.contains(part), isSample || session.isSignedIn else { return }
        loading.insert(part)
        errors[part] = nil
        let context = context
        defer { if isCurrent(context) { loading.remove(part) } }
        do {
            switch part {
            case .overview:
                let value = try await fetch({ try $0.overview() }, { try await client.overview(token: $0) })
                guard isCurrent(context) else { return }
                overview = value
            case .province(let slug):
                let value = try await fetch({ try $0.province(slug) }, { try await client.province(slug, token: $0) })
                guard isCurrent(context) else { return }
                provinces[slug] = value
            case .sync:
                let value = try await fetch({ try $0.sync() }, { try await client.sync(token: $0) })
                guard isCurrent(context) else { return }
                sync = value
            case .run(let id):
                let value = try await fetch({ try $0.run(id) }, { try await client.run(id, token: $0) })
                guard isCurrent(context) else { return }
                runs[id] = value
            }
            loadedAt[part] = .now
        } catch {
            guard isCurrent(context) else { return }
            session.handleAuthFailure(error, generation: context.session)
            guard isCurrent(context) else { return }
            errors[part] = message(for: error, part: part)
        }
    }

    /// Loads the parts that were never loaded or are at least `age` seconds old.
    func refresh(_ parts: [Part], olderThan age: TimeInterval = 0, now: Date = .now) async {
        for part in parts where loadedAt[part].map({ now.timeIntervalSince($0) >= age }) ?? true {
            await load(part)
        }
    }

    /// Coming to the foreground: renew a login older than 12 hours (as the Empire app), then refresh what is on
    /// screen unless it just loaded.
    func refreshOnForeground(visible parts: [Part], now: Date = .now) async {
        guard !isSample, session.isSignedIn, !session.isBusy, !foregroundRefreshing else { return }
        foregroundRefreshing = true
        let context = context
        defer { if isCurrent(context) { foregroundRefreshing = false } }
        if session.lastRenewedAt.map({ now.timeIntervalSince($0) > 12 * 60 * 60 }) ?? true {
            await session.restore()
            guard isCurrent(context), session.isSignedIn, !session.needsRestoreRetry else { return }
        }
        await refresh(parts, olderThan: 10, now: now)
    }

    /// Forgets everything (logout, access denied); answers still on their way are dropped.
    func clear() {
        resetGeneration += 1
        overview = nil
        provinces = [:]
        sync = nil
        runs = [:]
        loading = []
        errors = [:]
        loadedAt = [:]
        foregroundRefreshing = false
    }

    #if DEBUG
    /// Logging out of sample mode: the real login takes over.
    func leaveSample() {
        samples = nil
        clear()
    }
    #endif

    // MARK: private

    private var context: Context { Context(session: session.generation, reset: resetGeneration) }
    private struct Context { let session: Int; let reset: Int }
    private func isCurrent(_ context: Context) -> Bool {
        context.session == session.generation && context.reset == resetGeneration
    }

    private func fetch<T>(_ sample: (AresusSamples) throws -> T, _ remote: (String) async throws -> T) async throws -> T {
        if let samples { return try sample(samples) }
        guard session.isSignedIn, let token = session.token else { throw HTTPError.unauthorized }
        return try await remote(token)
    }

    private func message(for error: Error, part: Part) -> String {
        switch (error, part) {
        case (HTTPError.server(404, _), .province): "Aresus does not watch this province."
        case (HTTPError.server(404, _), .run): "This run is no longer kept."
        case (is DecodingError, _): "The server's answer could not be read."
        case (let error as URLError, _) where error.code == .notConnectedToInternet: "No connection."
        default: error.localizedDescription
        }
    }
}

/// The app's "now". In sample mode it runs from the samples' moment, so relative times read as they would live.
nonisolated struct AresusClock: Sendable {
    var offset: TimeInterval = 0
    func now(_ real: Date = .now) -> Date { real.addingTimeInterval(offset) }
}
