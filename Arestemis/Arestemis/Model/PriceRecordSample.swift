#if DEBUG
import Foundation

/// Invented asking prices for sample mode (brief 256), worded as the server words them (`~/Arestemis/src/arestemis/
/// texts.py`), in both languages. `-sampleData` shows them; `-sampleNoPrices` shows the samples as a server from before
/// them would (no records, no verdicts). The tests' sample backend leaves them out unless asked, so the contract's
/// listings stay as they are there.
///
/// - Hunt 2 (Herman Miller Aeron, up to €450 on Kleinanzeigen and eBay): 23 fitting listings, usually €400–450, the
///   cheapest of the last 7 days €360, the weekly median falling; Kleinanzeigen and eBay each with their own range.
///   Listing 31 (€400) is cheap, 30 (€480 VB) expensive, 29 (€420) has none (most have none), and listing 43, made up
///   here, asks €95: unusually cheap. The auction (32) and the free chair (28) never enter a record.
/// - Hunt 5 (jeans on Kleinanzeigen and Vinted): 3 fitting listings, too few for a range: counts and the cheapest only.
/// - Hunt 4 (bookcase): none yet.
enum PriceRecordSample {
    /// The unusually cheap listing, added to hunt 2.
    static let unusuallyCheapID = 43

    static func content(_ original: SampleContent, now: Date) throws -> SampleContent {
        var content = original
        let since = ArestemisSamples.iso(now.addingTimeInterval(-30 * 86_400))
        let until = ArestemisSamples.iso(now)
        content.priceRecords = [
            2: aeron(since: since, until: until, now: now),
            5: jeans(since: since, until: until),
            4: ItemPriceSummary(huntID: 4, since: since, until: until,
                                overall: ItemPriceStats(source: nil, count: 0,
                                                        display: LocalizedText(en: "0 fitting listings",
                                                                               de: "0 passende Angebote")),
                                note: note),
        ]
        let verdicts: [Int: ItemPriceVerdict] = [31: verdict(.cheap, price: 400), 30: verdict(.expensive, price: 480)]
        content.matches = content.matches.map { match in
            var match = match
            if let verdict = verdicts[match.id] { match.priceVerdict = verdict }
            return match
        }
        if !content.matches.contains(where: { $0.id == unusuallyCheapID }) {
            content.matches.append(try unusuallyCheap(now: now))
        }
        return content
    }

    static let note = LocalizedText(
        en: "Asking prices of fitting listings within this search’s price limits (including VB allowance), without shipping or buyer protection. These are not sale prices.",
        de: "Angebotspreise passender Angebote innerhalb der Preisgrenzen dieser Suche (einschließlich VB-Spielraum), ohne Versand oder Käuferschutz. Das sind keine Verkaufspreise.")

    private static func aeron(since: String, until: String, now: Date) -> ItemPriceSummary {
        let weeks = [ItemPriceWeek(weekStart: monday(before: now, weeksAgo: 2), count: 9, median: 435),
                     ItemPriceWeek(weekStart: monday(before: now, weeksAgo: 0), count: 8, median: 415)]
        let overall = ItemPriceStats(
            source: nil, count: 23, median: 425, q25: 400, q75: 450, cheapest7d: 360, weeklyMedians: weeks, trend: .down,
            display: LocalizedText(
                en: "23 fitting listings · Usually €400.00–€450.00 asked · Cheapest in the last 7 days: €360.00 · Weekly median falling",
                de: "23 passende Angebote · Üblicher Angebotspreis 400,00 €–450,00 € · Günstigstes Angebot der letzten 7 Tage: 360,00 € · Wöchentlicher Median fällt"))
        let kleinanzeigen = ItemPriceStats(
            source: .kleinanzeigen, count: 14, median: 420, q25: 395, q75: 445, cheapest7d: 360,
            display: LocalizedText(
                en: "14 fitting listings · Usually €395.00–€445.00 asked · Cheapest in the last 7 days: €360.00",
                de: "14 passende Angebote · Üblicher Angebotspreis 395,00 €–445,00 € · Günstigstes Angebot der letzten 7 Tage: 360,00 €"))
        let ebay = ItemPriceStats(
            source: .ebay, count: 9, median: 435, q25: 410, q75: 450, cheapest7d: 399,
            display: LocalizedText(
                en: "9 fitting listings · Usually €410.00–€450.00 asked · Cheapest in the last 7 days: €399.00",
                de: "9 passende Angebote · Üblicher Angebotspreis 410,00 €–450,00 € · Günstigstes Angebot der letzten 7 Tage: 399,00 €"))
        return ItemPriceSummary(huntID: 2, since: since, until: until, overall: overall, sites: [kleinanzeigen, ebay],
                                note: note)
    }

