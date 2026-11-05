import Foundation
import Synchronization
import Observation

/// One store for the app: the overview (hunt, portals, counts), the sites each kind of search can use (`GET /kinds`),
/// the matches by state (of every search or of one), the filtered-out listings, the search over found listings (`GET
/// /matches?q=`), applications, settings, and the search's helpers. Views read it and call its actions; nothing here
/// knows about views.
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

    /// Which listings a list holds: one filter's, of every search (`hunt` nil) or of one.
    struct ListScope: Hashable {
        let hunt: Int?
        let filter: MatchFilter
    }

    /// The listings filtered out of every search (`GET /rejected`), or of one.
    struct RejectedList: Equatable {
        var items: [Rejected] = []
        var loaded = false
        var isLoading = false
        var error: String?
    }

    struct ApplicationState: Equatable {
        var application: Application?
        var isLoading = false
        var error: String?
    }

    /// A price monitor's history over one window, as last loaded for its card's last read.
    struct PriceHistory: Equatable {
        var prices: Prices?
        /// The card's `checked` the history was loaded for: a newer read brings a newer point, so it is asked again.
        var loadedFor: String?
        var isLoading = false
        var error: String?
    }

    /// An everywhere monitor's offers and sites (brief 157), as last loaded for its card's last read.
    struct OffersState: Equatable {
        var offers: PriceOffers?
        /// The card's `checked` when they were loaded: a newer read loads them again.
        var loadedFor: String?
        var isLoading = false
        var error: String?
    }

    struct PriceHistoryKey: Hashable {
        let hunt: Int
        let days: Int
    }

    struct Notice: Equatable, Identifiable {
        let id = UUID()
        let text: String
    }

    static let pageSize = 50

    let session: EmpireSession
    /// The store runs on the samples in memory (DEBUG's `-sampleData`, the tour): it asks no server, keeps no drafts and
    /// does not refresh with the login.
    let isSample: Bool
    let places: PlaceSearch
    private let backend: any ArestemisBackend
    private let keptDraft: KeptSearchDraft

    // overview
    private(set) var overview: Overview?
    private(set) var isLoadingOverview = false
    private(set) var overviewError: String?
    private(set) var lastOverviewLoad: Date?

    // sites (brief 119)
    /// The last `GET /kinds` answer: each kind of search and its sites. Nil until one arrived (offline, a server from
    /// before it); the forms then show the lists of before (`SiteChoices`). A failed reload keeps the last answer.
    private(set) var kinds: [OfferedKind]?
    private var isLoadingKinds = false

    // matches
    private(set) var matchesByID: [Int: Match] = [:]
    /// Each hunt's newest matches for its page (ids, newest first), loaded when the page opens.
    private(set) var huntLatest: [Int: [Int]] = [:]
    private(set) var lists: [ListScope: MatchList] = [:]
    private(set) var changingState: Set<Int> = []
    private(set) var matchErrors: [Int: String] = [:]

    // filtered out, of every search (nil) and of single ones
    private(set) var rejectedLists: [Int?: RejectedList] = [:]

    // price monitors (brief 137)
    private(set) var priceHistories: [PriceHistoryKey: PriceHistory] = [:]
    /// Monitors whose switches are being saved from their page (`saveMonitor`).
    private(set) var savingMonitors: Set<Int> = []
    /// The newest switches asked for while a save of the same monitor was on its way: sent once it has answered.
    private var monitorWanted: [Int: PriceSearch] = [:]
    /// Everywhere monitors' offers and sites, by hunt id (brief 157).
    private(set) var priceOffers: [Int: OffersState] = [:]

    // applications, settings, search
    private(set) var applications: [Int: ApplicationState] = [:]
    private(set) var settings: Settings?
    private(set) var isLoadingSettings = false
    private(set) var settingsError: String?
    private(set) var isSavingSearch = false
    private(set) var searchError: String?
    /// The field the server named with its refusal of a save ("search.url", `FieldRefusal`), so a form can show the
    /// sentence at that field; nil for a refusal of the whole search.
    private(set) var searchErrorField: String?
    private(set) var isParsing = false
    private(set) var parseError: String?

    /// The last action that failed, shown briefly over the tabs.
    private(set) var notice: Notice?
    var undo: UndoOffer?

    private var resetGeneration = 0
    private var foregroundRefreshing = false
    /// How long the search over listings waits for typing to pause.
    private let findDelay: Duration

    init(session: EmpireSession, backend: any ArestemisBackend, sample: Bool = false,
         placeDelay: Duration = .milliseconds(300), findDelay: Duration = ListingSearch.delay,
         defaults: UserDefaults = .standard) {
        self.session = session
        self.backend = backend
        self.findDelay = findDelay
        keptDraft = KeptSearchDraft(defaults: defaults)
        // In memory on the samples: DEBUG's `-sampleData`, and the tour in every build (brief 139).
        isSample = sample
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

    var hunts: [HuntCard] { overview?.hunts ?? [] }
    /// One hunt's card, as known now.
    func card(_ id: Int) -> HuntCard? { hunts.first { $0.id == id } }
    /// A hunt being started, paused, saved, renamed or deleted (its buttons wait).
    func isChanging(hunt id: Int) -> Bool { changingHunts.contains(id) }
    private(set) var changingHunts: Set<Int> = []
    private var nextTemporaryHuntID = -1
    /// Counts every time the lists are forgotten (a hunt deleted, a logout), so a page asked for before is dropped.
    private var listGeneration = 0
    private var deletedHunts: Set<Int> = []
    struct MonitorListScope: Hashable {
        let hunt: Int
        let filter: MatchFilter
        let kind: MonitorListingKind
    }

    private struct MonitorFeed: Hashable {
        let hunt: Int
        let kind: MonitorListingKind
    }

    /// Used and Alarms share the pager and match values, with separate membership, filters and cursors.
    private(set) var monitorLists: [MonitorListScope: MatchList] = [:]
    private var monitorIDs: [MonitorFeed: Set<Int>] = [:]
    private var monitorGeneration: [Int: Int] = [:]
    private var monitorLoadedFor: [MonitorListScope: MonitorListingsRead] = [:]
    private var monitorLimits: [MonitorListScope: Int] = [:]
    private var monitorRequests: [MonitorListScope: MonitorRequest] = [:]
    /// Cancellation is recorded synchronously, so returning to a filter can start a new request before an older
    /// transport finishes cancelling. Its late defer/result may only touch its own request.
    private nonisolated final class MonitorRequest: Sendable {
        private let cancelled = Mutex(false)
        private let wantedLimit = Mutex(0)
        var isCancelled: Bool { cancelled.withLock { $0 } }
        var limit: Int { wantedLimit.withLock { $0 } }
        func require(_ limit: Int) { wantedLimit.withLock { $0 = max($0, limit) } }
        func cancel() { cancelled.withLock { $0 = true } }
    }
    /// A read begun before a state action must not undo that action even after it has completed.
    private var stateRevision = 0
    private var matchStateRevision: [Int: Int] = [:]

    // reading (brief 180)
    /// Listings opened here whose read the server has not confirmed: on their way, or failed (sent again at the next
    /// opening). They stay read here whatever a list or overview says meanwhile.
    private var unconfirmedReads: Set<Int> = []
    private var sendingReads: Set<Int> = []
    /// Counts the listings read here; each unread new one's hunt, by the count it was read at, until an overview asked
    /// for after it arrived (an older answer still counts it as unread).
    private var readRevision = 0
    private var countedReads: [Int: (hunt: Int, revision: Int)] = [:]


    /// Loads the home screen. `quiet` keeps the current one on screen and reports nothing (refreshes after actions).
    func reloadOverview(quiet: Bool = false) async {
        guard canAct, !isLoadingOverview else { return }
        isLoadingOverview = true
        if !quiet { overviewError = nil }
        let context = context
        let revision = stateRevision
        let reads = readRevision
        defer { if isCurrent(context) { isLoadingOverview = false } }
        do {
            var loaded = try await backend.overview()
            guard isCurrent(context) else { return }
            uncount(readsAfter: reads, in: &loaded)
            // An overview arriving during an action must keep its pending card (or pending deletion).
            let pending = hunts.filter { changingHunts.contains($0.id) }
            loaded.hunts.removeAll { changingHunts.contains($0.id) || deletedHunts.contains($0.id) }
            loaded.hunts.append(contentsOf: pending)
            loaded.hunts.sort { $0.id < $1.id }
            // A monitor whose switches are being saved keeps them as shown until the server answered.
            for index in loaded.hunts.indices where savingMonitors.contains(loaded.hunts[index].id) {
                if let shown = card(loaded.hunts[index].id) { loaded.hunts[index].hunt.search = shown.hunt.search }
            }
            for old in hunts where !loaded.hunts.contains(where: { $0.id == old.id && $0.hunt.search == old.hunt.search }) {
                invalidateMonitorListings(old.id)
            }
            loaded.latest.removeAll { deletedHunts.contains($0.huntID) }
            overview = loaded
            syncFlatHunt()
            overviewError = nil
            lastOverviewLoad = .now
            for match in loaded.latest { remember(match, since: revision) }
            // Settings are fetched once, right after the first home screen, so the Settings sheet opens complete.
            if settings == nil { Task { await self.loadSettings() } }
            // The sites come with the home screen: at launch and every pull to refresh, and with every reload until an
            // answer came. A form asks again when it opens.
            if !quiet || kinds == nil { Task { await self.loadKinds() } }
        } catch {
            guard isCurrent(context) else { return }
            if !quiet || overview == nil { handle(error, context: context) { self.overviewError = $0 } }
            else { session.handleAuthFailure(error, generation: context.session, token: context.token) }
        }
    }

    /// The account's three newest matches, across all hunts, as they are now (a state changed here shows before the
    /// next overview).
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
        for scope in lists.keys.sorted(by: Self.loadOrder) where lists[scope]?.loaded == true {
            await loadMatches(scope.filter, hunt: scope.hunt, quiet: true)
        }
        let scopes = monitorLists.keys.sorted {
            ($0.hunt, $0.kind.rawValue, $0.filter.rawValue) < ($1.hunt, $1.kind.rawValue, $1.filter.rawValue)
        }
        for scope in scopes where monitorLists[scope]?.loaded == true {
            await loadMonitorListings(scope.kind, hunt: scope.hunt, filter: scope.filter, force: true)
        }
    }

    // MARK: - sites

    /// The sites' names from the server: the overview's sites and `/kinds`.
    var siteNames: SiteNames { SiteNames(statuses: overview?.sources ?? [], kinds: kinds) }

    /// What a search form of this kind offers under Portals, with the sites its search has chosen and, in the thing
    /// form, its delivery choice.
    func siteChoices(_ kind: SearchKind, chosen: Set<Source>, delivery: Delivery? = nil) -> SiteChoices {
        SiteChoices(kind: kind, kinds: kinds, chosen: chosen, names: siteNames, delivery: delivery)
    }

    /// `GET /kinds`, quietly: a failure (offline, a server from before it) keeps the last answer and says nothing; only
    /// a refused login counts (401 logs out, 403 closes the app).
    func loadKinds() async {
        guard canAct, !isLoadingKinds else { return }
        isLoadingKinds = true
        let context = context
        defer { if isCurrent(context) { isLoadingKinds = false } }
        do {
            let loaded = try await backend.kinds()
            guard isCurrent(context) else { return }
            kinds = loaded
        } catch {
            guard isCurrent(context) else { return }
            session.handleAuthFailure(error, generation: context.session, token: context.token)
        }
    }

    // MARK: - hunts

    private func putHunt(_ hunt: Hunt) {
        if let old = card(hunt.id), old.hunt.search != hunt.search { invalidateMonitorListings(hunt.id) }
        if let index = overview?.hunts.firstIndex(where: { $0.id == hunt.id }) {
            overview?.hunts[index].hunt = hunt
            if !hunt.active { overview?.hunts[index].sources = [] }
        } else {
            overview?.hunts.append(HuntCard(hunt: hunt, counts: .init(new: 0, today: 0, saved: 0, applied: 0),
                                            sources: [], slowed: false))
        }
        syncFlatHunt()
    }
    private func syncFlatHunt() {
        let flat = hunts.first { $0.hunt.kind == .flat }?.hunt
        overview?.hunt = flat
    }
    private func restoreCard(_ card: HuntCard) {
        if let old = self.card(card.id), old.hunt.search != card.hunt.search { invalidateMonitorListings(card.id) }
        overview?.hunts.removeAll { $0.id == card.id }
        overview?.hunts.append(card)
        overview?.hunts.sort { $0.id < $1.id }
        syncFlatHunt()
    }

    func setActive(id: Int, active: Bool) async {
        guard canAct, !changingHunts.contains(id), let card = hunts.first(where: { $0.id == id }),
              card.hunt.active != active else { return }
        changingHunts.insert(id)
        let context = context
        defer { if isCurrent(context) { changingHunts.remove(id) } }
        var optimistic = card.hunt
        optimistic.active = active
        putHunt(optimistic)
        do {
            let saved = try await backend.setActive(id: id, active: active)
            guard isCurrent(context) else { return }
            putHunt(saved)
            changingHunts.remove(id)
            await reloadOverview(quiet: true)
        } catch {
            guard isCurrent(context) else { return }
            restoreCard(card)
            handle(error, context: context) { self.show($0) }
        }
    }

    /// A pending creation uses a temporary id; only the affected card is rolled back on refusal. A refusal is shown as a
    /// notice over the tabs, unless it names a field the calling form shows it at (`fieldsShown`, the watch form's
    /// address and description): then the form alone says it.
    @discardableResult
    func saveHunt(id: Int?, kind: HuntKind, name: String?, search: HuntSearch,
                  fieldsShown: Set<String> = []) async -> Hunt? {
        guard canAct, search.kind == kind, !isSavingSearch else { return nil }
        let old = id.flatMap { id in hunts.first { $0.id == id } }
        guard id == nil || (old != nil && !changingHunts.contains(id!)) else { return nil }
        let actionID = id ?? nextTemporaryHuntID
        if id == nil { nextTemporaryHuntID -= 1 }
        changingHunts.insert(actionID)
        isSavingSearch = true
        clearSearchError()
        let context = context
        defer { if isCurrent(context) { changingHunts.remove(actionID); isSavingSearch = false } }
        let now = ArestemisSamples.iso(.now)
        var optimistic = old?.hunt ?? Hunt(id: actionID, kind: kind, active: false, search: search,
                                           created: now, updated: now, activated: nil)
        optimistic.search = search
        optimistic.name = name
        putHunt(optimistic)
        do {
            let saved: Hunt
            if let id { saved = try await backend.updateHunt(id: id, search: search, name: name) }
            else { saved = try await backend.createHunt(kind: kind, name: name, search: search) }
            guard isCurrent(context) else { return nil }
            overview?.hunts.removeAll { $0.id == actionID }
            if let old { restoreCard(old) }
            putHunt(saved)
            if !isSample, let account = session.accountID { keptDraft.drop(account: account, huntID: id, kind: kind) }
            changingHunts.remove(actionID)
            await reloadOverview(quiet: true)
            return saved
        } catch {
            guard isCurrent(context) else { return nil }
            overview?.hunts.removeAll { $0.id == actionID }
            if let old { restoreCard(old) }
            syncFlatHunt()
            handle(error, context: context) { message in
                let field = (error as? FieldRefusal)?.field
                self.searchError = message
                self.searchErrorField = field
                let shownAtField = field.map { fieldsShown.contains($0) } ?? false
                if !shownAtField { self.show(message) }
            }
            return nil
        }
    }
    @discardableResult
    /// Renames through `PATCH /hunts/{id}`, which changes the name alone: saving the search again (`PUT`) would make the
    /// server seed every feed again, drop listings waiting for the AI check and read a watched page anew.
    func renameHunt(id: Int, name: String?) async -> Bool {
        guard canAct, let old = hunts.first(where: { $0.id == id }), !changingHunts.contains(id) else { return false }
        changingHunts.insert(id)
        clearSearchError()
        let context = context
        defer { if isCurrent(context) { changingHunts.remove(id) } }
        var optimistic = old.hunt
        optimistic.name = name
        putHunt(optimistic)
        do {
            let saved = try await backend.renameHunt(id: id, name: name)
            guard isCurrent(context) else { return false }
            putHunt(saved)
            // A kept draft's baseline holds the old name.
            if !isSample, let account = session.accountID { keptDraft.drop(account: account, huntID: id, kind: saved.kind) }
            return true
        } catch {
            guard isCurrent(context) else { return false }
            restoreCard(old)
            syncFlatHunt()
            handle(error, context: context) { self.searchError = $0; self.show($0) }
            return false
        }
    }
    @discardableResult
    func deleteHunt(id: Int) async -> Bool {
        guard canAct, !changingHunts.contains(id), let card = hunts.first(where: { $0.id == id }) else { return false }
        changingHunts.insert(id)
        clearSearchError()
        let context = context
        defer { if isCurrent(context) { changingHunts.remove(id) } }
        overview?.hunts.removeAll { $0.id == id }
        syncFlatHunt()
        do {
            try await backend.deleteHunt(id: id)
            guard isCurrent(context) else { return false }
            deletedHunts.insert(id)
            if !isSample, let account = session.accountID { keptDraft.drop(account: account, huntID: id, kind: card.hunt.kind) }
            let removed = Set(matchesByID.values.filter { $0.huntID == id }.map(\.id))
            for match in removed {
                matchesByID[match] = nil
                applications[match] = nil
                unconfirmedReads.remove(match)
                countedReads[match] = nil
            }
            overview?.latest.removeAll { $0.huntID == id }
            huntLatest[id] = nil
            priceHistories = priceHistories.filter { $0.key.hunt != id }
            priceOffers[id] = nil
            invalidateMonitorListings(id)
            monitorIDs = monitorIDs.filter { $0.key.hunt != id }
            // Every list is asked again when it shows (the counts and pages of every search changed).
            listGeneration += 1
            lists = [:]
            rejectedLists = [:]
            changingHunts.remove(id)
            await reloadOverview(quiet: true)
            return true
        } catch {
            guard isCurrent(context) else { return false }
            restoreCard(card)
            handle(error, context: context) { self.searchError = $0; self.show($0) }
            return false
        }
    }

    // MARK: - the forms' drafts

    /// The saved hunt as its form shows it (search and name); nil for a new one or a hunt of another kind.
    func savedDraft<Draft: KeptDraft>(_ type: Draft.Type, huntID: Int?) -> Draft? {
        hunts.first { $0.id == huntID }.flatMap { Draft(saved: $0.hunt) }
    }

    /// A form's draft: the saved hunt (or an empty form), with the edits kept for it while it is unchanged.
    func searchDraft<Draft: KeptDraft>(_ type: Draft.Type, huntID: Int?) -> Draft {
        let saved = savedDraft(type, huntID: huntID)
        guard !isSample, let account = session.accountID else { return saved ?? Draft() }
        return keptDraft.restore(saved: saved, account: account, huntID: huntID)
    }

    /// Keeps a form's unsaved edits for the next time it opens (forgotten once they equal the saved hunt again).
    func keepSearchDraft<Draft: KeptDraft>(_ draft: Draft, huntID: Int?) {
        guard !isSample, canAct, let account = session.accountID else { return }
        keptDraft.keep(draft, saved: savedDraft(Draft.self, huntID: huntID), account: account, huntID: huntID)
    }

    func itemSearchDraft(huntID: Int? = nil) -> ItemSearchDraft {
        #if DEBUG
        // Screenshots: `-sampleDelivery pickup|shipping|either` chooses that delivery in the form, as a tap would (the
        // form then switches off the sites it rules out).
        if isSample, let delivery = LaunchArguments.value("-sampleDelivery").flatMap(Delivery.init(rawValue:)) {
            var draft = savedDraft(ItemSearchDraft.self, huntID: huntID) ?? ItemSearchDraft()
            draft.delivery = delivery
            return draft
        }
        #endif
        return searchDraft(ItemSearchDraft.self, huntID: huntID)
    }

    func flatSearchDraft(huntID: Int?) -> SearchDraft {
        #if DEBUG
        // Screenshots: an unsaved change, so the form shows its Save.
        if isSample, LaunchArguments.current.contains("-sampleSearchDraft") {
            var draft = savedDraft(SearchDraft.self, huntID: huntID) ?? SearchDraft()
            draft.people = draft.people == 1 ? 2 : 1
            return draft
        }
        #endif
        return searchDraft(SearchDraft.self, huntID: huntID)
    }

    /// A refusal shown at its field goes once that field is changed (and before every save).
    func clearSearchError() {
        searchError = nil
        searchErrorField = nil
    }

    /// "Describe it": what the server read from the sentence for a search of this kind, or nil (then `parseError`
    /// says why).
    func parse(text: String, kind: HuntKind) async -> HuntParseResult? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canAct, !isParsing, !text.isEmpty else { return nil }
        isParsing = true
        parseError = nil
        let context = context
        defer { if isCurrent(context) { isParsing = false } }
        do {
            let parsed = try await backend.parse(text: text, kind: kind)
            return isCurrent(context) ? parsed : nil
        } catch {
            guard isCurrent(context) else { return nil }
            handle(error, context: context) { self.parseError = $0 }
            return nil
        }
    }

    // MARK: - matches

    /// The matches of a filter, of every search or of one, newest first, as known now (including changes made here since
    /// the last load).
    func matches(_ filter: MatchFilter, hunt: Int? = nil) -> [Match] {
        matchesByID.values.filter { filter.includes($0) && (hunt == nil || $0.huntID == hunt) }.sorted { $0.id > $1.id }
    }

    func list(_ filter: MatchFilter, hunt: Int? = nil) -> MatchList { lists[ListScope(hunt: hunt, filter: filter)] ?? MatchList() }

    /// Every search's lists before single ones', each in the filters' order (the foreground refresh).
    private static func loadOrder(_ a: ListScope, _ b: ListScope) -> Bool {
        let filters = MatchFilter.allCases
        return (a.hunt ?? 0, filters.firstIndex(of: a.filter) ?? 0) < (b.hunt ?? 0, filters.firstIndex(of: b.filter) ?? 0)
    }

    /// A hunt's newest matches for its page, as known now; nil until they were loaded (`loadLatest(hunt:)`).
    func latest(hunt id: Int) -> [Match]? {
        if card(id)?.hunt.search.price != nil {
            return monitorList(.alarms, hunt: id).loaded ? Array(monitorMatches(.alarms, hunt: id).prefix(3)) : nil
        }
        return huntLatest[id].map { ids in ids.compactMap { matchesByID[$0] }.filter { $0.state != .dismissed } }
    }

    /// Price monitors request actual alarms before the server applies the limit; ordinary hunt feeds stay mixed.
    func loadLatest(hunt id: Int, force: Bool = false) async {
        guard canAct, id > 0, let search = card(id)?.hunt.search else { return }
        if search.price != nil {
            await loadMonitorListings(.alarms, hunt: id, force: force, limit: 3)
            return
        }
        let context = context
        let revision = stateRevision
        do {
            let page = try await backend.matches(hunt: id, state: nil, limit: 3, before: nil)
            guard !Task.isCancelled, isCurrent(context), card(id)?.hunt.search == search else { return }
            for match in page.items { remember(match, since: revision) }
            huntLatest[id] = page.items.map(\.id)
        } catch {
            guard isCurrent(context) else { return }
            session.handleAuthFailure(error, generation: context.session, token: context.token)
        }
    }

    /// What a match is: a monitor's alarm, a change on a watched page, a thing for sale, or a flat; by its listing (the
    /// price's change, the page's change, a thing's details), else by its hunt's kind (a match loaded before its
    /// details), else a flat.
    func kind(of match: Match) -> SearchKind {
        if match.isPriceChange { return .price }
        if match.isPageChange { return .watch }
        if match.isThing { return .item }
        return card(match.huntID).flatMap { SearchKind($0.hunt.kind) } ?? .flat
    }

    /// A thing for sale: its listing has a thing's details, or its hunt is a thing hunt (no application for it).
    func isThing(_ match: Match) -> Bool { kind(of: match) == .item }

    func match(_ id: Int) -> Match? { matchesByID[id] ?? overview?.latest.first { $0.id == id } }

    /// The first page of a filter, of every search or of one (or, with `more`, the next one).
    func loadMatches(_ filter: MatchFilter, hunt: Int? = nil, more: Bool = false, quiet: Bool = false) async {
        let scope = ListScope(hunt: hunt, filter: filter)
        guard canAct, !(lists[scope]?.isLoading ?? false) else { return }
        let before = more ? lists[scope]?.ids.min() : nil
        if more && (before == nil || lists[scope]?.more != true) { return }
        lists[scope, default: MatchList()].isLoading = true
        if !quiet { lists[scope]?.error = nil }
        let generation = listGeneration
        let context = context
        let revision = stateRevision
        defer { if isCurrent(context) && generation == listGeneration { lists[scope]?.isLoading = false } }
        do {
            let page = try await backend.matches(hunt: hunt, state: filter.states, seen: filter.seen, limit: Self.pageSize,
                                                 before: before)
            guard isCurrent(context) && generation == listGeneration else { return }
            merge(page, scope: scope, appending: more, since: revision)
        } catch {
            guard isCurrent(context) && generation == listGeneration else { return }
            if quiet { session.handleAuthFailure(error, generation: context.session, token: context.token) }
            else { handle(error, context: context) { self.lists[scope]?.error = $0 } }
        }
    }

    /// `GET /matches?q=`: the found listings of every search (or of one) that match the words, best match first, the
    /// server's order (brief 132). The matches are remembered, so a swipe on one changes it everywhere. A refused login
    /// goes to the session first; an answer for a login that has ended meanwhile is dropped (`CancellationError`).
    func findMatches(_ words: String, hunt: Int?, limit: Int = ListingSearch.limit) async throws -> MatchPage {
        guard canAct else { throw CancellationError() }
        let context = context
        let revision = stateRevision
        let page: MatchPage
        do {
            page = try await backend.findMatches(words, hunt: hunt, limit: limit)
        } catch {
            guard isCurrent(context) else { throw CancellationError() }
            session.handleAuthFailure(error, generation: context.session, token: context.token)
            throw error
        }
        guard isCurrent(context) else { throw CancellationError() }
        for match in page.items { remember(match, since: revision) }
        return page
    }

    /// A new search over found listings, of every search (nil) or of one (its own page).
    func listingSearch(hunt: Int?) -> ListingSearch {
        ListingSearch(hunt: hunt, delay: findDelay) { [weak self] words in
            guard let self else { throw CancellationError() }
            return try await self.findMatches(words, hunt: hunt)
        }
    }

    /// One match, from memory or the server (a link to a match not loaded yet). Nil if it cannot be had.
    @discardableResult
    func loadMatch(_ id: Int) async -> Match? {
        if let known = match(id) { return known }
        guard canAct else { return nil }
        matchErrors[id] = nil
        let context = context
        let revision = stateRevision
        do {
            let loaded = try await backend.match(id: id)
            guard isCurrent(context) else { return nil }
            remember(loaded, since: revision)
            return match(id)
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
        stateRevision += 1
        matchStateRevision[id] = stateRevision
        changingState.insert(id)
        var changed = current
        changed.state = state
        matchesByID[id] = changed
        let context = context
        defer { if isCurrent(context) { changingState.remove(id) } }
        do {
            let returned = try await backend.setState(state, match: id)
            guard isCurrent(context), !deletedHunts.contains(current.huntID) else { return }
            stateRevision += 1
            matchStateRevision[id] = stateRevision
            matchesByID[id] = keepingRead(returned)
            // Offered as soon as the server confirmed, before the counts reload, so it follows the swipe at once.
            if state == .dismissed, returned.state == .dismissed {
                undo = UndoOffer(message: String(localized: "Listing dismissed.")) { [weak self] in
                    guard let self, self.isCurrent(context), self.match(id)?.state == .dismissed else { return }
                    await self.setState(current.state, for: id)
                }
            }
            await reloadOverview(quiet: true)          // the counts are the server's
        } catch {
            guard isCurrent(context), !deletedHunts.contains(current.huntID) else { return }
            stateRevision += 1
            matchStateRevision[id] = stateRevision
            matchesByID[id] = keepingRead(current)
            handle(error, context: context) { self.show("\(state.failure) \($0)") }
        }
    }

    /// A listing's page opened (brief 180): it is read at once, here and on the server (`POST /matches/{id}/seen`), and
    /// keeps its state (only the user's actions change states). A new one loses its dot and leaves the "● 3 NEW" counts
    /// of its search and the account at once; the next overview confirms them. Sent once per listing; a failure keeps it
    /// read here, says nothing, and is sent again at the next opening.
    func markRead(_ id: Int) async {
        guard canAct, let current = match(id) else { return }
        if !current.seen {
            var read = current
            read.seen = true
            matchesByID[id] = read
            if read.state == .new { uncount(read) }
            unconfirmedReads.insert(id)
        }
        guard unconfirmedReads.contains(id), !sendingReads.contains(id) else { return }
        sendingReads.insert(id)
        let context = context
        defer { if isCurrent(context) { sendingReads.remove(id) } }
        do {
            _ = try await backend.markSeen(match: id)
            guard isCurrent(context) else { return }
            unconfirmedReads.remove(id)
        } catch {
            guard isCurrent(context) else { return }
            // Quietly: a refused login still counts (401 logs out, 403 closes the app); anything else waits for the
            // next opening.
            session.handleAuthFailure(error, generation: context.session, token: context.token)
        }
    }

    /// The accent dot: a new listing not opened yet.
    func showsNewDot(_ match: Match) -> Bool { match.state == .new && !match.seen }

    /// An unread new listing just read: one less in its search's and the account's new count.
    private func uncount(_ match: Match) {
        readRevision += 1
        countedReads[match.id] = (match.huntID, readRevision)
        guard var overview else { return }
        overview.counts.new = max(0, overview.counts.new - 1)
        if let index = overview.hunts.firstIndex(where: { $0.id == match.huntID }) {
            overview.hunts[index].counts.new = max(0, overview.hunts[index].counts.new - 1)
        }
        self.overview = overview
    }

    /// An overview asked for before some listings were read still counts them as unread new ones (they were new when
    /// read; a state changed since is not in it either): they are taken out again. The ones read before it was asked for
    /// are in its counts, and forgotten.
    private func uncount(readsAfter revision: Int, in overview: inout Overview) {
        for (id, read) in countedReads {
            guard read.revision > revision else {
                countedReads[id] = nil
                continue
            }
            overview.counts.new = max(0, overview.counts.new - 1)
            if let index = overview.hunts.firstIndex(where: { $0.id == read.hunt }) {
                overview.hunts[index].counts.new = max(0, overview.hunts[index].counts.new - 1)
            }
        }
    }

    // MARK: - filtered out

    /// The listings filtered out of every search (nil) or of one, as last loaded.
    func rejected(hunt: Int? = nil) -> RejectedList { rejectedLists[hunt] ?? RejectedList() }

    func loadRejected(hunt: Int? = nil) async {
        guard canAct, !(rejectedLists[hunt]?.isLoading ?? false) else { return }
        rejectedLists[hunt, default: RejectedList()].isLoading = true
        rejectedLists[hunt]?.error = nil
        let generation = listGeneration
        let context = context
        defer { if isCurrent(context) && generation == listGeneration { rejectedLists[hunt]?.isLoading = false } }
        do {
            let page = try await backend.rejected(hunt: hunt, limit: Self.pageSize)
            guard isCurrent(context) && generation == listGeneration else { return }
            rejectedLists[hunt]?.items = page.items
            rejectedLists[hunt]?.loaded = true
        } catch {
            guard isCurrent(context) && generation == listGeneration else { return }
            handle(error, context: context) { self.rejectedLists[hunt]?.error = $0 }
        }
    }

    // MARK: - monitor listings (Used and Alarms)

    func usedList(_ filter: MatchFilter = .all, hunt: Int) -> MatchList {
        monitorList(.used, hunt: hunt, filter: filter)
    }

    func usedMatches(_ filter: MatchFilter = .all, hunt: Int) -> [Match] {
        monitorMatches(.used, hunt: hunt, filter: filter)
    }

    func loadUsed(_ filter: MatchFilter = .all, hunt: Int, more: Bool = false, force: Bool = false) async {
        await loadMonitorListings(.used, hunt: hunt, filter: filter, more: more, force: force)
    }

    func monitorList(_ kind: MonitorListingKind, hunt: Int, filter: MatchFilter = .all) -> MatchList {
        monitorLists[MonitorListScope(hunt: hunt, filter: filter, kind: kind)] ?? MatchList()
    }

    func monitorMatches(_ kind: MonitorListingKind, hunt: Int, filter: MatchFilter = .all) -> [Match] {
        (monitorIDs[MonitorFeed(hunt: hunt, kind: kind)] ?? []).compactMap { matchesByID[$0] }
            .filter { $0.huntID == hunt && filter.includes($0.state) }.sorted { $0.id > $1.id }
    }

    func showsUsed(hunt: Int) -> Bool {
        card(hunt)?.hunt.search.price?.mode == .everywhere
            && (card(hunt)?.hunt.search.price?.includeUsed == true || !usedMatches(hunt: hunt).isEmpty)
    }

    private func invalidateMonitorListings(_ hunt: Int) {
        monitorGeneration[hunt, default: 0] += 1
        monitorLists = monitorLists.filter { $0.key.hunt != hunt }
        monitorLoadedFor = monitorLoadedFor.filter { $0.key.hunt != hunt }
        monitorRequests = monitorRequests.filter { $0.key.hunt != hunt }
        monitorLimits = monitorLimits.filter { $0.key.hunt != hunt }
    }

    /// Endpoints own feed membership. Known records keep shared state, including Used with its switch off.
    /// The inline Alarms read asks for three; opening its page expands that cached first page to the ordinary limit.
    func loadMonitorListings(_ kind: MonitorListingKind, hunt: Int, filter: MatchFilter = .all,
                             more: Bool = false, force: Bool = false, limit: Int = pageSize) async {
        let scope = MonitorListScope(hunt: hunt, filter: filter, kind: kind)
        let feed = MonitorFeed(hunt: hunt, kind: kind)
        guard canAct, hunt > 0, let card = card(hunt), kind.supports(card.hunt.search.price) else { return }
        if let pending = monitorRequests[scope], !pending.isCancelled {
            pending.require(limit)
            return
        }
        let read = MonitorListingsRead(card)
        if !more, !force, monitorLists[scope]?.loaded == true, monitorLoadedFor[scope] == read,
           (monitorLimits[scope] ?? 0) >= limit { return }
        let before = more ? monitorLists[scope]?.ids.min() : nil
        if more && (before == nil || monitorLists[scope]?.more != true) { return }
        let generation = monitorGeneration[hunt, default: 0]
        let context = context
        let revision = stateRevision
        let request = MonitorRequest()
        request.require(limit)
        monitorRequests[scope] = request
        monitorLists[scope, default: MatchList()].isLoading = true
        monitorLists[scope]?.error = nil
        defer {
            if isCurrent(context), monitorRequests[scope] === request {
                monitorLists[scope]?.isLoading = false
                monitorRequests[scope] = nil
            }
        }
        do {
            let page = try await withTaskCancellationHandler {
                switch kind {
                case .used: try await backend.used(hunt: hunt, state: filter.states, limit: limit, before: before)
                case .alarms: try await backend.priceAlarms(hunt: hunt, state: filter.states, limit: limit, before: before)
                }
            } onCancel: {
                request.cancel()
            }
            guard !Task.isCancelled, monitorRequests[scope] === request, isCurrent(context),
                  self.card(hunt)?.hunt.search == card.hunt.search,
                  monitorGeneration[hunt, default: 0] == generation else { return }
            let returned = Set(page.items.map(\.id))
            let lowest = page.items.map(\.id).min() ?? 0
            let upper = before ?? Int.max
            // Refresh removes records only from this feed's covered range, keeping unrelated feeds intact.
            for id in monitorIDs[feed] ?? [] {
                guard let known = matchesByID[id], filter.includes(known.state), !returned.contains(id),
                      !changingState.contains(id), (matchStateRevision[id] ?? 0) <= revision,
                      id < upper, !page.more || id >= lowest else { continue }
                monitorIDs[feed]?.remove(id)
            }
            for match in page.items { remember(match, since: revision) }
            monitorIDs[feed, default: []].formUnion(returned)
            let ids = (more ? monitorLists[scope]?.ids ?? [] : []) + page.items.map(\.id)
            monitorLists[scope]?.ids = Array(Set(ids)).sorted(by: >)
            monitorLists[scope]?.loaded = true
            monitorLists[scope]?.more = page.more
            monitorLoadedFor[scope] = read
            monitorLimits[scope] = more ? max(monitorLimits[scope] ?? 0, limit) : limit
        } catch {
            guard !Task.isCancelled, monitorRequests[scope] === request, isCurrent(context),
                  monitorGeneration[hunt, default: 0] == generation, self.card(hunt) != nil else { return }
            handle(error, context: context) { self.monitorLists[scope]?.error = $0 }
        }
        // Show all may open while the inline request is pending. Expand it once that request completes.
        if request.limit > limit, !Task.isCancelled, !request.isCancelled, isCurrent(context),
           monitorRequests[scope] === request, monitorLoadedFor[scope] == read {
            monitorRequests[scope] = nil
            monitorLists[scope]?.isLoading = false
            await loadMonitorListings(kind, hunt: hunt, filter: filter, limit: request.limit)
        }
    }

    // MARK: - price monitors

    /// A monitor's history over a window (30, 90 or 365 days), as last loaded.
    func prices(hunt id: Int, days: Int) -> PriceHistory {
        priceHistories[PriceHistoryKey(hunt: id, days: days)] ?? PriceHistory()
    }

    /// Loads a monitor's history over a window, quietly: again only once its card shows a newer read (a new point), or
    /// when `force`d (pull to refresh). A failure keeps what was shown; with nothing shown yet its sentence stays
    /// (`error`). A monitor without its history has none (the server's 404).
    func loadPrices(hunt id: Int, days: Int, force: Bool = false) async {
        let key = PriceHistoryKey(hunt: id, days: days)
        guard canAct, id > 0, let card = card(id), card.hunt.search.price?.history == true,
              !(priceHistories[key]?.isLoading ?? false) else { return }
        let checked = card.price?.checked
        if !force, let known = priceHistories[key], known.prices != nil, known.loadedFor == checked { return }
        priceHistories[key, default: PriceHistory()].isLoading = true
        let context = context
        defer { if isCurrent(context) { priceHistories[key]?.isLoading = false } }
        do {
            let loaded = try await backend.prices(hunt: id, days: days)
            guard isCurrent(context), self.card(id) != nil else { return }
            priceHistories[key]?.prices = loaded
            priceHistories[key]?.loadedFor = checked
            priceHistories[key]?.error = nil
        } catch HTTPError.server(404, _) {
            guard isCurrent(context) else { return }
            priceHistories[key]?.prices = Prices(points: [], low: nil, high: nil)
            priceHistories[key]?.loadedFor = checked
        } catch {
            guard isCurrent(context) else { return }
            if priceHistories[key]?.prices == nil {
                handle(error, context: context) { self.priceHistories[key]?.error = $0 }
            } else {
                session.handleAuthFailure(error, generation: context.session, token: context.token)
            }
        }
    }

    /// `POST /search/spelling` (brief 178): the server's suggestions for misspelled words of a thing search. A refused
    /// login goes to the session first; an answer for a login that has ended meanwhile is dropped (`CancellationError`).
    func spelling(_ words: [String]) async throws -> Spelling {
        guard canAct else { throw CancellationError() }
        let context = context
        do {
            let answer = try await backend.spelling(words: words)
            guard isCurrent(context) else { throw CancellationError() }
            return answer
        } catch let error as CancellationError {
            throw error
        } catch {
            guard isCurrent(context) else { throw CancellationError() }
            session.handleAuthFailure(error, generation: context.session, token: context.token)
            throw error
        }
    }

    /// `POST /price/preview`: what the server reads on a product page now. A refused login goes to the session first;
    /// an answer for a login that has ended meanwhile is dropped (`CancellationError`).
    func pricePreview(url: String) async throws -> PricePreview {
        guard canAct else { throw CancellationError() }
        let context = context
        do {
            let preview = try await backend.pricePreview(url: url)
            guard isCurrent(context) else { throw CancellationError() }
            return preview
        } catch let error as CancellationError {
            throw error
        } catch {
            guard isCurrent(context) else { throw CancellationError() }
            session.handleAuthFailure(error, generation: context.session, token: context.token)
            throw error
        }
    }

    /// A new preview for the monitor's form.
    func pricePreviewModel() -> PricePreviewModel {
        PricePreviewModel { [weak self] url in
            guard let self else { throw CancellationError() }
            return try await self.pricePreview(url: url)
        }
    }

    /// `POST /price/preview` with the product's words (brief 157): the product the server finds on the sites now. A
    /// refused login goes to the session first; an answer for a login that has ended meanwhile is dropped.
    func productPreview(_ words: ProductPreviewQuery) async throws -> ProductPreview {
        guard canAct else { throw CancellationError() }
        let context = context
        do {
            let preview = try await backend.productPreview(words)
            guard isCurrent(context) else { throw CancellationError() }
            return preview
        } catch let error as CancellationError {
            throw error
        } catch {
            guard isCurrent(context) else { throw CancellationError() }
            session.handleAuthFailure(error, generation: context.session, token: context.token)
            throw error
        }
    }

    /// A new product preview for the monitor's form (Überall).
    func productPreviewModel() -> ProductPreviewModel {
        ProductPreviewModel(pause: PreviewPacing.productPause) { [weak self] words in
            guard let self else { throw CancellationError() }
            return try await self.productPreview(words)
        }
    }

    /// An everywhere monitor's offers and sites, as last loaded.
    func offers(hunt id: Int) -> OffersState { priceOffers[id] ?? OffersState() }

    /// Loads an everywhere monitor's offers and sites, quietly: again only once its card shows a newer read, or when
    /// `force`d (pull to refresh, Try again). A failure keeps what was shown; with nothing shown yet its sentence stays.
    /// A page monitor has none (the server's 404).
    func loadOffers(hunt id: Int, force: Bool = false) async {
        guard canAct, id > 0, let card = card(id), card.hunt.search.price?.mode == .everywhere,
              !(priceOffers[id]?.isLoading ?? false) else { return }
        let checked = card.price?.checked
        if !force, let known = priceOffers[id], known.offers != nil, known.loadedFor == checked { return }
        priceOffers[id, default: OffersState()].isLoading = true
        let context = context
        defer { if isCurrent(context) { priceOffers[id]?.isLoading = false } }
        do {
            let loaded = try await backend.offers(hunt: id)
            guard isCurrent(context), self.card(id) != nil else { return }
            priceOffers[id]?.offers = loaded
            priceOffers[id]?.loadedFor = checked
            priceOffers[id]?.error = nil
        } catch HTTPError.server(404, _) {
            guard isCurrent(context) else { return }
            priceOffers[id]?.offers = PriceOffers()
            priceOffers[id]?.loadedFor = checked
        } catch {
            guard isCurrent(context) else { return }
            if priceOffers[id]?.offers == nil {
                handle(error, context: context) { self.priceOffers[id]?.error = $0 }
            } else {
                session.handleAuthFailure(error, generation: context.session, token: context.token)
            }
        }
    }

    /// The shop an alarm names: the cheapest offer's (`source_name`) for an everywhere monitor's alarm, nil otherwise
    /// (a page monitor's alarm names nothing; its shop is the host under it).
    func alarmShop(of match: Match) -> String? {
        guard match.isPriceChange, card(match.huntID)?.hunt.search.price?.mode == .everywhere else { return nil }
        return HuntText.text(match.listing.sourceName)
    }

    /// A monitor's switches changed on its page (brief 137, "changeable anytime"): shown at once and saved with the whole
    /// search (`PUT`, the name as it is). Changes made while one is on its way are sent once it has answered, the newest
    /// only. A refusal puts back what the server last confirmed, with a notice. Only the switches and the conditions come
    /// from the server's answer, so a start or pause meanwhile is kept.
    func saveMonitor(id: Int, search: PriceSearch) async {
        guard canAct, id > 0, let card = card(id), card.hunt.search.price != nil else { return }
        var shown = card.hunt
        shown.search = .price(search)
        putHunt(shown)
        guard !savingMonitors.contains(id) else {
            monitorWanted[id] = search
            return
        }
        savingMonitors.insert(id)
        let context = context
        defer { if isCurrent(context) { savingMonitors.remove(id); monitorWanted[id] = nil } }
        var confirmed = card.hunt.search
        var sending = search
        while true {
            do {
                let saved = try await backend.updateHunt(id: id, search: .price(sending), name: self.card(id)?.hunt.name)
                guard isCurrent(context) else { return }
                confirmed = saved.search
                if let next = monitorWanted.removeValue(forKey: id), next != sending {
                    sending = next
                    continue
                }
                if var current = self.card(id)?.hunt {
                    current.search = saved.search
                    current.updated = saved.updated
                    putHunt(current)
                }
                break
            } catch {
                guard isCurrent(context) else { return }
                monitorWanted[id] = nil
                if var current = self.card(id)?.hunt {
                    current.search = confirmed
                    putHunt(current)
                }
                handle(error, context: context) { self.show(String(localized: "Not saved. \($0)")) }
                return
            }
        }
        savingMonitors.remove(id)
        await reloadOverview(quiet: true)
    }

    // MARK: - applications

    func application(_ match: Int) -> ApplicationState { applications[match] ?? ApplicationState() }

    /// The application text for a match: the one already written for it if it fits the current mode, else the
    /// server writes it (`regenerate` = "Write again").
    func loadApplication(for id: Int, regenerate: Bool = false) async {
        guard canAct, !(applications[id]?.isLoading ?? false) else { return }
        guard let loadedMatch = await loadMatch(id) else { return }
        if kind(of: loadedMatch) != .flat {
            applications[id] = ApplicationState(error: String(localized: "Application texts are for flats."))
            return
        }
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
        changingHunts = []
        overview = nil
        overviewError = nil
        lastOverviewLoad = nil
        isLoadingOverview = false
        kinds = nil
        isLoadingKinds = false
        forgetMatches()
        settings = nil
        settingsError = nil
        isLoadingSettings = false
        isSavingSearch = false
        clearSearchError()
        isParsing = false
        parseError = nil
        notice = nil
        foregroundRefreshing = false
        places.reset()
    }

    private func forgetMatches() {
        undo = nil
        listGeneration += 1
        deletedHunts = []
        matchesByID = [:]
        huntLatest = [:]
        lists = [:]
        unconfirmedReads = []
        sendingReads = []
        countedReads = [:]
        changingState = []
        matchErrors = [:]
        rejectedLists = [:]
        applications = [:]
        priceHistories = [:]
        priceOffers = [:]
        monitorLists = [:]
        monitorIDs = [:]
        monitorGeneration = [:]
        monitorLoadedFor = [:]
        monitorLimits = [:]
        monitorRequests = [:]
        matchStateRevision = [:]
        savingMonitors = []
        monitorWanted = [:]
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

    private func remember(_ match: Match, since revision: Int? = nil) {
        // A match whose state is being changed here keeps the state shown until the server answers.
        guard !deletedHunts.contains(match.huntID), !changingState.contains(match.id),
              revision.map({ (matchStateRevision[match.id] ?? 0) <= $0 }) ?? true else { return }
        matchesByID[match.id] = keepingRead(match)
    }

    /// Read here stays read, whatever an answer from before the server knew it says (the server never unreads one).
    private func keepingRead(_ match: Match) -> Match {
        guard !match.seen, unconfirmedReads.contains(match.id) || matchesByID[match.id]?.seen == true else { return match }
        var read = match
        read.seen = true
        return read
    }

    /// A page from the server is the truth for its scope: matches of that filter (and search) it no longer lists are
    /// gone (changed or removed elsewhere), within the range the page covers.
    private func merge(_ page: MatchPage, scope: ListScope, appending: Bool, since revision: Int) {
        let returned = Set(page.items.map(\.id))
        let lowest = page.items.map(\.id).min() ?? 0
        let upper = appending ? (lists[scope]?.ids.min() ?? Int.max) : Int.max
        for (id, match) in matchesByID where (scope.hunt == nil || match.huntID == scope.hunt)
            && scope.filter.includes(match) && !returned.contains(id)
            && !changingState.contains(id) && (matchStateRevision[id] ?? 0) <= revision && id < upper && (!page.more || id >= lowest) {
            matchesByID[id] = nil
        }
        for match in page.items { remember(match, since: revision) }
        let ids = page.items.map(\.id)
        lists[scope, default: MatchList()].ids = appending ? (lists[scope]?.ids ?? []) + ids : ids
        lists[scope]?.more = page.more
        lists[scope]?.loaded = true
        lists[scope]?.error = nil
    }
}

extension MatchState {
    /// "Could not make the listing a favorite."
    var failure: String {
        switch self {
        case .new: String(localized: "Could not reset the listing.")
        case .saved: String(localized: "Could not make the listing a favorite.")
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
