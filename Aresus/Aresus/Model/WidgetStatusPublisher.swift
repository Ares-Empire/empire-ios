import WidgetKit
import Foundation

/// Keeps the widget in step with the app: every overview the app loads is saved as the widget's status and the widget
/// reloaded (so it never waits for its own next fetch); logging out or losing access to Aresus deletes it.
/// `.disabled` for samples, tests and screenshots, so they never touch the real file.
struct WidgetStatusPublisher {
    let store: WidgetStatusStore?
    var reloadTimelines: () -> Void = { WidgetCenter.shared.reloadTimelines(ofKind: AresusWidgetKind.status) }

    static let disabled = WidgetStatusPublisher(store: nil, reloadTimelines: {})
    static func live() -> WidgetStatusPublisher { WidgetStatusPublisher(store: .appGroup) }

    func publish(_ overview: Overview) {
        guard let store else { return }
        try? store.save(WidgetStatus(overview: overview))   // if saving fails, the widget still fetches on its own
        reloadTimelines()
    }

    func clear() {
        guard let store else { return }
        try? store.delete()
        reloadTimelines()
    }
}
