import Foundation
import Observation

/// The app's links (aresus/docs/API.md → Pushes; the Empire app opens `aresus://`):
/// `aresus://province/<slug>`, `aresus://sync/run/<id>`, `aresus://server`, `aresus://sync`, `aresus://`.
nonisolated enum AresusLink: Equatable, Sendable {
    case home
    case server
    case province(String)
    case sync
    case run(Int)

    init?(url: URL) {
        guard url.scheme?.lowercased() == "aresus" else { return nil }
        let host = (url.host(percentEncoded: false) ?? "").lowercased()
        let path = url.path(percentEncoded: false).split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        switch (host, path.count) {
        case ("", 0): self = .home
        case ("server", 0): self = .server
        case ("sync", 0): self = .sync
        case ("province", 1) where Self.isSlug(path[0]): self = .province(path[0])
        case ("sync", 2) where path[0] == "run":
            guard let id = Int(path[1]), id > 0, String(id) == path[1] else { return nil }
            self = .run(id)
        default: return nil
        }
    }

    /// A province slug as the hub writes them ("aresium", "empire"): lowercase letters, digits, - and _.
    static func isSlug(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 64 && text.first != "-" && text.first != "_"
            && text.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" || $0 == "_" }
    }
}

/// A run sheet to show (`.sheet(item:)` needs an identity).
nonisolated struct RunRef: Identifiable, Hashable, Sendable {
    let id: Int
}

/// Where the app is: the tab, the pushed province pages, the open run sheet, Settings. Links and notification taps change it
/// here; the views only follow it.
@MainActor @Observable
final class AresusNavigation {
    enum Tab: String, Hashable, CaseIterable { case aresus, aresync }

    var tab: Tab
    var provincePath: [String]            // slugs pushed on the Aresus tab
    var openRun: RunRef?
    var showsSettings = false
    /// Bumped to scroll the Aresus tab to the server card.
    private(set) var serverRequest = 0

    init(tab: Tab = .aresus, provincePath: [String] = [], openRun: RunRef? = nil) {
        self.tab = tab
        self.provincePath = provincePath
        self.openRun = openRun
    }

    /// Follows an `aresus://` link (from iOS, the Empire app or a notification). False for anything else.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let link = AresusLink(url: url) else { return false }
        open(link)
        return true
    }

    func open(_ link: AresusLink) {
        switch link {
        case .home:
            break                          // opening the app keeps where it was
        case .server:
            openRun = nil
            tab = .aresus
            provincePath = []
            serverRequest += 1
        case .province(let slug):
            openRun = nil
            tab = .aresus
            provincePath = [slug]
        case .sync:
            openRun = nil
            tab = .aresync
        case .run(let id):
            tab = .aresync
            openRun = RunRef(id: id)
        }
    }

    /// The data on screen, which refreshes while it is visible.
    var visibleParts: [AresusStore.Part] {
        switch tab {
        case .aresus: provincePath.last.map { [.province($0)] } ?? [.overview]
        case .aresync: [.sync]
        }
    }

    /// Back to the start (after a logout).
    func reset() {
        tab = .aresus
        provincePath = []
        openRun = nil
        showsSettings = false
    }
}

#if DEBUG
extension AresusNavigation {
    /// Screenshots: `-tab aresus|aresync`, `-openProvince <slug>`, `-openRun <id>`, `-openSheet settings`.
    static func launched(arguments: [String]) -> AresusNavigation {
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        let navigation = AresusNavigation(tab: value("-tab").flatMap(Tab.init(rawValue:)) ?? .aresus)
        if let slug = value("-openProvince"), AresusLink.isSlug(slug) { navigation.open(.province(slug)) }
        if let id = value("-openRun").flatMap(Int.init), id > 0 { navigation.open(.run(id)) }
        navigation.showsSettings = value("-openSheet") == "settings"
        return navigation
    }
}
#endif
