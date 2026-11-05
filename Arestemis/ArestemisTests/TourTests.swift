import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Arestemis

/// Brief 139: the tour's eight steps in order, what each points at and the screen it gets ready, Skip and Done, once per
/// account by itself and again from Settings, never touching the account's data, the words in both languages, and the
/// shared scrolling it uses.
@MainActor
struct TourTests {
    private static func running(at step: TourStep = .welcome) async throws -> (TourModel, TourWorld) {
        let tour = TourModel()
        await tour.start(at: step)
        #expect(tour.phase == .running)
        let world = try #require(tour.world)
        return (tour, world)
    }

    /// The app's defaults for one test, empty.
    private static func defaults() -> UserDefaults {
        let name = "arestemis.tour.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: the steps

    @Test func eightStepsInTheApprovedOrder() {
        #expect(TourStep.allCases == [.welcome, .newSearch, .search, .newListings, .searches, .listing,
                                      .monitorsAndWatches, .filteredOut])
        #expect(TourStep.allCases.map(\.rawValue) == Array(1...8))
    }

    @Test func eachStepPointsAtItsPartOfItsRealScreen() async throws {
        let (tour, world) = try await Self.running()
        let navigation = world.navigation
        #expect(tour.count == 8)
        var seen: [TourStep] = []
        repeat {
            seen.append(tour.step)
            #expect(tour.number == seen.count)
            switch tour.step {
            case .welcome:
                #expect(tour.targets.isEmpty)
                #expect(navigation.tab == .hunt && navigation.huntPath.isEmpty)
            case .newSearch:
                #expect(tour.targets == [.kindCard])
                #expect(navigation.tab == .hunt && navigation.huntPath == [.newSearch])
            case .search:
                // The first search's card, on the list of searches.
                #expect(tour.targets == [.huntCard(world.store.hunts[0].id)])
                #expect(navigation.tab == .hunt && navigation.huntPath.isEmpty)
            case .newListings:
                // The newest listing of the search with the newest finding: its row swipes.
                let first = try #require(NewListings.groups(world.store.matches(.new)).first?.matches.first)
                #expect(tour.targets == [.newListing(first.id)])
                #expect(navigation.tab == .listings && navigation.part == .new && navigation.listingsPath.isEmpty)
            case .searches:
                #expect(tour.targets == [.findAll])
                #expect(navigation.tab == .listings && navigation.part == .searches && navigation.listingsPath.isEmpty)
            case .listing:
                // A flat's listing: its facts, with what to check at their foot (brief 142: no "Why it fits").
                #expect(tour.targets == [.listingFacts])
                let match = try #require(world.flatMatch)
                #expect(world.store.kind(of: try #require(world.store.match(match))) == .flat)
                #expect(navigation.tab == .listings && navigation.listingsPath == [.match(match)])
            case .monitorsAndWatches:
                // A page watch and a price monitor that stand together on the list, one ring around both.
                let cards = world.store.hunts
                let spots = tour.targets
                #expect(spots.count == 2)
                guard case .huntCard(let watch) = spots.first, case .huntCard(let monitor) = spots.last,
                      let index = cards.firstIndex(where: { $0.id == watch }) else {
                    Issue.record("not two cards: \(spots)")
                    break
                }
                #expect(cards[index].hunt.kind == .watch)
                #expect(cards[index + 1].id == monitor && cards[index + 1].hunt.kind == .price)
                #expect(navigation.tab == .hunt && navigation.huntPath.isEmpty)
            case .filteredOut:
                // The flat search's listings at New, with "Filtered out" under them.
                #expect(tour.targets == [.filteredOut])
                let hunt = try #require(world.flatHunt)
                #expect(navigation.tab == .listings && navigation.listingsPath == [.hunt(hunt)])
                #expect(navigation.filter == .new)
                await world.store.loadRejected(hunt: hunt)
                #expect(!world.store.rejected(hunt: hunt).items.isEmpty)
                #expect(tour.nextStep == nil)
            }
            tour.next()
        } while tour.phase == .running
        #expect(seen == TourStep.allCases)
        // Done at the last step ends it.
        #expect(tour.phase == .ended && tour.world == nil)
    }

    @Test func nextGetsTheStepsScreenReadyAgainAfterTheTapsOnTheWay() async throws {
        let (tour, world) = try await Self.running(at: .search)
        let navigation = world.navigation
        // The person opens the ringed search's page, then a listing's page on the other tab, and opens a sheet.
        navigation.huntPath.append(.hunt(world.store.hunts[0].id))
        navigation.tab = .listings
        navigation.listingsPath = [.match(41)]
        navigation.sheet = .rejected(nil)
        tour.next()
        #expect(tour.step == .newListings)
        #expect(navigation.tab == .listings && navigation.listingsPath.isEmpty && navigation.part == .new)
        #expect(navigation.sheet == nil)
        tour.next()
        tour.next()
        tour.next()
        #expect(tour.step == .monitorsAndWatches)
        #expect(navigation.tab == .hunt && navigation.huntPath.isEmpty)
    }

    @Test(arguments: TourStep.allCases)
    func skipEndsTheTourAtAnyStep(step: TourStep) async throws {
        let (tour, _) = try await Self.running(at: step)
        #expect(tour.step == step)
        tour.end()
        #expect(tour.phase == .ended && tour.world == nil && tour.targets.isEmpty)
        tour.next()                                         // nothing after the end
        #expect(tour.phase == .ended)
    }

    @Test func endingWhileTheWorldIsMadeLeavesNothing() async throws {
        let tour = TourModel()
        tour.end()
        await tour.start()
        #expect(tour.phase == .ended && tour.world == nil)
    }

    @Test func aWorldThatCannotBeMadeEndsQuietly() async {
        struct Broken: Error {}
        let tours = TourRunner(offer: TourOffer(defaults: Self.defaults()),
                               makeTour: { TourModel(makeWorld: { throw Broken() }) })
        await tours.start(account: nil)
        #expect(tours.tour?.phase == .failed(Broken().localizedDescription))
        tours.clearEnded()
        #expect(tours.tour == nil)
    }

    // MARK: once per account, and from Settings

    @Test func itStartsByItselfOncePerAccount() async throws {
        let defaults = Self.defaults()
        let tours = TourRunner(offer: TourOffer(defaults: defaults))
        let free = TourOffer.Moment(account: "account-a", mainScreen: true, busy: false)

        await tours.offer(free)
        let first = try #require(tours.tour)
        #expect(first.phase == .running)
        // While it runs, nothing starts another.
        await tours.offer(TourOffer.Moment(account: "account-b", mainScreen: true, busy: false))
        #expect(tours.tour === first)
        tours.end()
        tours.clearEnded()
        #expect(tours.tour == nil)

        // The same account again (another launch): never by itself.
        await tours.offer(free)
        #expect(tours.tour == nil)
        #expect(TourRunner(offer: TourOffer(defaults: defaults)).offer.starts(free) == false)
        // Another account on this iPhone: once for it too.
        await tours.offer(TourOffer.Moment(account: "account-b", mainScreen: true, busy: false))
        #expect(tours.tour != nil)
    }

    @Test func neverOverANotificationASheetOrAPageOrInTheSample() {
        let offer = TourOffer(defaults: Self.defaults())
        #expect(offer.starts(TourOffer.Moment(account: "account-a", mainScreen: true, busy: false)))
        // A notification or link being opened, a sheet up or a page pushed.
        #expect(!offer.starts(TourOffer.Moment(account: "account-a", mainScreen: true, busy: true)))
        // Before the main screen (logging in, loading).
        #expect(!offer.starts(TourOffer.Moment(account: "account-a", mainScreen: false, busy: false)))
        // Sample mode and no login have no account.
        #expect(!offer.starts(TourOffer.Moment(account: nil, mainScreen: true, busy: false)))
        // Nothing of it was remembered by asking.
        #expect(!offer.shown(account: "account-a"))
    }

    @Test func settingsStartsItAgainAndItIsThenSeen() async throws {
        let defaults = Self.defaults()
        let tours = TourRunner(offer: TourOffer(defaults: defaults))
        tours.offer.remember(account: "account-a")
        // Settings → Help → Tour of Arestemis, though the account has seen it.
        await tours.start(account: "account-a")
        #expect(tours.tour?.phase == .running && tours.tour?.step == .welcome)
        tours.end()
        tours.clearEnded()
        // Started from Settings before it ever showed by itself: it does not show by itself afterwards.
        await tours.start(account: "account-c")
        tours.end()
        tours.clearEnded()
        await tours.offer(TourOffer.Moment(account: "account-c", mainScreen: true, busy: false))
        #expect(tours.tour == nil)
    }

    // MARK: never the account's data

    @Test func theTourNeverTouchesTheAccountsData() async throws {
        // The account's own store on its (fake) server, loaded as the app has it.
        let (account, transport, session) = try await makeStore()
        await account.reloadOverview()
        let requests = transport.requests.count
        let part = UserDefaults.standard.object(forKey: ListingsPartMemory.key)
        let token = session.token

        let (tour, world) = try await Self.running()
        // Its own store on the samples in memory, with a session that never logged in.
        #expect(world.store.isSample)
        #expect(world.store.session !== session && world.store.session.token == nil)
        #expect(world.store !== account)
        // Doing things on the way changes only the tour's world.
        let new = try #require(world.store.matches(.new).first)
        await world.store.setState(.dismissed, for: new.id)
        await world.store.setActive(id: world.store.hunts[0].id, active: false)
        world.navigation.choose(.searches)
        #expect(world.store.match(new.id)?.state == .dismissed)
        while tour.phase == .running { tour.next() }

        #expect(transport.requests.count == requests)
        #expect(account.match(new.id)?.state != .dismissed)
        #expect(account.hunts.first?.hunt.active == true)
        #expect(session.token == token && session.isSignedIn)
        #expect((UserDefaults.standard.object(forKey: ListingsPartMemory.key) as? String) == (part as? String))
        // Its own defaults are emptied when it goes.
        #expect(UserDefaults(suiteName: TourWorld.suite)?.string(forKey: ListingsPartMemory.key) == nil)
    }

    @Test func aSampleApplicationIsSignedWithTheToursName() async throws {
        let (_, world) = try await Self.running()
        let flat = try #require(world.flatMatch)
        await world.store.loadApplication(for: flat)
        let text = try #require(world.store.application(flat).application?.text)
        #expect(text.hasPrefix("Hello,") && text.hasSuffix(TourData.name))
    }

    // MARK: the tour's own data

    @Test func theToursDataIsInTheAppsLanguage() throws {
        let now = Date.now
        let en = try TourData.content(now: now, language: .english)
        let de = try TourData.content(now: now, language: .german)
        // The same four searches, one of each kind, with the same listings in both languages.
        #expect(de.overview.hunts.map(\.hunt.kind) == [.flat, .item, .watch, .price])
        #expect(en.overview.hunts.map(\.id) == de.overview.hunts.map(\.id))
        #expect(en.matches.map(\.id) == de.matches.map(\.id) && en.rejected.map(\.id) == de.rejected.map(\.id))

        // Every word people read is the app's language; names stay names (the console, the sites, the towns).
        for (english, german) in zip(en.matches, de.matches) {
            if english.listing.title != "Nintendo Switch 2" { #expect(english.listing.title != german.listing.title) }
            #expect(english.reason != german.reason)
            #expect(english.listing.description.isEmpty || english.listing.description != german.listing.description)
            #expect(english.warnings.isEmpty || english.warnings != german.warnings)
            #expect(english.listing.page?.now == nil || english.listing.page?.now != german.listing.page?.now)
        }
        for (english, german) in zip(en.rejected, de.rejected) {
            #expect(english.listing.title != german.listing.title && english.reason != german.reason)
            #expect(english.listing.description != german.listing.description)
        }
        #expect(de.kinds.map(\.name) == ["Wohnung", "Dinge", "Preismonitor", "Webseite beobachten"])
        #expect(en.kinds.map(\.name) == ["Flat", "Things", "Price monitor", "Watch a website"])
        let watch = try #require(de.overview.hunts.first { $0.hunt.kind == .watch })
        #expect(watch.hunt.name == "Schnitzel in der Mensa")
        #expect(watch.page?.now == "Dienstag: Schweineschnitzel mit Pommes")
        #expect(watch.hunt.search.watch?.change == "es diese Woche Schnitzel gibt")
        #expect(de.overview.hunts[0].hunt.search.flat?.extra == "Balkon wäre schön, kein Erdgeschoss")
        let flat = try #require(de.matches.first)
        #expect(flat.listing.title == "Helle 2-Zimmer-Wohnung mit Balkon in Schwabing")
        #expect(flat.reason.hasPrefix("Zwei Zimmer mit Balkon in Schwabing"))
        // The price alarm in the app's own words and money.
        let euros = { (amount: Double, language: AppLanguage) in PriceWords.money(amount, language: language) }
        #expect(de.matches.last?.reason
                == "Nintendo Switch 2: \(euros(449, .german)) (vorher \(euros(483.99, .german)))")
        #expect(en.matches.last?.reason == "Nintendo Switch 2: €449.00 (was €483.99)")
        // A made-up application in the app's language, signed by the tour's name.
        let application = try #require(de.application)
        #expect(application(flat.listing, TourData.name).hasPrefix("Hallo,"))
        #expect(application(flat.listing, TourData.name).contains("„Helle 2-Zimmer-Wohnung mit Balkon in Schwabing“"))
        #expect(application(flat.listing, TourData.name).hasSuffix("\nAlex"))
    }

    @Test func theToursDataIsAroundNow() throws {
        let now = Date.now
        let content = try TourData.content(now: now, language: .english)
        // Found minutes or hours ago, a move-in date ahead, the console's history up to an hour ago.
        let flat = try #require(content.matches.first)
        let found = try #require(Timestamp.parse(flat.found))
        #expect(found < now && now.timeIntervalSince(found) < 3600)
        let moveIn = try #require(flat.listing.availableFrom.flatMap { DateOnly.parse($0) })
        #expect(moveIn > now)
        let last = try #require(content.histories[TourData.monitor]?.last.flatMap { Timestamp.parse($0.at) })
        #expect(abs(now.addingTimeInterval(-3600).timeIntervalSince(last)) < 1)
    }

    // MARK: the words

    @Test func theCardsSayWhatTheyShowInBothLanguages() {
        let en = AppLanguage.english, de = AppLanguage.german
        #expect(TourStep.allCases.map { $0.title(de) } == [
            "Arestemis sucht für dich", "Neue Suche", "Eine Suche", "Angebote → Neu", "Angebote → Suchen",
            "Ein Angebot", "Preismonitor und Webseite beobachten", "Aussortiert",
        ])
        #expect(TourStep.allCases.map { $0.title(en) } == [
            "Arestemis searches for you", "New search", "A search", "Listings → New", "Listings → Searches",
            "A listing", "Price monitor and Watch a website", "Filtered out",
        ])
        for step in TourStep.allCases {
            for language in [en, de] {
                let lines = step.lines(language)
                #expect(!lines.isEmpty && lines.allSatisfy { !$0.text.isEmpty })
                // One or two sentences a line (a sentence ends with its mark and a space or the end; "1.100 €" is none).
                for line in lines {
                    #expect(line.text.matches(of: /[.?!](\s|$)/).count <= 2, "\(step): \(line.text)")
                }
            }
            #expect(step.text(de) != step.text(en))
        }
        // The Preismonitor and the page watch: a line each, led by the kind's name as New search shows it.
        #expect(TourStep.monitorsAndWatches.lines(de).map(\.label) == ["Preismonitor", "Webseite beobachten"])
        #expect(TourStep.monitorsAndWatches.lines(de).map(\.label)
                == [SearchKind.price.choiceTitle(language: de), SearchKind.watch.choiceTitle(language: de)])
        #expect(TourStep.monitorsAndWatches.text(de) == """
            Preismonitor: Ein Push, wenn ein Produkt in einem Shop oder überall günstiger oder wieder lieferbar ist, dazu die Kurve.
            Webseite beobachten: Ein Push, wenn auf einer Seite etwas Neues erscheint: eine Version, eine Stelle, der Speiseplan.
            """)
        #expect(TourStep.newListings.text(de)
                == "Alles Neue, nach Suche geordnet. Wisch ein Angebot nach rechts für deine Favoriten, nach links zum Entfernen.")
        // "du", never "Sie" as the address.
        for step in TourStep.allCases {
            #expect(!step.text(de).contains(" Ihr") && !step.text(de).contains("Ihnen"))
        }
    }

    // MARK: the shared scrolling

    @Test func withinTheSafeAreaItScrollsOnlyAsFarAsItTakes() {
        let visible: ClosedRange<CGFloat> = 0...480
        // Shown, a margin in from the edges: no scroll.
        #expect(TourScrollPlace(frame: CGRect(x: 0, y: 100, width: 300, height: 120), height: 480,
                                visible: visible).scrollAnchor == nil)
        // Below: its lower edge comes to the margin above the end. The anchor puts the control's top at
        // y × (480 − 120): 480 − 12 − 120 = 348.
        let below = TourScrollPlace(frame: CGRect(x: 0, y: 700, width: 300, height: 120), height: 480, visible: visible)
        let anchor = try? #require(below.scrollAnchor)
        #expect(abs((anchor?.y ?? 0) * 360 - 348) < 0.001)
        // Above the top: back down, its top a margin under the start.
        let above = TourScrollPlace(frame: CGRect(x: 0, y: -50, width: 300, height: 120), height: 480, visible: visible)
        #expect(abs((above.scrollAnchor?.y ?? 0) * 360 - 12) < 0.001)
    }

    @Test func oneRingAroundTwoCardsScrollsAsAGroup() throws {
        // A watch's card (180 high) over a monitor's (270), far down: the scroll moves the first card as far as the pair
        // must move.
        let watch = CGRect(x: 0, y: 1200, width: 300, height: 180)
        let monitor = CGRect(x: 0, y: 1390, width: 300, height: 270)
        let pair = try #require(TourScrollPlace(frames: [watch, monitor], height: 480, visible: 0...480))
        #expect(pair.frame == watch.union(monitor) && pair.first == watch)
        let y = try #require(pair.scrollAnchor).y
        // The pair (460) is taller than the room between the margins (456): its top a margin under the start.
        #expect(abs(y * (480 - 180) - 12) < 0.001)
        // A shorter pair: its lower edge at the margin above the end.
        let short = try #require(TourScrollPlace(frames: [watch, monitor.insetBy(dx: 0, dy: 20)], height: 480,
                                                 visible: 0...480))
        let top = try #require(short.scrollAnchor).y * (480 - 180)
        #expect(abs(top + (short.frame.height) - 468) < 0.001)
        // Once the pair's top is at the margin it shows as far as it can, though taller than the room: no more scrolling.
        let atTop = [watch, monitor].map { $0.offsetBy(dx: 0, dy: 12 - 1200) }
        #expect(TourScrollPlace(frames: atTop, height: 480, visible: 0...480)?.scrollAnchor == nil)
        // Without the safe area (Aresium's tour): one control as before.
        #expect(TourScrollPlace(frames: [watch], height: 600)?.first == nil)
    }
}
