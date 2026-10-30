import Foundation
import Observation

/// One store for the app: the overview (hunt, portals, counts), the matches by state, the filtered-out listings,
/// applications, settings, and the search's helpers. Views read it and call its actions; nothing here knows about views.
///
/// - Optimistic changes (a match's state, start/pause, settings) show at once and roll back with a notice on failure.
/// - Every request remembers the login it started with (`Context`); answers that arrive after a logout or a switch of
///   account are dropped.
/// - Failures go to `EmpireSession.handleAuthFailure`: 401 ends the login everywhere, 403 closes this app (the session
///   then calls `clear()` through `onAppDataReset`).
@MainActor @Observable
final class ArestemisStore {
    struct MatchList: Equatable {
        var ids: [Int] = []
        var more = false
        var loaded = false
        var isLoading = false
        var error: String?
    }

    struct ApplicationState: Equatable {
        var application: Application?
        var isLoading = false
        var error: String?
    }

    struct Notice: Equatable, Identifiable {
        let id = UUID()
        let text: String
    }

    static let pageSize = 50

    let session: EmpireSession
    let isSample: Bool
    let places: PlaceSearch
    private let backend: any ArestemisBackend
    private let keptDraft: KeptSearchDraft

    // overview
    private(set) var overview: Overview?
    private(set) var isLoadingOverview = false
    private(set) var overviewError: String?
    private(set) var lastOverviewLoad: Date?
    private(set) var isTogglingHunt = false

    // matches
    private(set) var matchesByID: [Int: Match] = [:]
    private(set) var lists: [MatchFilter: MatchList] = [:]
    private(set) var seen: Set<Int> = []
    private(set) var changingState: Set<Int> = []
    private(set) var matchErrors: [Int: String] = [:]

    // filtered out
    private(set) var rejected: [Rejected] = []
    private(set) var rejectedLoaded = false
    private(set) var isLoadingRejected = false
    private(set) var rejectedError: String?

    // applications, settings, search
    private(set) var applications: [Int: ApplicationState] = [:]
    private(set) var settings: Settings?
    private(set) var isLoadingSettings = false
    private(set) var settingsError: String?
    private(set) var isSavingSearch = false
    private(set) var searchError: String?
    private(set) var isParsing = false
    private(set) var parseError: String?

    /// The last action that failed, shown briefly over the tabs.
    private(set) var notice: Notice?
    var undo: UndoOffer?

    private var resetGeneration = 0
    private var foregroundRefreshing = false

    init(session: EmpireSession, backend: any ArestemisBackend, sample: Bool = false,
         placeDelay: Duration = .milliseconds(300), defaults: UserDefaults = .standard) {
        self.session = session
        self.backend = backend
        keptDraft = KeptSearchDraft(defaults: defaults)
        #if DEBUG
        isSample = sample
        #else
        isSample = false
        #endif
        places = PlaceSearch(delay: placeDelay, fetch: { [backend] query in
            // The login this request goes with, so its refusal names it (`EmpireSession.handleAuthFailure`).
            let generation = session.generation
            let token = session.token
            do {
                return try await backend.places(query: query)
            } catch {
                session.handleAuthFailure(error, generation: generation, token: token)
                throw error
            }
        })
        places.onFailure = { [weak session] error in
            // A failure that ended the login or closed the app says nothing more here.
            session?.isSignedIn == true ? error.localizedDescription : nil
        }
        session.onAppDataReset { [weak self] in self?.clear() }
    }

    private var canAct: Bool { isSample || session.isSignedIn }

    // MARK: - overview

    var hunt: Hunt? { overview?.hunt }

    /// Loads the home screen. `quiet` keeps the current one on screen and reports nothing (refreshes after actions).
    func reloadOverview(quiet: Bool = false) async {
        guard canAct, !isLoadingOverview else { return }
        isLoadingOverview = true
        if !quiet { overviewError = nil }
        let context = context
        defer { if isCurrent(context) { isLoadingOverview = false } }
        do {
            let loaded = try await backend.overview()
            guard isCurrent(context) else { return }
            overview = loaded
            overviewError = nil
            lastOverviewLoad = .now
            for match in loaded.latest { remember(match) }
        } catch {
            guard isCurrent(context) else { return }
            if !quiet || overview == nil { handle(error, context: context) { self.overviewError = $0 } }
            else { session.handleAuthFailure(error, generation: context.session, token: context.token) }
        }
    }

