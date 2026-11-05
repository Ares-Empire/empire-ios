import Foundation
import Observation
import os

// The tour (brief 139, Patrik 2026-11-02: "it's not actually clear what Seite beobachten is for … We should add a tour
// to Arestemis (like Aresium has) that explains it"; eight steps, the sketch's section 6). It runs the app's real tabs
// on a world of its own: its own searches and listings in the app's language (`TourData`) as a server in memory
// (`SampleBackend`), its own store, a session that is never logged in and its own navigation, so the account's searches,
// listings, drafts and choices are never touched. Each step points at one part of a real screen (`TourSpot`, the shared veil and
// ring of `Shared/Design/TourPieces.swift`) and says what it is for in one or two sentences; Next goes on, Skip ends it.
// It shows by itself once per account on this iPhone, after the first login (`TourOffer`), and again from Settings →
// Help. The look is `Screens/TourScreens.swift`.

/// The tour's steps, in order. The raw value numbers a step (DEBUG `-tour <n>`).
nonisolated enum TourStep: Int, CaseIterable, Sendable {
    case welcome = 1, newSearch, search, newListings, searches, listing, monitorsAndWatches, filteredOut

    /// The card's title: the place the step is about, as the app names it.
    func title(_ language: AppLanguage = .current) -> String {
        switch self {
        case .welcome: language.string("Arestemis searches for you")
        case .newSearch: language.string("New search")
        case .search: language.string("A search")
        case .newListings: language.string("Listings → New")
        case .searches: language.string("Listings → Searches")
        case .listing: language.string("A listing")
        case .monitorsAndWatches: language.string("Price monitor and Watch a website")
        case .filteredOut: language.string("Filtered out")
        }
    }

    /// The card's words, as lines: one or two short sentences; the Preismonitor and the page watch get a line each,
    /// led by the kind's name.
    func lines(_ language: AppLanguage = .current) -> [TourLine] {
        switch self {
        case .welcome:
            [TourLine(language.string("Every few minutes it reads the sites, checks each new listing against your search and sends you a push when one fits. The tour shows sample searches."))]
        case .newSearch:
            [TourLine(language.string("Four kinds: Flat (2 rooms up to €1,100), Things (a Kallax up to €40), Price monitor (one product's price) and Watch a website (a new version). Tap an example and the form is filled in."))]
        case .search:
            [TourLine(language.string("It runs until you pause it; the number shows the new listings you haven't seen yet. Tap the card for its page."))]
        case .newListings:
            [TourLine(language.string("Everything new, grouped by search. Swipe right to make a listing a favorite, left to dismiss it."))]
        case .searches:
            [TourLine(language.string("Each search with its listings. The magnifying glass searches all of them."))]
        case .listing:
            [TourLine(language.string("The facts at a glance, “–” where the listing doesn't say, and what to check yourself. For flats, “Application text” gives you a text to send."))]
        case .monitorsAndWatches:
            // The kinds' names as New search shows them (`SearchKind.choiceTitle`, the same words).
            [TourLine(label: language.string("Price monitor"),
                      language.string("A push when a product gets cheaper or is back in stock, in one shop or everywhere, with its curve.")),
             TourLine(label: language.string("Watch a website"),
                      language.string("A push when something new appears on a page: a version, a job, the menu."))]
        case .filteredOut:
            [TourLine(language.string("What the check turned down in the last 7 days, each with its reason. If good listings end up here, the search is too strict."))]
        }
    }

    /// The card's words as one text, a line about a kind led by "Name: " (as the card shows it).
    func text(_ language: AppLanguage = .current) -> String {
        lines(language).map { line in line.label.map { "\($0): \(line.text)" } ?? line.text }.joined(separator: "\n")
    }
}

/// One line of a card's words; a line about one kind is led by its name.
nonisolated struct TourLine: Equatable, Sendable {
    var label: String? = nil
    let text: String

    init(label: String? = nil, _ text: String) {
        self.label = label
        self.text = text
    }
}

