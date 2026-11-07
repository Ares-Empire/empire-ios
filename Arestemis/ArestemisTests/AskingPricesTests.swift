import Foundation
import Testing
@testable import Arestemis

/// Brief 256 (the server's brief 254): a thing search's asking prices and a listing's price verdict. The decoding of the
/// server's own samples is in `ServerSamplesTests`; here a server from before them, the words in either language, that
/// nothing shows without a verdict, the route, when the store asks, and sample mode.
@MainActor
struct AskingPricesTests {
    private final class Token {}

    private func server(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: Token.self).url(forResource: "server-\(name)", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func record(_ name: String = "item-price-record", hunt: Int? = nil) throws -> ItemPriceSummary {
        let record = try JSONDecoder().decode(ItemPriceSummary.self, from: server(name))
        guard let hunt else { return record }
        return ItemPriceSummary(huntID: hunt, currency: record.currency, days: record.days, since: record.since,
                                until: record.until, overall: record.overall, sites: record.sites, note: record.note)
    }

    private func names() -> SiteNames {
        SiteNames(kinds: [OfferedKind(kind: .item, name: "Things", sources: [
            KindSource(source: .kleinanzeigen, name: "Kleinanzeigen"), KindSource(source: .ebay, name: "eBay"),
        ])])
    }

    // MARK: a server from before them

    /// No `price_verdict`: none. One that is malformed, or of a kind this build does not know, is none too, and the
    /// listing still loads.
    @Test func aMatchWithoutOrWithAnUnreadableVerdict() throws {
        let plain = try sample(Match.self, "match")
        #expect(plain.priceVerdict == nil)
        var object = try #require(try JSONSerialization.jsonObject(with: server("item-price-match")) as? [String: Any])
        for broken: Any in [["verdict": "fair", "price": 30], ["verdict": "cheap"], "cheap", NSNull()] {
            object["price_verdict"] = broken
            let match = try JSONDecoder().decode(Match.self, from: JSONSerialization.data(withJSONObject: object))
            #expect(match.id == 254 && match.priceVerdict == nil)
        }
    }

    /// A record without the optional numbers (a trend this build does not know, no weeks, no sites) still reads; one
    /// missing a language shows the other.
    @Test func aRecordReadLeniently() throws {
        let json = #"""
            {"hunt_id": 2, "since": "2026-10-08T12:00:00Z", "until": "2026-11-07T12:00:00Z",
             "overall": {"source": null, "count": 9, "trend": "sideways", "display": {"en": "9 fitting listings"}},
             "note": {"de": "Nur Angebotspreise."}}
            """#
        let record = try JSONDecoder().decode(ItemPriceSummary.self, from: Data(json.utf8))
        #expect(record.days == 30 && record.currency == "EUR" && record.sites.isEmpty)
        #expect(record.overall.trend == nil && record.overall.weeklyMedians.isEmpty && record.overall.usual == nil)
        #expect(record.overall.display.text(.german) == "9 fitting listings")
        #expect(record.note.text(.english) == "Nur Angebotspreise.")
    }

    // MARK: words

    /// The card picks the app's language from the server's two, one fact per line, numbers kept with their words; two
    /// sites with their own range; the server's note.
    @Test func theCardInEitherLanguage() throws {
        let summary = try record()
        let german = PriceRecordCard(summary, names: names(), language: .german)
        #expect(german.title == "Angebotspreise" && german.period == "Letzte 30 Tage" && german.empty == nil)
        #expect(german.lines.map(spaces) == ["16 passende Angebote", "Üblicher Angebotspreis 23,50 €–30,00 €",
                                             "Günstigstes Angebot der letzten 7 Tage: 22,00 €",
                                             "Wöchentlicher Median steigt"])
        #expect(german.lines[2].contains("7\u{a0}Tage") && german.lines[2].hasSuffix("22,00\u{a0}€"))
        #expect(german.sites.map(\.name) == ["Kleinanzeigen", "eBay"])
        #expect(german.sites.map { spaces($0.range) } == ["21,50–28,50 €", "24,00–30,50 €"])
        #expect(german.sites.map(\.count) == ["8 Angebote", "8 Angebote"])
        #expect(german.note?.hasPrefix("Angebotspreise passender Angebote") == true)

        let english = PriceRecordCard(summary, names: names(), language: .english)
        #expect(english.title == "Asking prices" && english.period == "Last 30 days")
        #expect(english.lines.map(spaces) == ["16 fitting listings", "Usually €23.50–€30.00 asked",
                                              "Cheapest in the last 7 days: €22.00", "Weekly median rising"])
        #expect(english.sites.map(\.range) == ["€21.50–28.50", "€24.00–30.50"])
        #expect(english.sites.map(\.count) == ["8 listings", "8 listings"])
        #expect(english.note?.hasSuffix("These are not sale prices.") == true)
        #expect(spaces(english.spoken)?.hasPrefix("Asking prices, Last 30 days. 16 fitting listings.") == true)
    }

    /// Few offers: the count and the cheapest only, no breakdown for one site; with two sites below 8 each, their counts;
    /// none yet: one quiet line instead.
    @Test func fewOrNoOffers() throws {
        let small = PriceRecordCard(try record("item-price-record-small"), names: names(), language: .german)
        #expect(small.lines.map(spaces) == ["2 passende Angebote", "Günstigstes Angebot der letzten 7 Tage: 32,00 €"])
        #expect(small.sites.isEmpty && small.empty == nil && small.note != nil)

        let few = try record("item-price-record-small")
        let two = ItemPriceSummary(huntID: 12, since: few.since, until: few.until, overall: few.overall, sites: [
            ItemPriceStats(source: .kleinanzeigen, count: 1, display: LocalizedText(en: "1 fitting listing",
                                                                                   de: "1 passendes Angebot")),
            few.sites[0],
        ], note: few.note)
        let counts = PriceRecordCard(two, names: names(), language: .german)
        #expect(counts.sites.map(\.range) == [nil, nil] && counts.sites.map(\.count) == ["1 Angebot", "2 Angebote"])
        #expect(PriceRecordCard(two, names: names(), language: .english).sites.map(\.count) == ["1 listing", "2 listings"])

        let none = ItemPriceSummary(huntID: 4, since: few.since, until: few.until,
                                    overall: ItemPriceStats(source: nil, count: 0, display: LocalizedText(
                                        en: "0 fitting listings", de: "0 passende Angebote")), note: few.note)
        let empty = PriceRecordCard(none, names: names(), language: .german)
        #expect(empty.lines.isEmpty && empty.sites.isEmpty && empty.note == nil)
        #expect(empty.empty == "Noch keine Preise. Sie kommen mit den ersten passenden Angeboten.")
        #expect(PriceRecordCard(none, names: names(), language: .english).empty
                == "No prices yet. They come with the first fitting listings.")
    }

    /// A site's range: whole euros when both ends are whole, else to the cent.
    @Test func siteRanges() {
        #expect(spaces(PriceRecordCard.range(395, 445, language: .german)) == "395–445 €")
        #expect(PriceRecordCard.range(395, 445, language: .english) == "€395–445")
        #expect(spaces(PriceRecordCard.range(1200, 1450.5, language: .german)) == "1.200,00–1.450,50 €")
        #expect(PriceRecordCard.range(1200, 1450.5, language: .english) == "€1,200.00–1,450.50")
    }

    @Test func numbersStayWithTheirWords() {
        #expect(PriceText.keepingNumbersTogether("der letzten 7 Tage: 22,00 €") == "der letzten 7\u{a0}Tage: 22,00\u{a0}€")
        #expect(PriceText.keepingNumbersTogether("16 fitting · €2.00 ") == "16\u{a0}fitting · €2.00 ")
        #expect(PriceText.keepingNumbersTogether("Teuer: üblich") == "Teuer: üblich")
    }

    /// The verdict's words in the app's language: the server's label, its line split after the label, its note; the
    /// tone and mark per kind.
    @Test func aVerdictInEitherLanguage() throws {
        let match = try JSONDecoder().decode(Match.self, from: server("item-price-match"))
        let german = try #require(PriceVerdictWords.shown(for: match, kind: .item, language: .german))
        #expect(german.label == "Teuer" && german.lead == "Teuer" && german.tone == .neutral && german.symbol == "arrow.up")
        #expect(spaces(german.rest) == ": üblicher Angebotspreis innerhalb deiner Suchgrenzen 23,50 €–30,00 €")
        #expect(german.note.hasPrefix("Angebotspreise passender Angebote"))
        let english = try #require(PriceVerdictWords.shown(for: match, kind: .item, language: .english))
        #expect(english.label == "Expensive"
                && spaces(english.line) == "Expensive: usually €23.50–€30.00 asked within your search limits")
        #expect(english.note.hasSuffix("These are not sale prices."))

        let unusual = try JSONDecoder().decode(Match.self, from: server("item-price-match-unusually-cheap"))
        let caution = try #require(PriceVerdictWords.shown(for: unusual, kind: .item, language: .german))
        #expect(caution.label == "Ungewöhnlich günstig – genau prüfen" && caution.tone == .caution)
        #expect(caution.symbol == "exclamationmark.circle")
        let cheap = PriceVerdictWords(PriceRecordSample.verdict(.cheap, price: 400), language: .english)
        #expect(cheap.label == "Cheap" && cheap.tone == .accent && cheap.symbol == "arrow.down")
        // A line that does not start with the label is shown whole.
        var other = PriceRecordSample.verdict(.cheap, price: 400)
        other = ItemPriceVerdict(verdict: .cheap, price: 400, comparisonCount: 9, q25: 1, q75: 2, label: other.label,
                                 display: LocalizedText(en: "Below the usual €400", de: "Unter üblichen 400 €"),
                                 note: other.note)
        let whole = PriceVerdictWords(other, language: .english)
        #expect(whole.lead == nil && whole.rest == whole.line && whole.line == "Below the usual €400")
    }

    /// No verdict, nothing: no label on the row, no line on the page. Only a thing for sale shows one.
    @Test func nothingShowsWithoutAVerdict() throws {
        let plain = try sample(Match.self, "ebay-match")
        #expect(plain.priceVerdict == nil)
        for kind in [SearchKind.item, .flat, .watch, .price] {
            #expect(PriceVerdictWords.shown(for: plain, kind: kind) == nil)
        }
        let judged = try JSONDecoder().decode(Match.self, from: server("item-price-match"))
        #expect(PriceVerdictWords.shown(for: judged, kind: .item) != nil)
        for kind in [SearchKind.flat, .watch, .price] { #expect(PriceVerdictWords.shown(for: judged, kind: kind) == nil) }
        var empty = try #require(judged.priceVerdict)
        empty = ItemPriceVerdict(verdict: .cheap, price: 1, comparisonCount: 8, q25: 1, q75: 2,
                                 label: LocalizedText(en: "", de: ""), display: empty.display, note: empty.note)
        var unlabelled = judged
        unlabelled.priceVerdict = empty
        #expect(PriceVerdictWords.shown(for: unlabelled, kind: .item) == nil)
    }

    // MARK: the route and the store

    @Test func theRoute() async throws {
        let transport = FakeTransport()
        transport.answer("GET /hunts/2/price-record", json: try server("item-price-record"))
        let api = ArestemisAPI(transport: transport, token: { "fictional-token" })
        let record = try await api.priceRecord(hunt: 2)
        #expect(record.overall.count == 16)
        let request = try #require(transport.requests("GET /hunts/2/price-record").only)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fictional-token")
        #expect(request.url?.query == nil && request.httpBody == nil)
    }

    /// Loaded for a thing search only, once per scan and search (again when forced); its answer kept per hunt.
    @Test func theStoreAsksForThingSearchesOnly() async throws {
        let (store, transport, _) = try await makeStore()
        try transport.answer("GET /hunts/2/price-record", encoding: record(hunt: 2))
        await store.reloadOverview()
        await store.loadPriceRecord(hunt: 1)                                   // a flat search: never asked
        #expect(transport.requests("GET /hunts/1/price-record").isEmpty && store.priceRecord(hunt: 1) == nil)
        await store.loadPriceRecord(hunt: 2)
        #expect(store.priceRecord(hunt: 2)?.overall.count == 16)
        await store.loadPriceRecord(hunt: 2)                                   // the same scan: not again
        #expect(transport.requests("GET /hunts/2/price-record").count == 1)
        await store.loadPriceRecord(hunt: 2, force: true)                      // pull to refresh
        #expect(transport.requests("GET /hunts/2/price-record").count == 2)
        // A record of another hunt is not this one's.
        try transport.answer("GET /hunts/2/price-record", encoding: record(hunt: 12))
        await store.loadPriceRecord(hunt: 2, force: true)
        #expect(store.priceRecord(hunt: 2) == nil)
    }

    /// A server from before them (404) or a failure shows nothing: no notice, no error, the login kept.
    @Test func aMissingOrFailingRecordShowsNothing() async throws {
        let (store, transport, session) = try await makeStore()
        await store.reloadOverview()
        await store.loadPriceRecord(hunt: 2)                                   // the fake server's 404
        #expect(store.priceRecord(hunt: 2) == nil && store.notice == nil && session.isSignedIn)
        transport.answer("GET /hunts/2/price-record", 500, json: Data(#"{"error":"Something broke"}"#.utf8))
        await store.loadPriceRecord(hunt: 2, force: true)
        #expect(store.priceRecord(hunt: 2) == nil && store.notice == nil && session.isSignedIn)
        // Shown once, a later failure keeps it.
        try transport.answer("GET /hunts/2/price-record", encoding: record(hunt: 2))
        await store.loadPriceRecord(hunt: 2, force: true)
        transport.answer("GET /hunts/2/price-record", 503, json: Data(#"{"error":"Busy"}"#.utf8))
        await store.loadPriceRecord(hunt: 2, force: true)
        #expect(store.priceRecord(hunt: 2)?.overall.count == 16 && store.notice == nil)
    }

    // MARK: sample mode

    /// `-sampleData`: hunt 2 with its record and one verdict of each kind (most of its listings none), hunt 5 with few
    /// offers, hunt 4 with none yet; without the option (the tests' samples, `-sampleNoPrices`) a 404 and no verdicts.
    @Test func sampleMode() async throws {
        let session = EmpireSession(app: .arestemis, storage: MemoryTokens(), restoreOnLaunch: false)
        let store = ArestemisStore(session: session, backend: try SampleBackend(options: .init(priceRecords: true)),
                                   sample: true, placeDelay: .zero)
        await store.reloadOverview()
        for hunt in [2, 4, 5] { await store.loadPriceRecord(hunt: hunt) }
        let aeron = try #require(store.priceRecord(hunt: 2))
        #expect(aeron.overall.usual == 400...450 && aeron.sites.count == 2 && aeron.overall.trend == .down)
        #expect(PriceRecordCard(aeron, names: store.siteNames, language: .german).sites.map(\.name) == ["Kleinanzeigen", "eBay"])
        #expect(store.priceRecord(hunt: 5)?.overall.usual == nil && store.priceRecord(hunt: 5)?.sites.count == 2)
        #expect(PriceRecordCard(try #require(store.priceRecord(hunt: 4)), names: store.siteNames).empty != nil)
        await store.loadMatches(.all, hunt: 2)
        let verdicts = store.matches(.all, hunt: 2).compactMap { $0.priceVerdict?.verdict }
        #expect(Set(verdicts) == [.cheap, .expensive, .unusuallyCheap] && verdicts.count == 3)
        #expect(store.match(PriceRecordSample.unusuallyCheapID)?.priceVerdict?.price == 95)
        #expect(store.matches(.all, hunt: 2).count { $0.priceVerdict == nil } >= 3)

        let plain = ArestemisStore(session: session, backend: try SampleBackend(), sample: true, placeDelay: .zero)
        await plain.reloadOverview()
        await plain.loadPriceRecord(hunt: 2)
        await plain.loadMatches(.all, hunt: 2)
        #expect(plain.priceRecord(hunt: 2) == nil && plain.matches(.all, hunt: 2).allSatisfy { $0.priceVerdict == nil })
    }

    private func spaces(_ text: String?) -> String? { text?.replacingOccurrences(of: "\u{a0}", with: " ") }
}
