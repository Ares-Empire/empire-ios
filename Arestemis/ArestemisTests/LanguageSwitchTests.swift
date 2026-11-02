import Foundation
import Testing
import UserNotifications
@testable import Arestemis

/// The app's texts follow Settings → Language while it runs (Shared/Language): asked in both languages.
struct LanguageSwitchTests {
    @Test(arguments: [AppLanguage.english, .german]) func modelTextsFollowTheLanguageShown(language: AppLanguage) {
        AppLanguage.$scoped.withValue(language) {
            let german = language == .german
            #expect(MatchFilter.saved.title == (german ? "Gespeichert" : "Saved"))
            // The notification actions' titles, set again when the app restarts in the other language.
            // (The categories are a set: the flat's is picked by its name.)
            let categories = MatchNotification.categories
            #expect(categories.first { $0.identifier == MatchNotification.category }?.actions.first?.title
                    == (german ? "Angebot öffnen" : "Open listing"))
            #expect(categories.first { $0.identifier == MatchNotification.watchCategory }?.actions.first?.title
                    == (german ? "Seite öffnen" : "Open page"))
            #expect(Format.money(1400) == (german ? "1.400\u{a0}€" : "€1,400"))
        }
    }
}