/// The parts of the real screens the tour points at; each marks itself with `.tourAnchor(_:)`.
nonisolated enum TourSpot: Hashable, Sendable {
    /// New search's first card: a kind with its examples.
    case kindCard
    /// A search's card on the Hunts list, by its id.
    case huntCard(Int)
    /// A listing's row in Listings → New, by the match's id.
    case newListing(Int)
    /// The Listings tab's magnifying glass: the search over every search's listings.
    case findAll
    /// A listing's facts on its page, with what to check at their foot.
    case listingFacts
    /// "Filtered out" at the end of a list of listings.
    case filteredOut
}

/// The tour's state, one model that tests drive step by step: the step, and the made-up world its screens run on.
@MainActor @Observable
final class TourModel {
    enum Phase: Equatable {
        /// The made-up world is being made (a moment: the samples are read from the app).
        case preparing
        case running
        /// The made-up world could not be made.
        case failed(String)
        /// Ended (Skip, Done, a notification or a link): the world is gone; the account's app is as it was.
        case ended
    }

    private(set) var phase = Phase.preparing
    private(set) var step = TourStep.welcome
    private(set) var world: TourWorld?
    /// The card's height at the bottom of the tabs: the pages under it keep that much room (`tourCardRoom`).
    var cardRoom: CGFloat = 0
    @ObservationIgnored private let makeWorld: () async throws -> TourWorld
    private static let log = Logger(subsystem: "de.ares-empire.arestemis", category: "tour")

    init(makeWorld: @escaping () async throws -> TourWorld = { try await TourWorld.make() }) {
        self.makeWorld = makeWorld
    }

    /// The steps, in order.
    var steps: [TourStep] { TourStep.allCases }
    /// How many steps, and the current one's place ("3 / 8").
    var count: Int { steps.count }
    var number: Int { (steps.firstIndex(of: step) ?? 0) + 1 }

    /// The step after the current one; nil at the last.
    var nextStep: TourStep? {
        guard let index = steps.firstIndex(of: step), steps.indices.contains(index + 1) else { return nil }
        return steps[index + 1]
    }

