import Foundation

/// Aresium's three looks: light and dark (the app's appearance, Settings → Appearance) and red, its special mode over
/// either. The widgets show red too while it is on (`WidgetSnapshotStore.redMode`).
nonisolated enum AppTheme: String, CaseIterable, Codable {
    case dark, light, red
}
