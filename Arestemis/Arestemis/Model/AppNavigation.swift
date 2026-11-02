import Foundation
import Observation

/// The two tabs: the hunts (the first tab, "Suche") and their listings ("Angebote"). A hunt's search opens from the hunt.
enum AppTab: String, Hashable, CaseIterable {
    case hunt, listings
}

/// The Listings tab's two parts (brief 133, Patrik's choice): everything new across the searches, grouped by search, or
/// one row per search, each opening that search's listings.
enum ListingsPart: String, CaseIterable, Hashable, Identifiable {
    case new, searches
    var id: String { rawValue }

    /// The switch's word: "New" / "Searches" ("Neu" / "Suchen").
    func title(language: AppLanguage = .current) -> String {
        switch self {
        case .new: language.string("New")
        case .searches: language.string("Searches")
        }
    }
}

/// What the Listings tab pushes: one search's listings (its page), the search over the found listings (of every search,
/// or of one), and a match's page.
enum ListingsRoute: Hashable {
    case hunt(Int)
    case find(hunt: Int?)
    case match(Int)

    /// The search this route belongs to, if it is one search's page or its search over listings.
    var hunt: Int? {
        switch self {
        case .hunt(let id): id
        case .find(let id): id
        case .match: nil
        }
    }
}

/// The part of the Listings tab the user chose last, kept across launches (nothing else of the tab is).
struct ListingsPartMemory {
    static let key = "arestemis.listingsPart"
    let defaults: UserDefaults

    /// New until the user chose otherwise.
    var chosen: ListingsPart { defaults.string(forKey: Self.key).flatMap(ListingsPart.init(rawValue:)) ?? .new }

    func remember(_ part: ListingsPart) { defaults.set(part.rawValue, forKey: Self.key) }
}

/// What the Hunts tab pushes: a hunt's page, a match's page, New search (the kinds to choose from, brief 135), or a
/// search form (a hunt's search, or a new one, empty or filled in from one of New search's examples).
enum HuntRoute: Hashable {
    case hunt(Int)
    case match(Int)
    case newSearch
    case form(SearchKind, hunt: Int?, example: SearchExample? = nil)
}

/// The filter of one search's listings: New · Saved · Applied · All (all = every state but dismissed, the API's default).
enum MatchFilter: String, CaseIterable, Hashable, Identifiable {
    case new, saved, applied, all
    var id: String { rawValue }

    var title: String { title() }

    /// The picker's word; `applied` is "Asked" while only things are shown (a seller is asked, not applied to).
    func title(asked: Bool = false, language: AppLanguage = .current) -> String {
        switch self {
        case .new: language.string("New")
        case .saved: language.string("Saved")
        case .applied: asked ? language.string("Asked") : language.string("Applied")
        case .all: language.string("All")
        }
    }

    /// The `state=` query; nil = the server's default.
    var states: [MatchState]? {
        switch self {
        case .new: [.new]
        case .saved: [.saved]
        case .applied: [.applied]
        case .all: nil
        }
    }

    func includes(_ state: MatchState) -> Bool {
        states?.contains(state) ?? (state != .dismissed)
    }

    /// The filters a search's page offers: a watch's changes and a monitor's alarms are only saved or dismissed, never
    /// applied for.
    static func choices(for kind: SearchKind?) -> [MatchFilter] {
        kind.map { !$0.appliesOrAsks } == true ? [.new, .saved, .all] : allCases
    }

    /// Where a search's listings open when nothing asks for a filter: New while it has new ones, else All.
    static func opening(_ counts: Overview.Counts?) -> MatchFilter {
        (counts?.new ?? 0) > 0 ? .new : .all
    }
}

/// The sheets shown over the tabs. `rejected`: the listings filtered out of every search (nil) or of one.
enum RootSheet: Identifiable, Equatable {
    case settings, rejected(Int?), application(Int)
    var id: String {
        switch self {
        case .settings: "settings"
        case .rejected(let hunt): "rejected-\(hunt.map(String.init) ?? "all")"
        case .application(let match): "application-\(match)"
        }
    }
}