    /// Makes the world, then shows `first` (the welcome; DEBUG screenshots start at any step).
    func start(at first: TourStep = .welcome) async {
        guard phase == .preparing, world == nil else { return }
        do {
            let world = try await makeWorld()
            guard phase == .preparing else {
                world.forget()                      // ended while it was being made
                return
            }
            self.world = world
            phase = .running
            go(to: first)
        } catch {
            Self.log.error("the tour's world was not made: \(String(describing: error), privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// Skip (on the card at every step but the last), Done (the last), or a notification or link the app opens: the
    /// world goes; the account's own app shows as it was left.
    func end() {
        guard phase != .ended else { return }
        phase = .ended
        world?.forget()
        world = nil
    }

    /// Next: the following step; at the last, Done ends the tour.
    func next() {
        guard phase == .running else { return }
        if let next = nextStep { go(to: next) } else { end() }
    }

    // MARK: where the tour points

    /// What the current step points at, as the screens mark it; empty while nothing is (the welcome). A spot that is not
    /// on the screen shown (the person opened a card's page, say) shows no veil there, so that screen is free until Next
    /// gets the step's screen ready again.
    var targets: [TourSpot] {
        guard phase == .running, let world else { return [] }
        switch step {
        case .welcome: return []
        case .newSearch: return [.kindCard]
        case .search: return world.store.hunts.first.map { [.huntCard($0.id)] } ?? []
        case .newListings:
            // The newest listing of the search with the newest finding: the row its swipe works on.
            return NewListings.groups(world.store.matches(.new)).first?.matches.first.map { [.newListing($0.id)] } ?? []
        case .searches: return [.findAll]
        case .listing: return [.listingFacts]
        case .monitorsAndWatches: return world.monitorAndWatch.map(TourSpot.huntCard)
        case .filteredOut: return [.filteredOut]
        }
    }

    // MARK: getting each step's screen ready

    private func go(to step: TourStep) {
        self.step = step
        prepare(step)
    }

    /// The real screen a step names, on the tour's own navigation (a tap the person made on the way is undone here, as
    /// Next always gets the step's screen ready).
    private func prepare(_ step: TourStep) {
        guard let world else { return }
        let navigation = world.navigation
        navigation.sheet = nil
        navigation.showsPlaceSearch = false
        navigation.showsDescribe = false
        switch step {
        case .welcome, .search, .monitorsAndWatches:
            navigation.tab = .hunt
            navigation.huntPath = []
        case .newSearch:
            navigation.tab = .hunt
            navigation.huntPath = [.newSearch]
        case .newListings:
            navigation.tab = .listings
            navigation.part = .new
            navigation.listingsPath = []
        case .searches:
            navigation.tab = .listings
            navigation.part = .searches
            navigation.listingsPath = []
        case .listing:
            // A flat's listing, opened from Searches as a tap on it would.
            navigation.tab = .listings
            navigation.part = .searches
            navigation.listingsPath = world.flatMatch.map { [.match($0)] } ?? []
        case .filteredOut:
            // The flat search's listings at New: one listing, then "Filtered out" under it.
            navigation.tab = .listings
            navigation.part = .searches
            if let hunt = world.flatHunt {
                navigation.filter = .new
                navigation.listingsPath = [.hunt(hunt)]
            }
        }
    }
}

/// The tour's made-up world: its own searches and listings in the app's language (`TourData`) as a server in memory
/// (`SampleBackend`), a store on it with a session of its own that is never logged in, and a navigation whose
/// remembered choice (New or Searches) lives in a defaults suite of its own. Nothing here reads or writes the account's store, the shared login, its drafts or the
/// app's defaults. `forget()` empties that suite.
@MainActor
final class TourWorld {
    /// The tour's own defaults (the Listings tab's remembered part, kept drafts): emptied when a world is made and when
    /// it goes.
    static let suite = "de.ares-empire.arestemis.tour"

    let store: ArestemisStore
    let navigation: AppNavigation
    /// The flat listing the listing step opens, and its search (whose "Filtered out" the last step shows).
    let flatMatch: Int?
    let flatHunt: Int?
    /// The last page watch before the first price monitor on the Hunts list (or the first of each): the two cards the
    /// step about them rings together.
    let monitorAndWatch: [Int]
    private let defaults: UserDefaults

    private init(store: ArestemisStore, navigation: AppNavigation, defaults: UserDefaults) {
        self.store = store
        self.navigation = navigation
        self.defaults = defaults
        let flat = NewListings.groups(store.matches(.new)).flatMap(\.matches)
            .first { store.kind(of: $0) == .flat }
        flatMatch = flat?.id
        flatHunt = flat?.huntID ?? store.hunts.first { $0.hunt.kind == .flat }?.id
        monitorAndWatch = Self.monitorAndWatch(store.hunts)
    }

    /// Makes the tour's data into a store of its own and loads what its steps show.
    static func make(now: Date = .now, language: AppLanguage = .current) async throws -> TourWorld {
        let defaults = UserDefaults(suiteName: suite) ?? UserDefaults()
        defaults.removePersistentDomain(forName: suite)
        let backend = try SampleBackend(content: TourData.content(now: now, language: language), now: now)
        // Its own session, never logged in: the tour asks no server and follows no login.
        let session = EmpireSession(app: .arestemis, storage: TourTokens(), restoreOnLaunch: false)
        let store = ArestemisStore(session: session, backend: backend, sample: true, defaults: defaults)
        await store.reloadOverview()
        guard store.overview != nil else { throw TourError.noSample(store.overviewError) }
        await store.loadKinds()
        await store.loadMatches(.new)
        return TourWorld(store: store, navigation: AppNavigation(defaults: defaults), defaults: defaults)
    }

    /// The cards the step about the Preismonitor and the page watch rings: a watch and a monitor that stand together.
    static func monitorAndWatch(_ hunts: [HuntCard]) -> [Int] {
        for (index, card) in hunts.enumerated() where card.hunt.kind == .price && index > 0
            && hunts[index - 1].hunt.kind == .watch {
            return [hunts[index - 1].id, card.id]
        }
        return [hunts.first { $0.hunt.kind == .watch }?.id, hunts.first { $0.hunt.kind == .price }?.id].compactMap { $0 }
    }

    /// Empties the tour's own defaults.
    func forget() {
        defaults.removePersistentDomain(forName: Self.suite)
    }

    enum TourError: LocalizedError {
        case noSample(String?)
        var errorDescription: String? {
            switch self { case .noSample(let message): message ?? "The sample did not load." }
        }
    }
}

/// The tour's session keeps no login.
private final class TourTokens: TokenStorage {
    func read() throws -> String? { nil }
    func save(_ token: String) throws {}
    func delete() throws {}
}

/// The tour's place in the app (`ContentView`): at most one runs, in place of the account's tabs; it starts by itself
/// once per account (`TourOffer`), from Settings → Help at any time, and goes when it ends.
@MainActor @Observable
final class TourRunner {
    private(set) var tour: TourModel?
    @ObservationIgnored let offer: TourOffer
    @ObservationIgnored private let makeTour: () -> TourModel

    init(offer: TourOffer = TourOffer(), makeTour: @escaping () -> TourModel = { TourModel() }) {
        self.offer = offer
        self.makeTour = makeTour
    }

    /// The tour now (Settings → Help, DEBUG `-tour`), at `step`: its world is made, then it shows. The account has seen
    /// it from now on, so it does not start by itself again.
    func start(at step: TourStep = .welcome, account: String?) async {
        guard tour == nil else { return }
        if let account { offer.remember(account: account) }
        let model = makeTour()
        tour = model
        await model.start(at: step)
    }

    /// The account's main screen showed: the tour starts by itself if the moment allows (`TourOffer`).
    func offer(_ moment: TourOffer.Moment) async {
        guard tour == nil, offer.starts(moment) else { return }
        await start(account: moment.account)
    }

    /// A notification, a link or logging out: the tour ends first.
    func end() { tour?.end() }

    /// The tour ended (Skip, Done, `end`) or could not start: it goes, and the account's tabs show as they were.
    func clearEnded() {
        switch tour?.phase {
        case .ended?, .failed?: tour = nil
        default: break
        }
    }
}

/// The tour shows by itself once per account on this iPhone (brief 139): when the account's main screen first shows
/// here (after its first login, or the first launch of a build with the tour), never over a notification or link being
/// opened, a sheet or a page pushed, never in sample mode. Remembered per account in the app's defaults once it has
/// started, so skipping it or closing the app during it does not bring it back; Settings → Help starts it again.
struct TourOffer {
    static let prefix = "arestemis.tourShown."
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// What the moment is like when the main screen shows.
    struct Moment: Equatable {
        /// The signed-in account; nil in sample mode or without a login.
        var account: String?
        /// The account's main screen is up (its overview arrived).
        var mainScreen: Bool
        /// A notification or link is being opened, a sheet is up, or a page is pushed on either tab.
        var busy: Bool
    }

    /// Whether the tour starts by itself now.
    func starts(_ moment: Moment) -> Bool {
        guard let account = moment.account, moment.mainScreen, !moment.busy else { return false }
        return !shown(account: account)
    }

    func shown(account: String) -> Bool { defaults.bool(forKey: Self.prefix + account) }

    /// The tour started for this account (by itself or from Settings): it does not start by itself again.
    func remember(account: String) { defaults.set(true, forKey: Self.prefix + account) }
}
