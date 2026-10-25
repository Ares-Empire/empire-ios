import SwiftUI

/// The app's appearance, chosen in Settings → General → Appearance (Patrik, 2026-10-24: light mode as part of the
/// standard design): like the iPhone (the default), light or dark. Each app keeps its own choice, as with the
/// language, in its own defaults. The root applies it (`AppRoot`) and the shared colours follow (`Ink`, `AppAccent`).
/// DEBUG screenshots: `-appearance light|dark` (launch arguments are read as defaults, so this overrides the choice).
nonisolated enum Appearance: String, CaseIterable, Sendable {
    case iPhone, light, dark

    static let key = "appearance"

    /// The saved choice; like the iPhone when nothing (or something unknown) is saved.
    init(saved: String?) {
        self = saved.flatMap(Appearance.init(rawValue:)) ?? .iPhone
    }

    /// What the window is told to show; nil follows the iPhone, also when it switches by itself in the evening.
    var colorScheme: ColorScheme? {
        switch self {
        case .iPhone: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// The choice's name, as the Settings row and page show it.
    var name: String {
        switch self {
        case .iPhone: String(localized: LocalizedStringResource("Like the iPhone", table: "Shared", locale: .appLanguage))
        case .light: String(localized: LocalizedStringResource("Light", table: "Shared", locale: .appLanguage,
                                                               comment: "Appearance: always light"))
        case .dark: String(localized: LocalizedStringResource("Dark", table: "Shared", locale: .appLanguage,
                                                              comment: "Appearance: always dark"))
        }
    }

    /// The fixed choice that shows the other look than the one on screen now (Aresium's sun button).
    static func toggled(from shown: ColorScheme) -> Appearance {
        shown == .dark ? .light : .dark
    }
}
