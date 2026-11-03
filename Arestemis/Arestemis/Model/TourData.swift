import Foundation

/// The tour's made-up server answers (brief 139), as small as its eight steps need and in the app's language, as
/// Aresium's tour has its own made-up bank file (`TourData` there). The contract's samples (`Samples/`, copies of the
/// server's `docs/samples`) are English and stay for the tests and screenshots; the tour shows this instead, so a German
/// iPhone sees German searches, listings and reasons. Its words are in the String Catalog (English here, German by
/// `strings.py fill`); names stay names (Herman Miller Aeron, Nintendo Switch 2, the sites, the towns), and money and
/// dates are formatted by the app. The answers are built as the server sends them and read through the app's own
/// decoders, so they stay valid for the screens. Times are set around `now`, dates a month or two ahead.
///
/// What the steps show: four searches, one of each kind (a flat; things: an Aeron office chair; a page watch on the
/// Mensa's menu; a price monitor on a Nintendo Switch 2, which stand together on the list for step 7); the flat's new
/// listing (the newest finding of all, the first row of Listings → New, the listing page of step 6) and its two
/// filtered-out listings (step 8); three chairs, the menu's change and the console's price alarm, so New has a group per
/// search; the kinds' names for New search.
enum TourData {
    /// The searches' ids, in the Hunts list's order.
    static let flat = 1, thing = 2, watch = 3, monitor = 4
    /// The name a made-up application text is signed with.
    static let name = "Alex"

