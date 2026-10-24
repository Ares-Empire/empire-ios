import Foundation
import Testing
@testable import Empire

/// The shared Settings screen's logic (Shared/Language/LanguageSetting.swift, Shared/Settings/SettingsInfo.swift) and the
/// account email it shows (`EmpireSession.email`).
@MainActor
struct SettingsTests {
    /// A setting on its own defaults suite (the suite name is its domain, like the bundle id in the app).
    private func makeSetting(phone: [String]? = ["de-DE", "en"]) -> (LanguageSetting, UserDefaults) {
        let domain = "settings-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        return (LanguageSetting(defaults: defaults, domain: domain, phoneLanguages: { phone }), defaults)
    }

    // MARK: language

    @Test func followsTheIPhoneUntilALanguageIsChosen() {
        let (setting, defaults) = makeSetting()
        #expect(setting.choice == nil)
        setting.choose(.english)
        #expect(setting.choice == .english)
        #expect(defaults.persistentDomain(forName: setting.domain)?[LanguageSetting.key] as? [String] == ["en"])
        setting.choose(.german)
        #expect(setting.choice == .german)
        setting.choose(nil)                         // like the iPhone: the app's own setting is gone, as in iOS
        #expect(setting.choice == nil)
        #expect(defaults.persistentDomain(forName: setting.domain)?[LanguageSetting.key] == nil)
    }

    @Test func readsTheListIOSSettingsWrites() {
        let (setting, defaults) = makeSetting()
        defaults.set(["en", "de"], forKey: LanguageSetting.key)        // Settings → Apps → the app → Language: English
        #expect(setting.choice == .english)
        defaults.set(["de-DE", "en"], forKey: LanguageSetting.key)
        #expect(setting.choice == .german)
    }

    @Test func likeTheIPhoneIsItsFirstLanguageTheAppsHave() {
        #expect(AppLanguage.preferred(["de-DE", "en"]) == .german)
        #expect(AppLanguage.preferred(["fr-FR", "de", "en"]) == .german)
        #expect(AppLanguage.preferred(["en-GB", "de"]) == .english)
        #expect(AppLanguage.preferred(["fr", "it"]) == .english)    // English for every other language
        #expect(AppLanguage.preferred([]) == .english)
        #expect(makeSetting(phone: ["fr", "de"]).0.phoneLanguage == .german)
        #expect(makeSetting(phone: nil).0.phoneLanguage == nil)
    }

    @Test func saysTheAppSwitchesOnlyWhenItsNextLanguageDiffers() {
        let (setting, _) = makeSetting(phone: ["de-DE"])
        #expect(!setting.announcesSwitch(current: .german, changedHere: false))   // following a German iPhone
        setting.choose(.english)
        #expect(setting.nextLanguage == .english)
        #expect(setting.announcesSwitch(current: .german, changedHere: true))
        setting.choose(.german)                     // back to what it shows: nothing switches
        #expect(!setting.announcesSwitch(current: .german, changedHere: true))
        setting.choose(nil)
        #expect(setting.announcesSwitch(current: .english, changedHere: true))   // shows English now, German next
    }

    @Test func withAnUnreadableIPhoneListOnlyAChangeAnnouncesASwitch() {
        let (setting, _) = makeSetting(phone: nil)
        #expect(setting.nextLanguage == nil)
        #expect(!setting.announcesSwitch(current: .german, changedHere: false))
        #expect(setting.announcesSwitch(current: .german, changedHere: true))
        setting.choose(.english)
        #expect(!setting.announcesSwitch(current: .english, changedHere: true))   // chosen = shown: no switch
    }

    @Test func namesEachLanguageInItself() {
        #expect(AppLanguage.german.name == "Deutsch")
        #expect(AppLanguage.english.name == "English")
    }

    // MARK: about

    @Test func opensTheLegalPagesInTheAppsLanguage() {
        #expect(LegalPage.privacy.url(in: .german).absoluteString == "https://www.ares-empire.de/datenschutz")
        #expect(LegalPage.privacy.url(in: .english).absoluteString == "https://www.ares-empire.de/privacy")
        #expect(LegalPage.imprint.url(in: .german).absoluteString == "https://www.ares-empire.de/impressum")
        #expect(LegalPage.imprint.url(in: .english).absoluteString == "https://www.ares-empire.de/imprint")
    }

    @Test func showsVersionAndBuild() {
        #expect(AppVersion.text(["CFBundleShortVersionString": "1.0", "CFBundleVersion": "12"]) == "1.0 (12)")
        #expect(AppVersion.text(["CFBundleShortVersionString": "1.0"]) == "1.0")
        #expect(AppVersion.text(nil) == "?")
    }

    @Test func unwrapsALicenceIntoParagraphsAndHeadings() {
        let text = "Copyright 2020 The Authors\r\n\r\n-----\r\nSIL OPEN FONT LICENSE Version 1.1\r\n-----\r\n\r\n"
            + "PREAMBLE\r\nThe goals of the\r\nlicense.\r\n\r\nDISCLAIMER\r\nTHE FONT SOFTWARE IS PROVIDED \"AS IS\",\r\nWITHOUT WARRANTY.\r\n"
        #expect(LicenceParagraph.paragraphs(text) == [
            LicenceParagraph(text: "Copyright 2020 The Authors", isHeading: false),
            LicenceParagraph(text: "SIL OPEN FONT LICENSE Version 1.1", isHeading: false),
            LicenceParagraph(text: "PREAMBLE", isHeading: true),
            LicenceParagraph(text: "The goals of the license.", isHeading: false),
            LicenceParagraph(text: "DISCLAIMER", isHeading: true),
            LicenceParagraph(text: "THE FONT SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY.", isHeading: false),
        ])
    }

    @Test func shipsBothFontLicences() throws {
        for font in BundledFont.allCases {
            let licence = try #require(font.licence())
            let paragraphs = LicenceParagraph.paragraphs(licence)
            #expect(paragraphs.first?.text.hasPrefix("Copyright") == true)
            #expect(paragraphs.contains { $0.isHeading && $0.text == "PERMISSION & CONDITIONS" })
        }
    }

    // MARK: account

    @Test func keepsTheAccountsEmailUntilLogout() async {
        let auth = EmpireFakeTransport(data: Data("""
        {"token":"fictional-token","record":{"id":"fictional-account","approved":true,"services":["empire"],
         "email":"member@example.invalid"}}
        """.utf8))
        let session = await empireSession(auth: auth)
        #expect(session.isSignedIn && session.email == "member@example.invalid")
        session.logOut()
        #expect(session.email == nil)
    }

    @Test func aLoginAnswerWithoutEmailStillLogsIn() async {
        let session = await empireSession()             // the shared fixture's record has no email
        #expect(session.isSignedIn && session.email == nil)
    }
}
