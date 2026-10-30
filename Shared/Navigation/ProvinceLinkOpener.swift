import Foundation

@MainActor
protocol ProvinceURLOpening {
    /// Opens the URL; false when nothing on the iPhone takes it (no installed app has the scheme).
    func open(_ url: URL) async -> Bool
}

/// Opens a province from the ring or its page: its iPhone app when installed, else its website. iOS says whether an
/// app took the URL, so no scheme needs declaring here (`LSApplicationQueriesSchemes`, which `canOpenURL` would need):
/// a new province app opens without a change to this app.
@MainActor
struct ProvinceLinkOpener {
    enum Outcome: Equatable {
        case app, website
        /// No URL was accepted by the system; the caller can explain why nothing opened.
        case notOpened
    }

    var application: any ProvinceURLOpening

    func open(app: String?, website: String?) async -> Outcome {
        if let app, let url = URL(string: app), url.scheme != nil, await application.open(url) {
            return .app
        }
        guard let website, let url = URL(string: website), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), url.host != nil else { return .notOpened }
        return await application.open(url) ? .website : .notOpened
    }
}
