import Foundation

/// The App Group shared by the app and the widget (entitlements: Aresium.entitlements, AresiumWidget.entitlements).
nonisolated enum AppGroup {
    static let identifier = "group.de.ares-empire.aresium"
}

extension WidgetLanguage {
    /// Where the Aresium widgets read the app's language choice (the App Group they share with the app).
    nonisolated static var aresium: WidgetLanguage {
        WidgetLanguage(defaults: UserDefaults(suiteName: AppGroup.identifier), app: "de.ares-empire.aresium")
    }
}
