import Foundation
import UserNotifications

/// Where a link or a notification takes the app: a match, and what to do once it is open.
struct ArestemisLink: Equatable {
    enum Then: Equatable {
        case show               // the match's page
        case application        // … with its application sheet
        case openListing        // … and the portal page in the browser
    }

    let match: Int
    var then: Then = .show

    /// `arestemis://match/41`, `arestemis://match/41?action=application`. Anything else (the bare `arestemis://` the
    /// Empire app uses to start the app) is not a link to follow.
    init?(url: URL) {
        guard url.scheme?.lowercased() == "arestemis" else { return nil }
        var parts = url.pathComponents.filter { $0 != "/" }
        if let host = url.host(), !host.isEmpty { parts.insert(host, at: 0) }
        guard parts.count == 2, parts[0] == "match", let id = Int(parts[1]), id > 0 else { return nil }
        match = id
        let action = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "action" }?.value
        then = action == "application" ? .application : .show
    }

    init(match: Int, then: Then = .show) {
        self.match = match
        self.then = then
    }
}

/// The push for a new match (Arestemis/docs/API.md → push), `url` = `arestemis://match/<id>`: a flat's in category
/// `ARESTEMIS_MATCH` with the actions "Open listing" and "Application", a thing's in `ARESTEMIS_ITEM` with "Open
/// listing", a watch's change in `ARESTEMIS_WATCH` with "Open page" (the watched page; brief 131). Tapping any opens the
/// match.
///
/// Wiring (Shared/Push, by the lead after merging): register `categories` with the PushCenter; when it reports a tapped
/// notification, pass its `url` and action identifier to `link(url:action:)` and route the result like a deep link
/// (`AppNavigation.follow`).
enum MatchNotification {
    static let category = "ARESTEMIS_MATCH"
    static let itemCategory = "ARESTEMIS_ITEM"
    static let watchCategory = "ARESTEMIS_WATCH"
    static let openListingAction = "ARESTEMIS_OPEN_LISTING"
    static let applicationAction = "ARESTEMIS_APPLICATION"

    static var categories: Set<UNNotificationCategory> {
        let open = UNNotificationAction(identifier: openListingAction, title: String(localized: "Open listing"),
                                        options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "safari"))
        let application = UNNotificationAction(identifier: applicationAction, title: String(localized: "Application"),
                                               options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "text.quote"))
        // The watched page opens like a listing (`ArestemisLink.Then.openListing`: the match, then its address).
        let openPage = UNNotificationAction(identifier: openListingAction, title: String(localized: "Open page"),
                                            options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "safari"))
        return [UNNotificationCategory(identifier: category, actions: [open, application], intentIdentifiers: [],
                                       options: []),
                UNNotificationCategory(identifier: itemCategory, actions: [open], intentIdentifiers: [], options: []),
                UNNotificationCategory(identifier: watchCategory, actions: [openPage], intentIdentifiers: [], options: [])]
    }

    /// A tapped notification (or one of its actions) as a link; nil when it is not about a match.
    static func link(url: URL?, action: String) -> ArestemisLink? {
        guard let url, var link = ArestemisLink(url: url) else { return nil }
        switch action {
        case openListingAction: link.then = .openListing
        case applicationAction: link.then = .application
        case UNNotificationDismissActionIdentifier: return nil
        default: break          // the notification itself: keep what the URL says
        }
        return link
    }
}
