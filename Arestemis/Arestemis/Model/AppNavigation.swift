import Foundation
import Observation

/// The two tabs: the hunts (the first tab, "Suche") and their listings ("Angebote"). A hunt's search opens from the hunt.
enum AppTab: String, Hashable, CaseIterable {
    case hunt, listings
}

/// What the Hunts tab pushes: a hunt's page, a match's page, or a search form (a hunt's search, or a new one).
enum HuntRoute: Hashable {
    case hunt(Int)
    case match(Int)
    case form(SearchKind, hunt: Int?)
}

/// The Listings tab's filter: New · Saved · Applied · All (all = every state but dismissed, the API's default).
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
}

/// The sheets shown over the tabs.
enum RootSheet: Identifiable, Equatable {
    case settings, rejected, application(Int)
    var id: String {
        switch self {
        case .settings: "settings"
        case .rejected: "rejected"
        case .application(let match): "application-\(match)"
        }
    }
}

/// Where the user is: the tab, each tab's pushed pages, the open sheet. Links and notifications go through `open`.
@MainActor @Observable
final class AppNavigation {
    var tab: AppTab = .hunt
    var huntPath: [HuntRoute] = []
    var listingsPath: [Int] = []
    var filter: MatchFilter = .new
    var sheet: RootSheet?
    /// New search asks which kind (the Hunts tab's confirmation dialog).
    var asksSearchKind = false
    var showsPlaceSearch = false
    /// A search form's "Describe it" sheet.
    var showsDescribe = false
    /// What the place search starts with (empty, or a sample query for screenshots).
    var placeQuery = ""
    /// Screenshots: where the next search form scrolls to ("size", "rent", "movein", "bottom").
    var formScroll: String?
    /// A link asked to open this match's portal page; the root opens it once the match is known.
    var pendingListing: Int?
    /// A link waiting for the tabs to be on screen (a match pushed before they appear keeps the tab bar showing).
    private(set) var pendingLink: ArestemisLink?

    /// A link or notification: queued until the tabs are on screen, then `open(_:)`.
    func follow(_ link: ArestemisLink) { pendingLink = link }

    /// The tabs are on screen: the queued link, if any, is opened.
    func openPendingLink() {
        guard let link = pendingLink else { return }
        pendingLink = nil
        open(link)
    }

    /// The match on the Listings tab, then what the link asked for.
    func open(_ link: ArestemisLink) {
        tab = .listings
        listingsPath = [link.match]
        asksSearchKind = false
        showsPlaceSearch = false
        showsDescribe = false
        sheet = link.then == .application ? .application(link.match) : nil
        pendingListing = link.then == .openListing ? link.match : nil
    }

    /// A match's page on the tab it was tapped on (the Hunts tab keeps it in its own stack).
    func showMatch(_ id: Int) {
        switch tab {
        case .hunt: huntPath.append(.match(id))
        case .listings: listingsPath.append(id)
        }
    }

    /// New search from anywhere: the Hunts tab at its start, asking which kind.
    func startNewSearch() {
        tab = .hunt
        huntPath = []
        asksSearchKind = true
    }

    /// The kind's empty form, pushed on the Hunts tab.
    func openNewForm(_ kind: SearchKind) {
        tab = .hunt
        huntPath.append(.form(kind, hunt: nil))
    }

    /// A new hunt was saved: its page replaces the form it was made in.
    func showCreated(_ id: Int) {
        if case .form(_, nil)? = huntPath.last { huntPath.removeLast() }
        huntPath.append(.hunt(id))
    }

    /// A hunt was deleted (from its page or its form): back to the list of hunts.
    func leaveDeleted() {
        huntPath = []
    }

    /// Back to the start (after logging out).
    func reset() {
        tab = .hunt
        huntPath = []
        listingsPath = []
        filter = .new
        sheet = nil
        asksSearchKind = false
        showsPlaceSearch = false
        showsDescribe = false
        placeQuery = ""
        formScroll = nil
        pendingListing = nil
        pendingLink = nil
    }
}

