import Foundation
import Testing
@testable import Arestemis

/// Brief 114: what the Hunts tab, a hunt's page, the thing form and a search's listings decide (`HuntsPresentation`,
/// `ItemFormatting`, `ItemSearchDraft`'s lines, `AppNavigation`), and the store's per-hunt latest matches. The Listings
/// tab's parts (brief 133): `ListingsTests`.
@MainActor
struct HuntsScreensTests {
    private func spaces(_ value: String?) -> String? { value?.replacingOccurrences(of: "\u{a0}", with: " ") }
    private func hunts() throws -> [HuntCard] { try sample(Overview.self, "overview").hunts }

    // MARK: New search's kinds

    @Test(arguments: [AppLanguage.english, .german])
    func theKindDialogOffersFlatThenThingThenWatch(_ language: AppLanguage) {
        let de = language == .german
        let choices = SearchKind.choices(offered: nil)
        #expect(choices == [.flat, .item, .watch])
        #expect(choices.map { $0.choiceTitle(language: language) }
                == (de ? ["Wohnung oder Zimmer", "Etwas kaufen", "Seite beobachten"]
                       : ["Flat or room", "Something to buy", "Watch a page"]))
        #expect(choices.map(\.huntKind) == [.flat, .item, .watch])
        #expect(SearchKind(.unknown("car")) == nil && SearchKind(.item) == .item)
        #expect(SearchKind.flat.symbol == "house" && SearchKind.item.symbol == "tag" && SearchKind.watch.symbol == "eye")
    }

    // MARK: a hunt's lines

    @Test(arguments: [AppLanguage.english, .german])
    func huntLines(_ language: AppLanguage) throws {
        let de = language == .german
        let cards = try hunts()
        let flat = HuntText(cards[0].hunt, now: Clock.now, calendar: Clock.berlin, language: language)
        let summary = SearchSummary(try #require(cards[0].hunt.search.flat), now: Clock.now, calendar: Clock.berlin,
                                    language: language)
        #expect(flat.kind == .flat && flat.title == summary.kinds && flat.newerApp == nil)
        #expect(spaces(flat.details?.replacingOccurrences(of: "\u{2060}", with: "")) == spaces(summary.details))

        // An own name is the title; what it looks for leads the details.
        let named = HuntText(cards[2].hunt, now: Clock.now, calendar: Clock.berlin, language: language)
        #expect(named.title == "A quieter flat")
        #expect(named.details?.hasPrefix(SearchSummary.unbreakable(summary.kinds)) == true)

        // A thing hunt's sites by the server's names (the overview's).
        let sites = SiteNames(statuses: try sample(Overview.self, "overview").sources)
        let thing = HuntText(cards[1].hunt, sites: sites, language: language)
        #expect(thing.kind == .item && thing.title == "Herman Miller Aeron")
        #expect(spaces(thing.details) == (de ? "bis 450 € · Abholung oder Versand · Garching (20 km) · Kleinanzeigen · eBay"
                                             : "up to €450 · Pickup or shipping · Garching (20 km) · Kleinanzeigen · eBay"))

        // Spaces only are no name.
        var blank = cards[1].hunt
        blank.name = "   "
        #expect(HuntText(blank, language: language).title == "Herman Miller Aeron")
    }

    @Test(arguments: [AppLanguage.english, .german])
    func aHuntOfANewerKindShowsItsNameAndNothingElse(_ language: AppLanguage) {
        let de = language == .german
        var hunt = Hunt(id: 9, kind: .unknown("car"), name: "Camper van", active: true, search: .unsupported,
                        created: "2026-10-24T08:12:00Z", updated: "2026-10-24T08:12:00Z", activated: nil)
        var text = HuntText(hunt, language: language)
        #expect(text.kind == nil && text.title == "Camper van" && text.details == nil)
        #expect(text.newerApp == (de ? "Braucht eine neuere App-Version" : "Needs a newer app"))
        hunt.name = nil
        text = HuntText(hunt, language: language)
        #expect(text.title == (de ? "Suche" : "Search"))
        // A known kind whose search this build cannot read is shown the same way.
        let unreadable = Hunt(id: 10, kind: .item, name: nil, active: false, search: .unsupported,
                              created: "2026-10-24T08:12:00Z", updated: "2026-10-24T08:12:00Z", activated: nil)
        #expect(HuntText(unreadable, language: language).kind == nil)
        #expect(HuntPageActions(unreadable) == HuntPageActions(hunt))
    }

    // MARK: a hunt's page

    @Test(arguments: [AppLanguage.english, .german])
    func whatAHuntsPageOffers(_ language: AppLanguage) throws {
        let de = language == .german
        let cards = try hunts()
        for card in cards {
            let actions = HuntPageActions(card.hunt)
            #expect(actions.startPause && actions.editSearch && actions.listings && actions.rename && actions.delete)
        }
        let newer = Hunt(id: 9, kind: .unknown("car"), name: nil, active: true, search: .unsupported,
                         created: "2026-10-24T08:12:00Z", updated: "2026-10-24T08:12:00Z", activated: nil)
        let actions = HuntPageActions(newer)
        #expect(!actions.startPause && !actions.editSearch && actions.listings && actions.rename && actions.delete)
        #expect(HuntPageActions.figureLabels(.flat, language: language)
                == (de ? ["Neu", "Heute", "Beworben"] : ["New", "Today", "Applied"]))
        #expect(HuntPageActions.figureLabels(.item, language: language)
                == (de ? ["Neu", "Heute", "Angefragt"] : ["New", "Today", "Asked"]))
    }

    @Test func renamingKeepsSixtyCharactersAndEmptyClears() {
        let long = String(repeating: "a", count: 70)
        #expect(HuntName.limited(long).count == 60 && HuntName.limited("Chair") == "Chair")
        #expect(HuntName.cleaned("  Office chair  ") == "Office chair")
        #expect(HuntName.cleaned("   ") == nil && HuntName.cleaned("") == nil)
        #expect(HuntName.cleaned(long)?.count == 60)
    }

    // MARK: a search's listings

    @Test(arguments: [AppLanguage.english, .german])
    func appliedOrAsked(_ language: AppLanguage) {
        let de = language == .german
        #expect(MatchFilter.allCases.map { $0.title(asked: false, language: language) }
                == (de ? ["Neu", "Gespeichert", "Beworben", "Alle"] : ["New", "Saved", "Applied", "All"]))
        #expect(MatchFilter.applied.title(asked: true, language: language) == (de ? "Angefragt" : "Asked"))
        #expect(MatchState.applied.word(thing: true, language: language) == (de ? "Angefragt" : "Asked"))
        #expect(MatchState.applied.word(thing: false, language: language) == (de ? "Beworben" : "Applied"))
        #expect(MatchState.saved.word(thing: true, language: language) == (de ? "Gespeichert" : "Saved"))
        #expect(MatchState.new.word(language: language) == nil && MatchState.dismissed.word(language: language) == nil)
        #expect(MatchState.new.word(includingNew: true, language: language) == (de ? "Neu" : "New"))
        #expect(MatchState.dismissed.word(includingNew: true, language: language) == nil)
    }

    // MARK: a thing's row and page

    @Test(arguments: [AppLanguage.english, .german])
    func aThingsPrice(_ language: AppLanguage) throws {
        let de = language == .german
        let matches = try sample(MatchPage.self, "item-matches").items
        #expect(matches[0].itemPrice(language: language).flatMap { spaces($0.amount) } == (de ? "400 €" : "€400"))
        #expect(matches[0].itemPrice(language: language)?.label == nil)
        #expect(spaces(matches[1].itemPrice(language: language)?.label) == (de ? "VB, 30 € darüber" : "VB, €30 over"))
        #expect(matches[3].itemPrice(language: language) == ItemPrice(amount: nil, label: de ? "Zu verschenken" : "Free"))

        var match = matches[1]
        match.overMax = nil
        #expect(match.itemPrice(language: language)?.label == "VB")
        let flat = try sample(MatchPage.self, "matches").items[0]
        #expect(flat.itemPrice(language: language) == nil)
    }

    @Test(arguments: [AppLanguage.english, .german])
    func aThingsRowFacts(_ language: AppLanguage) throws {
        let de = language == .german
        let matches = try sample(MatchPage.self, "item-matches").items
        #expect(matches[0].listing.itemRowFacts(language: language)
                == (de ? "Wie neu · Abholung, 5 km · Garching" : "Like new · Pickup, 5 km · Garching"))
        #expect(matches[2].listing.itemRowFacts(language: language)
                == (de ? "Gut · Versand · Garching" : "Good · Shipping · Garching"))
        #expect(spaces(matches[1].listing.itemFactsWithPrice(language: language))
                == (de ? "480 € VB · Gut · Abholung, 5 km · Garching" : "€480 VB · Good · Pickup, 5 km · Garching"))
        #expect(matches[0].itemSourceLine(language: language)
                == (de ? "Kleinanzeigen · Schon online beim Start" : "Kleinanzeigen · Online at start"))
        #expect(matches[1].itemSourceLine(now: Clock.now, calendar: Clock.berlin, language: language)
                == matches[1].sourceLine(now: Clock.now, calendar: Clock.berlin))
    }

    @Test(arguments: [AppLanguage.english, .german])
    func aThingsPageFacts(_ language: AppLanguage) throws {
        let de = language == .german
        var match = try sample(MatchPage.self, "item-matches").items[0]
        match = try reserved(match, label: "Sehr Gut")
        let facts = match.listing.itemDetailFacts(now: Clock.now, calendar: Clock.berlin, language: language)
        #expect(facts.first?.value == (de ? "Wie neu (Sehr Gut)" : "Like new (Sehr Gut)"))
        #expect(facts.contains { $0.value == (de ? "Nur Abholung" : "Pickup only") })
        #expect(facts.first { $0.unit == "km" }?.value == "5")
        #expect(facts.last?.value == (de ? "Reserviert" : "Reserved"))
        #expect(!facts.contains { $0.label == (de ? "Versandkosten" : "Shipping cost") })
    }

    /// The same listing, reserved, with the site's own word for its condition.
    private func reserved(_ match: Match, label: String) throws -> Match {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(match)) as! [String: Any]
        var listing = object["listing"] as! [String: Any]
        var item = listing["item"] as! [String: Any]
        item["reserved"] = true
        item["condition_label"] = label
        listing["item"] = item
        object["listing"] = listing
        return try JSONDecoder().decode(Match.self, from: JSONSerialization.data(withJSONObject: object))
    }

    // MARK: the thing form

    @Test func radiusSteps() {
        #expect(RadiusSteps.up(from: 20) == 50 && RadiusSteps.down(from: 20) == 10)
        #expect(RadiusSteps.up(from: 30) == 50 && RadiusSteps.down(from: 30) == 20)
        #expect(RadiusSteps.up(from: 200) == 200 && RadiusSteps.down(from: 5) == 5)
        #expect(RadiusSteps.up(from: 0) == 5 && RadiusSteps.down(from: 0) == 5)
    }

    @Test func placesAndWordsToLeaveOut() throws {
        let places = try sample([Place].self, "places")
        var draft = ItemSearchDraft()
        #expect(draft.add(places[0]) && !draft.add(places[0]))
        let more = (1...6).map { Place(id: "test:\($0)", name: "Town \($0)", region: nil, sources: [.kleinanzeigen]) }
        for place in more { draft.add(place) }
        #expect(draft.places.count == ItemSearchDraft.maxPlaces)
        #expect(draft.addExclude("  defekt ") && !draft.addExclude("Defekt") && !draft.addExclude("  "))
        #expect(draft.exclude == ["defekt"])
        draft.delivery = .shipping
        #expect(!draft.asksPlaces)
    }

    @Test(arguments: [AppLanguage.english, .german])
    func linesUnderTheFields(_ language: AppLanguage) {
        let de = language == .german
        var draft = ItemSearchDraft()
        // A new form: what is only still empty says so under Save, not under its field.
        #expect(draft.fieldLine(.query, language: language) == nil && draft.fieldLine(.places, language: language) == nil)
        #expect(draft.hint(language: language) == (de ? "Gib ein, was du suchst." : "Type what you look for."))
        draft.query = "A"
        #expect(draft.fieldLine(.query, language: language) == (de ? "Gib ein, was du suchst." : "Type what you look for."))
        draft.query = String(repeating: "a", count: 101)
        #expect(draft.fieldLine(.query, language: language) == (de ? "Höchstens 100 Zeichen." : "At most 100 characters."))
        draft.query = "Aeron"
        #expect(draft.hint(language: language) == (de ? "Wähle einen Ort oder Versand." : "Choose a place, or Shipping."))
        draft.priceMin = "500"
        draft.priceMax = "400"
        #expect(draft.fieldLine(.priceOrder, language: language)
                == (de ? "Der niedrigste Preis liegt über dem höchsten." : "The lowest price is above the highest."))
        draft.priceMin = ""
        draft.delivery = .shipping
        #expect(draft.isValid && draft.hint(language: language) == nil)
        draft.sources = []
        #expect(draft.fieldLine(.sources, language: language)
                == (de ? "Wähle mindestens ein Portal." : "Choose at least one portal."))
        #expect(draft.fieldLine(.radius, language: language) == nil)          // not a problem: no line
    }

    // MARK: the store

    @Test func aHuntsPageLoadsItsOwnLatest() async throws {
        let session = EmpireSession(app: .arestemis, storage: MemoryTokens(), restoreOnLaunch: false)
        let store = ArestemisStore(session: session, backend: try SampleBackend(), sample: true, placeDelay: .zero)
        await store.reloadOverview()
        #expect(store.latest(hunt: 2) == nil)
        await store.loadLatest(hunt: 2)
        #expect(store.latest(hunt: 2)?.map(\.id) == [32, 31, 30])
        #expect(store.latest(hunt: 2)?.allSatisfy { store.isThing($0) } == true)
        await store.loadLatest(hunt: 1)
        #expect(store.latest(hunt: 1)?.map(\.id) == [41, 40, 38])
        #expect(store.latest(hunt: 1)?.contains { store.isThing($0) } == false)
        // A dismissed match leaves the page.
        await store.setState(.dismissed, for: 31)
        #expect(store.latest(hunt: 2)?.map(\.id) == [32, 30])
        // An unknown hunt is not remembered; a deleted one is forgotten.
        await store.loadLatest(hunt: 99)
        #expect(store.latest(hunt: 99) == nil)
        #expect(await store.deleteHunt(id: 2))
        #expect(store.latest(hunt: 2) == nil)
    }

    @Test func aThingIsKnownByItsHuntToo() async throws {
        let (store, _, _) = try await makeStore()
        await store.reloadOverview()
        var match = try sample(MatchPage.self, "matches").items[0]
        #expect(!store.isThing(match))
        match = Match(id: 77, huntID: 2, state: .new, found: match.found, listing: match.listing, reason: "",
                      warnings: [])
        #expect(match.listing.item == nil && store.isThing(match))       // a thing hunt's match without details yet
    }

    @Test func sampleStatesForScreenshots() async throws {
        let session = EmpireSession(app: .arestemis, storage: MemoryTokens(), restoreOnLaunch: false)
        let store = ArestemisStore(session: session, backend: try SampleBackend(options: .init(slowed: true, newerKind: true)),
                                   sample: true, placeDelay: .zero)
        await store.reloadOverview()
        #expect(store.hunts.map(\.slowed) == [false, true, false, true, true, false, false, false, false])
        #expect(store.hunts.last?.hunt.kind == .unknown("car") && store.hunts.last?.hunt.search == .unsupported)
    }

    // MARK: navigation

    @Test func newSearchAndTheFormsItOpens() {
        let navigation = AppNavigation()
        navigation.tab = .listings
        navigation.huntPath = [.hunt(1)]
        navigation.startNewSearch()
        #expect(navigation.tab == .hunt && navigation.huntPath.isEmpty && navigation.asksSearchKind)
        navigation.openNewForm(.item)
        #expect(navigation.huntPath == [.form(.item, hunt: nil)])
        // Saving it shows the new hunt's page in the form's place.
        navigation.showCreated(4)
        #expect(navigation.huntPath == [.hunt(4)])
        navigation.huntPath.append(.form(.item, hunt: 4))
        navigation.leaveDeleted()
        #expect(navigation.huntPath.isEmpty)
        navigation.asksSearchKind = true
        navigation.open(ArestemisLink(match: 31))
        #expect(!navigation.asksSearchKind && navigation.tab == .listings && navigation.listingsPath == [.match(31)])
        navigation.asksSearchKind = true
        navigation.reset()
        #expect(!navigation.asksSearchKind && navigation.formScroll == nil)
    }

    @Test func launchArgumentsReachEveryScreen() throws {
        let cards = try hunts()
        func apply(_ arguments: [String]) -> AppNavigation {
            let navigation = AppNavigation()
            LaunchOptions(arguments: ["-sampleData"] + arguments).apply(to: navigation, hunts: cards, firstMatch: nil)
            return navigation
        }
        #expect(apply(["-tab", "search"]).huntPath == [.form(.flat, hunt: 1)])
        #expect(apply(["-tab", "search"]).tab == .hunt)
        #expect(apply(["-openHunt", "2"]).huntPath == [.hunt(2)])
        #expect(apply(["-openItemForm"]).huntPath == [.form(.item, hunt: 2)])
        #expect(apply(["-openForm", "3"]).huntPath == [.form(.flat, hunt: 3)])
        #expect(apply(["-newItemForm", "-scrollBottom"]).huntPath == [.form(.item, hunt: nil)])
        #expect(apply(["-newItemForm", "-scrollBottom"]).formScroll == "bottom")
        #expect(apply(["-openHunt", "2", "-openItemForm"]).huntPath == [.hunt(2), .form(.item, hunt: 2)])
        #expect(apply(["-newSearch"]).asksSearchKind)
        #expect(apply(["-openItemForm", "-openSheet", "describe"]).showsDescribe)
        #expect(LaunchOptions.route(.firstItem, hunts: []) == .form(.item, hunt: nil))
        #expect(LaunchOptions.route(.firstHunt, hunts: []) == .form(.flat, hunt: nil))
        let options = LaunchOptions(arguments: ["-sampleData", "-sampleSlowed", "-sampleNewerKind", "-openSearch", "2"])
        #expect(options.slowed && options.newerKind && options.tab == .listings && options.form == nil)
    }
}
