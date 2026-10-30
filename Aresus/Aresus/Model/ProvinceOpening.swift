import UIKit

/// Lives in the app target: Shared is also compiled into widgets, where UIApplication.shared is unavailable.
struct SystemProvinceURLOpener: ProvinceURLOpening {
    func open(_ url: URL) async -> Bool { await UIApplication.shared.open(url, options: [:]) }
}

extension ProvinceDetail {
    var canOpen: Bool {
        slug != "aresus" && (!(app?.isEmpty ?? true) || !(url?.isEmpty ?? true))
    }
}