/// DEBUG launch arguments for screenshots: `-sampleData`, `-sampleNoHunt`, `-samplePaused`, `-sampleLoading`,
/// `-sampleSlowed` (the thing hunt is checked less often), `-sampleNewerKind` (a hunt of a kind this build does not know),
/// `-sampleEbayNotReady` (eBay not set up on the server: greyed in the thing form, read by no hunt),
/// `-sampleHunt <id>` (Listings for that hunt), `-tab hunt|listings` (`search`: the first hunt's form),
/// `-filter new|saved|applied|all`, `-openMatch <id>`, `-openHunt <id>` (a hunt's page), `-openForm <id>` (that hunt's
/// form), `-openItemForm` (the first thing hunt's form), `-newItemForm` / `-newFlatForm` (an empty form), `-newSearch`
/// (the kind dialog), `-openSheet settings|application|rejected|place|describe` (place and describe over a form, the
/// first hunt's unless another is asked for), `-scrollBottom` (Hunts and the forms), `-scrollTo size|rent|movein`
/// (the flat form), `-sampleUndo`, `-sampleSearchDraft`, `-sampleMoreLoading`, `-sampleMoreFailure`,
/// `-sampleLongDescription`; Settings → Flats: `-sampleOwnMode` (the switch off), `-sampleNoTexts` (nothing written
/// yet), `-openSettingsPage ownText|notes|aboutMe` (with `-openSheet settings`, read by `SettingsSheet`). In a release
/// build all are ignored.
struct LaunchOptions {
    /// Which search form opens at launch.
    enum Form: Equatable {
        case hunt(Int)              // -openForm <id>
        case firstHunt              // -tab search, or a sheet over a form without another form asked for
        case firstItem              // -openItemForm
        case new(SearchKind)        // -newFlatForm, -newItemForm
    }

    var sample = false
    var noHunt = false
    var paused = false
    var loading = false
    var slowed = false
    var newerKind = false
    var ebayNotReady = false
    var sampleUndo = false
    var moreLoading = false
    var moreFailure = false
    var longDescription = false
    var ownMode = false
    var sampleHunt: Int?
    var noTexts = false
    var tab: AppTab?
    var filter: MatchFilter?
    var openMatch: Int?
    var openHunt: Int?
    var form: Form?
    var newSearch = false
    var openSheet: String?
    var scrollTo: String?

    init(arguments: [String]) {
        #if DEBUG
        func value(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        sampleHunt = value("-sampleHunt").flatMap(Int.init)
        sample = arguments.contains("-sampleData")
        noHunt = arguments.contains("-sampleNoHunt")
        paused = arguments.contains("-samplePaused")
        loading = arguments.contains("-sampleLoading")
        slowed = arguments.contains("-sampleSlowed")
        newerKind = arguments.contains("-sampleNewerKind")
        ebayNotReady = arguments.contains("-sampleEbayNotReady")
        sampleUndo = arguments.contains("-sampleUndo")
        moreLoading = arguments.contains("-sampleMoreLoading")
        moreFailure = arguments.contains("-sampleMoreFailure")
        longDescription = arguments.contains("-sampleLongDescription")
        ownMode = arguments.contains("-sampleOwnMode")
        noTexts = arguments.contains("-sampleNoTexts")
        let tabValue = value("-tab")
        tab = tabValue == "search" ? .hunt : tabValue.flatMap(AppTab.init(rawValue:)) ?? (sampleHunt == nil ? nil : .listings)
        filter = value("-filter").flatMap(MatchFilter.init(rawValue:))
        openMatch = value("-openMatch").flatMap(Int.init)
        openHunt = value("-openHunt").flatMap(Int.init)
        openSheet = value("-openSheet")
        if let id = value("-openForm").flatMap(Int.init) { form = .hunt(id) }
        else if arguments.contains("-openItemForm") { form = .firstItem }
        else if arguments.contains("-newItemForm") { form = .new(.item) }
        else if arguments.contains("-newFlatForm") { form = .new(.flat) }
        else if tabValue == "search" || openSheet == "place" || openSheet == "describe" { form = .firstHunt }
        newSearch = arguments.contains("-newSearch")
        scrollTo = value("-scrollTo") ?? (arguments.contains("-scrollBottom") ? "bottom" : nil)
        #endif
    }

    /// Puts the navigation where the arguments ask (sample mode only), once the hunts are known.
    func apply(to navigation: AppNavigation, hunts: [HuntCard] = [], firstMatch: Int?) {
        guard sample else { return }
        if let tab { navigation.tab = tab }
        if let filter { navigation.filter = filter }
        if let openMatch { navigation.follow(ArestemisLink(match: openMatch)) }
        if let openHunt {
            navigation.tab = .hunt
            navigation.huntPath = [.hunt(openHunt)]
        }
        if let route = form.flatMap({ Self.route($0, hunts: hunts) }) {
            navigation.tab = .hunt
            navigation.huntPath.append(route)
            navigation.formScroll = scrollTo
        }
        if newSearch { navigation.startNewSearch() }
        switch openSheet {
        case "settings": navigation.sheet = .settings
        case "rejected":
            navigation.tab = .listings
            navigation.sheet = .rejected
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
        case .new(let kind): return .form(kind, hunt: nil)
        }
    }
}
