import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Aresium

/// Brief 46: Settings → Messages and the offer after the first import (the screens' logic), and red mode's graph line.
/// The scheduling itself is brief 45's (`MessageTests`); these use its `FakeMessageCenter`. Made-up files only.
@MainActor
struct MessageScreensTests {
    private func model(center: FakeMessageCenter = FakeMessageCenter()) -> AresiumMessages {
        let defaults = UserDefaults(suiteName: "message-screens-" + UUID().uuidString)!
        let model = AresiumMessages(defaults: defaults, center: center)
        model.setContext(MessageContext(phone: true, language: .english))
        return model
    }

    private func preferences(enabled: Bool = true, reminder: Bool = true, review: Bool = true) -> MessagePreferences {
        MessagePreferences(enabled: enabled, importReminder: reminder, monthReview: review)
    }

    // MARK: the row on the Settings list

    @Test func theRowSaysOffOrWhatIsOn() {
        let allowed = MessageAuthorization.allowed
        #expect(MessageWording.state(MessagePreferences(), authorization: .notAsked, language: .english) == "Off")
        #expect(MessageWording.state(preferences(), authorization: allowed, language: .english) == "On")
        #expect(MessageWording.state(preferences(review: false), authorization: allowed, language: .english) == "Reminder only")
        #expect(MessageWording.state(preferences(reminder: false), authorization: allowed, language: .english) == "Review only")
        #expect(MessageWording.state(preferences(reminder: false, review: false), authorization: allowed,
                                     language: .english) == "None chosen")
        // iOS has them off: nothing comes, whatever is chosen. Off stays Off (nothing was asked of iOS for it).
        #expect(MessageWording.state(preferences(), authorization: .denied, language: .english) == "Off in iOS")
        #expect(MessageWording.state(preferences(enabled: false), authorization: .denied, language: .english) == "Off")
        // Turned on before iOS answered (or asking failed): what is chosen.
        #expect(MessageWording.state(preferences(), authorization: .notAsked, language: .english) == "On")
    }

    @Test func theRowInGerman() {
        let allowed = MessageAuthorization.allowed
        #expect(MessageWording.state(MessagePreferences(), authorization: allowed, language: .german) == "Aus")
        #expect(MessageWording.state(preferences(), authorization: allowed, language: .german) == "An")
        #expect(MessageWording.state(preferences(review: false), authorization: allowed, language: .german) == "Nur Erinnerung")
        #expect(MessageWording.state(preferences(reminder: false), authorization: allowed, language: .german) == "Nur Rückblick")
        #expect(MessageWording.state(preferences(reminder: false, review: false), authorization: allowed,
                                     language: .german) == "Keine gewählt")
        #expect(MessageWording.state(preferences(), authorization: .denied, language: .german) == "In iOS aus")
    }

    @Test func theRowFollowsTheModel() async {
        let center = FakeMessageCenter()
        await center.permission(.notAsked, answer: false)
        let model = model(center: center)
        #expect(MessageWording.state(model.preferences, authorization: model.authorization, language: .english) == "Off")
        model.setEnabled(true)                  // iOS asks; the person says Don't Allow
        await model.idle()
        #expect(model.authorization == .denied)
        #expect(MessageWording.state(model.preferences, authorization: model.authorization, language: .english) == "Off in iOS")
        #expect(model.preferences.importReminder && model.preferences.monthReview, "the switches keep what was chosen")
    }

    // MARK: the page's words and time

    @Test func intervalsOfferLineAndNote() {
        #expect(MessageInterval.allCases.map { MessageWording.interval($0, language: .english) }
                == ["Every week", "Every 2 weeks", "Every month"])
        #expect(MessageInterval.allCases.map { MessageWording.interval($0, language: .german) }
                == ["Jede Woche", "Alle 2 Wochen", "Jeden Monat"])
        #expect(MessageWording.offerLine(.fortnight, language: .english)
                == "A reminder every 2 weeks after your last import, and a review of last month on the 3rd.")
        #expect(MessageWording.offerLine(.week, language: .english).contains("every week"))
        #expect(MessageWording.offerLine(.month, language: .german).hasPrefix("Jeden Monat"))
        let note = MessageWording.note(lockOn: false, language: .english)
        #expect(note == "These messages are made on this iPhone. Nothing is sent anywhere.")
        #expect(MessageWording.note(lockOn: true, language: .english)
                == note + " While the lock is on, they show no numbers.")
    }

    @Test func theTimePickerKeepsHourAndMinuteOnly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        // The last Sunday of October: the clocks go back, yet the picker shows the chosen wall-clock time.
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 9))!
        var chosen = MessagePreferences(enabled: true, interval: .week)
        chosen.hour = 7
        chosen.minute = 45
        let shown = MessageTime.date(of: chosen, on: day, calendar: calendar)
        #expect(calendar.dateComponents([.hour, .minute], from: shown) == DateComponents(hour: 7, minute: 45))
        let picked = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 21, minute: 5))!
        let changed = MessageTime.setting(picked, in: chosen, calendar: calendar)
        #expect(changed.hour == 21 && changed.minute == 5)
        #expect(changed.enabled && changed.interval == .week && changed.importReminder && changed.monthReview)
    }

    // MARK: when the offer shows

    @Test func theOfferWaitsForEverythingElse() {
        let free = ReminderOffer.Moment(ready: true)
        #expect(ReminderOffer.shows(free))
        #expect(!ReminderOffer.shows(ReminderOffer.Moment()))
        // Brief 99: the quick sort's offer (or its flow) goes first. Brief 215: not in the opening of the app whose
        // import readied it.
        for blocked: WritableKeyPath<ReminderOffer.Moment, Bool> in [\.tour, \.locked, \.importing, \.picker, \.result,
                                                                       \.window, \.quickSort, \.firstOpening] {
            var moment = free
            moment[keyPath: blocked] = true
            #expect(!ReminderOffer.shows(moment))
        }
    }

    /// The person's phone store without categories, its dashboard with messages, and imports, as the app wires them.
    private struct Setup {
        let phone: PhoneBackend
        let dashboard: DashboardStore
        let imports: ImportStore
        let messages: AresiumMessages
        let center: FakeMessageCenter

        var offers: Bool {
            ReminderOffer.shows(ReminderOffer.Moment(messages: messages, imports: imports, tour: false, locked: false,
                                                     window: false))
        }
    }

    private func setup(chosen: [String] = [], outbox: BankOutbox? = nil) async throws -> Setup {
        let transport = RoutedTransport()
        let session = await PhoneTest.session(nil, transport: transport)
        let phone = try await PhoneTest.backend(chosen: chosen)
        let dashboard = DashboardStore(session: session, backend: phone)
        let center = FakeMessageCenter()
        await center.permission(.notAsked, answer: true)
        let messages = model(center: center)
        messages.setPhoneMode(true, ledger: phone.ledger)
        dashboard.messages = messages
        let imports = ImportStore(dashboard: dashboard, background: PhoneActivity(), outbox: outbox)
        return Setup(phone: phone, dashboard: dashboard, imports: imports, messages: messages, center: center)
    }

    @Test func theOfferComesAfterTheCategoryPickerAndTheResultOnce() async throws {
        let s = try await setup()
        #expect(!s.offers, "nothing imported yet")
        s.imports.debugImport([ImportThenCategoriesTests.bankFile])
        await s.imports.importPendingFiles()
        #expect(s.messages.shouldOfferReminder)
        // The category picker after the first import, with the result waiting under it: not now.
        #expect(s.imports.asksForCategories && !s.offers)
        await s.imports.categoriesClosed()?.value
        // The result line, counted again: not with it either.
        #expect(s.imports.banner != nil && !s.offers)
        s.imports.close()
        // Brief 215 changed the moment on purpose (the first-run review's finding 11): after them it waits for the next
        // opening of the app, so the first minute asks two things at most.
        #expect(!s.offers && s.messages.offerWaitsForNextOpening, "not in the opening of the first import")
        s.messages.appOpenedAgain()
        #expect(s.offers, "after them, the next time Aresium is opened")
        // Not now answers it for good: the next import that adds payments offers nothing.
        s.messages.declineReminderOffer()
        #expect(!s.offers && !s.messages.preferences.enabled)
        s.imports.debugImport([PhoneTest.vrBank([("09.10.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -990)],
                                                name: "more.csv")])
        await s.imports.importPendingFiles()
        s.imports.categoriesClosed()
        s.imports.dismiss()
        #expect(s.phone.summary.payments == 5 && !s.offers)
        #expect(await s.center.permissionRequests == 0, "Not now asks iOS nothing")
    }

    @Test func theOfferNeverShowsWithTheSendCard() async throws {
        let formats = BankOutbox(file: PhoneTest.storage().bankOutboxURL,
                                 api: BankOutboxAPI(transport: RoutedTransport()), appVersion: "1.0 (7)")
        let s = try await setup(chosen: ["groceries"], outbox: formats)
        // An unknown bank's file, confirmed in the file check window: the result offers to send its format.
        s.imports.debugImport([try PhoneTest.fixture("unknown-fiktivbank.csv")])
        await s.imports.importPendingFiles()
        let check = FileCheckModel(request: try #require(s.imports.layoutRequest), phone: s.phone, imports: s.imports)
        #expect(await check.yes())
        await s.imports.importPendingFiles()
        #expect(s.imports.banner?.share != nil && !s.imports.asksForCategories)
        #expect(s.messages.shouldOfferReminder && !s.offers, "the send card first")
        // Its Not now closes the result: the offer follows in its place, the next time Aresium is opened (brief 215
        // moved it there on purpose: the first import's opening asks two things at most).
        s.imports.close()
        #expect(!s.offers)
        s.messages.appOpenedAgain()
        #expect(s.offers)
    }

    // MARK: Turn on

    @Test func turnOnSetsBothMessagesAndKeepsHowOftenAndTheTime() async throws {
        let s = try await setup()
        // Chosen before and turned off again: both messages off, every week at 07:30.
        var earlier = MessagePreferences(enabled: false, importReminder: false, interval: .week, monthReview: false)
        earlier.hour = 7
        earlier.minute = 30
        s.messages.setPreferences(earlier)
        s.imports.debugImport([ImportThenCategoriesTests.bankFile])
        await s.imports.importPendingFiles()
        await s.imports.categoriesClosed()?.value
        s.imports.close()
        s.messages.appOpenedAgain()          // brief 215: the offer waits for the next opening of the app
        #expect(s.offers)
        s.messages.acceptReminderOffer()
        await s.messages.idle()
        let now = s.messages.preferences
        #expect(now.enabled && now.importReminder && now.monthReview)
        #expect(now.interval == .week && now.hour == 7 && now.minute == 30)
        // iOS was asked once, allowed, and the reminders are planned from the import.
        #expect(await s.center.permissionRequests == 1)
        #expect(s.messages.authorization == .allowed)
        #expect(await s.center.pendingIdentifiers().contains("aresium.reminder.1"))
        // Answered for good: neither now nor after turning Messages off again and importing more.
        #expect(!s.offers)
        s.messages.setEnabled(false)
        s.imports.debugImport([PhoneTest.vrBank([("10.10.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -455)],
                                                name: "later.csv")])
        await s.imports.importPendingFiles()
        s.imports.categoriesClosed()
        s.imports.dismiss()
        #expect(!s.messages.shouldOfferReminder && !s.offers)
    }

    @Test func turnedOnKeepsEverythingButTheThreeSwitches() {
        var before = MessagePreferences(enabled: false, importReminder: false, interval: .month, monthReview: false)
        before.hour = 20
        let after = ReminderOffer.turnedOn(before)
        #expect(after == MessagePreferences(enabled: true, importReminder: true, interval: .month, monthReview: true,
                                            hour: 20, minute: 0))
    }

    // MARK: red mode's graph line

    /// On the red wall the expense line was the website's black (about 1.3:1): it now reads as the category graphs'
    /// lines do, at least 3:1 (WCAG's minimum for graphics) against the wall's ground and its lightest stop. Income
    /// keeps its green, which reads there too.
    @Test func redModesGraphLinesReadOnTheRedWall() {
        let red = Palette(theme: .red)
        let wall = [red.background, Color(hex: "520A1A")]
        for ground in wall {
            #expect(contrast(red.expense, ground) >= 3)
            #expect(contrast(red.income, ground) >= 3)
        }
        // Light and dark keep their colours.
        #expect(hex(Palette(theme: .dark).expense) == 0xFF2D4B)
        #expect(hex(Palette(theme: .light).expense) == 0xE11030)
    }

    private func components(_ color: Color) -> (Double, Double, Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }

    private func hex(_ color: Color) -> UInt32 {
        let (r, g, b) = components(color)
        func byte(_ value: Double) -> UInt32 { UInt32((value * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    private func contrast(_ a: Color, _ b: Color) -> Double {
        func luminance(_ color: Color) -> Double {
            let (r, g, b) = components(color)
            func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        let (high, low) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (high + 0.05) / (low + 0.05)
    }
}