    private static func jeans(since: String, until: String) -> ItemPriceSummary {
        let overall = ItemPriceStats(
            source: nil, count: 3, cheapest7d: 22,
            display: LocalizedText(en: "3 fitting listings · Cheapest in the last 7 days: €22.00",
                                   de: "3 passende Angebote · Günstigstes Angebot der letzten 7 Tage: 22,00 €"))
        let kleinanzeigen = ItemPriceStats(
            source: .kleinanzeigen, count: 1,
            display: LocalizedText(en: "1 fitting listing", de: "1 passendes Angebot"))
        let vinted = ItemPriceStats(
            source: Source("vinted"), count: 2, cheapest7d: 22,
            display: LocalizedText(en: "2 fitting listings · Cheapest in the last 7 days: €22.00",
                                   de: "2 passende Angebote · Günstigstes Angebot der letzten 7 Tage: 22,00 €"))
        return ItemPriceSummary(huntID: 5, since: since, until: until, overall: overall, sites: [kleinanzeigen, vinted],
                                note: note)
    }

    /// A verdict against hunt 2's other 22 offers, usually €400–450.
    static func verdict(_ kind: ItemPriceVerdict.Kind, price: Double) -> ItemPriceVerdict {
        let label: LocalizedText = switch kind {
        case .cheap: LocalizedText(en: "Cheap", de: "Günstig")
        case .expensive: LocalizedText(en: "Expensive", de: "Teuer")
        case .unusuallyCheap: LocalizedText(en: "Unusually cheap – check carefully",
                                            de: "Ungewöhnlich günstig – genau prüfen")
        }
        return ItemPriceVerdict(
            verdict: kind, price: price, comparisonCount: 22, q25: 400, q75: 450, label: label,
            display: LocalizedText(en: "\(label.en): usually €400.00–€450.00 asked within your search limits",
                                   de: "\(label.de): üblicher Angebotspreis innerhalb deiner Suchgrenzen 400,00 €–450,00 €"),
            note: note)
    }

    /// An Aeron for €95, shipped from far away: the kind of listing that is bait, a scam or not what it says.
    private static func unusuallyCheap(now: Date) throws -> Match {
        let found = ArestemisSamples.iso(now.addingTimeInterval(-12 * 60))
        let json = """
            {"id": \(unusuallyCheapID), "hunt_id": 2, "state": "new", "seen": false, "found": "\(found)",
             "listing": {"source": "kleinanzeigen", "source_name": "Kleinanzeigen",
              "url": "https://www.kleinanzeigen.de/s-anzeige/sample-chair/9000000043",
              "title": "Herman Miller Aeron Remastered, like new", "kind": null, "rent_warm": null, "rent_cold": null,
              "sqm": null, "rooms": null, "flatmates": null, "city": "Bremen", "district": null, "address": null,
              "available_from": null, "available_until": null, "furnished": null, "posted": "\(found)",
              "image_url": null, "description": "Fictional office chair listing for the sample app. Shipping only.",
              "item": {"price": 95, "price_kind": "fixed", "shipping": "yes", "shipping_cost": 14.9,
                       "condition": "like_new", "condition_label": null, "seller": "private", "distance_km": null,
                       "reserved": false, "bids": null, "ends": null}},
             "reason": "An office chair matching the search.", "warnings": [], "application": null,
             "at_start": false, "over_max": null}
            """
        var match = try JSONDecoder().decode(Match.self, from: Data(json.utf8))
        match.priceVerdict = verdict(.unusuallyCheap, price: 95)
        return match
    }

    /// The Monday 00:00 UTC that starts the week `weeksAgo` weeks before the one `now` is in.
    private static func monday(before now: Date, weeksAgo: Int) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        return ArestemisSamples.iso(start.addingTimeInterval(-Double(weeksAgo) * 7 * 86_400))
    }
}
#endif
