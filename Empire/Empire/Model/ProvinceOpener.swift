import UIKit

@MainActor
protocol ProvinceURLOpening {
    func canOpenURL(_ url: URL) -> Bool
    func open(_ url: URL) async -> Bool
}

struct SystemProvinceURLOpener: ProvinceURLOpening {
    func canOpenURL(_ url: URL) -> Bool { UIApplication.shared.canOpenURL(url) }
    func open(_ url: URL) async -> Bool { await UIApplication.shared.open(url, options: [:]) }
}

@MainActor
struct ProvinceOpener {
    var application: any ProvinceURLOpening = SystemProvinceURLOpener()

    @discardableResult
    func open(_ province: Province) async -> Bool {
        guard !province.isComingSoon else { return false }
        if let app = province.app, let url = URL(string: app), url.scheme != nil,
           application.canOpenURL(url) {
            return await application.open(url)
        }
        guard let url = URL(string: province.url), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), url.host != nil else { return false }
        return await application.open(url)
    }
}
