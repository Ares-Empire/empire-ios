import UIKit

@MainActor
protocol ProvinceURLOpening {
    /// Opens the URL; false when nothing on the iPhone takes it (no installed app has the scheme).
    func open(_ url: URL) async -> Bool
}

struct SystemProvinceURLOpener: ProvinceURLOpening {
    func open(_ url: URL) async -> Bool { await UIApplication.shared.open(url, options: [:]) }
}

/// Opens a province from the ring or its page: its iPhone app when installed, else its website. iOS says whether an
/// app took the URL, so no scheme needs declaring here (`LSApplicationQueriesSchemes`, which `canOpenURL` would need):
/// a new province app opens without a change to this app.
@MainActor
struct ProvinceOpener {
    enum Outcome: Equatable {
        case app, website
        /// Nothing opened (coming soon; or no app installed and no website): the caller shows the province's page.
        case notOpened
    }

    var application: any ProvinceURLOpening = SystemProvinceURLOpener()

    func open(_ province: Province) async -> Outcome {
        guard !province.isComingSoon else { return .notOpened }
        if let app = province.app, let url = URL(string: app), url.scheme != nil, await application.open(url) {
            return .app
        }
        guard let url = URL(string: province.url), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), url.host != nil else { return .notOpened }
        return await application.open(url) ? .website : .notOpened
    }
}