    /// The three newest matches as they are now (a state changed here shows before the next overview).
    var latest: [Match] {
        (overview?.latest ?? []).map { matchesByID[$0.id] ?? $0 }.filter { $0.state != .dismissed }
    }

    /// Back in the foreground: renew an old login (12 h, like the Empire app), then refresh what is older than 30 s.
    func refreshOnForeground(now: Date = .now) async {
        guard !isSample, session.isSignedIn, !session.isBusy, !foregroundRefreshing else { return }
        foregroundRefreshing = true
        let context = context
        defer { if isCurrent(context) { foregroundRefreshing = false } }
        if session.lastRenewedAt.map({ now.timeIntervalSince($0) > 12 * 3600 }) ?? true {
            await session.restore()
            guard isCurrent(context), session.isSignedIn, !session.needsRestoreRetry else { return }
        }
        guard lastOverviewLoad.map({ now.timeIntervalSince($0) > 30 }) ?? true else { return }
        await reloadOverview(quiet: true)
        for filter in MatchFilter.allCases where lists[filter]?.loaded == true {
            await loadMatches(filter, quiet: true)
        }
    }

    // MARK: - search draft

    func searchDraft() -> SearchDraft {
        #if DEBUG
        if isSample, LaunchArguments.current.contains("-sampleSearchDraft") {
            var draft = hunt.map { SearchDraft($0.search) } ?? SearchDraft()
            draft.people = draft.people == 1 ? 2 : 1
            return draft
        }
        #endif
        guard !isSample, let account = session.accountID else {
            return hunt.map { SearchDraft($0.search) } ?? SearchDraft()
        }
        return keptDraft.restore(for: hunt?.search, account: account)
    }

    func keepSearchDraft(_ draft: SearchDraft, baseline: Search?) {
        guard !isSample, canAct, let account = session.accountID else { return }
        keptDraft.keep(draft, baseline: baseline, account: account)
    }

    private func dropSearchDraft() {
        guard !isSample, let account = session.accountID else { return }
        keptDraft.drop(account: account)
    }

    // MARK: - hunt

    /// Start or pause, shown at once; rolled back if the server refuses.
    func setHuntActive(_ active: Bool) async {
        guard canAct, !isTogglingHunt, let hunt = overview?.hunt, hunt.active != active else { return }
        isTogglingHunt = true
        overview?.hunt?.active = active
        let context = context
        defer { if isCurrent(context) { isTogglingHunt = false } }
        do {
            let returned = try await backend.setHunt(id: hunt.id, active: active)
            guard isCurrent(context) else { return }
            overview?.hunt = returned
            await reloadOverview(quiet: true)
        } catch {
            guard isCurrent(context) else { return }
            if overview?.hunt?.id == hunt.id { overview?.hunt?.active = hunt.active }
            handle(error, context: context) { self.show(active ? String(localized: "Could not start the hunt. \($0)")
                                                                     : String(localized: "Could not pause the hunt. \($0)")) }
        }
    }

    /// Creates the hunt (paused, as the server does) or replaces its search. True when saved.
    @discardableResult
    func saveSearch(_ search: Search) async -> Bool {
        guard canAct, !isSavingSearch else { return false }
        isSavingSearch = true
        searchError = nil
        let context = context
        defer { if isCurrent(context) { isSavingSearch = false } }
        do {
            let saved: Hunt
            if let hunt = overview?.hunt {
                saved = try await backend.updateHunt(id: hunt.id, search: search)
            } else {
                saved = try await backend.createHunt(search)
            }
            guard isCurrent(context) else { return false }
            dropSearchDraft()
            overview?.hunt = saved
            await reloadOverview(quiet: true)
            return true
        } catch {
            guard isCurrent(context) else { return false }
            handle(error, context: context) { self.searchError = $0 }
            return false
        }
    }

