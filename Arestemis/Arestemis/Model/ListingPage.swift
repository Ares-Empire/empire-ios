import Foundation

/// A listing's page (brief 142, Patrik 2026-11-03, after builds 12 and 13: the long reasoning "not really needed …
/// it fits because of the filter. If anything short notes on what couldn't be confirmed … and an overview of the stats
/// … not text explaining it but kinda like listings do it"; "the flat description is cut off"; and "the Bewerbung
/// button is colorful and confusing … whereas the button to the listing is less visible"). Decided here, so the page
/// only lays it out: the facts (`Listing.detailFacts`, `Listing.itemDetailFacts`), what to check, the line under a
/// description that is only the site's preview, and the buttons. The AI's `reason` is not on the page any more (the
/// listing fits because of the search); it stays in the data and on Filtered out, where it says why a listing was
/// turned down.

extension Match {
    /// The AI's warnings as the page's notes "To check" ("Floor not stated", "Rent may be cold rent"): each once, without
    /// empty ones, in the server's order.
    var checks: [String] {
        var seen = Set<String>()
        return warnings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

extension Listing {
    /// Under a description that is only the site's preview (`descriptionPartial`, server brief 141): "Only a preview.
    /// The whole text is on Immowelt.", the site by the server's name; tapping it opens the listing. Nil for a whole
    /// text, and for none (there is nothing to call a preview).
    func previewLine(language: AppLanguage = .current) -> String? {
        guard descriptionPartial, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return language.string("Only a preview. The whole text is on \(sourceName).")
    }
}

/// The buttons under a listing, the main one first: Open on the site (in the accent fill), and for a flat the
/// application text as the second, quiet one (it only gives the text to copy; Arestemis never sends it). A thing has no
/// application, a watched page's change and a price alarm open their page or shop.
enum ListingButton: Equatable, Hashable {
    /// "Open on ImmoScout24": a flat's or a thing's listing on its site.
    case openOnSite(String)
    /// A watched page's change: the page.
    case openPage
    /// A price monitor's alarm: the product in its shop.
    case openInShop
    /// A flat's application text, to copy into the site.
    case applicationText

    /// The buttons of a listing of this kind, the main one first; `site` is the server's name for the site.
    static func buttons(for kind: SearchKind, site: String) -> [ListingButton] {
        switch kind {
        case .flat: [.openOnSite(site), .applicationText]
        case .item: [.openOnSite(site)]
        case .watch: [.openPage]
        case .price: [.openInShop]
        }
    }

    /// The main button opens the listing; the application text is the quiet second one.
    var isMain: Bool { self != .applicationText }

    /// Whether it opens the listing's address.
    var opensListing: Bool { self != .applicationText }

    /// A small mark before the words, for the quiet button only.
    var symbol: String? { self == .applicationText ? "doc.text" : nil }

    func title(language: AppLanguage = .current) -> String {
        switch self {
        case .openOnSite(let site): language.string("Open on \(site)")
        case .openPage: language.string("Open page")
        case .openInShop: language.string("Open in shop")
        case .applicationText: language.string("Application text")
        }
    }
}

/// The star in a listing's top bar, beside its state menu (brief 180, Patrik 2026-11-05: "add a little star to each
/// findings page so it's easy to favorite them"): off while the listing is new, on (filled, in the accent) while it is a
/// favorite, the state `saved`; a tap turns one into the other. An applied or dismissed listing has none: it is dealt
/// with, and the state menu still offers everything.
enum FavoriteStar: Equatable {
    case off, on

    /// Nil for a state that shows no star.
    init?(_ state: MatchState) {
        switch state {
        case .new: self = .off
        case .saved: self = .on
        case .applied, .dismissed: return nil
        }
    }

    var symbol: String { self == .on ? "star.fill" : "star" }

    /// The state a tap sets: a favorite, or new again (read stays read).
    var next: MatchState { self == .on ? .new : .saved }

    /// What VoiceOver says a tap does: "Favorite" / "Favorit", "Remove from favorites" / "Kein Favorit mehr".
    func action(language: AppLanguage = .current) -> String {
        self == .on ? language.string("Remove from favorites") : language.string("Favorite")
    }
}
