import Foundation

/// Where drops live between the share sheet and the app: Aresus's own App Group, which the app and its share extension
/// both have (`Aresus.entitlements`, `AresusShare.entitlements`). Files waiting to be sent and the background upload
/// session's files belong here, so an upload the share sheet starts goes on after it closes and the app sees it.
/// The folder `AresusDrops` is compiled into the app and the extension (ares-empire/docs/ARESYNC-DROP.md).
nonisolated enum DropContainer {
    /// The App Group both targets name in their entitlements.
    static let appGroup = "group.de.ares-empire.aresus"
    /// The background `URLSession` the uploads run in; its `sharedContainerIdentifier` is `appGroup`.
    static let uploadSession = "de.ares-empire.aresus.drops.upload"

    /// The group's folder; nil only when the entitlement is missing (a build without the paid team's signing).
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }
}