    /// Deletes the hunt and with it every match. True when deleted.
    @discardableResult
    func deleteSearch() async -> Bool {
        guard canAct, !isSavingSearch, let hunt = overview?.hunt else { return false }
        isSavingSearch = true
        searchError = nil
        let context = context
        defer { if isCurrent(context) { isSavingSearch = false } }
        do {
            try await backend.deleteHunt(id: hunt.id)
            guard isCurrent(context) else { return false }
            dropSearchDraft()
            overview?.hunt = nil
            overview?.latest = []
            forgetMatches()
            await reloadOverview(quiet: true)
            return true
        } catch {
            guard isCurrent(context) else { return false }
            handle(error, context: context) { self.searchError = $0 }
            return false
        }
    }

    /// "Describe it": what the server read from the sentence, or nil (then `parseError` says why).
    func parse(_ text: String) async -> ParsedSearch? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canAct, !isParsing, !text.isEmpty else { return nil }
        isParsing = true
        parseError = nil
        let context = context
        defer { if isCurrent(context) { isParsing = false } }
        do {
            let parsed = try await backend.parse(text)
            guard isCurrent(context) else { return nil }
            return parsed
        } catch {
            guard isCurrent(context) else { return nil }
            handle(error, context: context) { self.parseError = $0 }
            return nil
        }
    }

    // MARK: - matches

    /// The matches of a filter, newest first, as known now (including changes made here since the last load).
    func matches(_ filter: MatchFilter) -> [Match] {
        matchesByID.values.filter { filter.includes($0.state) }.sorted { $0.id > $1.id }
    }

    func list(_ filter: MatchFilter) -> MatchList { lists[filter] ?? MatchList() }

    func match(_ id: Int) -> Match? { matchesByID[id] ?? overview?.latest.first { $0.id == id } }

    /// The first page of a filter (or, with `more`, the next one).
    func loadMatches(_ filter: MatchFilter, more: Bool = false, quiet: Bool = false) async {
        guard canAct, !(lists[filter]?.isLoading ?? false) else { return }
        let before = more ? lists[filter]?.ids.min() : nil
        if more && (before == nil || lists[filter]?.more != true) { return }
        lists[filter, default: MatchList()].isLoading = true
        if !quiet { lists[filter]?.error = nil }
        let context = context
        defer { if isCurrent(context) { lists[filter]?.isLoading = false } }
        do {
            let page = try await backend.matches(states: filter.states, limit: Self.pageSize, before: before)
            guard isCurrent(context) else { return }
            merge(page, filter: filter, appending: more)
        } catch {
            guard isCurrent(context) else { return }
            if quiet { session.handleAuthFailure(error, generation: context.session, token: context.token) }
            else { handle(error, context: context) { self.lists[filter]?.error = $0 } }
        }
    }

    /// One match, from memory or the server (a link to a match not loaded yet). Nil if it cannot be had.
    @discardableResult
    func loadMatch(_ id: Int) async -> Match? {
        if let known = match(id) { return known }
        guard canAct else { return nil }
        matchErrors[id] = nil
        let context = context
        do {
            let loaded = try await backend.match(id: id)
            guard isCurrent(context) else { return nil }
            remember(loaded)
            return loaded
        } catch {
            guard isCurrent(context) else { return nil }
            handle(error, context: context) { self.matchErrors[id] = $0 }
            return nil
        }
    }

    /// Save, mark applied, dismiss: shown at once, rolled back with a notice if the server refuses.
    func setState(_ state: MatchState, for id: Int) async {
        guard canAct, !changingState.contains(id), let current = match(id), current.state != state else { return }
        if state == .dismissed { undo = nil }
        changingState.insert(id)
        var changed = current
        changed.state = state
        matchesByID[id] = changed
        let context = context
        defer { if isCurrent(context) { changingState.remove(id) } }
        do {
            let returned = try await backend.setState(state, match: id)
            guard isCurrent(context) else { return }
            matchesByID[id] = returned
            // Offered as soon as the server confirmed, before the counts reload, so it follows the swipe at once.
            if state == .dismissed, returned.state == .dismissed {
                undo = UndoOffer(message: String(localized: "Listing dismissed.")) { [weak self] in
                    guard let self, self.isCurrent(context), self.match(id)?.state == .dismissed else { return }
                    await self.setState(current.state, for: id)
                }
            }
            await reloadOverview(quiet: true)          // the counts are the server's
        } catch {
            guard isCurrent(context) else { return }
            matchesByID[id] = current
            handle(error, context: context) { self.show("\(state.failure) \($0)") }
        }
    }

    /// Opening a new match keeps it `new` (only the user's actions change states); its "new" dot fades.
    func markSeen(_ id: Int) { seen.insert(id) }

    func showsNewDot(_ match: Match) -> Bool { match.state == .new && !seen.contains(match.id) }

    // MARK: - filtered out

    func loadRejected() async {
        guard canAct, !isLoadingRejected else { return }
        isLoadingRejected = true
        rejectedError = nil
        let context = context
        defer { if isCurrent(context) { isLoadingRejected = false } }
        do {
            let page = try await backend.rejected(limit: Self.pageSize)
            guard isCurrent(context) else { return }
            rejected = page.items
            rejectedLoaded = true
        } catch {
            guard isCurrent(context) else { return }
            handle(error, context: context) { self.rejectedError = $0 }
        }
    }

    // MARK: - applications

    func application(_ match: Int) -> ApplicationState { applications[match] ?? ApplicationState() }

    /// The application text for a match: the one already written for it if it fits the current mode, else the
    /// server writes it (`regenerate` = "Write again").
    func loadApplication(for id: Int, regenerate: Bool = false) async {
        guard canAct, !(applications[id]?.isLoading ?? false) else { return }
        let cached = match(id)?.application ?? applications[id]?.application
        if !regenerate, let cached, settings.map({ $0.applicationMode == cached.mode }) ?? true {
            applications[id] = ApplicationState(application: cached)
            return
        }
        applications[id, default: ApplicationState()].isLoading = true
        applications[id]?.error = nil
        let context = context
        defer { if isCurrent(context) { applications[id]?.isLoading = false } }
        do {
            // A text written in the other mode is replaced, not reused.
            let written = try await backend.application(match: id, regenerate: regenerate || cached != nil)
            guard isCurrent(context) else { return }
            applications[id]?.application = written
            if matchesByID[id] != nil { matchesByID[id]?.application = written }
        } catch {
            guard isCurrent(context) else { return }
            handle(error, context: context) { self.applications[id]?.error = $0 }
        }
    }

    // MARK: - settings

    func loadSettings() async {
        guard canAct, !isLoadingSettings else { return }
        isLoadingSettings = true
        settingsError = nil
        let context = context
        defer { if isCurrent(context) { isLoadingSettings = false } }
        do {
            let loaded = try await backend.settings()
            guard isCurrent(context) else { return }
            settings = loaded
        } catch {
            guard isCurrent(context) else { return }
            handle(error, context: context) { self.settingsError = $0 }
        }
    }

    /// Shown at once; the old settings come back with a notice if the server refuses.
    func saveSettings(_ new: Settings) async {
        guard canAct, let old = settings, new != old else { return }
        settings = new
        let context = context
        do {
            let saved = try await backend.saveSettings(new)
            guard isCurrent(context) else { return }
            if settings == new { settings = saved }
        } catch {
            guard isCurrent(context) else { return }
            if settings == new { settings = old }
            handle(error, context: context) { self.show(String(localized: "Settings not saved. \($0)")) }
        }
    }

    // MARK: - notices

    func dismissNotice() { notice = nil }

    private func show(_ text: String) { notice = Notice(text: text) }

    // MARK: - forgetting

    /// Everything this app knows about the account (logout, or this app denied).
    func clear() {
        if !isSample { keptDraft.clear() }
        undo = nil
        resetGeneration += 1
        overview = nil
        overviewError = nil
        lastOverviewLoad = nil
        isLoadingOverview = false
        isTogglingHunt = false
        forgetMatches()
        settings = nil
        settingsError = nil
        isLoadingSettings = false
        isSavingSearch = false
        searchError = nil
        isParsing = false
        parseError = nil
        notice = nil
        foregroundRefreshing = false
        places.reset()
    }

    private func forgetMatches() {
        undo = nil
        matchesByID = [:]
        lists = [:]
        seen = []
        changingState = []
        matchErrors = [:]
        rejected = []
        rejectedLoaded = false
        isLoadingRejected = false
        rejectedError = nil
        applications = [:]
    }

    // MARK: - plumbing

    /// What an action started with. Its requests read the same login (`ArestemisAPI` reads `session.token` before
    /// its first suspension, on the main actor), so a refusal names that one (`handleAuthFailure`).
    private struct Context { let session: Int; let reset: Int; let token: String? }
    private var context: Context { Context(session: session.generation, reset: resetGeneration, token: session.token) }
    private func isCurrent(_ context: Context) -> Bool {
        context.session == session.generation && context.reset == resetGeneration
    }

    private func handle(_ failure: Error, context: Context, report: (String) -> Void) {
        session.handleAuthFailure(failure, generation: context.session, token: context.token)
        guard isCurrent(context) else { return }
        report(failure.localizedDescription)
    }

    private func remember(_ match: Match) {
        // A match whose state is being changed here keeps the state shown until the server answers.
        guard !changingState.contains(match.id) else { return }
        matchesByID[match.id] = match
    }

    /// A page from the server is the truth for its filter: matches of that filter it no longer lists are gone
    /// (changed or removed elsewhere), within the range the page covers.
    private func merge(_ page: MatchPage, filter: MatchFilter, appending: Bool) {
        let returned = Set(page.items.map(\.id))
        let lowest = page.items.map(\.id).min() ?? 0
        let upper = appending ? (lists[filter]?.ids.min() ?? Int.max) : Int.max
        for (id, match) in matchesByID where filter.includes(match.state) && !returned.contains(id)
            && !changingState.contains(id) && id < upper && (!page.more || id >= lowest) {
            matchesByID[id] = nil
        }
        for match in page.items { remember(match) }
        let ids = page.items.map(\.id)
        lists[filter, default: MatchList()].ids = appending ? (lists[filter]?.ids ?? []) + ids : ids
        lists[filter]?.more = page.more
        lists[filter]?.loaded = true
        lists[filter]?.error = nil
    }
}

