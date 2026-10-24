import Foundation
import Observation

enum AppTab: String, Hashable, CaseIterable {
    case hunt, listings, search
}

/// The Listings tab's filter: New · Saved · Applied · All (all = every state but dismissed, the API's default).
enum MatchFilter: String, CaseIterable, Hashable, Identifiable {
    case new, saved, applied, all
    var id: String { rawValue }

    var title: String {
        switch self {
        case .new: "New"
        case .saved: "Saved"
        case .applied: "Applied"
        case .all: "All"
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

/// Where the user is: the tab, each tab's pushed matches, the open sheet. Links and notifications go through `open`.
@MainActor @Observable
final class AppNavigation {
    var tab: AppTab = .hunt
    var huntPath: [Int] = []
    var listingsPath: [Int] = []
    var filter: MatchFilter = .new
    var sheet: RootSheet?
    var showsPlaceSearch = false
    /// The Search tab's "Describe it" sheet.
    var showsDescribe = false
    /// What the place search starts with (empty, or a sample query for screenshots).
    var placeQuery = ""
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
        showsPlaceSearch = false
        showsDescribe = false
        sheet = link.then == .application ? .application(link.match) : nil
        pendingListing = link.then == .openListing ? link.match : nil
    }

    func showMatch(_ id: Int) {
        switch tab {
        case .hunt: huntPath.append(id)
        default:
            tab = .listings
            listingsPath.append(id)
        }
    }

    /// Back to the start (after logging out).
    func reset() {
        tab = .hunt
        huntPath = []
        listingsPath = []
        filter = .new
        sheet = nil
        showsPlaceSearch = false
        showsDescribe = false
        placeQuery = ""
        pendingListing = nil
        pendingLink = nil
    }
}

/// DEBUG launch arguments for screenshots: `-sampleData`, `-sampleNoHunt`, `-samplePaused`, `-sampleLoading`,
/// `-tab hunt|listings|search`, `-filter new|saved|applied|all`, `-openMatch <id>`,
/// `-openSheet settings|application|rejected|place|describe`, `-scrollBottom` (Hunt and Search),
/// `-scrollTo size|rent|movein` (Search). In a release build all are ignored.
struct LaunchOptions {
    var sample = false
    var noHunt = false
    var paused = false
    var loading = false
    var tab: AppTab?
    var filter: MatchFilter?
    var openMatch: Int?
    var openSheet: String?
    var scrollTo: String?

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
        tab = value("-tab").flatMap(AppTab.init(rawValue:))
        filter = value("-filter").flatMap(MatchFilter.init(rawValue:))
        openMatch = value("-openMatch").flatMap(Int.init)
        openSheet = value("-openSheet")
        scrollTo = value("-scrollTo") ?? (arguments.contains("-scrollBottom") ? "bottom" : nil)
        #endif
    }

    /// Puts the navigation where the arguments ask (sample mode only).
    func apply(to navigation: AppNavigation, firstMatch: Int?) {
        guard sample else { return }
        if let tab { navigation.tab = tab }
        if let filter { navigation.filter = filter }
        if let openMatch { navigation.follow(ArestemisLink(match: openMatch)) }
        switch openSheet {
        case "settings": navigation.sheet = .settings
        case "rejected":
            navigation.tab = .listings
            navigation.sheet = .rejected
        case "application":
            if let match = openMatch ?? firstMatch { navigation.follow(ArestemisLink(match: match, then: .application)) }
        case "place":
            navigation.tab = .search
            navigation.placeQuery = "Garch"
            navigation.showsPlaceSearch = true
        case "describe":
            navigation.tab = .search
            navigation.showsDescribe = true
        default: break
        }
    }
}