    static func content(now: Date = .now, language: AppLanguage = .current) throws -> SampleContent {
        let words = Words(language: language)
        let decoder = JSONDecoder()
        func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
            try decoder.decode(type, from: JSONSerialization.data(withJSONObject: object))
        }
        let times = Times(now: now)
        let hunts: [[String: Any]] = [flatCard(words, times), thingCard(times), watchCard(words, times),
                                      monitorCard(times)]
        let overview: [String: Any] = [
            "version": 2,
            "me": ["id": "tour", "name": name],
            "hunt": hunts[0]["hunt"]!,
            "sources": ["wg_gesucht", "kleinanzeigen", "immowelt", "immoscout24", "ebay"].map { source in
                ["source": source, "name": siteNames[source]!, "state": "ok", "checked": times.lastScan,
                 "note": NSNull()]
            },
            "last_scan": times.lastScan,
            "counts": ["new": 0, "today": 0, "saved": 0, "applied": 0],    // counted by the sample server
            "latest": [],
            "hunts": hunts,
        ]
        return SampleContent(overview: try decode(Overview.self, overview),
                             matches: try decode([Match].self, matches(words, times)),
                             rejected: try decode([Rejected].self, rejected(words, times)),
                             settings: try decode(Settings.self, [
                                "application_mode": "ai", "own_text": "", "application_notes": "", "about_me": "",
                                "notify": ["push": true, "time_sensitive": true],
                             ]),
                             kinds: try decode([OfferedKind].self, kinds(language)),
                             places: [],
                             histories: [monitor: try history(now: now)],
                             application: { listing, name in words.application(title: listing.title, name: name) })
    }

    // MARK: the searches

    private static let siteNames = ["wg_gesucht": "WG-Gesucht", "kleinanzeigen": "Kleinanzeigen",
                                    "immowelt": "Immowelt", "immoscout24": "ImmoScout24", "ebay": "eBay"]
    private static let flatSites = ["wg_gesucht", "kleinanzeigen", "immowelt", "immoscout24"]
    private static let munich: [String: Any] = ["id": "wg:90", "name": "München", "region": "Bayern",
                                                "sources": flatSites]
    private static let garching: [String: Any] = ["id": "wg:400", "name": "Garching bei München", "region": "Bayern",
                                                  "sources": flatSites]
    private static let mensa = "https://www.studierendenwerk-muenchen-oberbayern.de/mensa/speiseplan/speiseplan_422_-de.html"
    private static let mediaMarkt = "https://www.mediamarkt.de/de/product/_nintendo-switch-2-2981741.html"

    private static func hunt(_ id: Int, _ kind: String, name: String?, search: [String: Any], _ times: Times,
                             lastScan: String? = nil) -> [String: Any] {
        ["id": id, "kind": kind, "name": name ?? NSNull(), "active": true, "search": search,
         "created": times.ago(days: 9), "updated": times.ago(days: 9), "activated": times.ago(days: 9),
         "last_scan": lastScan ?? times.lastScan]
    }

    private static func card(_ hunt: [String: Any], sources: [String] = [], page: Any = NSNull(),
                             price: Any = NSNull()) -> [String: Any] {
        ["hunt": hunt, "counts": ["new": 0, "today": 0, "saved": 0, "applied": 0], "sources": sources,
         "slowed": false, "page": page, "price": price]
    }

    /// A flat or a WG room in Munich or Garching, up to €1,000 warm, moving in next month or the two after.
    private static func flatCard(_ words: Words, _ times: Times) -> [String: Any] {
        card(hunt(flat, "flat", name: nil, search: [
            "kinds": ["flat", "wg"], "people": 1, "flatmates_max": 2, "places": [munich, garching],
            "districts": ["Schwabing", "Maxvorstadt"], "sqm_min": 28, "sqm_max": NSNull(), "room_sqm_min": 14,
            "room_sqm_max": NSNull(), "rooms_min": NSNull(), "rent_cold_min": NSNull(), "rent_cold_max": NSNull(),
            "rent_warm_min": 400, "rent_warm_max": 1000, "move_in_from": times.moveIn, "move_in_until": times.moveInUntil,
            "sublet": "exclude", "extra": words.string("A balcony would be nice, not on the ground floor"),
            "sources": flatSites,
        ], times), sources: flatSites)
    }

    /// An office chair: Herman Miller Aeron up to €450, around Garching, on Kleinanzeigen and eBay.
    private static func thingCard(_ times: Times) -> [String: Any] {
        card(hunt(thing, "item", name: nil, search: [
            "query": "Herman Miller Aeron", "exclude": [], "price_min": NSNull(), "price_max": 450, "vb_over_max": 45,
            "condition_min": NSNull(), "for_parts": false, "auctions": true, "delivery": "either", "places": [garching],
            "radius_km": 20, "seller": "any", "extra": "", "sources": ["kleinanzeigen", "ebay"],
        ], times), sources: ["kleinanzeigen", "ebay"])
    }

    /// The Mensa's menu, read twice a day: is there schnitzel this week?
    private static func watchCard(_ words: Words, _ times: Times) -> [String: Any] {
        card(hunt(watch, "watch", name: words.string("Schnitzel at the Mensa"), search: [
            "url": mensa, "change": words.string("there is schnitzel this week"), "every": 720,
        ], times, lastScan: times.ago(hours: 3)), page: [
            "page_title": words.string("Mensa Garching menu"), "host": "www.studierendenwerk-muenchen-oberbayern.de",
            "now": words.schnitzel, "read": "ok", "checked": times.ago(hours: 3), "changed": times.ago(days: 1),
            "note": NSNull(),
        ])
    }

    /// A Nintendo Switch 2 at MediaMarkt: its history, and an alarm under €450 or when it is back in stock.
    private static func monitorCard(_ times: Times) -> [String: Any] {
        card(hunt(monitor, "price", name: nil, search: [
            "url": mediaMarkt, "history": true, "alarm": ["below": 450.0, "back_in_stock": true], "every": 60,
        ], times, lastScan: times.ago(minutes: 2)), price: [
            "reader": "plain", "product": "Nintendo Switch 2", "host": "www.mediamarkt.de", "price": 449.0,
            "currency": "EUR", "availability": "in_stock", "source": "shop", "read": "ok", "checked": times.ago(minutes: 2),
            "note": NSNull(), "low_30d": 449.0, "high_30d": 483.99, "since": times.ago(days: 365),
        ])
    }

    // MARK: the listings

    private static func listing(source: String, title: String, url: String, city: String? = nil,
                                description: String = "", flat: [String: Any] = [:], item: Any = NSNull(),
                                page: Any = NSNull(), priceChange: Any = NSNull(), posted: Any = NSNull())
        -> [String: Any] {
        var listing: [String: Any] = [
            "source": source, "source_name": siteNames[source] ?? URLComponents(string: url)?.host ?? source,
            "url": url, "title": title, "kind": NSNull(), "rent_warm": NSNull(), "rent_cold": NSNull(),
            "sqm": NSNull(), "rooms": NSNull(), "flatmates": NSNull(), "city": city ?? NSNull(), "district": NSNull(),
            "address": NSNull(), "available_from": NSNull(), "available_until": NSNull(), "furnished": NSNull(),
            "posted": posted, "image_url": NSNull(), "description": description, "item": item, "page": page,
            "price_change": priceChange,
        ]
        listing.merge(flat) { _, new in new }
        return listing
    }

    private static func match(_ id: Int, hunt: Int, state: String = "new", found: String, listing: [String: Any],
                              reason: String, warnings: [String] = []) -> [String: Any] {
        ["id": id, "hunt_id": hunt, "state": state, "found": found, "listing": listing, "reason": reason,
         "warnings": warnings, "application": NSNull(), "at_start": false, "over_max": NSNull()]
    }

    private static func chair(price: Int, kind: String, shipping: String, cost: Any = NSNull(), condition: String,
                              distance: Any = NSNull(), bids: Any = NSNull(), ends: Any = NSNull()) -> [String: Any] {
        ["price": price, "price_kind": kind, "shipping": shipping, "shipping_cost": cost, "condition": condition,
         "condition_label": NSNull(), "seller": "private", "distance_km": distance, "reserved": false, "bids": bids,
         "ends": ends]
    }

    private static func matches(_ words: Words, _ times: Times) -> [[String: Any]] {
        [
            // The flat: the newest finding of all, so it heads Listings → New; step 6 opens it.
            match(101, hunt: flat, found: times.ago(minutes: 3), listing: listing(
                source: "immoscout24", title: words.string("Bright 2-room flat with balcony in Schwabing"),
                url: "https://www.immobilienscout24.de/expose/90000101", city: "München",
                description: words.string("Bright 2-room flat on the 3rd floor with a south-facing balcony. Fitted kitchen, cellar, bike room. Hohenzollernplatz underground station 3 minutes away."),
                // Furnished is not stated, so step 6's "–" is on the page.
                flat: ["kind": "flat", "rent_warm": 980, "rent_cold": 820, "sqm": 42, "rooms": 2, "district": "Schwabing",
                       "address": "Hohenzollernstraße", "available_from": times.moveIn],
                posted: times.ago(minutes: 4)),
                  reason: words.string("Two rooms with a balcony in Schwabing, under your warm rent limit and free when you want to move in."),
                  warnings: [words.string("The listing does not say how much the deposit is.")]),
            // Three office chairs.
            match(201, hunt: thing, found: times.ago(minutes: 25), listing: listing(
                source: "ebay", title: words.string("Herman Miller Aeron office chair, size B, auction"),
                url: "https://www.ebay.de/itm/900000000201", city: "Freising",
                description: words.string("Size B, original armrests, a few marks on the base."),
                item: chair(price: 310, kind: "auction", shipping: "yes", cost: 24.99, condition: "good", bids: 7,
                            ends: times.ahead(hours: 2)),
                posted: times.ago(minutes: 30)),
                  reason: words.string("An Aeron in size B; the bid is still well under your limit.")),
            match(202, hunt: thing, found: times.ago(hours: 2), listing: listing(
                source: "kleinanzeigen", title: words.string("Herman Miller Aeron, size B, like new"),
                url: "https://www.kleinanzeigen.de/s-anzeige/aeron/9000000202", city: "Garching",
                description: words.string("Barely used, from a home office. Pickup in Garching."),
                item: chair(price: 400, kind: "fixed", shipping: "pickup_only", condition: "like_new", distance: 5),
                posted: times.ago(hours: 2)),
                  reason: words.string("An Aeron in size B under your price limit, 5 km away.")),
            match(203, hunt: thing, found: times.ago(hours: 5), listing: listing(
                source: "kleinanzeigen", title: words.string("Aeron office chair with adjustable armrests"),
                url: "https://www.kleinanzeigen.de/s-anzeige/aeron/9000000203", city: "München",
                description: words.string("Size B, black. Shipping possible."),
                item: chair(price: 420, kind: "negotiable", shipping: "yes", cost: 39.0, condition: "good"),
                posted: times.ago(hours: 5)),
                  reason: words.string("An Aeron that ships, a little under your limit.")),
            // The menu changed: schnitzel on Tuesday.
            match(301, hunt: watch, found: times.ago(days: 1), listing: listing(
                source: "page", title: words.string("Mensa Garching menu"), url: mensa,
                page: ["added": [words.schnitzel], "removed": [words.string("Tuesday: vegetable lasagne")],
                       "now": words.schnitzel]),
                  reason: words.string("Pork schnitzel with fries on Tuesday")),
            // The console fell under the alarm's price.
            match(401, hunt: monitor, found: times.ago(hours: 1), listing: listing(
                source: "page", title: "Nintendo Switch 2", url: mediaMarkt,
                priceChange: ["old": 483.99, "new": 449.0, "currency": "EUR", "availability": "in_stock",
                              "kind": "below"]),
                  reason: words.alarm(product: "Nintendo Switch 2", new: 449.0, old: 483.99)),
        ]
    }

    /// What the check turned down for the flat, each with its reason (step 8).
    private static func rejected(_ words: Words, _ times: Times) -> [[String: Any]] {
        [
            ["id": 501, "hunt_id": flat, "found": times.ago(hours: 6), "listing": listing(
                source: "immoscout24", title: words.string("Furnished 1-room flat, Maxvorstadt"),
                url: "https://www.immobilienscout24.de/expose/90000501", city: "München",
                description: words.string("Furnished, for a limited time only."),
                flat: ["kind": "flat", "rent_warm": 950, "sqm": 30, "rooms": 1, "district": "Maxvorstadt",
                       "available_from": times.moveIn, "available_until": times.subletEnd, "furnished": true],
                posted: times.ago(hours: 6)),
             "reason": words.string("A sublet with an end date; you excluded sublets.")],
            ["id": 502, "hunt_id": flat, "found": times.ago(hours: 20), "listing": listing(
                source: "kleinanzeigen", title: words.string("Swap: my 2 rooms in Schwabing for 3 rooms"),
                url: "https://www.kleinanzeigen.de/s-anzeige/tausch/3000000502", city: "München",
                description: words.string("Flat swap: I offer 2 rooms and am looking for 3."),
                flat: ["kind": "flat", "rent_warm": 890, "sqm": 45, "rooms": 2, "district": "Schwabing"],
                posted: times.ago(hours: 20)),
             "reason": words.string("A flat swap, not a flat to rent.")],
        ]
    }

    // MARK: the kinds and the price history

    /// New search's kinds, named as this build names them (the server's own names would be the same words).
    private static func kinds(_ language: AppLanguage) -> [[String: Any]] {
        func site(_ source: String, _ name: String, auctions: Bool = false, delivery: String = "both") -> [String: Any] {
            ["source": source, "name": name, "ready": true, "auctions": auctions, "delivery": delivery]
        }
        return [
            ["kind": "flat", "name": SearchKind.flat.choiceTitle(language: language),
             "sources": flatSites.map { site($0, siteNames[$0]!) }],
            ["kind": "item", "name": SearchKind.item.choiceTitle(language: language),
             "sources": [site("kleinanzeigen", "Kleinanzeigen"), site("ebay", "eBay", auctions: true),
                         site("mydealz", "mydealz", delivery: "shipping"), site("bikemarkt", "MTB-News Bikemarkt"),
                         site("ikea_preowned", "IKEA Preowned", delivery: "pickup"),
                         site("vinted", "Vinted", delivery: "shipping")]],
            ["kind": "price", "name": SearchKind.price.choiceTitle(language: language), "sources": []],
            ["kind": "watch", "name": SearchKind.watch.choiceTitle(language: language), "sources": []],
        ]
    }

    /// The console's year of prices: the contract's sample history (numbers only), moved to end an hour ago.
    private static func history(now: Date) throws -> [PricePoint] {
        let raw = try ArestemisSamples.decode(Prices.self, from: "prices-9")
        guard let last = raw.points.last.flatMap({ Timestamp.parse($0.at) }) else { return raw.points }
        let shift = now.addingTimeInterval(-3600).timeIntervalSince(last)
        return try ArestemisSamples.decode(Prices.self, from: "prices-9", shift: shift).points
    }

    // MARK: words and times

    /// The tour's words in one language.
    private struct Words {
        let language: AppLanguage

        func string(_ key: LocalizedStringResource) -> String { language.string(key) }

        /// The menu's line now.
        var schnitzel: String { string("Tuesday: pork schnitzel with fries") }

        /// The price alarm's summary, as the app words an alarm ("Nintendo Switch 2: €449.00 (was €483.99)").
        func alarm(product: String, new: Double, old: Double) -> String {
            let new = PriceWords.money(new, language: language), old = PriceWords.money(old, language: language)
            return language.string("\(product): \(new) (was \(old))")
        }

        /// A made-up application text for a flat, in the app's language.
        func application(title: String, name: String) -> String {
            language.string("Hello,\n\nI read your listing “\(title)” with great interest. I live quietly and tidily, I don't smoke, and the rent is secure.\n\nI would be glad to come to a viewing; my times are flexible.\n\nBest regards\n\(name)")
        }
    }

    /// The tour's moments around `now`, as the server writes them.
    private struct Times {
        let now: Date

        var lastScan: String { ago(seconds: 40) }
        func ago(seconds: TimeInterval) -> String { ArestemisSamples.iso(now.addingTimeInterval(-seconds)) }
        func ago(minutes: Double) -> String { ago(seconds: minutes * 60) }
        func ago(hours: Double) -> String { ago(seconds: hours * 3600) }
        func ago(days: Double) -> String { ago(seconds: days * 86_400) }
        func ahead(hours: Double) -> String { ArestemisSamples.iso(now.addingTimeInterval(hours * 3600)) }

        /// Moving in: the first of next month, until the first of the month two after; a sublet ends four months on.
        var moveIn: String { firstOfMonth(after: 1) }
        var moveInUntil: String { firstOfMonth(after: 3) }
        var subletEnd: String { firstOfMonth(after: 5) }

        private func firstOfMonth(after months: Int) -> String {
            let calendar = Calendar.app
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            return DateOnly.string(calendar.date(byAdding: .month, value: months, to: start) ?? start)
        }
    }
}
