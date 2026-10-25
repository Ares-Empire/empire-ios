import Foundation
import Testing
import UserNotifications
@testable import Empire

/// Switching the language while the app runs (Shared/Language): what a tap on Settings → Language does, the
/// confirmation's words, the widget's copy of the choice, the launch arguments after a restart, and the app's own
/// lookups in both languages.
struct LanguageSwitchTests {
    // MARK: a tap on a row

    @Test func theChosenRowDoesNothing() {
        #expect(LanguageTap.tap(.english, choice: .english, shown: .english, iPhone: { .german }) == .keep)
        #expect(LanguageTap.tap(nil, choice: nil, shown: .german, iPhone: { .german }) == .keep)
    }

    @Test func anotherLanguageAsksFirst() {
        #expect(LanguageTap.tap(.english, choice: nil, shown: .german, iPhone: { .german })
                == .confirm(LanguageSwitch(choice: .english, language: .english)))
        #expect(LanguageTap.tap(.german, choice: .english, shown: .english, iPhone: { .english })
                == .confirm(LanguageSwitch(choice: .german, language: .german)))
        // "Like the iPhone" brings the iPhone's language.
        #expect(LanguageTap.tap(nil, choice: .english, shown: .english, iPhone: { .german })
                == .confirm(LanguageSwitch(choice: nil, language: .german)))
    }

    @Test func theSameLanguageIsSavedWithoutAsking() {
        #expect(LanguageTap.tap(.german, choice: nil, shown: .german, iPhone: { .german })
                == .save(LanguageSwitch(choice: .german, language: .german)))
        #expect(LanguageTap.tap(nil, choice: .german, shown: .german, iPhone: { .german })
                == .save(LanguageSwitch(choice: nil, language: .german)))
    }

    @Test func readsTheIPhonesLanguageOnlyForThatRow() {
        var reads = 0
        _ = LanguageTap.tap(.english, choice: nil, shown: .german, iPhone: { reads += 1; return .german })
        _ = LanguageTap.tap(.german, choice: .german, shown: .german, iPhone: { reads += 1; return .german })
        #expect(reads == 0)
        _ = LanguageTap.tap(nil, choice: .english, shown: .english, iPhone: { reads += 1; return .german })
        #expect(reads == 1)
    }

    // MARK: the confirmation

    /// In the language it switches to, whichever the app shows now (the test runs in English, `AppLanguage.$scoped`
    /// puts the app in the other language).
    @Test(arguments: [AppLanguage.english, .german]) func asksInTheLanguageItSwitchesTo(shown: AppLanguage) {
        AppLanguage.$scoped.withValue(shown) {
            let english = LanguageSwitch(choice: .english, language: .english)
            #expect(english.title == "Switch to English?")
            #expect(english.message(app: "Aresus") == "Aresus restarts in English.")
            #expect(english.confirm == "Restart")
            let german = LanguageSwitch(choice: nil, language: .german)
            #expect(german.title == "Auf Deutsch umstellen?")
            #expect(german.message(app: "Arestemis") == "Arestemis startet auf Deutsch neu.")
            #expect(german.confirm == "Neu starten")
        }
    }

    // MARK: the widget

    private func widgetLanguage() -> (WidgetLanguage, UserDefaults) {
        let suite = "widget-language-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (WidgetLanguage(defaults: defaults, app: "de.ares-empire.aresus"), defaults)
    }

    @Test func theWidgetReadsTheAppsChoice() {
        let (widget, defaults) = widgetLanguage()
        var reloads = 0
        #expect(widget.choice == nil)
        #expect(widget.language == AppLanguage.launched)            // no choice: the iPhone's
        widget.publish(.german) { reloads += 1 }
        #expect(widget.choice == .german && widget.language == .german && reloads == 1)
        widget.publish(.german) { reloads += 1 }                   // unchanged (e.g. the next launch): no reload
        #expect(reloads == 1)
        widget.publish(nil) { reloads += 1 }                       // like the iPhone
        #expect(widget.choice == nil && widget.language == AppLanguage.launched && reloads == 2)
        // Apps sharing the App Group keep their choices apart.
        let other = WidgetLanguage(defaults: defaults, app: "de.ares-empire.arestemis")
        widget.publish(.english) { reloads += 1 }
        #expect(other.choice == nil && widget.choice == .english)
    }

    @Test func noAppGroupMeansTheWidgetFollowsTheIPhone() {
        let widget = WidgetLanguage(defaults: nil, app: "de.ares-empire.aresus")
        var reloads = 0
        widget.publish(.german) { reloads += 1 }
        #expect(widget.choice == nil && widget.language == AppLanguage.launched && reloads == 0)
    }

    // MARK: launch arguments after a restart

    @Test func aRestartDropsTheArgumentsThatOpenAScreen() {
        let launched = ["/path/Aresus", "-sampleData", "-sampleAllGood", "-openSheet", "settings", "-openLanguage",
                        "-tab", "aresync", "-scrollToEnd", "-openProvince", "aresium", "-switchLanguage", "en",
                        "-AppleLanguages", "(de)", "-sampleVaultFile", "/tmp/vault.json"]
        #expect(LaunchArguments.afterRestart(launched)
                == ["/path/Aresus", "-sampleData", "-sampleAllGood", "-AppleLanguages", "(de)",
                    "-sampleVaultFile", "/tmp/vault.json"])
        #expect(LaunchArguments.afterRestart(["/path/Aresus", "-tab"]) == ["/path/Aresus"])     // a value missing
    }

    // MARK: the app's own lookups

    /// The app module's lookups, in each language (the suite runs in English; with `-testLanguage de` the other way).
    @Test(arguments: [AppLanguage.english, .german]) func lookupsFollowTheLanguageShown(language: AppLanguage) {
        AppLanguage.$scoped.withValue(language) {
            let german = language == .german
            #expect(String(localized: "Approvals") == (german ? "Freigaben" : "Approvals"))
            #expect(String(localized: "Approvals, \(1400) pending")
                    == (german ? "Freigaben, 1.400 offen" : "Approvals, 1,400 pending"))
            // With a comment: Foundation's lookup with the app language's bundle and locale.
            #expect(EmpireStyle.statusWord("CONQUERED") == (german ? "EROBERT" : "CONQUERED"))
            // A Shared table (the Settings section headings).
            #expect(String(localized: LocalizedStringResource("Help", table: "Shared", locale: .appLanguage))
                    == (german ? "Hilfe" : "Help"))
            #expect(SupportKind.idea.title == (german ? "Idee oder Wunsch" : "Idea or wish"))   // with a comment
            #expect(HTTPError.unauthorized.localizedDescription.hasPrefix(german ? "Deine Anmeldung" : "Your session"))
            #expect(LegalPage.privacy.url().lastPathComponent == (german ? "datenschutz" : "privacy"))
        }
    }
}
