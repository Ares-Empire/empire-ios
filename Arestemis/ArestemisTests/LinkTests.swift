import Foundation
import Testing
import UserNotifications
@testable import Arestemis

/// Deep links (`arestemis://match/<id>`), the match notification's actions, and where they take the app.
@MainActor
struct LinkTests {
    @Test(arguments: [
        ("arestemis://match/41", 41, ArestemisLink.Then.show),
        ("arestemis://match/41?action=application", 41, .application),
        ("arestemis://match/7?action=somethingelse", 7, .show),
        ("ARESTEMIS://match/41", 41, .show),
        ("arestemis:///match/41", 41, .show),
    ])
    func linksToAMatch(url: String, match: Int, then: ArestemisLink.Then) throws {
        let parsed = try #require(URL(string: url))
        let link = try #require(ArestemisLink(url: parsed))
        #expect(link.match == match && link.then == then)
    }

    @Test(arguments: ["arestemis://", "arestemis://match", "arestemis://match/abc", "arestemis://match/0",
                      "arestemis://match/-3", "arestemis://match/41/extra", "arestemis://hunt/1",
                      "https://www.ares-empire.de/match/41", "aresium://match/41"])
    func otherURLsAreNotLinks(url: String) throws {
        let parsed = try #require(URL(string: url))
        #expect(ArestemisLink(url: parsed) == nil)
    }

    @Test func notificationActionsRoute() {
        let url = URL(string: "arestemis://match/41")
        #expect(MatchNotification.link(url: url, action: UNNotificationDefaultActionIdentifier) == ArestemisLink(match: 41))
        #expect(MatchNotification.link(url: url, action: MatchNotification.applicationAction)
                == ArestemisLink(match: 41, then: .application))
        #expect(MatchNotification.link(url: url, action: MatchNotification.openListingAction)
                == ArestemisLink(match: 41, then: .openListing))
        #expect(MatchNotification.link(url: URL(string: "arestemis://match/41?action=application"),
                                       action: UNNotificationDefaultActionIdentifier)?.then == .application)
        #expect(MatchNotification.link(url: url, action: UNNotificationDismissActionIdentifier) == nil)
        #expect(MatchNotification.link(url: nil, action: UNNotificationDefaultActionIdentifier) == nil)
        #expect(MatchNotification.link(url: URL(string: "https://example.invalid"), action: MatchNotification.applicationAction) == nil)
    }

    @Test func theMatchCategory() throws {
        let categories = MatchNotification.categories
        #expect(categories.count == 1)
        let category = try #require(categories.first)
        #expect(category.identifier == "ARESTEMIS_MATCH")
        #expect(category.actions.map(\.title) == ["Open listing", "Application"])
        #expect(category.actions.map(\.identifier) == [MatchNotification.openListingAction, MatchNotification.applicationAction])
        #expect(category.actions.allSatisfy { $0.options.contains(.foreground) })
    }

    @Test func aLinkOpensTheMatchOnTheListingsTab() {
        let navigation = AppNavigation()
        navigation.huntPath = [38]
        navigation.sheet = .settings
        navigation.open(ArestemisLink(match: 41))
        #expect(navigation.tab == .listings && navigation.listingsPath == [41])
        #expect(navigation.sheet == nil && navigation.pendingListing == nil)

        navigation.open(ArestemisLink(match: 40, then: .application))
        #expect(navigation.listingsPath == [40] && navigation.sheet == .application(40))

        navigation.open(ArestemisLink(match: 38, then: .openListing))
        #expect(navigation.listingsPath == [38] && navigation.sheet == nil && navigation.pendingListing == 38)
    }

    @Test func followedLinksWaitForTheTabs() {
        let navigation = AppNavigation()
        navigation.follow(ArestemisLink(match: 41, then: .application))
        #expect(navigation.listingsPath.isEmpty && navigation.pendingLink == ArestemisLink(match: 41, then: .application))
        navigation.openPendingLink()
        #expect(navigation.listingsPath == [41] && navigation.sheet == .application(41) && navigation.pendingLink == nil)
        navigation.openPendingLink()
        #expect(navigation.listingsPath == [41])
    }

    @Test func resetGoesBackToTheStart() {
        let navigation = AppNavigation()
        navigation.open(ArestemisLink(match: 41, then: .openListing))
        navigation.filter = .all
        navigation.follow(ArestemisLink(match: 40))
        navigation.reset()
        #expect(navigation.tab == .hunt && navigation.listingsPath.isEmpty && navigation.filter == .new)
        #expect(navigation.pendingListing == nil && navigation.pendingLink == nil && navigation.sheet == nil)
    }

    @Test func showingAMatchStaysOnTheHuntTab() {
        let navigation = AppNavigation()
        navigation.showMatch(41)
        #expect(navigation.tab == .hunt && navigation.huntPath == [41])
        navigation.tab = .search
        navigation.showMatch(40)
        #expect(navigation.tab == .listings && navigation.listingsPath == [40])
    }

    @Test func filters() {
        #expect(MatchFilter.new.states == [.new] && MatchFilter.all.states == nil)
        #expect(MatchFilter.all.includes(.applied) && !MatchFilter.all.includes(.dismissed))
        #expect(MatchFilter.saved.includes(.saved) && !MatchFilter.saved.includes(.new))
    }

    @Test func launchArguments() {
        let options = LaunchOptions(arguments: ["app", "-sampleData", "-samplePaused", "-tab", "listings", "-filter", "all",
                                                "-openSheet", "application", "-scrollTo", "rent"])
        #expect(options.sample && options.paused && !options.noHunt && !options.loading)
        #expect(options.tab == .listings && options.filter == .all && options.openSheet == "application")
        #expect(options.scrollTo == "rent" && options.openMatch == nil)
        let navigation = AppNavigation()
        options.apply(to: navigation, firstMatch: 41)
        #expect(navigation.filter == .all && navigation.pendingLink == ArestemisLink(match: 41, then: .application))

        let place = AppNavigation()
        LaunchOptions(arguments: ["-sampleData", "-openSheet", "place"]).apply(to: place, firstMatch: nil)
        #expect(place.tab == .search && place.showsPlaceSearch && place.placeQuery == "Garch")

        let texts = LaunchOptions(arguments: ["-sampleData", "-sampleOwnMode", "-sampleNoTexts", "-openSheet", "settings"])
        #expect(texts.ownMode && texts.noTexts && !options.ownMode && !options.noTexts)

        let real = AppNavigation()
        LaunchOptions(arguments: ["-tab", "search"]).apply(to: real, firstMatch: nil)     // only with the samples
        #expect(real.tab == .hunt)
    }
}
