import Foundation
import Testing
import UserNotifications
@testable import Arestemis

/// Brief 131: page watches in the app. The contract's types (`WatchSearch`, `PageState`, `Listing.page`, the kind in
/// `/kinds`), the form's draft (required fields, how often, the name, a pasted text), the card's lines per state in both
/// languages, a found change's lines, the push category, the samples and the server's refusals at their fields.
@MainActor
struct WatchTests {
    private let en = AppLanguage.english
    private let de = AppLanguage.german

    private func decodePage(_ json: String) throws -> PageState {
        try JSONDecoder().decode(PageState.self, from: Data(json.utf8))
    }

    private func page(_ read: PageState.Read, now: String? = nil, note: String? = nil, checked: String? = nil,
                      changed: String? = nil) -> PageState {
        PageState(pageTitle: "Fjord shelf", host: "shop.example", now: now, read: read, checked: checked,
                  changed: changed, note: note)
    }

    // MARK: decoding

    @Test func aWatchHuntAndItsPage() throws {
        let overview = try sample(Overview.self, "overview")
        let watches = overview.hunts.filter { $0.hunt.kind == .watch }
        #expect(watches.map(\.id) == [6, 7, 8])
        let kallax = try #require(watches.first)
        #expect(kallax.hunt.search.watch == WatchSearch(url: "https://www.ikea.com/de/de/p/kallax-regal-weiss-80275887/",
                                                       change: "the price is under 45 €", every: 60))
        #expect(kallax.sources.isEmpty)
        #expect(kallax.page?.read == .ok && kallax.page?.now == "KALLAX 44,99 €" && kallax.page?.host == "www.ikea.com")
        #expect(watches[1].page?.read == .blocked && watches[1].page?.now == nil && watches[1].page?.note != nil)
        // The other kinds have no page.
        #expect(overview.hunts.filter { $0.hunt.kind != .watch }.allSatisfy { $0.page == nil })
        #expect(try JSONEncoder().encode(HuntKind.watch) == Data(#""watch""#.utf8))
    }

    @Test(arguments: [("waiting", PageState.Read.waiting), ("ok", .ok), ("unreadable", .unreadable),
                      ("failing", .failing), ("blocked", .blocked), ("captcha_wall", .unknown("captcha_wall"))])
    func everyReadDecodes(_ raw: String, _ read: PageState.Read) throws {
        let page = try decodePage("""
            {"page_title": null, "host": "shop.example", "now": null, "read": "\(raw)", "checked": null,
             "changed": null, "note": "A note."}
            """)
        #expect(page.read == read && page.host == "shop.example" && page.pageTitle == nil)
        // It is kept as it came.
        #expect(try JSONDecoder().decode(PageState.self, from: JSONEncoder().encode(page)) == page)
    }

    @Test func aPageStateIsReadLeniently() throws {
        let bare = try decodePage("{}")
        #expect(bare.read == .waiting && bare.host.isEmpty && bare.now == nil && bare.note == nil)
        // A page state that cannot be read leaves the card (and the overview) as they are, without the page.
        var object = try #require(try JSONSerialization.jsonObject(with: ArestemisSamples.data("overview")) as? [String: Any])
        var hunts = try #require(object["hunts"] as? [[String: Any]])
        hunts[5]["page"] = "not a page"
        object["hunts"] = hunts
        let overview = try JSONDecoder().decode(Overview.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(overview.hunts[5].hunt.kind == .watch && overview.hunts[5].page == nil)
    }

    @Test func aFoundChange() throws {
        let page = try sample(MatchPage.self, "watch-matches")
        let change = try #require(page.items.first)
        #expect(change.listing.source == .page && change.listing.sourceName == "www.ikea.com")
        #expect(change.listing.item == nil && change.isPageChange && !change.isThing)
        #expect(change.listing.page == PageChange(added: ["Neuer niedrigerer Preis", "44,99 €", "Gültig bis 15.11.2026"],
                                                  removed: ["49,99 €"], now: "KALLAX 44,99 €"))
        let atStart = page.items[1]
        #expect(atStart.atStart && atStart.listing.page?.added.isEmpty == true)
        // A flat's and a thing's listing have no page.
        #expect(try sample(Match.self, "match").listing.page == nil)
        let lenient = try JSONDecoder().decode(PageChange.self, from: Data(#"{"now": "FJORD 44,99 €"}"#.utf8))
        #expect(lenient == PageChange(now: "FJORD 44,99 €"))
    }

    @Test func theKindIsOfferedByTheServer() throws {
        let kinds = try sample([OfferedKind].self, "kinds")
        let watch = try #require(kinds.first { $0.kind == .watch })
        #expect(watch.name == "Watch a website" && watch.sources.isEmpty)
        #expect(SearchKind.choices(offered: kinds) == [.flat, .item, .price, .watch])
        // A server without watches: not offered. No answer, or an answer naming none of them: all four.
        #expect(SearchKind.choices(offered: kinds.filter { $0.kind != .watch }) == [.flat, .item, .price])
        #expect(SearchKind.choices(offered: nil) == [.flat, .item, .price, .watch])
        #expect(SearchKind.choices(offered: []) == [.flat, .item, .price, .watch])
        #expect(SearchKind(.watch) == .watch && SearchKind.watch.huntKind == .watch && SearchKind.watch.symbol == "eye")
        #expect(SearchKind.watch.choiceTitle(language: en) == "Watch a website")
        #expect(SearchKind.watch.choiceTitle(language: de) == "Webseite beobachten")
        #expect(SiteChoices.fallback(.watch).isEmpty)
    }

    // MARK: the form's draft

    @Test(arguments: [AppLanguage.english, .german])
    func requiredFields(_ language: AppLanguage) {
        let german = language == .german
        var draft = WatchSearchDraft()
        // A new form: nothing is wrong under the fields; under Save, what is missing first.
        #expect(draft.problems == [.url, .change] && draft.search() == nil)
        #expect(draft.fieldLine(.url, language: language) == nil && draft.fieldLine(.change, language: language) == nil)
        #expect(draft.hint(language: language) == (german ? "Füg die Adresse der Seite ein." : "Paste the page's address."))
        draft.url = "  ikea.com/de  "
        #expect(draft.hint(language: language)
                == (german ? "Beschreib, auf welche Änderung geachtet werden soll." : "Describe the change to watch for."))
        draft.change = "ab"
        #expect(draft.fieldLine(.change, language: language) == (german ? "Mindestens 3 Zeichen." : "At least 3 characters."))
        draft.change = String(repeating: "a", count: 501)
        #expect(draft.fieldLine(.change, language: language) == (german ? "Höchstens 500 Zeichen." : "At most 500 characters."))
        draft.change = "  the price is under 45 €\n"
        #expect(draft.isValid && draft.hint(language: language) == nil)
        #expect(draft.search() == WatchSearch(url: "ikea.com/de", change: "the price is under 45 €", every: 60))
        draft.url = "https://example.com/" + String(repeating: "a", count: 2000)
        #expect(draft.fieldLine(.url, language: language) == (german ? "Höchstens 2.000 Zeichen." : "At most 2,000 characters."))
    }

    @Test(arguments: [AppLanguage.english, .german])
    func howOften(_ language: AppLanguage) {
        let german = language == .german
        #expect(WatchSearchDraft().every == 60 && WatchSearch.defaultEvery == 60)
        #expect(WatchSearch.everyChoices == [15, 30, 60, 180, 360, 720, 1440])
        #expect(WatchSearch.everyChoices.map { WatchInterval.title($0, language: language) }
                == (german ? ["Alle 15 Min.", "Alle 30 Min.", "Jede Stunde", "Alle 3 Stunden", "Alle 6 Stunden",
                              "Alle 12 Stunden", "Einmal am Tag"]
                           : ["Every 15 min", "Every 30 min", "Every hour", "Every 3 hours", "Every 6 hours",
                              "Every 12 hours", "Once a day"]))
        // A newer server's interval stays choosable as it is.
        #expect(WatchInterval.choices(keeping: 60) == WatchSearch.everyChoices)
        #expect(WatchInterval.choices(keeping: 90) == [15, 30, 60, 90, 180, 360, 720, 1440])
        #expect(WatchInterval.title(90, language: language) == (german ? "Alle 90 Min." : "Every 90 min"))
    }

    @Test func theNameRule() {
        var draft = WatchSearchDraft(WatchSearch(url: "https://www.ikea.com/p/1", change: "under 45 €", every: 180),
                                     name: nil)
        #expect(draft.name.isEmpty && draft.sentName == nil && draft.every == 180)
        // Empty: the page's title once its address was read, else the host of the address typed, else "Optional".
        let saved = draft.url
        #expect(draft.namePlaceholder(savedURL: saved, pageTitle: "KALLAX Regal", language: en) == "KALLAX Regal")
        #expect(draft.namePlaceholder(savedURL: saved, pageTitle: nil, language: en) == "www.ikea.com")
        draft.url = "https://shop.example/shelf"
        #expect(draft.namePlaceholder(savedURL: saved, pageTitle: "KALLAX Regal", language: en) == "shop.example")
        draft.url = ""
        #expect(draft.namePlaceholder(language: en) == "Optional" && draft.namePlaceholder(language: de) == "Optional")
        // Sent trimmed, at most 60 characters, nothing for spaces.
        draft.name = "   "
        #expect(draft.sentName == nil)
        draft.name = "  Shelf price "
        #expect(draft.sentName == "Shelf price")
        draft.name = String(repeating: "n", count: 70)
        #expect(draft.sentName?.count == 60)
        #expect(WatchSearchDraft(WatchSearch(url: "u", change: "c", every: 15), name: "Mine").name == "Mine")
    }

    @Test(arguments: [
        ("Look at this: https://www.ikea.com/de/de/p/kallax-regal-weiss-80275887/ only 49,99 €",
         "https://www.ikea.com/de/de/p/kallax-regal-weiss-80275887/"),
        ("KALLAX Regal\nhttps://shop.example/shelf?id=4\nhttps://other.example/", "https://shop.example/shelf?id=4"),
        ("Seen on www.ikea.com/de/de/p/kallax today", "www.ikea.com/de/de/p/kallax"),
        // An address alone, or typed, stays exactly as it is.
        ("ikea.com", "ikea.com"),
        ("https://shop.example/a b", "https://shop.example/a"),
        ("https://shop.example/shelf", "https://shop.example/shelf"),
        // Words without a web link stay: the server says what it cannot watch.
        ("just some words", "just some words"),
        ("write to someone@example.com please", "write to someone@example.com please"),
    ])
    func aPastedTextKeepsItsFirstLink(_ pasted: String, _ kept: String) {
        #expect(WatchAddress.fromField(pasted) == kept)
        var draft = WatchSearchDraft()
        draft.url = pasted
        draft.takeAddress(pasted)
        #expect(draft.url == kept)
    }

    @Test func theAddressHost() {
        #expect(WatchAddress.host("https://www.IKEA.com/de/") == "www.ikea.com")
        #expect(WatchAddress.host("ikea.com/de") == "ikea.com")
        #expect(WatchAddress.host("  ") == nil && WatchAddress.host("") == nil)
    }

    @Test func keptDraftsOfAWatch() throws {
        let suite = "WatchTests.kept.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let kept = KeptSearchDraft(defaults: defaults)
        let saved = WatchSearchDraft(WatchSearch(url: "https://shop.example/", change: "under 45 €", every: 60), name: nil)
        var edited = saved
        edited.change = "under 40 €"
        kept.keep(edited, saved: saved, account: "a", huntID: 6)
        #expect(kept.restore(saved: saved, account: "a", huntID: 6) == edited)
        // Saved elsewhere meanwhile: the kept edit is dropped.
        var other = saved
        other.every = 15
        #expect(kept.restore(saved: other, account: "a", huntID: 6) == other)
        // A new watch's draft, and nothing kept while it is empty.
        var fresh = WatchSearchDraft()
        fresh.url = "shop.example"
        kept.keep(fresh, saved: nil, account: "a")
        #expect(kept.restore(WatchSearchDraft.self, saved: nil, account: "a") == fresh)
        kept.keep(WatchSearchDraft(), saved: nil, account: "a")
        #expect(kept.restore(WatchSearchDraft.self, saved: nil, account: "a") == WatchSearchDraft())
    }

    // MARK: the card

    @Test(arguments: [AppLanguage.english, .german])
    func theCardsLinePerState(_ language: AppLanguage) {
        let german = language == .german
        func text(_ page: PageState?) -> WatchCardText {
            WatchCardText(page, now: Clock.now, calendar: Clock.berlin, language: language)
        }
        let hint = german ? "Beim Bearbeiten wird es noch einmal versucht." : "Editing the watch tries again."
        let cannot = german ? "Die Seite lässt sich gerade nicht lesen." : "The page can't be read right now."

        // ok: what the page says now is the main fact, an amount kept with its sign.
        let ok = text(page(.ok, now: "FJORD 49,99 €", checked: "2026-10-24T10:00:00Z", changed: "2026-10-24T09:00:00Z"))
        #expect(ok.fact == "FJORD 49,99\u{a0}€" && ok.note == nil)
        #expect(ok.times == (german ? "Geprüft vor 2 Min. · Geändert vor 1 Std." : "Checked 2 min ago · Changed 1 h ago"))
        // waiting, and a watch without a page yet (just made): reading.
        for waiting in [text(page(.waiting)), text(nil)] {
            #expect(waiting.fact == nil && waiting.times == nil)
            #expect(waiting.note == (german ? "Seite wird gelesen…" : "Reading the page…"))
        }
        // unreadable, failing: the server's note, or a quiet line of the app's own when it sent none.
        #expect(text(page(.unreadable, note: "This page doesn't show it; it may need a browser.")).note
                == "This page doesn't show it; it may need a browser.")
        #expect(text(page(.unreadable)).note == (german ? "Die Seite zeigt das nicht." : "This page doesn't show it."))
        let failing = text(page(.failing, now: "FJORD 49,99 €", checked: "2026-10-24T09:30:00Z"))
        #expect(failing.fact == nil && failing.note == cannot)
        #expect(failing.times == (german ? "Geprüft vor 32 Min." : "Checked 32 min ago"))
        // blocked: the note, then that editing tries again.
        #expect(text(page(.blocked, note: "Cloudflare refuses the server since 13:00.")).note
                == "Cloudflare refuses the server since 13:00. " + hint)
        #expect(text(page(.blocked)).note == cannot + " " + hint)
        // A state this build does not know: the server's note only.
        let unknown = text(page(.unknown("captcha_wall"), now: "FJORD 49,99 €", note: "A new kind of refusal."))
        #expect(unknown.fact == nil && unknown.note == "A new kind of refusal.")
        #expect(text(page(.unknown("captcha_wall"))).note == nil)
    }

    @Test(arguments: [AppLanguage.english, .german])
    func theCardsNameAndHost(_ language: AppLanguage) throws {
        let cards = try sample(Overview.self, "overview").hunts
        let kallax = try #require(cards.first { $0.id == 6 })
        var text = HuntText(kallax.hunt, page: kallax.page, language: language)
        #expect(text.kind == .watch && text.newerApp == nil)
        #expect(text.title == "KALLAX Regal, weiß, 77x147 cm - IKEA Deutschland" && text.details == "www.ikea.com")
        // An own name first; without a page title, the host is the name (and not repeated under it).
        let named = try #require(cards.first { $0.id == 7 })
        text = HuntText(named.hunt, page: named.page, language: language)
        #expect(text.title == "AirPods Pro 3" && text.details == "geizhals.de")
        var hunt = named.hunt
        hunt.name = nil
        text = HuntText(hunt, page: named.page, language: language)
        #expect(text.title == "geizhals.de" && text.details == nil)
        // A watch the overview has not sent a page for yet: its address's host.
        text = HuntText(hunt, page: nil, language: language)
        #expect(text.title == "geizhals.de")
        #expect(cards.filter { $0.hunt.kind == .watch }.map { SearchRow($0, language: language).text.title }
                == ["KALLAX Regal, weiß, 77x147 cm - IKEA Deutschland", "AirPods Pro 3", "Schnitzel at the Mensa"])
    }

    @Test(arguments: [AppLanguage.english, .german])
    func aWatchsWordsAndFigures(_ language: AppLanguage) {
        let german = language == .german
        let watch = HuntWords(.watch, language: language)
        #expect(watch.status(active: true) == (german ? "Beobachtung läuft" : "Watching"))
        #expect(watch.status(active: false) == (german ? "Pausiert" : "Paused"))
        // A blocked watch: the server reads its page no more until it is edited.
        #expect(watch.status(active: true, stopped: true) == (german ? "Angehalten" : "Stopped"))
        #expect(watch.status(active: false, stopped: true) == (german ? "Pausiert" : "Paused"))
        #expect(watch.start == (german ? "Beobachtung starten" : "Start watching"))
        #expect([watch.newTitle, watch.editTitle, watch.create, watch.save, watch.delete]
                == (german ? ["Neue Beobachtung", "Beobachtung bearbeiten", "Beobachtung anlegen", "Beobachtung speichern",
                              "Beobachtung löschen"]
                           : ["New watch", "Edit watch", "Create watch", "Save watch", "Delete watch"]))
        #expect(watch.startsPaused == (german ? "Die Beobachtung beginnt pausiert." : "The watch starts paused."))
        #expect(watch.editButton == (german ? "Bearbeiten" : "Edit"))
        #expect(HuntWords(.flat, language: language).editButton == (german ? "Suche bearbeiten" : "Edit search"))
        // The other kinds keep their words.
        let search = HuntWords(.item, language: language)
        #expect(search.status(active: true) == (german ? "Suche läuft" : "Hunting"))
        #expect(search.start == (german ? "Suche starten" : "Start hunting"))
        #expect(HuntWords(nil, language: language).delete == (german ? "Suche löschen" : "Delete search"))
        // A watch's third figure is Saved (its changes are never applied for).
        let figures = HuntPageActions.figures(.watch, counts: .init(new: 1, today: 2, saved: 3, applied: 4), language: language)
        #expect(figures.map(\.label) == (german ? ["Neu", "Heute", "Gespeichert"] : ["New", "Today", "Saved"]))
        #expect(figures.map(\.value) == [1, 2, 3] && figures.map(\.filter) == [.new, .all, .saved])
        #expect(HuntPageActions.figures(.flat, counts: .init(new: 1, today: 2, saved: 3, applied: 4)).map(\.value) == [1, 2, 4])
    }

    // MARK: a found change

    @Test(arguments: [AppLanguage.english, .german])
    func aFoundChangesLines(_ language: AppLanguage) throws {
        let german = language == .german
        let items = try sample(MatchPage.self, "watch-matches").items
        let change = items[0]
        #expect(change.watchTitle == "KALLAX now 44,99\u{a0}€ instead of 49,99\u{a0}€")
        #expect(change.watchNowLine(language: language) == (german ? "Jetzt: " : "Now: ") + "KALLAX 44,99\u{a0}€")
        #expect(change.watchSourceLine(now: Clock.now, calendar: Clock.berlin, language: language)
                == (german ? "www.ikea.com · vor 1 Std." : "www.ikea.com · 1 h ago"))
        let atStart = items[1]
        #expect(atStart.watchSourceLine(now: Clock.now, calendar: Clock.berlin, language: language)
                == "www.studierendenwerk-muenchen-oberbayern.de · "
                    + (german ? "Schon so beim Start der Beobachtung" : "Already true when the watch started"))
        // Without a summary the page's title; without a now line none.
        var bare = change
        bare = Match(id: bare.id, huntID: bare.huntID, state: .new, found: bare.found, listing: bare.listing, reason: " ",
                     warnings: [])
        #expect(bare.watchTitle == "KALLAX Regal, weiß, 77x147 cm - IKEA Deutschland")
        #expect(try sample(Match.self, "match").watchNowLine(language: language) == nil)
        #expect(WatchText.keepingAmounts("from € 45 to 45 EUR, $ 3 and 2 cats") == "from €\u{a0}45 to 45\u{a0}EUR, $\u{a0}3 and 2 cats")
    }

    // MARK: the push

    @Test func theWatchCategory() throws {
        let categories = MatchNotification.categories
        #expect(categories.count == 4)
        let watch = try #require(categories.first { $0.identifier == "ARESTEMIS_WATCH" })
        #expect(MatchNotification.watchCategory == "ARESTEMIS_WATCH")
        #expect(watch.actions.map(\.title) == ["Open page"])
        #expect(watch.actions.map(\.identifier) == [MatchNotification.openListingAction])
        #expect(watch.actions.allSatisfy { $0.options.contains(.foreground) })
        // Its tap opens the match; its action the match and then the watched page, as the others'.
        let url = URL(string: "arestemis://match/35")
        #expect(MatchNotification.link(url: url, action: UNNotificationDefaultActionIdentifier) == ArestemisLink(match: 35))
        #expect(MatchNotification.link(url: url, action: MatchNotification.openListingAction)
                == ArestemisLink(match: 35, then: .openListing))
    }

    // MARK: the store, the samples and the server's refusals

    private func sampleStore(_ options: SampleBackend.Options = .init()) async throws -> ArestemisStore {
        let session = EmpireSession(app: .arestemis, storage: MemoryTokens(), restoreOnLaunch: false)
        let store = ArestemisStore(session: session, backend: try SampleBackend(options: options), sample: true,
                                   placeDelay: .zero)
        await store.reloadOverview()
        return store
    }

    @Test func theSampleHasAWatchInEachState() async throws {
        let store = try await sampleStore()
        let watches = store.hunts.filter { $0.hunt.kind == .watch }
        #expect(watches.map { $0.page?.read } == [.ok, .blocked, .ok])
        #expect(watches.allSatisfy { $0.sources.isEmpty })
        // "page" is never a portal.
        #expect(store.overview?.sources.contains { $0.source == .page } == false)
        await store.loadKinds()
        #expect(SearchKind.choices(offered: store.kinds) == [.flat, .item, .price, .watch])
        for read in ["waiting", "unreadable", "failing", "ok", "somethingnew"] {
            let shown = try await sampleStore(.init(watchRead: read))
            #expect(shown.card(7)?.page?.read == PageState.Read(rawValue: read))
        }
    }

    @Test func aChangeIsAWatchsMatch() async throws {
        let store = try await sampleStore()
        await store.loadLatest(hunt: 6)
        let change = try #require(store.latest(hunt: 6)?.first)
        #expect(change.id == 35 && store.kind(of: change) == .watch && !store.isThing(change))
        // Known by its hunt too, before its page arrives.
        let early = Match(id: 99, huntID: 8, state: .new, found: change.found,
                          listing: try sample(Match.self, "match").listing, reason: "", warnings: [])
        #expect(store.kind(of: early) == .watch)
        // No application for it.
        await store.loadSettings()
        await store.loadApplication(for: 35)
        #expect(store.application(35).application == nil && store.application(35).error == "Application texts are for flats.")
        // Saved and dismissed as for things.
        await store.setState(.saved, for: 35)
        #expect(store.match(35)?.state == .saved && store.card(6)?.counts.saved == 1)
    }

    @Test func aNewWatchIsReadFirst() async throws {
        let store = try await sampleStore()
        let search = WatchSearch(url: "https://shop.example/shelf", change: "under 45 €", every: 30)
        let created = try #require(await store.saveHunt(id: nil, kind: .watch, name: nil, search: .watch(search)))
        let card = try #require(store.card(created.id))
        #expect(card.hunt.kind == .watch && !card.hunt.active && card.hunt.search.watch == search)
        #expect(card.page?.read == .waiting && card.page?.host == "shop.example")
        #expect(WatchCardText(card.page, language: en).note == "Reading the page…")
        #expect(HuntText(card.hunt, page: card.page, language: en).title == "shop.example")
        #expect(store.savedDraft(WatchSearchDraft.self, huntID: created.id) == WatchSearchDraft(search, name: nil))
    }

    @Test func theSamplesRefusalsComeAtTheirField() async throws {
        let store = try await sampleStore()
        let hunted = WatchSearch(url: "https://www.kleinanzeigen.de/s-anzeige/x/1", change: "under 45 €", every: 60)
        #expect(await store.saveHunt(id: nil, kind: .watch, name: nil, search: .watch(hunted)) == nil)
        #expect(store.searchError == "Kleinanzeigen has its own hunt in Arestemis." && store.searchErrorField == "search.url")
        store.clearSearchError()
        #expect(store.searchError == nil && store.searchErrorField == nil)
        #expect(!store.hunts.contains { $0.hunt.search.watch == hunted })
    }

    @Test func theServersRefusalNamesItsField() async throws {
        let transport = FakeTransport()
        let (store, _, _) = try await makeStore(transport: transport)
        await store.reloadOverview()
        transport.answer("POST /hunts", 400, json: Data("""
            {"error": "Diese Adresse kann nicht beobachtet werden.", "field": "search.url"}
            """.utf8))
        let search = WatchSearch(url: "http://10.0.0.1/", change: "anything new", every: 60)
        #expect(await store.saveHunt(id: nil, kind: .watch, name: "Router", search: .watch(search)) == nil)
        #expect(store.searchError == "Diese Adresse kann nicht beobachtet werden." && store.searchErrorField == "search.url")
        // Called from elsewhere (Rename), the refusal is also a notice over the tabs; the form shows it at its field alone.
        #expect(store.notice?.text == "Diese Adresse kann nicht beobachtet werden.")
        store.dismissNotice()
        #expect(await store.saveHunt(id: nil, kind: .watch, name: nil, search: .watch(search),
                                     fieldsShown: ["search.url", "search.change"]) == nil)
        #expect(store.searchErrorField == "search.url" && store.notice == nil)
        let sent = try #require(try body(transport.requests("POST /hunts").first))
        #expect(sent["kind"] as? String == "watch" && sent["name"] as? String == "Router")
        let sentSearch = try #require(sent["search"] as? [String: Any])
        #expect(sentSearch["url"] as? String == "http://10.0.0.1/" && sentSearch["change"] as? String == "anything new")
        #expect(sentSearch["every"] as? Int == 60 && sentSearch.count == 3)
        // A refusal without a field stays under Save.
        transport.answer("POST /hunts", 400, json: Data(#"{"error": "Something else."}"#.utf8))
        #expect(await store.saveHunt(id: nil, kind: .watch, name: nil, search: .watch(search)) == nil)
        #expect(store.searchError == "Something else." && store.searchErrorField == nil)
        #expect(await store.saveHunt(id: nil, kind: .watch, name: nil, search: .watch(search),
                                     fieldsShown: ["search.url", "search.change"]) == nil)
        #expect(store.notice?.text == "Something else.")
        #expect(FieldRefusal(status: 409, data: Data(#"{"error": "x", "field": "name"}"#.utf8)) == nil)
        #expect(FieldRefusal(status: 400, data: Data(#"{"error": " ", "field": "name"}"#.utf8)) == nil)
    }

    // MARK: launch arguments

    @Test func launchArgumentsForTheWatchScreens() throws {
        let cards = try sample(Overview.self, "overview").hunts
        func apply(_ arguments: [String]) -> AppNavigation {
            let navigation = AppNavigation()
            LaunchOptions(arguments: ["-sampleData"] + arguments).apply(to: navigation, hunts: cards, firstMatch: nil)
            return navigation
        }
        #expect(apply(["-openWatchForm"]).huntPath == [.form(.watch, hunt: 6)])
        #expect(apply(["-newWatchForm"]).huntPath == [.form(.watch, hunt: nil)])
        #expect(LaunchOptions.route(.firstWatch, hunts: []) == .form(.watch, hunt: nil))
        let options = LaunchOptions(arguments: ["-sampleData", "-scrollToHunt", "6", "-sampleWatchRead", "failing"])
        #expect(options.scrollToHunt == 6 && options.watchRead == "failing")
    }
}
