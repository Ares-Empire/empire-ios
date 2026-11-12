#if DEBUG
import Foundation

/// `-sampleData -sampleLook -openMatch 34`: a fictional coat hunt (brief 268), its finding with a look and photos, and two
/// filtered-out coats of it (`-openSearch 5 -openSheet rejected`). The photos are made-up pictures bundled in `Samples/`
/// (`sample://`, `SamplePhotos`), never fetched from a site. `-sampleLookVote up|down|none` sets the finding's vote (up
/// when not given).
enum LookSample {
    static func content(_ original: SampleContent) throws -> SampleContent {
        var content = original
        guard let card = content.overview.hunts.firstIndex(where: { $0.id == 5 }),
              var search = content.overview.hunts[card].hunt.search.item,
              let index = content.matches.firstIndex(where: { $0.id == 34 }) else { return content }
        search.query = "Fur coat"
        search.moreQueries = []
        search.extra = ""
        search.priceMax = 400
        search.look = "Long men's coat with a straight cut and real fur."
        search.lookMin = 6
        content.overview.hunts[card].hunt.search = .item(search)

        var listing = try JSONSerialization.jsonObject(with: JSONEncoder().encode(content.matches[index].listing)) as! [String: Any]
        var item = listing["item"] as? [String: Any] ?? [:]
        func photos(_ names: [String]) -> [String] { names.map { "\(SamplePhotoScheme.name)://\($0)" } }
        func accepted(_ object: [String: Any]) throws -> Listing {
            try JSONDecoder().decode(Listing.self, from: JSONSerialization.data(withJSONObject: object))
        }

        let coat = photos(["look-coat-front.jpg", "look-coat-back.jpg", "look-coat-collar.jpg"])
        item["price"] = 240
        listing["item"] = item
        listing["title"] = "Northwood long fur coat"
        listing["url"] = "https://example.invalid/listings/northwood-coat"
        listing["description"] = "Fictional sample: a long coat with a straight cut."
        listing["image_url"] = coat[0]
        listing["photo_urls"] = coat
        let vote: Vote? = switch LaunchArguments.value("-sampleLookVote") {
        case "none": nil
        case let value?: Vote(rawValue: value) ?? .up
        case nil: .up
        }
        let found = content.matches[index].found
        content.matches[index] = Match(
            id: 34, huntID: 5, state: .new, found: found, listing: try accepted(listing),
            reason: "Matches the search.", warnings: [],
            look: LookVerdict(score: 8, length: .long, cut: .men, fur: .real,
                              reason: "Long, straight cut that falls below the knee, with a broad shawl collar. The dark brown fur looks dense and even.",
                              reasonDE: "Langer, gerader Schnitt bis unter das Knie, mit breitem Schalkragen. Der dunkelbraune Pelz wirkt dicht und gleichmäßig."),
            vote: vote)

        // Filtered out by the look check: its reason as the server writes it, "Look n/10: <German reason>".
        let jacket = photos(["look-jacket.jpg"])
        item["price"] = 120
        listing["item"] = item
        listing["title"] = "Northwood cropped jacket"
        listing["url"] = "https://example.invalid/listings/northwood-jacket"
        listing["description"] = "Fictional sample: a short jacket."
        listing["image_url"] = jacket[0]
        listing["photo_urls"] = jacket
        content.rejected.append(Rejected(id: 13, huntID: 5, found: found, listing: try accepted(listing),
                                         reason: "Look 4/10: Zu kurz, endet an der Hüfte statt unter dem Knie.",
                                         vote: .down))
        let overcoat = photos(["look-overcoat.jpg"])
        item["price"] = 90
        listing["item"] = item
        listing["title"] = "Camel wool overcoat"
        listing["url"] = "https://example.invalid/listings/camel-overcoat"
        listing["description"] = "Fictional sample: a wool coat without fur."
        listing["image_url"] = overcoat[0]
        listing["photo_urls"] = overcoat
        content.rejected.append(Rejected(id: 14, huntID: 5, found: found, listing: try accepted(listing),
                                         reason: "Look 3/10: Wollmantel ohne Pelz, schmale Revers statt breitem Kragen."))
        return content
    }
}
#endif
