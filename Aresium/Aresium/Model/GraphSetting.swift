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

/// Settings → Dashboard → "Graph moves away when scrolling" (brief 56, Patrik 2026-10-31: "When scrolling up in the
/// categories under the graph, the graph should move up so categories get more space"): the graph stands at the top of
/// the list it belongs to (the start screen's and a month's categories, a category's months) and goes up with it, so the
/// rows get the screen; scrolling back to the top brings it back. On by default; off, the graph stays above the list as
/// before. Kept like the Graph setting, in the app's defaults (not in the export); the tour takes it when it starts.
nonisolated enum GraphMotionSetting {
    static let key = "aresium.graphMoves"
    static let movesByDefault = true

    /// The saved choice, or on while none is saved.
    static func moves(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) == nil ? movesByDefault : defaults.bool(forKey: key)
    }
}