extension MatchState {
    /// "Could not save the listing."
    var failure: String {
        switch self {
        case .new: String(localized: "Could not reset the listing.")
        case .saved: String(localized: "Could not save the listing.")
        case .applied: String(localized: "Could not mark the listing as applied.")
        case .dismissed: String(localized: "Could not dismiss the listing.")
        }
    }
}

/// Places as you type (`GET /places?q=`, at least 2 characters), asked once typing pauses.
@MainActor @Observable
final class PlaceSearch {
    private(set) var query = ""
    private(set) var results: [Place] = []
    private(set) var isSearching = false
    private(set) var error: String?
    @ObservationIgnored var onFailure: (Error) -> String? = { $0.localizedDescription }
    @ObservationIgnored private var task: Task<Void, Never>?
    private let delay: Duration
    private let fetch: (String) async throws -> [Place]

    init(delay: Duration, fetch: @escaping (String) async throws -> [Place]) {
        self.delay = delay
        self.fetch = fetch
    }

    func update(_ text: String) {
        query = text
        task?.cancel()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            results = []
            isSearching = false
            error = nil
            return
        }
        isSearching = true
        task = Task { [delay, fetch] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            do {
                let found = try await fetch(query)
                guard !Task.isCancelled else { return }
                results = found
                error = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.error = onFailure(error)
            }
            isSearching = false
        }
    }

    /// Waits for the search in flight (tests).
    func settle() async { await task?.value }

    func reset() {
        task?.cancel()
        task = nil
        query = ""
        results = []
        isSearching = false
        error = nil
    }
}
