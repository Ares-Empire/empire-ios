import Foundation
import Testing
import UserNotifications
@testable import Arestemis

/// Brief 137: the Preismonitor in the app. The contract's types (`PriceSearch`, `PriceState` with its reader,
/// `PriceChange`, `PricePreview`, `Prices`) read from the server's own samples and leniently; the preview's pacing and
/// states; the rule of the two switches (at least one) in the form and on the monitor's page; the alarm's limit a little
/// under the price found; the card's lines per state; the chart's points, steps and stretches; an alarm's words in both
/// languages; the push category; the watch form's examples; the store's requests and the samples.
@MainActor
struct PriceMonitorTests {
    private let en = AppLanguage.english
    private let de = AppLanguage.german
    private final class Token {}

    /// The Arestemis server's own sample answers (`ArestemisTests/ServerSamples`).
    private func server(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: Token.self).url(forResource: "server-\(name)", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func spaces(_ text: String?) -> String? { text?.replacingOccurrences(of: "\u{a0}", with: " ") }

    // MARK: decoding

    @Test func theServersMonitorsDecode() throws {
        let overview = try JSONDecoder().decode(Overview.self, from: server("overview"))
        let monitors = overview.hunts.filter { $0.hunt.kind == .price }
        #expect(monitors.map(\.id) == [8, 9])
        let both = try #require(monitors.first)
        #expect(both.hunt.search.price == PriceSearch(url: "https://shop.example/shelf/", history: true,
                                                      alarm: .init(below: 450, backInStock: true), every: 60))
        #expect(both.sources.isEmpty && both.page == nil)
        let state = try #require(both.price)
        #expect(state.product == "Nintendo Switch 2" && state.host == "shop.example" && state.price == 449)
        #expect(state.currency == "EUR" && state.availability == .inStock && state.source == "shop" && state.read == .ok)
        #expect(state.low30d == 449 && state.high30d == 483.99 && state.reader == .plain)
        // History only: no alarm; read with a browser through an exit, its note says so.
        let history = monitors[1]
        #expect(history.hunt.search.price?.alarm == nil && history.hunt.search.price?.history == true)
        #expect(history.price?.reader == .browserExit && history.price?.note?.contains("exit") == true)
        // The other kinds have no product; a watch's page has its reader (brief 136).
        #expect(overview.hunts.filter { $0.hunt.kind != .price }.allSatisfy { $0.price == nil })
        #expect(overview.hunts.first { $0.id == 41 }?.page?.reader == .browser)
        #expect(try JSONEncoder().encode(HuntKind.price) == Data(#""price""#.utf8))
        // The history, the alarm and the kind in /kinds.
        let prices = try JSONDecoder().decode(Prices.self, from: server("prices"))
        #expect(prices.points.map(\.price) == [483.99, 449] && prices.low == 449 && prices.high == 483.99)
        #expect(prices.points.allSatisfy { $0.currency == "EUR" && $0.availability == .inStock })
        let page = try JSONDecoder().decode(MatchPage.self, from: server("matches"))
        let alarm = try #require(page.items.first { $0.listing.priceChange != nil })
        #expect(alarm.listing.priceChange == PriceChange(old: 483.99, new: 449, kind: .below))
        #expect(alarm.isPriceChange && !alarm.isPageChange && !alarm.isThing && alarm.listing.source == .page)
        let kinds = try JSONDecoder().decode([OfferedKind].self, from: server("kinds"))
        #expect(kinds.first { $0.kind == .price }?.name == "Price monitor")
    }

    @Test func statesAreReadLeniently() throws {
        func state(_ json: String) throws -> PriceState { try JSONDecoder().decode(PriceState.self, from: Data(json.utf8)) }
        let bare = try state("{}")
        #expect(bare.read == .waiting && bare.host.isEmpty && bare.reader == .plain && bare.availability == .unknown)
        #expect(bare.price == nil && bare.product == nil && bare.low30d == nil)
        // An availability, a reader or a read this build does not know.
        let newer = try state(#"{"host": "shop.example", "availability": "sold_out_forever", "reader": "carrier_pigeon", "read": "asleep"}"#)
        #expect(newer.availability == .unknown && newer.reader == .unknown("carrier_pigeon") && newer.read == .unknown("asleep"))
        #expect(try JSONDecoder().decode(PriceState.self, from: JSONEncoder().encode(newer)) == newer)
        for (raw, reader) in [("plain", PageReader.plain), ("browser", .browser), ("browser_exit", .browserExit)] {
            #expect(try state(#"{"reader": "\#(raw)"}"#).reader == reader)
            let page = try JSONDecoder().decode(PageState.self, from: Data(#"{"host": "a.example", "reader": "\#(raw)"}"#.utf8))
            #expect(page.reader == reader)
        }
        #expect(try JSONDecoder().decode(PageState.self, from: Data("{}".utf8)).reader == .plain)
        // A change and a point the same way.
        let change = try JSONDecoder().decode(PriceChange.self, from: Data(#"{"new": 12.5, "kind": "teleported", "availability": "x"}"#.utf8))
        #expect(change == PriceChange(old: nil, new: 12.5, currency: "EUR", availability: .unknown, kind: .unknown))
        let point = try JSONDecoder().decode(PricePoint.self, from: Data(#"{"at": "2026-11-02T12:00:00Z", "price": 3}"#.utf8))
        #expect(point.currency == "EUR" && point.availability == .unknown)
        let preview = try JSONDecoder().decode(PricePreview.self, from: Data("""
            {"product": "NINTENDO Switch 2", "price": 483.99, "currency": "EUR", "availability": "in_stock", "source": "ai"}
            """.utf8))
        #expect(preview.product == "NINTENDO Switch 2" && preview.price == 483.99 && preview.source == "ai")
        // A product state that cannot be read leaves the card (and the overview) as they are, without it.
        var object = try #require(try JSONSerialization.jsonObject(with: ArestemisSamples.data("overview")) as? [String: Any])
        var hunts = try #require(object["hunts"] as? [[String: Any]])
        let index = try #require(hunts.firstIndex { ($0["hunt"] as? [String: Any])?["id"] as? Int == 9 })
        hunts[index]["price"] = "not a state"
        object["hunts"] = hunts
        let overview = try JSONDecoder().decode(Overview.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(overview.hunts[index].hunt.kind == .price && overview.hunts[index].price == nil)
    }

    @Test func theSearchIsSentWhole() throws {
        let alarmOff = PriceSearch(url: "https://shop.example/p/1", history: true, alarm: nil, every: 60)
        let sent = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(alarmOff)) as? [String: Any])
        #expect(sent["alarm"] is NSNull && sent["history"] as? Bool == true && sent.count == 4)
        let backOnly = PriceSearch(url: "u", history: false, alarm: .init(below: nil, backInStock: true))
        let alarm = try #require((try JSONSerialization.jsonObject(with: JSONEncoder().encode(backOnly)) as? [String: Any])?["alarm"]
                                 as? [String: Any])
        #expect(alarm["below"] is NSNull && alarm["back_in_stock"] as? Bool == true)
        // The server's defaults for what is missing.
        let read = try JSONDecoder().decode(PriceSearch.self, from: Data(#"{"url": "u"}"#.utf8))
        #expect(read == PriceSearch(url: "u", history: false, alarm: nil, every: 60))
        #expect(!read.isComplete && backOnly.isComplete && !PriceSearch(url: "u", history: true, alarm: .init()).isComplete)
        #expect(PriceSearch(url: "shop.example/p", history: true, alarm: nil).shopURL?.absoluteString == "https://shop.example/p")
        #expect(PriceSearch(url: "javascript:alert(1)", history: true, alarm: nil).shopURL == nil)
    }

    // MARK: the preview

    @Test func whatLooksLikeALink() {
        let complete = ["https://www.mediamarkt.de/de/product/_nintendo-switch-2-2981741.html", "shop.example/p/1",
                        "https://shop.example/?id=12", "  https://shop.example/p  "]
        let incomplete = ["", "https://", "mediamarkt", "mediamarkt.de", "https://shop.example/", "shop.e/p",
                          "look at this: shop.example/p", "ftp://shop.example/p", "shop.123/p"]
        #expect(complete.allSatisfy(PricePreviewModel.looksComplete))
        #expect(!incomplete.contains(where: PricePreviewModel.looksComplete))
    }

    /// A fake server for the preview: records when each link was asked, and answers as told.
    private final class PreviewServer {
        var asked: [(link: String, at: ContinuousClock.Instant)] = []
        var answers: [String: Result<PricePreview, Error>] = [:]
        var clock: TestClock?
        var gate: RequestGate?

        func fetch(_ link: String) async throws -> PricePreview {
            asked.append((link, clock?.now ?? ContinuousClock.now))
            if let gate { self.gate = nil; await gate.pause() }
            return try (answers[link] ?? .success(PricePreview(product: "Product \(link.suffix(1))", price: 100,
                                                               currency: "EUR", availability: .inStock))).get()
        }
    }

    private func model(_ server: PreviewServer, spacing: Duration = .milliseconds(300)) -> PricePreviewModel {
        PricePreviewModel(pause: .milliseconds(20), spacing: spacing) { try await server.fetch($0) }
    }

    @Test func thePreviewWaitsForTypingAndReadsTheNewestLinkOnly() async {
        let server = PreviewServer()
        let preview = model(server)
        // Typed letter by letter: only what looks like a link, and only once typing pauses.
        for text in ["s", "shop.", "shop.example/", "shop.example/p/", "shop.example/p/1"] { preview.update(text) }
        #expect(preview.phase == .reading)
        await preview.settle()
        #expect(server.asked.map(\.link) == ["shop.example/p/1"])
        #expect(preview.preview?.product == "Product 1" && preview.link == "shop.example/p/1")
        #expect(spaces(preview.line(language: en)) == "Found: Product 1 · €100.00 · in stock")
        #expect(spaces(preview.line(language: de)) == "Gefunden: Product 1 · 100,00 € · lieferbar")
        // The same link again (a space typed at its end) is not asked again.
        preview.update("shop.example/p/1 ")
        await preview.settle()
        #expect(server.asked.count == 1 && preview.preview != nil)
        // A link that is not complete any more clears the line.
        preview.update("shop.example")
        #expect(preview.phase == .idle && preview.line() == nil)
    }

    @Test func neverTwoPreviewsWithinTheSpacing() async throws {
        let server = PreviewServer()
        let clock = TestClock()
        server.clock = clock
        let preview = PricePreviewModel(pause: .zero, spacing: .milliseconds(300),
                                        now: { clock.now }, sleep: clock.sleep) { try await server.fetch($0) }
        preview.update("shop.example/p/1")
        await preview.settle()
        // A second link right after: it waits its turn; a third typed meanwhile replaces it.
        preview.update("shop.example/p/2")
        await clock.sleeping(for: .milliseconds(300))
        preview.update("shop.example/p/3")
        await preview.typingSettled()
        clock.advance(by: .milliseconds(300))
        await preview.settle()
        try #require(server.asked.map(\.link) == ["shop.example/p/1", "shop.example/p/3"])
        let gap = server.asked[0].at.duration(to: server.asked[1].at)
        #expect(gap >= .milliseconds(300))
        #expect(preview.preview?.product == "Product 3")
    }

    @Test func oneAtATimeAndAnOldAnswerIsDropped() async throws {
        let server = PreviewServer()
        let clock = TestClock()
        let gate = RequestGate()
        server.clock = clock
        server.gate = gate
        let preview = model(server, spacing: .zero)
        preview.update("shop.example/p/1")
        // Asked, not answered yet.
        await gate.waitUntilPaused()
        preview.update("shop.example/p/2")
        await preview.typingSettled()
        #expect(server.asked.count == 1, "the old request is still held")
        clock.advance(by: .milliseconds(150))
        gate.resume()
        await preview.settle()
        // The second waited for the first; the first's answer was dropped, as its link was no longer in the field.
        try #require(server.asked.map(\.link) == ["shop.example/p/1", "shop.example/p/2"])
        let gap = server.asked[0].at.duration(to: server.asked[1].at)
        #expect(gap >= .milliseconds(150))
        #expect(preview.preview?.product == "Product 2")
    }

    @Test func refusalsAndFailures() async {
        let server = PreviewServer()
        let refused = "This page shows no single product with a price."
        server.answers["shop.example/list"] = .failure(FieldRefusal(field: "url", message: refused))
        server.answers["shop.example/down"] = .failure(HTTPError.server(503, "The AI is not answering."))
        let preview = model(server, spacing: .zero)
        preview.update("shop.example/list")
        await preview.settle()
        // The refusal in the server's words, as a problem under the link; no quiet line then.
        #expect(preview.phase == .refused(refused) && preview.refusal == refused && preview.line() == nil)
        preview.update("shop.example/down")
        await preview.settle()
        #expect(preview.phase == .failed("The AI is not answering.") && preview.line() == "The AI is not answering.")
        // Another device asked just now (429): the link waits its turn again, quietly, then is read.
        var first = true
        let busy = PricePreviewModel(pause: .milliseconds(20), spacing: .milliseconds(100)) { link in
            if first {
                first = false
                throw HTTPError.server(429, "Wait 5 seconds before another preview.")
            }
            return PricePreview(product: "Later", price: 5, currency: "EUR", availability: .preorder)
        }
        busy.update("shop.example/p/9")
        await busy.settle()
        #expect(busy.preview?.product == "Later")
        #expect(spaces(busy.line(language: en)) == "Found: Later · €5.00 · preorder")
    }

    // MARK: the two switches

    @Test(arguments: [AppLanguage.english, .german])
    func theFormNeedsOneOfTheTwo(_ language: AppLanguage) {
        let german = language == .german
        var draft = PriceSearchDraft()
        // A new form opens on Everywhere (brief 157); One shop is brief 137's form, unchanged.
        #expect(draft.mode == .everywhere)
        draft.mode = .page
        // A new form: the history on, the alarm off; the link missing says so under Save only.
        #expect(draft.history && !draft.alarm && draft.problems == [.url])
        #expect(draft.hint(language: language) == (german ? "Füg den Link zum Produkt ein." : "Paste the product's link."))
        #expect(draft.switchesLine(language: language) == nil && draft.urlLine(language: language) == nil)
        draft.url = "  https://shop.example/p/1 "
        #expect(draft.search() == PriceSearch(url: "https://shop.example/p/1", history: true, alarm: nil, every: 60))
        // Both off: nothing to save, one quiet line under the switches.
        draft.history = false
        #expect(draft.problems == [.neither] && draft.search() == nil && draft.hint(language: language) == nil)
        #expect(draft.switchesLine(language: language) == (german ? "Mindestens eins von beiden." : "At least one of the two."))
        // The alarm on without a condition: the server's words.
        draft.alarm = true
        #expect(draft.problems == [.alarmCondition] && draft.search() == nil)
        #expect(draft.switchesLine(language: language)
                == (german ? "Sag, wann der Alarm kommen soll." : "Say when the alarm should ring."))
        draft.below = 450
        #expect(draft.search()?.alarm == PriceSearch.Alarm(below: 450, backInStock: false) && draft.search()?.history == false)
        // Turned off, the conditions stay in the form but are not sent, and do not count as a change.
        draft.history = true
        draft.alarm = false
        #expect(draft.search()?.alarm == nil)
        var other = draft
        other.below = nil
        #expect(draft == other)
        other.alarm = true
        #expect(draft != other)
        // A link too long says so under it.
        draft.url = String(repeating: "a", count: 2001)
        #expect(draft.urlLine(language: language) == (german ? "Höchstens 2.000 Zeichen." : "At most 2,000 characters."))
        // A pasted text keeps its first link; the name is sent trimmed, or not at all.
        draft.takeAddress("Look: https://shop.example/p/2 for 49,99 €")
        #expect(draft.url == "https://shop.example/p/2")
        draft.name = "  Console  "
        #expect(draft.sentName == "Console")
        draft.name = " "
        #expect(draft.sentName == nil)
        #expect(draft.namePlaceholder(product: "NINTENDO Switch 2", language: language) == "NINTENDO Switch 2")
        #expect(draft.namePlaceholder(product: nil, language: language) == "shop.example")
        #expect(PriceSearchDraft().namePlaceholder(product: nil, language: language) == "Optional")
    }

    @Test(arguments: [AppLanguage.english, .german])
    func thePageRefusesTurningOffTheLast(_ language: AppLanguage) {
        let link = "https://shop.example/p/1"
        let search = PriceSearch(url: link, history: true, alarm: nil)
        var switches = MonitorSwitches(search)
        // The history is the only one on: turning it off is refused, nothing changes.
        let refused = switches.setHistory(false, in: search)
        #expect(refused == .refused && switches.history)
        #expect(MonitorSwitches.line(refused, language: language)
                == (language == .german ? "Mindestens eins von beiden." : "At least one of the two."))
        // The alarm on: both conditions, the price a little under the price read; saved at once.
        let alarmOn = switches.setAlarm(true, in: search, price: 483.99, currency: "EUR")
        let withAlarm = PriceSearch(url: link, history: true, alarm: .init(below: 450, backInStock: true))
        #expect(alarmOn == .save(withAlarm) && MonitorSwitches.line(alarmOn) == nil)
        // Now the history may go; then the alarm may not.
        let historyOff = switches.setHistory(false, in: withAlarm)
        #expect(historyOff == .save(PriceSearch(url: link, history: false, alarm: withAlarm.alarm)))
        let alarmOff = switches.setAlarm(false, in: withAlarm, price: nil, currency: nil)
        #expect(alarmOff == .refused && switches.alarm)
        // Every condition off: held on the page (not saved) with the server's words, until one is on again.
        _ = switches.setBelow(nil, in: withAlarm)
        let held = switches.setBackInStock(false, in: withAlarm)
        #expect(held == .hold(PriceSearch.Alarm()))
        #expect(MonitorSwitches.line(held, language: language)
                == (language == .german ? "Sag, wann der Alarm kommen soll." : "Say when the alarm should ring."))
        let limit = switches.setBelow(399, in: withAlarm)
        #expect(limit == .save(PriceSearch(url: link, history: false, alarm: .init(below: 399, backInStock: false))))
        // A limit of 0 is no limit.
        let zero = switches.setBelow(0, in: withAlarm)
        #expect(zero == .hold(PriceSearch.Alarm()))
    }

    // MARK: the alarm's limit

    @Test func theLimitIsALittleUnderThePrice() {
        let cases: [(Double?, Double?)] = [(483.99, 450), (49.99, 45), (12.99, 12), (1299, 1200), (529, 500),
                                           (100, 90), (19.5, 18), (1, nil), (0, nil), (nil, nil), (-5, nil)]
        for (price, limit) in cases { #expect(PriceLimit.suggested(under: price) == limit) }
        // Another currency is never compared with a limit in euros.
        #expect(PriceLimit.suggested(under: 483.99, currency: "USD") == nil)
        #expect(PriceLimit.suggested(under: 483.99, currency: "eur") == 450)
    }

    @Test func turningTheAlarmOnFillsItsConditions() throws {
        var draft = PriceSearchDraft()
        // With the price found: both conditions, the limit under it.
        let waits = draft.turnAlarmOn(price: 483.99)
        #expect(!waits)
        #expect(draft.alarm && draft.below == 450 && draft.backInStock)
        // Off and on again: the conditions as they were.
        draft.alarm = false
        draft.below = 420
        draft.backInStock = false
        draft.turnAlarmOn(price: 483.99)
        #expect(draft.below == 420 && !draft.backInStock)
        // Before the price is found: the limit waits for it, and fills once it comes, not over a typed one.
        var waiting = PriceSearchDraft()
        let limitWaits = waiting.turnAlarmOn(price: nil)
        #expect(limitWaits)
        #expect(waiting.below == nil && waiting.backInStock)
        let filled = waiting.prefillLimit(price: 483.99)
        #expect(filled && waiting.below == 450)
        let again = waiting.prefillLimit(price: 200)
        #expect(!again && waiting.below == 450)
        // The example (one per kind since brief 142; Everywhere since brief 157): the product in words, the alarm's
        // limit a little under the cheapest price once found.
        var below = try #require(SearchExample.everywhere.priceDraft)
        #expect(below.mode == .everywhere && below.product == "AirPods Max" && below.url.isEmpty)
        #expect(below.alarm && below.history && below.below == nil && !below.backInStock)
        #expect(below.problems == [.alarmCondition])
        below.prefillLimit(price: 529)
        #expect(below.below == 500)
        #expect(SearchExample.examples(for: .price) == [.everywhere])
        #expect(SearchExample.kallax.priceDraft == nil)
    }

    // MARK: the card

    private func state(_ read: PageState.Read, price: Double? = 449, note: String? = nil,
                       availability: Availability = .inStock) -> PriceState {
        PriceState(product: "Nintendo Switch 2", host: "shop.example", price: price, currency: "EUR",
                   availability: availability, read: read, checked: "2026-10-24T09:58:40Z", note: note)
    }

    @Test(arguments: [AppLanguage.english, .german])
    func theCardsLinesPerState(_ language: AppLanguage) {
        let german = language == .german
        func text(_ state: PriceState?, compact: Bool = true) -> PriceCardText {
            PriceCardText(state, compact: compact, now: Clock.now, calendar: Clock.berlin, language: language)
        }
        // Read well: the price and its availability, when it was checked; the note only on the page.
        let ok = text(state(.ok, note: "Read with a browser, every 30 minutes."))
        #expect(spaces(ok.price) == (german ? "449,00 €" : "€449.00") && ok.note == nil)
        #expect(ok.availability == (german ? "lieferbar" : "in stock"))
        #expect(ok.checked == (german ? "Geprüft vor 4 Min." : "Checked 4 min ago"))
        #expect(text(state(.ok, note: "Read with a browser, every 30 minutes."), compact: false).note
                == "Read with a browser, every 30 minutes.")
        #expect(text(state(.ok, availability: .outOfStock)).availability == (german ? "nicht lieferbar" : "out of stock"))
        #expect(text(state(.ok, availability: .unknown)).availability == nil)
        // Not read yet: one quiet line, no price.
        let waiting = text(nil)
        #expect(waiting.price == nil && waiting.note == (german ? "Seite wird gelesen…" : "Reading the page…")
                && waiting.checked == nil)
        // Not readable, failing, blocked: the server's note (or the app's words), never the last price.
        #expect(text(state(.unreadable)).note == (german ? "Diese Seite zeigt kein einzelnes Produkt mit Preis."
                                                  : "This page shows no single product with a price."))
        #expect(text(state(.failing, note: "No answer since yesterday.")).note == "No answer since yesterday.")
        #expect(text(state(.failing)).price == nil)
        let blocked = text(state(.blocked, note: "Cloudflare refuses the server."))
        #expect(blocked.note == "Cloudflare refuses the server. "
                + (german ? "Speichern versucht es noch einmal." : "Saving it again tries again."))
        #expect(text(state(.unknown("new"), note: "Read in a new way.")).note == "Read in a new way.")
        // A blocked monitor reads Stopped, as a watch.
        let search = PriceSearch(url: "u", history: true, alarm: nil)
        var card = HuntCard(hunt: Hunt(id: 9, kind: .price, active: true, search: .price(search), created: "", updated: "",
                                       activated: nil),
                            counts: .init(new: 0, today: 0, saved: 0, applied: 0), sources: [], slowed: false,
                            price: state(.blocked))
        #expect(card.isStopped)
        card.price = state(.ok)
        #expect(!card.isStopped)
    }

    @Test(arguments: [AppLanguage.english, .german])
    func theQuietLineSaysWhatItDoes(_ language: AppLanguage) throws {
        let german = language == .german
        // The page monitors (an everywhere monitor's lines: `PriceEverywhereTests`).
        let cards = try sample(Overview.self, "overview").hunts.filter { $0.hunt.search.price?.mode == .page }
        #expect(cards.map(\.id) == [9, 10, 11])
        let lines = cards.map { HuntText($0, language: language) }
        #expect(lines.map(\.title) == ["Nintendo Switch 2", "Headphones", "LEGO Titanic"])
        #expect(lines.map { spaces($0.details) } == (german ? [
            "www.mediamarkt.de · Alarm unter 450 € oder wieder lieferbar",
            "Sony WH-1000XM6 · www.otto.de · Nur Verlauf",
            "www.lego.com · Alarm, wenn wieder lieferbar",
        ] : [
            "www.mediamarkt.de · Alarm under €450 or back in stock",
            "Sony WH-1000XM6 · www.otto.de · History only",
            "www.lego.com · Alarm when back in stock",
        ]))
        let below = PriceSearch(url: "u", history: true, alarm: .init(below: 449.5, backInStock: false))
        #expect(spaces(PriceWords.mode(below, language: language)) == (german ? "Alarm unter 449,50 €" : "Alarm under €449.50"))
        // Before the first read: the host of the link.
        var hunt = cards[0].hunt
        #expect(HuntText(hunt, price: nil, language: language).title == "www.mediamarkt.de")
        #expect(HuntText.automaticTitle(hunt.search, price: cards[0].price) == "Nintendo Switch 2")
        hunt.name = "Console"
        #expect(HuntText(hunt, price: cards[0].price, language: language).details?.hasPrefix("Nintendo Switch 2 · ") == true)
        // Listings → Searches: favorites only, never applied.
        #expect(SearchRow(cards[0], language: language).line == (german ? "1 Favorit" : "1 favorite"))
    }

    @Test(arguments: [AppLanguage.english, .german])
    func aMonitorsWordsAndFigures(_ language: AppLanguage) {
        let german = language == .german
        let words = HuntWords(.price, language: language)
        #expect(words.status(active: true) == (german ? "Beobachtung läuft" : "Watching"))
        #expect(words.status(active: true, stopped: true) == (german ? "Angehalten" : "Stopped"))
        #expect(words.start == (german ? "Beobachtung starten" : "Start watching"))
        #expect(words.newTitle == (german ? "Neuer Preismonitor" : "New price monitor"))
        #expect(words.editTitle == (german ? "Preismonitor bearbeiten" : "Edit price monitor"))
        #expect(words.create == (german ? "Preismonitor anlegen" : "Create price monitor"))
        #expect(words.startsPaused == (german ? "Der Preismonitor beginnt pausiert." : "The price monitor starts paused."))
        #expect(words.deleteQuestion == (german ? "Preismonitor löschen?" : "Delete the price monitor?"))
        #expect(HuntPageActions.figureLabels(.price, language: language)
                == (german ? ["Neu", "Heute", "Favoriten"] : ["New", "Today", "Favorites"]))
        #expect(MatchFilter.choices(for: .price) == [.new, .saved, .all])
        #expect(!SearchKind.price.appliesOrAsks && SearchKind.price.symbol == "chart.line.downtrend.xyaxis")
        #expect(SearchKind.price.choiceTitle(language: language) == (german ? "Preismonitor" : "Price monitor"))
        #expect(SearchKind.price.pitch(language: language) == (german
            ? "Ein Produkt: ein Push, wenn es günstiger wird."
            : "One product: a push when it gets cheaper."))
        #expect(SiteChoices.fallback(.price).isEmpty)
    }

    // MARK: the chart

    private func point(_ at: String, _ price: Double, _ availability: Availability = .inStock,
                       currency: String = "EUR") -> PricePoint {
        PricePoint(at: at, price: price, currency: currency, availability: availability)
    }

    @Test func pointsAsStepsInStretches() {
        let prices = Prices(points: [
            point("2026-10-01T10:00:00Z", 499), point("2026-10-02T10:00:00Z", 499),
            point("2026-10-03T10:00:00Z", 489, .outOfStock), point("2026-10-04T10:00:00Z", 489, .outOfStock),
            point("2026-10-05T10:00:00Z", 479), point("2026-10-06T10:00:00Z", 449, .preorder),
        ], low: 449, high: 499)
        let chart = PriceChart(prices, limit: 450, days: 30)
        #expect(chart.points.map(\.price) == [499, 499, 489, 489, 479, 449])
        // Each stretch runs to the next one's first point, so the steps join: in stock, out of stock, in stock again
        // (a preorder is not out of stock).
        #expect(chart.stretches.map(\.outOfStock) == [false, true, false])
        #expect(chart.stretches.map { $0.points.map(\.id) } == [[0, 1, 2], [2, 3, 4], [4, 5]])
        #expect(chart.hasOutOfStock && chart.newest?.price == 449 && chart.limit == 450)
        // The plot spans the prices and the limit, with room; and the days the points cover.
        #expect(chart.range.lowerBound < 449 && chart.range.upperBound > 499)
        #expect(chart.span.lowerBound == Timestamp.parse("2026-10-01T10:00:00Z")
                && chart.span.upperBound == Timestamp.parse("2026-10-06T10:00:00Z"))
        // A limit far under the prices widens the range to show it.
        #expect(PriceChart(prices, limit: 300).range.lowerBound < 300)
        // Without points: nothing to draw.
        let empty = PriceChart(Prices(points: [], low: nil, high: nil), limit: 450)
        #expect(empty.isEmpty && empty.stretches.isEmpty && empty.newest == nil && empty.extremes() == nil)
        // One point: one stretch of one point.
        #expect(PriceChart(Prices(points: [point("2026-10-01T10:00:00Z", 10)], low: 10, high: 10)).stretches.count == 1)
    }

    @Test func anotherCurrencyAndTheLimit() {
        // Points in another currency than the newest's are left out; a limit in euros is not drawn over dollars.
        let mixed = Prices(points: [point("2026-10-01T10:00:00Z", 40, currency: "EUR"),
                                    point("2026-10-02T10:00:00Z", 45, currency: "USD"),
                                    point("2026-10-03T10:00:00Z", 44, currency: "USD")], low: 40, high: 40)
        let chart = PriceChart(mixed, limit: 42)
        #expect(chart.currency == "USD" && chart.points.map(\.price) == [45, 44] && chart.limit == nil)
        #expect(PriceChart.axisPrice(45, currency: "EUR", language: .english) == "€45")
        #expect(PriceChart(Prices(points: [point("2026-10-01T10:00:00Z", 40)], low: 40, high: 40), limit: 0).limit == nil)
    }

    @Test(arguments: [AppLanguage.english, .german])
    func theChartsWords(_ language: AppLanguage) throws {
        let german = language == .german
        let chart = PriceChart(Prices(points: [point("2026-10-01T10:00:00Z", 483.99)], low: 449, high: 483.99))
        #expect(spaces(chart.extremes(language: language))
                == (german ? "Tiefstpreis 449,00 € · Höchstpreis 483,99 €" : "Lowest €449.00 · Highest €483.99"))
        let point = try #require(chart.points.first)
        #expect(spaces(chart.spoken(point, language: language)) == (german ? "483,99 €, lieferbar" : "€483.99, in stock"))
        #expect(PriceWords.window(90, language: language) == (german ? "90 Tage" : "90 days"))
        let day = try #require(Timestamp.parse("2026-10-05T10:00:00Z"))
        #expect(PriceChart.dayLabel(day, days: 30, calendar: Clock.berlin, language: language) == (german ? "5. Okt." : "5 Oct"))
        #expect(PriceChart.dayLabel(day, days: 365, calendar: Clock.berlin, language: language) == (german ? "Okt" : "Oct"))
    }

    // MARK: an alarm

    @Test(arguments: [AppLanguage.english, .german])
    func anAlarmsWords(_ language: AppLanguage) throws {
        let german = language == .german
        let page = try sample(MatchPage.self, "price-matches")
        let below = try #require(page.items.first { $0.id == 39 })
        #expect(spaces(below.priceTitle(language: language))
                == (german ? "Nintendo Switch 2: 449,00 € (vorher 483,99 €)" : "Nintendo Switch 2: €449.00 (was €483.99)"))
        #expect(spaces(PriceWords.alarmLabel(try #require(below.listing.priceChange), language: language))
                == (german ? "vorher 483,99 €" : "was €483.99"))
        let back = try #require(page.items.first { $0.id == 37 })
        #expect(back.priceTitle(language: language)
                == (german ? "Nintendo Switch 2 ist wieder lieferbar" : "Nintendo Switch 2 is back in stock"))
        #expect(PriceWords.alarmLabel(try #require(back.listing.priceChange), language: language)
                == (german ? "wieder lieferbar" : "back in stock"))
        // Without the old price: the new one alone; another currency in its own sign.
        let first = PriceChange(old: nil, new: 12.99, currency: "USD", kind: .lower)
        #expect(spaces(PriceWords.alarm(product: " Game ", change: first, language: language))
                == (german ? "Game: 12,99 $" : "Game: US$12.99"))
        #expect(back.priceSourceLine(now: Timestamp.parse("2026-10-09T10:01:30Z")!, calendar: Clock.berlin, language: language)
                == "www.mediamarkt.de · " + (german ? "vor 1 Min." : "1 min ago"))
        // An alarm without a change (an older server's) is its sentence.
        let bare = Match(id: 1, huntID: 9, state: .new, found: "", listing: back.listing, reason: "Cheaper now", warnings: [])
        #expect(Match(id: 1, huntID: 9, state: .new, found: "", listing: try listing(without: back), reason: "Cheaper now",
                      warnings: []).priceTitle() == "Cheaper now")
        #expect(bare.isPriceChange)
    }

    private func listing(without match: Match) throws -> Listing {
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(match.listing)) as? [String: Any])
        object["price_change"] = NSNull()
        return try JSONDecoder().decode(Listing.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test func anAlarmIsAPriceMonitorsAndNeverApplied() async throws {
        let store = try await sampleStore()
        let alarm = try #require(await store.loadMatch(39))
        #expect(store.kind(of: alarm) == .price && !store.isThing(alarm))
        // A watch's change stays a watch's.
        let change = try #require(await store.loadMatch(35))
        #expect(store.kind(of: change) == .watch)
        await store.loadApplication(for: 39)
        #expect(store.application(39).error == "Application texts are for flats.")
    }

    // MARK: the push

    @Test func thePriceCategory() throws {
        let categories = MatchNotification.categories
        let price = try #require(categories.first { $0.identifier == "ARESTEMIS_PRICE" })
        #expect(MatchNotification.priceCategory == "ARESTEMIS_PRICE")
        #expect(price.actions.map(\.title) == ["Open in shop"])
        #expect(price.actions.map(\.identifier) == [MatchNotification.openListingAction])
        #expect(price.actions.allSatisfy { $0.options.contains(.foreground) })
        let url = URL(string: "arestemis://match/39")
        #expect(MatchNotification.link(url: url, action: UNNotificationDefaultActionIdentifier) == ArestemisLink(match: 39))
        #expect(MatchNotification.link(url: url, action: MatchNotification.openListingAction)
                == ArestemisLink(match: 39, then: .openListing))
    }

    // MARK: the watch form's examples

    @Test(arguments: [AppLanguage.english, .german])
    func theWatchFormsExamples(_ language: AppLanguage) {
        let german = language == .german
        #expect(WatchChange.allCases.map { $0.title(language: language) } == (german
            ? ["eine neue Version erscheint", "ein neuer Eintrag dazukommt", "sich ein Datum ändert", "eigene Beschreibung"]
            : ["a new version comes out", "a new entry appears", "a date changes", "own description"]))
        // A chip fills the sentence (replacing what is there), for the user to sharpen.
        let sentence = WatchChange.dateChanges.apply(to: "anything", language: language)
        #expect(sentence == (german ? "sich ein Datum ändert" : "a date changes"))
        #expect(WatchChange.example(in: " \(sentence) ", language: language) == .dateChanges)
        // "Own description" empties an example's sentence, and keeps the user's own words.
        #expect(WatchChange.own.apply(to: sentence, language: language).isEmpty)
        #expect(WatchChange.own.apply(to: "3.4.0 is out", language: language) == "3.4.0 is out")
        #expect(WatchChange.example(in: "3.4.0 is out", language: language) == nil && WatchChange.own.sentence() == nil)
        // New search's example opens the form with its chip's sentence.
        #expect(WatchChange.example(in: SearchExample.newVersion.watchDraft(language: language)?.change ?? "",
                                    language: language) == .newVersion)
    }

    // MARK: the store and the server

    private func sampleStore(_ options: SampleBackend.Options = .init()) async throws -> ArestemisStore {
        let session = EmpireSession(app: .arestemis, storage: MemoryTokens(), restoreOnLaunch: false)
        let store = ArestemisStore(session: session, backend: try SampleBackend(options: options), sample: true,
                                   placeDelay: .zero)
        await store.reloadOverview()
        return store
    }

    @Test func thePreviewAndTheHistoryAreAsked() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        transport.answer("POST /price/preview", json: Data("""
            {"product": "NINTENDO Switch 2", "price": 483.99, "currency": "EUR", "availability": "in_stock", "source": "shop"}
            """.utf8))
        let found = try await store.pricePreview(url: "https://shop.example/p/1")
        #expect(found.product == "NINTENDO Switch 2")
        let sent = try #require(try body(transport.requests("POST /price/preview").first))
        #expect(sent as? [String: String] == ["url": "https://shop.example/p/1"])
        // The server's refusal at its field, in its words.
        transport.answer("POST /price/preview", 400, json: Data("""
            {"error": "This page shows no single product with a price.", "field": "url"}
            """.utf8))
        await #expect(throws: FieldRefusal(field: "url", message: "This page shows no single product with a price.")) {
            try await store.pricePreview(url: "https://shop.example/")
        }
        // The history, once per read of the card; again when asked to.
        transport.answer("GET /hunts/9/prices", json: try server("prices"))
        await store.loadPrices(hunt: 9, days: 90)
        await store.loadPrices(hunt: 9, days: 90)
        let asked = transport.requests("GET /hunts/9/prices")
        #expect(asked.count == 1 && asked.first?.url?.query() == "days=90")
        #expect(store.prices(hunt: 9, days: 90).prices?.points.count == 2 && store.prices(hunt: 9, days: 30).prices == nil)
        await store.loadPrices(hunt: 9, days: 90, force: true)
        #expect(transport.requests("GET /hunts/9/prices").count == 2)
        // A newer read on the card asks again.
        var object = try #require(try JSONSerialization.jsonObject(with: ArestemisSamples.data("overview")) as? [String: Any])
        var hunts = try #require(object["hunts"] as? [[String: Any]])
        let index = try #require(hunts.firstIndex { ($0["hunt"] as? [String: Any])?["id"] as? Int == 9 })
        var price = try #require(hunts[index]["price"] as? [String: Any])
        price["checked"] = "2026-10-24T11:00:00Z"
        hunts[index]["price"] = price
        object["hunts"] = hunts
        transport.answer("GET /overview", json: try JSONSerialization.data(withJSONObject: object))
        await store.reloadOverview()
        await store.loadPrices(hunt: 9, days: 90)
        #expect(transport.requests("GET /hunts/9/prices").count == 3)
        // A monitor without its history asks nothing; the server's 404 reads as no points.
        await store.loadPrices(hunt: 11, days: 30)
        #expect(transport.requests("GET /hunts/11/prices").isEmpty)
        transport.answer("GET /hunts/10/prices", 404, json: Data(#"{"error": "Not found"}"#.utf8))
        await store.loadPrices(hunt: 10, days: 30)
        #expect(store.prices(hunt: 10, days: 30).prices?.points.isEmpty == true && store.prices(hunt: 10, days: 30).error == nil)
    }

    @Test func theSwitchesAreSavedFromThePage() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        var hunt = try #require(store.card(10)?.hunt)
        let original = try #require(hunt.search.price)
        #expect(hunt.name == "Headphones")
        var first = original
        first.alarm = .init(below: 300, backInStock: true)
        var newest = first
        newest.history = false
        hunt.search = .price(newest)
        try transport.answer("PUT /hunts/10", encoding: hunt)
        // The server's overview afterwards has the newest switches.
        var object = try #require(try JSONSerialization.jsonObject(with: ArestemisSamples.data("overview")) as? [String: Any])
        var hunts = try #require(object["hunts"] as? [[String: Any]])
        let index = try #require(hunts.firstIndex { ($0["hunt"] as? [String: Any])?["id"] as? Int == 10 })
        var saved = try #require(hunts[index]["hunt"] as? [String: Any])
        saved["search"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(newest))
        hunts[index]["hunt"] = saved
        object["hunts"] = hunts
        transport.answer("GET /overview", json: try JSONSerialization.data(withJSONObject: object))
        let gate = RequestGate()
        transport.gates["PUT /hunts/10"] = gate
        let saving = Task { await store.saveMonitor(id: 10, search: first) }
        await gate.waitUntilPaused()
        // Shown at once; changes made meanwhile wait, and only the newest is sent once the first has answered.
        #expect(store.card(10)?.hunt.search.price == first && store.savingMonitors.contains(10))
        var between = first
        between.every = 720
        await store.saveMonitor(id: 10, search: between)
        await store.saveMonitor(id: 10, search: newest)
        #expect(store.card(10)?.hunt.search.price == newest)
        gate.resume()
        await saving.value
        let puts = transport.requests("PUT /hunts/10")
        #expect(puts.count == 2 && !store.savingMonitors.contains(10))
        // The whole search, and the name as it is (a PUT without it would clear it).
        let sent = try #require(try body(puts.last))
        #expect(sent["name"] as? String == "Headphones")
        let search = try #require(sent["search"] as? [String: Any])
        #expect(search["history"] as? Bool == false && search["every"] as? Int == 360)
        #expect((search["alarm"] as? [String: Any])?["below"] as? Double == 300)
        #expect(store.card(10)?.hunt.search.price == newest)

        // A refusal puts back what the server confirmed last, with a notice.
        transport.answer("PUT /hunts/10", 400, json: Data("""
            {"error": "Say when the alarm should ring.", "field": "search.alarm"}
            """.utf8))
        var refused = newest
        refused.alarm = .init(below: 1, backInStock: false)
        await store.saveMonitor(id: 10, search: refused)
        #expect(store.card(10)?.hunt.search.price == newest)
        #expect(store.notice?.text.contains("Say when the alarm should ring.") == true)
        // A search of another kind is never saved here.
        await store.saveMonitor(id: 1, search: original)
        #expect(transport.requests("PUT /hunts/1").isEmpty)
    }

    @Test func theSampleHasMonitors() async throws {
        let store = try await sampleStore()
        let monitors = store.hunts.filter { $0.hunt.search.price?.mode == .page }
        #expect(monitors.map(\.id) == [9, 10, 11] && monitors.allSatisfy { $0.sources.isEmpty && $0.price?.read == .ok })
        #expect(monitors.map { $0.hunt.search.price?.history } == [true, true, false])
        #expect(monitors.map { $0.hunt.search.price?.alarm == nil } == [false, true, false])
        // Its history over each window: 30 days hold fewer points than a year; the lowest and highest in euros.
        await store.loadPrices(hunt: 9, days: 30)
        await store.loadPrices(hunt: 9, days: 365)
        let month = try #require(store.prices(hunt: 9, days: 30).prices)
        let year = try #require(store.prices(hunt: 9, days: 365).prices)
        #expect(month.points.count < year.points.count && month.low == 449 && month.high == 483.99 && year.high == 529)
        #expect(PriceChart(month, limit: 450, days: 30).hasOutOfStock)
        // Its alarms: the price under the limit (new) and back in stock (saved).
        await store.loadMatches(.all, hunt: 9)
        #expect(store.matches(.all, hunt: 9).map(\.id) == [39, 37])
        // The preview's imitation and the switches' rule, as the server's.
        let found = try await store.pricePreview(url: "https://www.mediamarkt.de/de/product/_nintendo-switch-2-2981741.html")
        #expect(found.product == "NINTENDO Switch 2" && found.price == 483.99)
        await #expect(throws: FieldRefusal.self) { try await store.pricePreview(url: "https://www.kleinanzeigen.de/s-x/k0") }
        let neither = PriceSearch(url: "https://shop.example/p/1", history: false, alarm: nil)
        #expect(await store.saveHunt(id: nil, kind: .price, name: nil, search: .price(neither)) == nil)
        #expect(store.searchErrorField == "search.history")
        let made = try #require(await store.saveHunt(id: nil, kind: .price, name: nil,
                                                     search: .price(PriceSearch(url: "https://shop.example/p/1",
                                                                                history: true, alarm: nil))))
        #expect(store.card(made.id)?.price?.read == .waiting && store.card(made.id)?.price?.host == "shop.example")
        // The page's switches change the sample in memory.
        var alarmOn = try #require(store.card(10)?.hunt.search.price)
        alarmOn.alarm = .init(below: 300, backInStock: false)
        await store.saveMonitor(id: 10, search: alarmOn)
        #expect(store.card(10)?.hunt.search.price == alarmOn)
    }

    @Test func launchArgumentsForTheMonitorScreens() throws {
        let cards = try sample(Overview.self, "overview").hunts
        func apply(_ arguments: [String]) -> AppNavigation {
            let navigation = AppNavigation()
            LaunchOptions(arguments: ["-sampleData"] + arguments).apply(to: navigation, hunts: cards, firstMatch: nil)
            return navigation
        }
        #expect(apply(["-openPriceForm"]).huntPath == [.form(.price, hunt: 9)])
        #expect(apply(["-newPriceForm"]).huntPath == [.form(.price, hunt: nil)])
        #expect(apply(["-newExample", "everywhere"]).huntPath == [.newSearch, .form(.price, hunt: nil, example: .everywhere)])
        let page = apply(["-openHunt", "9", "-scrollTo", "switches"])
        #expect(page.huntPath == [.hunt(9)] && page.formScroll == "switches")
        #expect(LaunchOptions.route(.firstPrice, hunts: []) == .form(.price, hunt: nil))
        #expect(LaunchOptions(arguments: ["-sampleData", "-pricePreview", "refused"]).pricePreview == "refused")
    }
}