/// Where the user is: the tab, each tab's pushed pages, the open sheet. Links and notifications go through `open`.
@MainActor @Observable
final class AppNavigation {
    var tab: AppTab = .hunt
    var huntPath: [HuntRoute] = []
    /// The Listings tab's part (New or Searches). The user's own choice is remembered across launches (`choose`); a link
    /// or a hunt's page shows a part without changing that choice.
    var part: ListingsPart
    var listingsPath: [ListingsRoute] = []
    /// The filter of the search's page that is open on the Listings tab.
    var filter: MatchFilter = .new
    var sheet: RootSheet?
    /// The hunt whose page opens with its name's field ready (a card's long press → Rename); the page takes it.
    var renaming: Int?
    var showsPlaceSearch = false
    /// A search form's "Describe it" sheet.
    var showsDescribe = false
    /// What the place search starts with (empty, or a sample query for screenshots).
    var placeQuery = ""
    /// Screenshots: where the next search form scrolls to ("size", "rent", "movein", "bottom").
    var formScroll: String?
    /// A link asked to open this match's portal page; the root opens it once the match is known.
    var pendingListing: Int?
    /// What the next search over listings starts with (empty, or words for screenshots: `-search`).
    var findQuery = ""
    /// A link waiting for the tabs to be on screen (a match pushed before they appear keeps the tab bar showing).
    private(set) var pendingLink: ArestemisLink?
    @ObservationIgnored private let partMemory: ListingsPartMemory

    init(defaults: UserDefaults = .standard) {
        partMemory = ListingsPartMemory(defaults: defaults)
        part = partMemory.chosen
    }

    /// The user picks a part: shown, and remembered for the next launch.
    func choose(_ part: ListingsPart) {
        self.part = part
        partMemory.remember(part)
    }

    /// A link or notification: queued until the tabs are on screen, then `open(_:)`.
    func follow(_ link: ArestemisLink) { pendingLink = link }

    /// The tabs are on screen: the queued link, if any, is opened.
    func openPendingLink() {
        guard let link = pendingLink else { return }
        pendingLink = nil
        open(link)
    }

    /// The match on the Listings tab over New (where a notification leads), then what the link asked for.
    func open(_ link: ArestemisLink) {
        tab = .listings
        part = .new
        listingsPath = [.match(link.match)]
        showsPlaceSearch = false
        showsDescribe = false
        sheet = link.then == .application ? .application(link.match) : nil
        pendingListing = link.then == .openListing ? link.match : nil
    }

    /// A match's page on the tab it was tapped on (the Hunts tab keeps it in its own stack).
    func showMatch(_ id: Int) {
        switch tab {
        case .hunt: huntPath.append(.match(id))
        case .listings: listingsPath.append(.match(id))
        }
    }

    /// The Listings tab at its start, as the user left its part (the Hunts tab's "All listings").
    func showListings() {
        tab = .listings
        listingsPath = []
    }

    /// One search's listings at a filter, from outside the Listings tab (a hunt's page: Listings and its figures): its
    /// page over Searches, so back leads to the searches.
    func showSearch(_ hunt: Int, filter: MatchFilter) {
        tab = .listings
        part = .searches
        listingsPath = [.hunt(hunt)]
        self.filter = filter
    }

    /// One search's listings at a filter, pushed on the Listings tab (a row of Searches, a group's heading in New).
    func openSearch(_ hunt: Int, filter: MatchFilter) {
        self.filter = filter
        listingsPath.append(.hunt(hunt))
    }

    /// The search over found listings, of every search (nil) or of one, pushed on the Listings tab.
    func find(hunt: Int?) {
        listingsPath.append(.find(hunt: hunt))
    }

    /// New search from anywhere: its page on the Hunts tab, over the list of hunts.
    func startNewSearch() {
        tab = .hunt
        huntPath = [.newSearch]
    }

