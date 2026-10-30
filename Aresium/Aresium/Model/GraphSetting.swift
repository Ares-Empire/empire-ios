import Foundation

/// Settings → Dashboard → Graph (brief 42, Patrik 2026-10-30): whether the dashboard shows its graph, above the start
/// screen's categories and above a category's months. On by default and kept across launches in the app's defaults.
/// Server mode and phone mode, the samples and the tour follow it: `ContentView` reads it with
/// `@AppStorage(GraphSetting.key)` and hands it to the dashboard; the tour takes it when it starts.
nonisolated enum GraphSetting {
    static let key = "aresium.graph"
    static let shownByDefault = true

    /// The saved choice, or on while none is saved.
    static func isShown(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) == nil ? shownByDefault : defaults.bool(forKey: key)
    }
}
