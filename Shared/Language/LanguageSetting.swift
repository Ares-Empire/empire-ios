import Foundation

/// The app's own language, chosen in its Settings → Language: the `AppleLanguages` list in the app's own defaults.
/// iOS's Settings → Apps → the app → Language keeps the same setting there (it writes `[chosen, …]` and removes it when
/// the iPhone's own language is picked), so the two always agree. On iOS 27 that entry shows only while the iPhone lists
/// two or more languages (tested 2026-10-24), which is why every app offers the choice in its own Settings.
/// iOS reads the setting when the app starts: a change shows once the app has been closed and opened again.
nonisolated struct LanguageSetting {
    static let key = "AppleLanguages"

    let defaults: UserDefaults
    /// The app's own defaults domain (its bundle id), read on its own so the iPhone's list never counts as a choice.
    let domain: String
    /// The iPhone's languages, most preferred first; nil when they cannot be read.
    let phoneLanguages: () -> [String]?

    /// This app's setting.
    static var standard: LanguageSetting {
        LanguageSetting(defaults: .standard, domain: Bundle.main.bundleIdentifier ?? "") {
            UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[key] as? [String]
        }
    }

    /// The language chosen for this app; nil when it follows the iPhone.
    var choice: AppLanguage? {
        guard let languages = defaults.persistentDomain(forName: domain)?[Self.key] as? [String],
              let first = languages.first else { return nil }
        return AppLanguage.preferred([first])
    }

    /// Saves the choice. nil ("like the iPhone") removes the app's own setting, as iOS does for the iPhone's language.
    func choose(_ language: AppLanguage?) {
        if let language {
            defaults.set([language.code], forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }

    /// What "like the iPhone" means right now; nil when the iPhone's languages cannot be read.
    var phoneLanguage: AppLanguage? { phoneLanguages().map(AppLanguage.preferred) }

    /// The language the app shows after its next start; nil when that depends on an unreadable iPhone list.
    var nextLanguage: AppLanguage? { choice ?? phoneLanguage }

    /// Whether to say that the app switches when it is next opened: its next language differs from the one it shows
    /// (`current`). When that cannot be told, after any change made on the page (`changedHere`).
    func announcesSwitch(current: AppLanguage, changedHere: Bool) -> Bool {
        guard let next = nextLanguage else { return changedHere }
        return next != current
    }
}

extension AppLanguage {
    /// The first of the given languages that the apps have, German or English; English when neither is listed
    /// (ares-empire/docs/LANGUAGES.md: German when the phone puts German before English, otherwise English).
    nonisolated static func preferred(_ languages: [String]) -> AppLanguage {
        for language in languages {
            if language.hasPrefix("de") { return .german }
            if language.hasPrefix("en") { return .english }
        }
        return .english
    }

    /// The language's name in that language, as language lists show it: "English", "Deutsch".
    nonisolated var name: String { self == .german ? "Deutsch" : "English" }
}