    /// A kind's new form, pushed on the Hunts tab (over New search): empty (as the user left it, `KeptSearchDraft`), or
    /// filled in from an example.
    func openNewForm(_ kind: SearchKind, example: SearchExample? = nil) {
        tab = .hunt
        huntPath.append(.form(kind, hunt: nil, example: example))
    }

    /// A new hunt was saved: its page replaces the form it was made in and New search under it, so back leads to the
    /// list of hunts.
    func showCreated(_ id: Int) {
        if case .form(_, nil, _)? = huntPath.last { huntPath.removeLast() }
        if huntPath.last == .newSearch { huntPath.removeLast() }
        huntPath.append(.hunt(id))
    }

    /// Rename from a search's card (its long press, on either tab): the search's page on the Hunts tab, its name's field
    /// ready.
    func rename(_ hunt: Int) {
        tab = .hunt
        huntPath = [.hunt(hunt)]
        renaming = hunt
    }

    /// A hunt was deleted (from its page or its form): back to the list of hunts; the Listings tab leaves its pages.
    func leaveDeleted(_ hunt: Int? = nil) {
        huntPath = []
        if let hunt, let index = listingsPath.firstIndex(where: { $0.hunt == hunt }) {
            listingsPath.removeSubrange(index...)
        }
    }

    /// Back to the start (after logging out).
    func reset() {
        tab = .hunt
        huntPath = []
        part = partMemory.chosen
        listingsPath = []
        filter = .new
        sheet = nil
        renaming = nil
        showsPlaceSearch = false
        showsDescribe = false
        placeQuery = ""
        findQuery = ""
        formScroll = nil
        pendingListing = nil
        pendingLink = nil
    }
}

/// DEBUG launch arguments for screenshots: `-sampleData`, `-sampleNoHunt`, `-samplePaused`, `-sampleLoading`,
/// `-sampleSlowed` (the thing hunt is checked less often), `-sampleNewerKind` (a hunt of a kind this build does not know),
/// `-sampleEbayNotReady` (eBay not set up on the server: greyed in the thing form, read by no hunt), `-sampleDelivery
/// pickup|shipping|either` (that delivery chosen in the thing form, read by `ArestemisStore.itemSearchDraft`),
/// `-tab hunt|listings` (`search`: the first hunt's form), brief 133's `-listings new|searches` (the Listings tab's part),
/// `-openSearch <id>` (that search's listings, over Searches), `-search <words>` (the search over listings with the words
/// typed, the keyboard down; within the search `-openSearch` opened), `-filter new|saved|applied|all` (a search's
/// listings), `-openMatch <id>`, `-openHunt <id>` (a hunt's page), `-openForm <id>` (that hunt's
/// form), `-openItemForm` (the first thing hunt's form), `-newItemForm` / `-newFlatForm` (an empty form), brief 131's
/// `-openWatchForm` (the first watch's form) and `-newWatchForm` (in the form `-watchURL <text>`, `-watchChange <text>`
/// and `-saveWatch`, read by `WatchSearchScreen`), `-sampleWatchRead <read>` (the second watch's page
/// state: waiting, ok, unreadable, failing, blocked or any other word), `-scrollToHunt <id>` (the Hunts list at that
/// hunt's card), brief 135's `-newSearch` (New search's page), `-newExample <example>` (an example's form, filled in, over
/// New search: `SearchExample`'s names, e.g. `twoRooms`, `kallax`, `newVersion`), `-renameHunt <id>` (that hunt's page
/// with its name's field open; `-renameText <text>` types in it, read by `HuntPage`), brief 137's `-openPriceForm` (the
/// first price monitor's form) and `-newPriceForm` (in the form `-priceURL <text>`, `-pricePreview reading|refused|failed`
/// and `-priceSwitches history|alarm|none`, read by `PriceSearchScreen`), `-priceDays 30|90|365` (the chart on a
/// monitor's page) and `-monitorLine refused|hold` (its switches' line, read by `MonitorPage`),
/// `-openSheet settings|application|rejected|place|describe` (place and describe over a form, the
/// first hunt's unless another is asked for; rejected: of the search `-openSearch` opened, else of every search), `-scrollBottom` (Hunts and the forms), `-scrollTo size|rent|movein`
/// (the flat form), `-scrollTo where` (the thing form), `-sampleUndo`, `-sampleSearchDraft`, `-sampleMoreLoading`,
/// `-sampleMoreFailure`, `-sampleLongDescription`; brief 139's `-tour <1–8>` (the tour at that step; `-tourSheet rejected|application`); Settings → Flats: `-sampleOwnMode` (the switch off), `-sampleNoTexts` (nothing written
/// yet), `-openSettingsPage ownText|notes|aboutMe` (with `-openSheet settings`, read by `SettingsSheet`). In a release
/// build all are ignored.
struct LaunchOptions {
    /// Which search form opens at launch.
    enum Form: Equatable {
        case hunt(Int)              // -openForm <id>
        case firstHunt              // -tab search, or a sheet over a form without another form asked for
        case firstItem              // -openItemForm
        case firstWatch             // -openWatchForm
        case firstPrice             // -openPriceForm
        case new(SearchKind)        // -newFlatForm, -newItemForm, -newWatchForm, -newPriceForm
        case example(SearchExample) // -newExample <example>
    }

