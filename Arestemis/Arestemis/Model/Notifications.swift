import Foundation
import UserNotifications

/// Where a link or a notification takes the app: a match, and what to do once it is open; or a search's page (brief
/// 180: the server's "No matching product for …" push for an everywhere monitor).
struct ArestemisLink: Equatable {
    enum Target: Equatable {
        case match(Int)
        case hunt(Int)
    }

    enum Then: Equatable {
        case show               // the match's (or the search's) page
        case application        // … with its application sheet
        case openListing        // … and the portal page in the browser
    }

    let target: Target
    var then: Then = .show

    /// The match it opens; nil for a search's page.
    var match: Int? {
        if case .match(let id) = target { id } else { nil }
    }

    /// The search whose page it opens; nil for a match.
    var hunt: Int? {
        if case .hunt(let id) = target { id } else { nil }
    }

    /// `arestemis://match/41`, `arestemis://match/41?action=application`, `arestemis://hunt/12`. Anything else (the bare
    /// `arestemis://` the Empire app uses to start the app) is not a link to follow.
    init?(url: URL) {
        guard url.scheme?.lowercased() == "arestemis" else { return nil }
        var parts = url.pathComponents.filter { $0 != "/" }
        if let host = url.host(), !host.isEmpty { parts.insert(host, at: 0) }
        guard parts.count == 2, let id = Int(parts[1]), id > 0 else { return nil }
        switch parts[0] {
        case "match":
            target = .match(id)
            let action = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "action" }?.value
            then = action == "application" ? .application : .show
        case "hunt":
            target = .hunt(id)
        default:
            return nil
        }
    }

    init(match: Int, then: Then = .show) {
        target = .match(match)
        self.then = then
    }

    /// A search's page: it shows, nothing more.
    init(hunt: Int) {
        target = .hunt(hunt)
    }
}

/// The push for a new match (Arestemis/docs/API.md → push), `url` = `arestemis://match/<id>`: a flat's in category
/// `ARESTEMIS_MATCH` with the actions "Open listing" and "Application text", a thing's in `ARESTEMIS_ITEM` with "Open
/// listing", a watch's change in `ARESTEMIS_WATCH` with "Open page" (the watched page; brief 131), a price monitor's
/// alarm in `ARESTEMIS_PRICE` with "Open in shop" (the product's page; brief 137). Tapping any opens the match. The
/// server's "No matching product for …" push (brief 179) comes in `ARESTEMIS_PRICE` too, with `url` =
/// `arestemis://hunt/<id>`: it opens the monitor's page, its "Open in shop" as well (there is no shop to open yet).
///
/// Wiring (Shared/Push, by the lead after merging): register `categories` with the PushCenter; when it reports a tapped
/// notification, pass its `url` and action identifier to `link(url:action:)` and route the result like a deep link
/// (`AppNavigation.follow`).
enum MatchNotification {
    static let category = "ARESTEMIS_MATCH"
    static let itemCategory = "ARESTEMIS_ITEM"
    static let watchCategory = "ARESTEMIS_WATCH"
    static let priceCategory = "ARESTEMIS_PRICE"
    static let openListingAction = "ARESTEMIS_OPEN_LISTING"
    static let applicationAction = "ARESTEMIS_APPLICATION"

    static var categories: Set<UNNotificationCategory> {
        let open = UNNotificationAction(identifier: openListingAction, title: String(localized: "Open listing"),
                                        options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "safari"))
        let application = UNNotificationAction(identifier: applicationAction, title: String(localized: "Application text"),
                                               options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "text.quote"))
        // The watched page opens like a listing (`ArestemisLink.Then.openListing`: the match, then its address).
        let openPage = UNNotificationAction(identifier: openListingAction, title: String(localized: "Open page"),
                                            options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "safari"))
        // The product's page opens like a listing too.
        let openShop = UNNotificationAction(identifier: openListingAction, title: String(localized: "Open in shop"),
                                            options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "safari"))
        return [UNNotificationCategory(identifier: category, actions: [open, application], intentIdentifiers: [],
                                       options: []),
                UNNotificationCategory(identifier: itemCategory, actions: [open], intentIdentifiers: [], options: []),
                UNNotificationCategory(identifier: watchCategory, actions: [openPage], intentIdentifiers: [], options: []),
                UNNotificationCategory(identifier: priceCategory, actions: [openShop], intentIdentifiers: [], options: [])]
    }

    /// A tapped notification (or one of its actions) as a link; nil when it is not about a match or a search.
    static func link(url: URL?, action: String) -> ArestemisLink? {
        guard let url, var link = ArestemisLink(url: url) else { return nil }
        if link.hunt != nil {
            // A search's page has no listing to open and no application text: every action just shows it.
            return action == UNNotificationDismissActionIdentifier ? nil : link
        }
        switch action {
        case openListingAction: link.then = .openListing
        case applicationAction: link.then = .application
        case UNNotificationDismissActionIdentifier: return nil
        default: break          // the notification itself: keep what the URL says
        }
        return link
    }
}
