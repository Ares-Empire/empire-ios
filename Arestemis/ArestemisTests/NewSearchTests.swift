import Foundation
import Testing
@testable import Arestemis

/// Brief 135: New search's cards (from `/kinds`) and examples, the one Name field in every form, renaming a search in
/// place, and a search card's long press; the words in both languages.
@MainActor
struct NewSearchTests {
    private let en = AppLanguage.english
    private let de = AppLanguage.german
    private func hunts() throws -> [HuntCard] { try sample(Overview.self, "overview").hunts }

    // MARK: New search's cards

    @Test func theCardsComeFromKindsInTheServersOrder() throws {
        // The sample as the server answers after brief 134: flat, item, price, watch; the Preismonitor's card since brief
        // 137.
        let kinds = try sample([OfferedKind].self, "kinds")
        let cards = NewSearchCard.cards(offered: kinds, language: en)
        #expect(cards.map(\.kind) == [.flat, .item, .price, .watch])
        #expect(cards.map(\.name) == ["Flat", "Things", "Price monitor", "Watch a website"])

        // The server's order and names, whatever they are; a kind of a newer server is left out, as is one this build
        // cannot open; a kind named twice is one card.
        let server = [OfferedKind(kind: .watch, name: "Webseite beobachten", sources: []),
                      OfferedKind(kind: .unknown("car"), name: "Auto", sources: []),
                      OfferedKind(kind: .price, name: "Preismonitor", sources: []),
                      OfferedKind(kind: .flat, name: "Wohnung", sources: []),
                      OfferedKind(kind: .watch, name: "Again", sources: [])]
        let ordered = NewSearchCard.cards(offered: server, language: de)
        #expect(ordered.map(\.kind) == [.watch, .price, .flat])
        #expect(ordered.map(\.name) == ["Webseite beobachten", "Preismonitor", "Wohnung"])
        // A server without watches offers none.
        #expect(NewSearchCard.cards(offered: kinds.filter { $0.kind != .watch }, language: en).map(\.kind)
                == [.flat, .item, .price])
        // A name the server leaves empty: this build's.
        let unnamed = NewSearchCard.cards(offered: [OfferedKind(kind: .item, name: "  ", sources: [])], language: en)
        #expect(unnamed.map(\.name) == ["Things"])
        // No answer (offline, an older server), or one naming none of this build's kinds: all four, never an empty page.
        let none: [[OfferedKind]?] = [nil, [], [OfferedKind(kind: .unknown("car"), name: "Car", sources: [])]]
        for answer in none {
            #expect(NewSearchCard.cards(offered: answer, language: en).map(\.kind) == [.flat, .item, .price, .watch])
        }
        #expect(NewSearchCard.cards(offered: nil, language: en).map(\.name)
                == ["Flat", "Things", "Price monitor", "Watch a website"])
        #expect(NewSearchCard.cards(offered: nil, language: de).map(\.name)
                == ["Wohnung", "Dinge", "Preismonitor", "Webseite beobachten"])
    }

    @Test(arguments: [AppLanguage.english, .german])
    func eachCardSaysWhatItDoesAndShowsItsExamples(_ language: AppLanguage) {
        let german = language == .german
        let cards = NewSearchCard.cards(offered: nil, language: language)
        #expect(cards.map(\.line) == (german ? [
            "Neue Angebote von WG-Gesucht, Kleinanzeigen, Immowelt und ImmoScout24, Minuten nachdem sie online sind.",
            "Gebraucht und günstig: Kleinanzeigen, eBay, Vinted, IKEA Preowned und mehr, mit Preisgrenze und Abholung in der Nähe.",
            "Ein Produkt in einem Shop: der Preisverlauf, und Bescheid, wenn es günstiger oder wieder lieferbar ist.",
            "Eine Seite, die du kennst: neue Version, neue Stelle, Tickets, der Speiseplan.",
        ] : [
            "New listings from WG-Gesucht, Kleinanzeigen, Immowelt and ImmoScout24, minutes after they go online.",
            "Used and cheap: Kleinanzeigen, eBay, Vinted, IKEA Preowned and more, with a price limit and pickup nearby.",
            "One product in one shop: its price history, and a word when it gets cheaper or is back in stock.",
            "A page you know: a new version, a new job, tickets, the canteen menu.",
        ]))
        #expect(cards.map { $0.examples.map { $0.title(language: language) } } == (german ? [
            ["2 Zimmer bis 1.100 € warm", "WG-Zimmer"],
            ["Kallax bis 40 €", "Rennrad Größe 56"],
            ["Preis unter … €", "Wieder lieferbar"],
            ["Neue Version", "Neue Stelle", "Speiseplan"],
        ] : [
            ["2 rooms up to €1,100 warm", "WG room"],
            ["Kallax up to €40", "Road bike size 56"],
            ["Price under € …", "Back in stock"],
            ["New version", "New job", "Canteen menu"],
        ]))
        #expect(language.string("What should Arestemis find for you?")
                == (german ? "Was soll Arestemis für dich finden?" : "What should Arestemis find for you?"))
        #expect(language.string("New search") == (german ? "Neue Suche" : "New search"))
    }

    // MARK: the examples fill their forms

    @Test(arguments: [AppLanguage.english, .german])
    func eachExampleFillsItsFormAndLeavesThePlaceToTheUser(_ language: AppLanguage) throws {
        let german = language == .german
        // A whole flat, at least 2 rooms, up to €1,100 warm; the town is the user's (the form asks for it under Save).
        let rooms = try #require(SearchExample.twoRooms.flatDraft)
        var flat = SearchDraft()
        flat.type = .flat
        flat.roomsMin = 2
        flat.warmRent.max = 1100
        #expect(rooms == flat && rooms.places.isEmpty && rooms.name.isEmpty)
        #expect(rooms.search().kinds == [.flat] && rooms.search().roomsMin == 2 && rooms.search().rentWarmMax == 1100)
        #expect(rooms.problems == [.noPlace])
        var wg = SearchDraft()
        wg.type = .wg
        #expect(SearchExample.wgRoom.flatDraft == wg)

        // The words and the price; the size where the form asks for it (Extras); pickup places stay the user's.
        let kallax = try #require(SearchExample.kallax.itemDraft(language: language))
        #expect(kallax.query == "Kallax" && kallax.priceMax == "40" && kallax.priceMin.isEmpty)
        #expect(kallax.vbOverMax == "4")                // the form's usual default: a tenth of the maximum
        #expect(kallax.places.isEmpty && kallax.name.isEmpty && kallax.problems == [.places])
        let bike = try #require(SearchExample.roadBike.itemDraft(language: language))
        #expect(bike.query == (german ? "Rennrad" : "Road bike") && bike.priceMax.isEmpty)
        #expect(bike.extra == (german ? "Rahmengröße 56" : "Frame size 56"))

        // The "Tell me when" sentence; the page's address is the user's.
        let changes: [(SearchExample, String, String)] = [
            (.newVersion, "a new version comes out", "eine neue Version erscheint"),
            (.newJob, "a new job is posted", "eine neue Stelle ausgeschrieben wird"),
            (.canteenMenu, "the new menu is out", "der neue Speiseplan online ist"),
        ]
        for (example, english, deutsch) in changes {
            let watch = try #require(example.watchDraft(language: language))
            #expect(watch.change == (german ? deutsch : english))
            #expect(watch.url.isEmpty && watch.every == WatchSearch.defaultEvery && watch.name.isEmpty)
            #expect(watch.problems == [.url])
        }

        // Each example fills its own kind's form, and only that.
        for example in SearchExample.allCases {
            let filled = [example.flatDraft != nil, example.itemDraft(language: language) != nil,
                          example.priceDraft != nil, example.watchDraft(language: language) != nil]
            #expect(filled == SearchKind.all.map { $0 == example.kind })
        }
        #expect(SearchKind.all.flatMap(SearchExample.examples(for:)) == SearchExample.allCases)
    }

    // MARK: the Name field

    @Test(arguments: [AppLanguage.english, .german])
    func theNamesPlaceholderIsTheAutomaticNameAndFollowsTheForm(_ language: AppLanguage) throws {
        let german = language == .german
        var flat = SearchDraft()
        #expect(flat.namePlaceholder(language: language) == (german ? "Wohnung oder WG-Zimmer" : "Flat or WG room"))
        flat.type = .wg
        #expect(flat.namePlaceholder(language: language) == (german ? "WG-Zimmer" : "WG room"))
        flat.type = .flat
        #expect(flat.namePlaceholder(language: language) == (german ? "Wohnung" : "Flat"))
        // A name typed changes the field, not its placeholder.
        flat.name = "Quiet flat"
        #expect(flat.namePlaceholder(language: language) == (german ? "Wohnung" : "Flat"))

        var thing = ItemSearchDraft()
        #expect(thing.namePlaceholder(language: language) == "Optional")
        thing.query = "  Kallax "
        #expect(thing.namePlaceholder(language: language) == "Kallax")

        // The placeholder is what the hunt's card shows while it has no name of its own.
        for card in try hunts() {
            var hunt = card.hunt
            hunt.name = nil
            let title = HuntText(hunt, page: card.page, language: language).title
            #expect(HuntText.automaticTitle(hunt.search, page: card.page, language: language) == title)
            if let draft = SearchDraft(saved: hunt) { #expect(draft.namePlaceholder(language: language) == title) }
            if let draft = ItemSearchDraft(saved: hunt) { #expect(draft.namePlaceholder(language: language) == title) }
        }
        #expect(HuntText.automaticTitle(.unsupported) == nil)
        #expect(HuntName.placeholder(nil, language: language) == "Optional")
    }

    @Test func everyFormsDraftCarriesTheName() throws {
        let cards = try hunts()
        let named = try #require(cards.first { $0.hunt.name == "A quieter flat" }?.hunt)
        #expect(SearchDraft(saved: named)?.name == "A quieter flat")
        #expect(SearchDraft(saved: named)?.sentName == "A quieter flat")
        let thing = try #require(cards.first { $0.hunt.kind == .item }?.hunt)
        #expect(ItemSearchDraft(saved: thing)?.name == "" && ItemSearchDraft(saved: thing)?.sentName == nil)
        #expect(SearchDraft(saved: thing) == nil && WatchSearchDraft(saved: named) == nil)
        let watch = try #require(cards.first { $0.hunt.name == "AirPods Pro 3" }?.hunt)
        #expect(WatchSearchDraft(saved: watch)?.name == "AirPods Pro 3")
        // Trimmed, at most 60 characters, nothing for spaces.
        var draft = ItemSearchDraft()
        draft.name = "  Kallax for the study  "
        #expect(draft.sentName == "Kallax for the study")
        draft.name = "   "
        #expect(draft.sentName == nil)
        draft.name = String(repeating: "a", count: 70)
        #expect(draft.sentName?.count == 60)
        // A thing draft kept by a build from before brief 135 (no name) still opens.
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ItemSearchDraft())) as! [String: Any]
        old["name"] = nil
        let decoded = try JSONDecoder().decode(ItemSearchDraft.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(decoded == ItemSearchDraft())
    }

    @Test func theNameIsSentKeptAndCleared() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        let hunt = try #require(store.card(3)?.hunt)            // "A quieter flat"
        try transport.answer("PUT /hunts/3", encoding: hunt)
        var draft = try #require(store.savedDraft(SearchDraft.self, huntID: 3))
        func sent() throws -> [String: Any]? { try body(transport.requests("PUT /hunts/3").last) }

        // Kept: the field as it opened.
        _ = await store.saveHunt(id: 3, kind: .flat, name: draft.sentName, search: .flat(draft.search()))
        #expect(try sent()?["name"] as? String == "A quieter flat")
        // Changed, trimmed.
        draft.name = "  Quiet flat  "
        _ = await store.saveHunt(id: 3, kind: .flat, name: draft.sentName, search: .flat(draft.search()))
        #expect(try sent()?["name"] as? String == "Quiet flat")
        // Cleared: null, so the hunt is named after what it looks for again (the contract's `""`/null).
        draft.name = "   "
        _ = await store.saveHunt(id: 3, kind: .flat, name: draft.sentName, search: .flat(draft.search()))
        let cleared = try #require(try sent())
        #expect(cleared.keys.contains("name") && cleared["name"] is NSNull)

        // A new thing search sends its name with the search.
        var thing = try #require(SearchExample.kallax.itemDraft())
        thing.delivery = .shipping
        thing.name = "Kallax for the study"
        let search = try #require(thing.search())
        let created = Hunt(id: 9, kind: .item, name: "Kallax for the study", active: false, search: .item(search),
                           created: "2026-11-02T10:00:00Z", updated: "2026-11-02T10:00:00Z", activated: nil)
        try transport.answer("POST /hunts", 201, encoding: created)
        #expect(await store.saveHunt(id: nil, kind: .item, name: thing.sentName, search: .item(search)) != nil)
        let posted = try #require(try body(transport.requests("POST /hunts").last))
        #expect(posted["name"] as? String == "Kallax for the study" && posted["kind"] as? String == "item")
    }

    // MARK: renaming in place

    @Test func renamingInPlaceSendsOnlyAChangedName() throws {
        let cards = try hunts()
        let named = try #require(cards.first { $0.id == 3 }?.hunt)
        var edit = NameEdit(named)
        #expect(edit.hunt == 3 && edit.text == "A quieter flat" && edit.original == "A quieter flat" && !edit.hasChanges)
        // Spaces around it change nothing: Return or a tap elsewhere just closes the field.
        edit.text = " A quieter flat "
        #expect(!edit.hasChanges)
        edit.text = "Quiet flat"
        #expect(edit.hasChanges && edit.name == "Quiet flat")
        // Empty: the automatic name again.
        edit.text = ""
        #expect(edit.hasChanges && edit.name == nil)
        // At most 60 characters, as typed.
        edit.text = String(repeating: "b", count: 75)
        #expect(edit.text.count == 60 && edit.name?.count == 60)

        // A search without its own name: the field opens empty (the automatic name shows grey in it).
        let unnamed = try #require(cards.first { $0.id == 2 }?.hunt)
        var fresh = NameEdit(unnamed)
        #expect(fresh.text.isEmpty && fresh.original == nil && !fresh.hasChanges)
        fresh.text = "   "
        #expect(!fresh.hasChanges)
        fresh.text = "Desk chair"
        #expect(fresh.hasChanges && fresh.name == "Desk chair")
    }

    @Test func aRenameSendsTheNameAlone() async throws {
        // PATCH /hunts/{id}: the server changes the name and nothing else (a PUT would start the search again).
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        let hunt = try #require(store.card(2)?.hunt)
        var renamed = hunt
        renamed.name = "Desk chair"
        try transport.answer("PATCH /hunts/2", encoding: renamed)
        var edit = NameEdit(hunt)
        edit.text = "Desk chair"
        #expect(await store.renameHunt(id: 2, name: edit.name))
        let sent = try #require(try body(transport.requests("PATCH /hunts/2").last))
        #expect(Set(sent.keys) == ["name"] && sent["name"] as? String == "Desk chair")
        #expect(transport.requests("PUT /hunts/2").isEmpty)
        #expect(store.card(2)?.hunt.name == "Desk chair" && store.card(2)?.hunt.search == hunt.search)
        #expect(HuntText(try #require(store.card(2)?.hunt)).title == "Desk chair")

        // Emptied: null, the automatic name again.
        try transport.answer("PATCH /hunts/2", encoding: hunt)
        var back = NameEdit(renamed)
        back.text = ""
        #expect(await store.renameHunt(id: 2, name: back.name))
        #expect(try body(transport.requests("PATCH /hunts/2").last)?["name"] is NSNull)
        #expect(HuntText(try #require(store.card(2)?.hunt)).title == "Herman Miller Aeron")
    }

    @Test func aRenameElsewhereDropsAFormsKeptEdits() async throws {
        let suite = "NewSearchTests.kept.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let (_, transport, session) = try await makeStore()
        let store = ArestemisStore(session: session, backend: ArestemisAPI(transport: transport, token: { session.token }),
                                   defaults: defaults)
        await store.reloadOverview()
        var edited = try #require(store.savedDraft(ItemSearchDraft.self, huntID: 2))
        edited.priceMax = "300"
        store.keepSearchDraft(edited, huntID: 2)
        #expect(store.itemSearchDraft(huntID: 2) == edited)
        // Renamed on another device: the form opens with the new name, not the edit that still carried the old one
        // (Save would have brought the old name back).
        var overview = try sample(Overview.self, "overview")
        overview.hunts[1].hunt.name = "Desk chair"
        try transport.answer("GET /overview", encoding: overview)
        await store.reloadOverview()
        let opened = store.itemSearchDraft(huntID: 2)
        #expect(opened.name == "Desk chair" && opened.priceMax == "450")
    }

    // MARK: a card's long press

    @Test func aCardsLongPressOffersRenamePauseOrStartAndDelete() async throws {
        for card in try hunts() {
            let actions = HuntPageActions(card.hunt)
            #expect(actions.rename && actions.startPause && actions.delete)
        }
        let newer = Hunt(id: 9, kind: .unknown("car"), name: "Camper van", active: true, search: .unsupported,
                         created: "2026-10-24T08:12:00Z", updated: "2026-10-24T08:12:00Z", activated: nil)
        let actions = HuntPageActions(newer)
        #expect(!actions.rename && !actions.startPause && actions.delete)

        // Rename, from either tab: the search's page on the Hunts tab, its name's field ready.
        let navigation = AppNavigation(defaults: try #require(UserDefaults(suiteName: "NewSearchTests.\(UUID())")))
        navigation.tab = .listings
        navigation.listingsPath = [.hunt(2)]
        navigation.huntPath = [.newSearch]
        navigation.rename(2)
        #expect(navigation.tab == .hunt && navigation.huntPath == [.hunt(2)] && navigation.renaming == 2)
        #expect(navigation.listingsPath == [.hunt(2)])

        // Pause, Start and Delete do what the page's buttons do.
        let session = EmpireSession(app: .arestemis, storage: MemoryTokens(), restoreOnLaunch: false)
        let store = ArestemisStore(session: session, backend: try SampleBackend(), sample: true, placeDelay: .zero)
        await store.reloadOverview()
        await store.setActive(id: 2, active: false)
        #expect(store.card(2)?.hunt.active == false)
        await store.setActive(id: 2, active: true)
        #expect(store.card(2)?.hunt.active == true)
        navigation.leaveDeleted(2)
        #expect(await store.deleteHunt(id: 2))
        #expect(store.card(2) == nil && navigation.huntPath.isEmpty && navigation.listingsPath.isEmpty)
    }

    // MARK: words

    @Test func theWordsInBothLanguages() {
        let words: [(String, String)] = [
            ("Rename", "Umbenennen"), ("Pause", "Pausieren"), ("Start", "Starten"), ("Delete", "Löschen"),
            ("Name", "Name"), ("Optional", "Optional"), ("Cancel", "Abbrechen"), ("Save", "Speichern"),
            ("Clear", "Leeren"), ("Opens the form", "Öffnet das Formular"),
            ("Opens the form filled in", "Öffnet das Formular ausgefüllt"),
            ("Flat", "Wohnung"), ("Things", "Dinge"), ("Watch a website", "Webseite beobachten"),
            ("Road bike", "Rennrad"), ("Frame size 56", "Rahmengröße 56"),
        ]
        for (english, german) in words {
            #expect(en.string(LocalizedStringResource(stringLiteral: english)) == english)
            #expect(de.string(LocalizedStringResource(stringLiteral: english)) == german)
        }
    }
}