    var sample = false
    var noHunt = false
    var paused = false
    var loading = false
    var slowed = false
    var newerKind = false
    var ebayNotReady = false
    var watchRead: String?
    var pricePreview: String?
    var scrollToHunt: Int?
    var sampleUndo = false
    var moreLoading = false
    var moreFailure = false
    var longDescription = false
    var ownMode = false
    var noTexts = false
    var tab: AppTab?
    var listings: ListingsPart?
    var openSearch: Int?
    var search: String?
    var filter: MatchFilter?
    var openMatch: Int?
    var openHunt: Int?
    var form: Form?
    var newSearch = false
    var renameHunt: Int?
    var openSheet: String?
    var scrollTo: String?
    /// `-tour <1–8>`: the tour at that step (brief 139); `-tourSheet rejected|application` then opens that sheet.
    var tour: Int?
    var tourSheet: String?

    init(arguments: [String]) {
        #if DEBUG
        func value(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        sample = arguments.contains("-sampleData")
        noHunt = arguments.contains("-sampleNoHunt")
        paused = arguments.contains("-samplePaused")
        loading = arguments.contains("-sampleLoading")
        slowed = arguments.contains("-sampleSlowed")
        newerKind = arguments.contains("-sampleNewerKind")
        ebayNotReady = arguments.contains("-sampleEbayNotReady")
        watchRead = value("-sampleWatchRead")
        pricePreview = value("-pricePreview")
        scrollToHunt = value("-scrollToHunt").flatMap(Int.init)
        sampleUndo = arguments.contains("-sampleUndo")
        moreLoading = arguments.contains("-sampleMoreLoading")
        moreFailure = arguments.contains("-sampleMoreFailure")
        longDescription = arguments.contains("-sampleLongDescription")
        ownMode = arguments.contains("-sampleOwnMode")
        noTexts = arguments.contains("-sampleNoTexts")
        listings = value("-listings").flatMap(ListingsPart.init(rawValue:))
        openSearch = value("-openSearch").flatMap(Int.init)
        search = value("-search")
        let tabValue = value("-tab")
        let listingsAsked = listings != nil || openSearch != nil || search != nil
        tab = tabValue == "search" ? .hunt : tabValue.flatMap(AppTab.init(rawValue:)) ?? (listingsAsked ? .listings : nil)
        filter = value("-filter").flatMap(MatchFilter.init(rawValue:))
        openMatch = value("-openMatch").flatMap(Int.init)
        openHunt = value("-openHunt").flatMap(Int.init)
        openSheet = value("-openSheet")
        if let id = value("-openForm").flatMap(Int.init) { form = .hunt(id) }
        else if arguments.contains("-openItemForm") { form = .firstItem }
        else if arguments.contains("-openWatchForm") { form = .firstWatch }
        else if arguments.contains("-openPriceForm") { form = .firstPrice }
        else if arguments.contains("-newPriceForm") { form = .new(.price) }
        else if arguments.contains("-newItemForm") { form = .new(.item) }
        else if arguments.contains("-newWatchForm") { form = .new(.watch) }
        else if arguments.contains("-newFlatForm") { form = .new(.flat) }
        else if let example = value("-newExample").flatMap(SearchExample.init(rawValue:)) { form = .example(example) }
        else if tabValue == "search" || openSheet == "place" || openSheet == "describe" { form = .firstHunt }
        newSearch = arguments.contains("-newSearch")
        renameHunt = value("-renameHunt").flatMap(Int.init)
        scrollTo = value("-scrollTo") ?? (arguments.contains("-scrollBottom") ? "bottom" : nil)
        tour = value("-tour").flatMap(Int.init)
        tourSheet = value("-tourSheet")
        #endif
    }

    /// Puts the navigation where the arguments ask (sample mode only), once the hunts are known.
    func apply(to navigation: AppNavigation, hunts: [HuntCard] = [], firstMatch: Int?) {
        guard sample else { return }
        if let tab { navigation.tab = tab }
        if let listings { navigation.part = listings }
        if let filter { navigation.filter = filter }
        if let openSearch {
            navigation.showSearch(openSearch,
                                  filter: filter ?? .opening(hunts.first { $0.id == openSearch }?.counts))
        }
        if let search {
            navigation.tab = .listings
            navigation.findQuery = search
            navigation.find(hunt: openSearch)
        }
        if let openMatch { navigation.follow(ArestemisLink(match: openMatch)) }
        if let openHunt {
            navigation.tab = .hunt
            navigation.huntPath = [.hunt(openHunt)]
            navigation.formScroll = scrollTo
        }
        if newSearch { navigation.startNewSearch() }
        if let route = form.flatMap({ Self.route($0, hunts: hunts) }) {
            navigation.tab = .hunt
            if case .example = form { navigation.huntPath = [.newSearch] }
            navigation.huntPath.append(route)
            navigation.formScroll = scrollTo
        }
        if let renameHunt { navigation.rename(renameHunt) }
        switch openSheet {
        case "settings": navigation.sheet = .settings
        case "rejected":
            navigation.tab = .listings
            navigation.sheet = .rejected(openSearch)
        case "application":
            if let match = openMatch ?? firstMatch { navigation.follow(ArestemisLink(match: match, then: .application)) }
        case "place":
            navigation.placeQuery = "Garch"
            navigation.showsPlaceSearch = true
        case "describe":
            navigation.showsDescribe = true
        default: break
        }
    }

    /// The form a launch asks for among these hunts (an empty one of the first hunt's kind when there is none).
    static func route(_ form: Form, hunts: [HuntCard]) -> HuntRoute? {
        func formOf(_ card: HuntCard?) -> HuntRoute? {
            guard let card else { return nil }
            return SearchKind(card.hunt.kind).map { .form($0, hunt: card.id) }
        }
        switch form {
        case .hunt(let id): return formOf(hunts.first { $0.id == id })
        case .firstHunt: return formOf(hunts.first) ?? .form(.flat, hunt: nil)
        case .firstItem: return formOf(hunts.first { $0.hunt.kind == .item }) ?? .form(.item, hunt: nil)
        case .firstWatch: return formOf(hunts.first { $0.hunt.kind == .watch }) ?? .form(.watch, hunt: nil)
        case .firstPrice: return formOf(hunts.first { $0.hunt.kind == .price }) ?? .form(.price, hunt: nil)
        case .new(let kind): return .form(kind, hunt: nil)
        case .example(let example): return .form(example.kind, hunt: nil, example: example)
        }
    }
}
