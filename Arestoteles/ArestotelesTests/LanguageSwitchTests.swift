import Foundation
import Testing
@testable import Arestoteles

/// The app's texts follow Settings → Language while it runs (Shared/Language): asked in both languages.
struct LanguageSwitchTests {
    @Test(arguments: [AppLanguage.english, .german]) func modelTextsFollowTheLanguageShown(language: AppLanguage) {
        AppLanguage.$scoped.withValue(language) {
            let german = language == .german
            #expect(VaultStore.offlineMessage.hasPrefix(german ? "Der Server ist nicht erreichbar" : "The server cannot"))
            #expect(Format.year(-44) == (german ? "44 v. Chr." : "44 BCE"))
        }
    }
}
