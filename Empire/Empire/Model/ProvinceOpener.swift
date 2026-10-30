import UIKit

struct SystemProvinceURLOpener: ProvinceURLOpening {
    func open(_ url: URL) async -> Bool { await UIApplication.shared.open(url, options: [:]) }
}

/// Empire keeps its coming-soon rule; the app/website opening order is shared with Aresus.
@MainActor
struct ProvinceOpener {
    typealias Outcome = ProvinceLinkOpener.Outcome
    var application: any ProvinceURLOpening = SystemProvinceURLOpener()

    func open(_ province: Province) async -> Outcome {
        guard !province.isComingSoon else { return .notOpened }
        return await ProvinceLinkOpener(application: application).open(app: province.app, website: province.url)
    }
}
