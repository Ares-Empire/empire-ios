import Foundation

/// The app's three looks. Shared with the widget, which shows the same one.
nonisolated enum AppTheme: String, CaseIterable, Codable {
    case dark, light, red
}
