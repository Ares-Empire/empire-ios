import Foundation
import WidgetKit

/// The app's language choice for its widget. A widget runs in its own process, which iOS starts in the iPhone's
/// language and which keeps its own defaults, so it would not see a choice made in the app. The app writes its choice
/// into the App Group it shares with the widget (at launch and on each switch) and reloads the widget's timelines; the
/// widget calls `follow()` before it builds an entry, and its views take `AppLanguage.current.locale`.
nonisolated struct WidgetLanguage {
    /// The App Group's defaults; nil when the entitlement is missing (then the widget follows the iPhone).
    let defaults: UserDefaults?
    /// The app's bundle id: apps sharing a group (`group.de.ares-empire.shared`) keep their choices apart.
    let app: String

    private var key: String { "appLanguage." + app }

    /// The app's choice, as the widget reads it; nil when the app follows the iPhone (or has not run yet).
    var choice: AppLanguage? {
        defaults?.string(forKey: key).flatMap(AppLanguage.init(rawValue:))
    }

    /// The app: tells the widget its choice (nil: "like the iPhone"). Reloads the widget only when the choice changed.
    func publish(_ choice: AppLanguage?, reload: () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        guard let defaults, self.choice != choice else { return }
        if let choice { defaults.set(choice.code, forKey: key) } else { defaults.removeObject(forKey: key) }
        reload()
    }

    /// The widget: the language it shows from now on (its process can live on between timelines, so it asks each time).
    @discardableResult
    func follow() -> AppLanguage {
        let language = choice ?? .launched
        AppLanguage.show(language)
        return language
    }
}
