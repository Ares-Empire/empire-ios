import Foundation
import Observation

/// One reversible local action. Only expiry/replacement of the undo offer or leaving the foreground sends it.
nonisolated enum BoardAction: Equatable, Sendable {
    case answer(String), done, drop

    func message(language: AppLanguage = .current) -> String {
        switch self {
        case .answer(let answer): language.string("Answered: \(answer)")
        case .done: language.string("Done")
        case .drop: language.string("Set aside")
        }
    }
}

@MainActor @Observable
final class BoardStore {
    private(set) var waiting: BoardWaiting?
    private(set) var loading = false
    private(set) var loadedAt: Date?
    private(set) var error: String?
    private(set) var notice: String?
    private(set) var failed: Set<Int> = []
    var undoOffer: UndoOffer?
    private var pending: Pending?
    private var hidden: Set<Int> = []
    private var generation = 0
    private var revision = 0
    private var refreshAgain = false
    let clock: AresusClock
    private let session: EmpireSession
    private let client: AresusAPI
    private var samples: AresusSamples?
    private var sampleValue: BoardWaiting?
    private var failNextSend: Bool

    var asks: [BoardItem] { (waiting?.asks ?? []).filter { !hidden.contains($0.id) } }
    var badgeCount: Int { asks.count }

    init(session: EmpireSession, client: AresusAPI = AresusAPI(), samples: AresusSamples? = nil,
         failNextSend: Bool = false) {
        let sampleNow = (try? samples?.boardWaiting().asks.first?.created)?.addingTimeInterval(7200)
        clock = AresusClock(offset: sampleNow.map { $0.timeIntervalSinceNow } ?? 0)
        self.session = session
        self.client = client
        self.samples = samples
        self.failNextSend = failNextSend
        session.onAppDataReset { [weak self] in self?.clear() }
    }

    func refresh(olderThan age: TimeInterval = 0, now: Date = .now) async {
        if loading {
            if age == 0 { refreshAgain = true }
            return
        }
        guard samples != nil || session.isSignedIn,
              loadedAt.map({ now.timeIntervalSince($0) >= age }) ?? true else { return }
        let epoch = generation
        let login = session.generation
        let token = session.token
        let version = revision
        loading = true
        error = nil
        defer {
            if epoch == generation {
                loading = false
                if refreshAgain {
                    refreshAgain = false
                    Task { [weak self] in await self?.refresh() }
                }
            }
        }
        do {
            let answer: BoardWaiting
            if let samples {
                if sampleValue == nil { sampleValue = try samples.boardWaiting() }
                answer = sampleValue ?? .empty
            } else {
                guard let token else { throw HTTPError.unauthorized }
                answer = try await client.boardWaiting(token: token)
            }
            guard epoch == generation, login == session.generation, version == revision else { return }
            waiting = answer
            failed.formIntersection(Set(answer.asks.map(\.id)))
            loadedAt = .now
        } catch {
            guard epoch == generation, login == session.generation else { return }
            session.handleAuthFailure(error, generation: login, token: token)
            guard epoch == generation else { return }
            self.error = error is DecodingError ? String(localized: "The server's answer could not be read.") : error.localizedDescription
        }
    }

    /// Replacing an offer commits the preceding action, while the new card immediately leaves the visible list.
    func perform(_ action: BoardAction, on item: BoardItem) {
        guard item.kind == .ask, item.state == .open, asks.contains(where: { $0.id == item.id }) else { return }
        if case .answer(let text) = action, BoardWords.ownAnswer(text) == nil { return }
        if action == .done, !item.options.isEmpty { return }
        if let previous = takePending() { Task { await send(previous) } }
        let entry = Pending(item: item, action: action, index: waiting?.asks.firstIndex(where: { $0.id == item.id }) ?? 0,
                            generation: generation, login: session.generation)
        pending = entry
        hidden.insert(item.id)
        failed.remove(item.id)
        notice = nil
        revision += 1
        undoOffer = UndoOffer(message: action.message(), onDismiss: { [weak self] in
            guard let self, self.pending?.id == entry.id, let pending = self.takePending() else { return }
            Task { await self.send(pending) }
        }, undoImmediately: { [weak self] in self?.undo(entry.id) })
    }

    /// Called at .inactive, including opening Claude. Taking the entry before awaiting prevents double sends.
    func leavingForeground() async {
        if let entry = takePending() { await send(entry) }
    }

    /// The undo bar's time elapsed. Also exposed for deterministic store tests, without sleeping through the bar.
    func commitPending() async {
        if let entry = takePending() { await send(entry) }
    }

    private func takePending() -> Pending? {
        guard let entry = pending else { return nil }
        pending = nil
        undoOffer = nil
        return entry
    }

    private func undo(_ id: UUID) {
        guard let entry = pending, entry.id == id else { return }
        pending = nil
        undoOffer = nil
        hidden.remove(entry.item.id)
        restore(entry)
        revision += 1
    }

    private func send(_ entry: Pending) async {
        guard entry.generation == generation, entry.login == session.generation else { return }
        let epoch = generation
        let login = session.generation
        let token = session.token
        do {
            let answer: BoardItem
            if samples != nil {
                if failNextSend {
                    failNextSend = false
                    throw URLError(.notConnectedToInternet)
                }
                var item = entry.item
                item.updated = clock.now()
                switch entry.action {
                case .answer(let text): item.state = .answered; item.answer = text
                case .done: item.state = .done
                case .drop: item.state = .dropped
                }
                answer = item
            } else {
                guard session.isSignedIn, let token else { throw HTTPError.unauthorized }
                switch entry.action {
                case .answer(let text): answer = try await client.boardAnswer(entry.item.id, answer: text, token: token)
                case .done: answer = try await client.boardDone(entry.item.id, token: token)
                case .drop: answer = try await client.boardDrop(entry.item.id, token: token)
                }
            }
            guard epoch == generation, login == session.generation else { return }
            remove(entry.item.id)
            if answer.kind == .ask, answer.state == .answered {
                waiting?.answered.append(answer)
                waiting?.answered.sort { $0.updated > $1.updated }
            }
            if samples != nil { sampleValue = waiting }
        } catch {
            guard epoch == generation, login == session.generation else { return }
            session.handleAuthFailure(error, generation: login, token: token)
            guard epoch == generation else { return }
            switch error {
            case HTTPError.server(404, _): remove(entry.item.id)
            case HTTPError.server(409, _):
                remove(entry.item.id)
                notice = String(localized: "Already answered elsewhere.")
                await refresh()
            default:
                hidden.remove(entry.item.id)
                restore(entry)
                failed.insert(entry.item.id)
                revision += 1
            }
        }
    }

    private func restore(_ entry: Pending) {
        guard waiting?.asks.contains(where: { $0.id == entry.item.id }) == false else { return }
        waiting?.asks.insert(entry.item, at: min(entry.index, waiting?.asks.count ?? 0))
    }

    private func remove(_ id: Int) {
        hidden.remove(id)
        failed.remove(id)
        waiting?.asks.removeAll { $0.id == id }
        waiting?.answered.removeAll { $0.id == id }
        revision += 1
    }

    func clear() {
        generation += 1
        revision += 1
        pending = nil
        undoOffer = nil
        hidden = []
        waiting = nil
        sampleValue = nil
        failed = []
        loading = false
        refreshAgain = false
        loadedAt = nil
        error = nil
        notice = nil
    }

    #if DEBUG
    func leaveSample() { clear(); samples = nil }
    #endif

    private struct Pending {
        let id = UUID()
        let item: BoardItem
        let action: BoardAction
        let index: Int
        let generation: Int
        let login: Int
    }
}
