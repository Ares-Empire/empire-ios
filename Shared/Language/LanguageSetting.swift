import Foundation

/// The app's own language, chosen in its Settings → Language: the `AppleLanguages` list in the app's own defaults.
/// iOS's Settings → Apps → the app → Language keeps the same setting there (it writes `[chosen, …]` and removes it when
/// the iPhone's own language is picked), so the two always agree. On iOS 27 that entry shows only while the iPhone lists
/// two or more languages (tested 2026-10-24), which is why every app offers the choice in its own Settings.
/// iOS reads the setting when it starts the app; a choice made in the app switches it at once (`AppRoot`).
nonisolated struct LanguageSetting {
    static let key = "AppleLanguages"

    let defaults: UserDefaults
    /// The app's own defaults domain (its bundle id), read on its own so the iPhone's list never counts as a choice.
    let domain: String
    /// The languages the app is asked for (`Locale.preferredLanguages`): the app's own choice first while there is one,
    /// otherwise the iPhone's list (it follows a change of the app's own defaults at once; tested 2026-10-25).
    var preferredLanguages: () -> [String] = { Locale.preferredLanguages }

    /// This app's setting.
    static var standard: LanguageSetting {
        LanguageSetting(defaults: .standard, domain: Bundle.main.bundleIdentifier ?? "")
    }

    /// The language chosen for this app; nil when it follows the iPhone.
    var choice: AppLanguage? {
        guard let languages = ownLanguages, let first = languages.first else { return nil }
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

    /// The language the app shows with this choice: the choice itself, or for "like the iPhone" the iPhone's.
    func language(for choice: AppLanguage?) -> AppLanguage {
        choice ?? iPhoneLanguage
    }

    /// The language the app shows when it follows the iPhone. An app cannot read the iPhone's list while it has a
    /// language of its own (iOS gives it the app's choice instead, and the global defaults are closed to it), so the
    /// app's own setting is set aside for the moment of the reading and put back at once.
    var iPhoneLanguage: AppLanguage {
        guard let own = ownLanguages else { return AppLanguage.preferred(preferredLanguages()) }
        defaults.removeObject(forKey: Self.key)
        let languages = preferredLanguages()
        defaults.set(own, forKey: Self.key)
        return AppLanguage.preferred(languages)
    }

    private var ownLanguages: [String]? {
        defaults.persistentDomain(forName: domain)?[Self.key] as? [String]
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
