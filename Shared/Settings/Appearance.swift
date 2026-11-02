import SwiftUI
import UIKit

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

extension Appearance {
    /// UIKit's look for a window or a view controller; `.unspecified` follows the iPhone (or the app it is shown in).
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .iPhone: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The app's appearance for its share extension (brief 100). The extension runs in its own process with its own
/// defaults, which iOS starts in the iPhone's look, so it would not see the choice made in the app. The app copies its
/// choice into an App Group it shares with the extension (at launch and on each change, `AppRoot(extensionLook:)`);
/// the extension sets it on its view controller. Widgets do not read it: they follow the home screen ("Light mode").
nonisolated struct ExtensionAppearance {
    /// The App Group's defaults; nil when the entitlement is missing (then the extension follows the iPhone).
    let defaults: UserDefaults?
    /// The app's bundle id, so apps sharing a group keep their choices apart.
    let app: String

    private var key: String { "appearance." + app }

    /// The app's choice, as the extension reads it; like the iPhone when the app has published none.
    var choice: Appearance { Appearance(saved: defaults?.string(forKey: key)) }

    /// The app: tells the extension its choice ("like the iPhone" removes it). Writes only when it changed.
    func publish(_ choice: Appearance) {
        guard let defaults, self.choice != choice else { return }
        if choice == .iPhone { defaults.removeObject(forKey: key) } else { defaults.set(choice.rawValue, forKey: key) }
    }
}
