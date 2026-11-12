#if DEBUG
import Foundation

/// `-sampleData -sampleLook -openMatch 34`: a fictional coat hunt and its photo votes.
enum LookSample {
    static func content(_ original: SampleContent) throws -> SampleContent {
        var content = original
        guard let card = content.overview.hunts.firstIndex(where: { $0.id == 5 }),
              var search = content.overview.hunts[card].hunt.search.item,
              let index = content.matches.firstIndex(where: { $0.id == 34 }) else { return content }
        search.query = "Fur coat"
        search.moreQueries = []
        search.look = "Long men's coat with a straight cut and real fur."
        search.lookMin = 6
        content.overview.hunts[card].hunt.search = .item(search)

        var listing = try JSONSerialization.jsonObject(with: JSONEncoder().encode(content.matches[index].listing)) as! [String: Any]
        listing["title"] = "Northwood long fur coat"
        listing["url"] = "https://example.invalid/listings/northwood-coat"
        listing["description"] = "Fictional sample: a long coat with a straight cut."
        let accepted = try JSONDecoder().decode(Listing.self, from: JSONSerialization.data(withJSONObject: listing))
        let found = content.matches[index].found
        content.matches[index] = Match(id: 34, huntID: 5, state: .new, found: found, listing: accepted,
                                      reason: "Matches the search.", warnings: [],
                                      look: LookVerdict(score: 8, length: .long, cut: .men, fur: .real,
                                                        reason: "Long, straight cut with a broad collar.",
                                                        reasonDE: "Langer, gerader Schnitt mit breitem Kragen."), vote: .up)
        listing["title"] = "Northwood cropped jacket"
        listing["url"] = "https://example.invalid/listings/northwood-jacket"
        listing["description"] = "Fictional sample: a short jacket."
        let rejected = try JSONDecoder().decode(Listing.self, from: JSONSerialization.data(withJSONObject: listing))
        content.rejected.append(Rejected(id: 13, huntID: 5, found: found, listing: rejected,
                                         reason: "Too short for the requested silhouette.", vote: .down))
        return content
    }
}
#endif
