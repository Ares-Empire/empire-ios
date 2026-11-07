import Foundation
import Testing
@testable import Aresium

/// Brief 215: what a new tester meets on the first run (`docs/reviews/2026-11-02-aresium-first-run.md`). Done with
/// nothing ticked asks to use the categories that fit (finding 1); while none is chosen the dashboard's card leads to
/// them and the quick sort waits; Current opens on last month in a month's first seven days, read with a fixed clock
/// (finding 2); the messages' offer waits for the next opening of the app (finding 11); Settings shows no sign-in while
/// signed out (finding 5); the running month's stretch is dashed (finding 12); the words in both languages (findings 3,
/// 7, 14). Made-up payments only; no test reads today's date.
@MainActor
@Suite(.serialized)
struct FirstRunTests {
    private let none = BackendAuth(token: nil)

    /// Made-up payments over three months, the newest on 1 and 2 November: the review's fresh export early in a month.
    /// 3 groceries (REWE), 2 rent (the landlord), 1 that fits no category.
    static let threeMonths = PhoneTest.vrBank([
        ("05.09.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -2345),
        ("01.10.2026", "Fiktiv Hausverwaltung", "Miete Oktober", -78000),
        ("12.10.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -1890),
        ("20.10.2026", "Fiktiv Laden", "Einkauf", -500),
        ("01.11.2026", "Fiktiv Hausverwaltung", "Miete November", -78000),
        ("02.11.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -1210),
    ], name: "three-months.csv")

    private final class Counter { var value = 0 }

    /// A clock the test moves (the app's is the iPhone's).
    private final class TestClock {
        var day: String
        init(_ day: String) { self.day = day }
        var now: Date { ReceiptDay.date(day)! }
    }

    /// The phone store with these categories and the three months imported (the engine's today 2 November), and a
    /// dashboard whose Current is read with `clock` (none: the newest month, as tests and the tour have it).
    private func dashboard(chosen: [String] = ["groceries", "rent"], clock: TestClock?) async throws
        -> (PhoneBackend, DashboardStore) {
        let phone = try await PhoneTest.backend(chosen: chosen)
        phone.today = { "2026-11-02" }
        _ = try await phone.importFiles([Self.threeMonths], auth: none)
        let store = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), backend: phone,
                                   clock: clock.map { clock in { clock.now } })
        await store.reload()
        #expect(store.error == nil)
        #expect(store.dashboard?.months.map(\.key) == ["2026-09", "2026-10", "2026-11"])
        return (phone, store)
    }

    // MARK: finding 2: which month Current shows

    @Test func theRuleOnItsOwn() {
        let months = ["2026-09", "2026-10", "2026-11"]
        // The 1st to the 7th of the running month: the month before.
        for day in ["2026-11-01", "2026-11-02", "2026-11-07"] {
            #expect(CurrentMonth.opening(months: months, openedOn: day) == "2026-10", "\(day)")
        }
        // From the 8th: the newest, as before.
        #expect(CurrentMonth.opening(months: months, openedOn: "2026-11-08") == "2026-11")
        #expect(CurrentMonth.opening(months: months, openedOn: "2026-11-30") == "2026-11")
        // The newest month is not the running one (nothing imported for it yet): the newest, a full month already.
        #expect(CurrentMonth.opening(months: ["2026-09", "2026-10"], openedOn: "2026-11-02") == "2026-10")
        #expect(CurrentMonth.opening(months: ["2026-08", "2026-09"], openedOn: "2026-11-02") == "2026-09")
        // No month before it in the data (a file of these two days only): the running month.
        #expect(CurrentMonth.opening(months: ["2026-11"], openedOn: "2026-11-02") == "2026-11")
        // Across the year.
        #expect(CurrentMonth.opening(months: ["2026-12", "2027-01"], openedOn: "2027-01-03") == "2026-12")
        #expect(CurrentMonth.monthBefore("2027-01") == "2026-12" && CurrentMonth.monthBefore("2026-11") == "2026-10")
        // No months, or no day: nothing to choose, or the newest.
        #expect(CurrentMonth.opening(months: [], openedOn: "2026-11-02") == nil)
        #expect(CurrentMonth.opening(months: months, openedOn: "") == "2026-11")
    }

    @Test func theOtherMonthIsOneTapAwayBothWays() {
        let months = ["2026-09", "2026-10", "2026-11"]
        // Opened on 2 November, Current shows October: the other is November; showing November, it is October.
        #expect(CurrentMonth.other(months: months, shown: "2026-10", openedOn: "2026-11-02") == "2026-11")
        #expect(CurrentMonth.other(months: months, shown: "2026-11", openedOn: "2026-11-02") == "2026-10")
        // From the 8th, November is shown by itself and there is no other.
        #expect(CurrentMonth.other(months: months, shown: "2026-11", openedOn: "2026-11-08") == nil)
        // An older month (a review message's) leads to the newest whatever the day; without a clock too.
        #expect(CurrentMonth.other(months: months, shown: "2026-09", openedOn: "2026-11-20") == "2026-11")
        #expect(CurrentMonth.other(months: months, shown: "2026-09", openedOn: nil) == "2026-11")
        #expect(CurrentMonth.other(months: months, shown: "2026-11", openedOn: nil) == nil)
    }

    @Test func currentOpensOnLastMonthInTheFirstDaysAndKeepsItWhileOpen() async throws {
        let clock = TestClock("2026-11-02")
        let (_, store) = try await dashboard(clock: clock)
        // The first look on 2 November after the import: October, a full month; November one tap away.
        #expect(store.openedOn == "2026-11-02")
        #expect(store.currentMonth?.key == "2026-10" && store.monthKey(.current) == "2026-10")
        #expect(store.rangeLabel(.current) == "Oct 2026")
        #expect(store.totals(.current)?.expense == store.dashboard?.byMonth["2026-10"]?.expense)
        #expect(store.route(category: "Groceries", side: .expenses, scope: .current).month == "2026-10")
        #expect(store.currentOtherMonth?.key == "2026-11")
        // Midnight passes into the 8th while the app is open: nothing moves, also when the dashboard is built again.
        clock.day = "2026-11-08"
        await store.reloadAfterTransactionChange()
        #expect(store.currentMonth?.key == "2026-10")
        // Back from the background: the day is read again, and from the 8th Current is the running month.
        store.appLeft()
        store.appReturned()
        #expect(store.openedOn == "2026-11-08" && store.currentMonth?.key == "2026-11")
        #expect(store.currentOtherMonth == nil)
        // Coming back without having left (inactive, as under Control Center) reads nothing again.
        clock.day = "2026-12-03"
        store.appReturned()
        #expect(store.openedOn == "2026-11-08")
    }

    @Test func theOtherMonthTappedHoldsUntilTheAppLeaves() async throws {
        let (_, store) = try await dashboard(clock: TestClock("2026-11-03"))
        #expect(store.currentMonth?.key == "2026-10")
        // "November so far": November, with October one tap back.
        store.showCurrent(month: "2026-11")
        #expect(store.currentMonth?.key == "2026-11" && store.currentOtherMonth?.key == "2026-10")
        await store.reloadAfterTransactionChange()
        #expect(store.currentMonth?.key == "2026-11", "a new dashboard keeps the choice")
        store.showCurrent(month: "2026-10")
        #expect(store.currentMonth?.key == "2026-10" && store.currentOtherMonth?.key == "2026-11")
        // Leaving the app ends any choice: the same rule again on return.
        store.showCurrent(month: "2026-11")
        store.appLeft()
        store.appReturned()
        #expect(store.currentMonth?.key == "2026-10")
    }

    @Test func aReviewAndTheWidgetsLinksStillOpenTheirMonth() async throws {
        let (_, store) = try await dashboard(clock: TestClock("2026-11-03"))
        // A month review's message (brief 46): its month.
        store.showReview(month: "2026-09")
        #expect(store.currentMonth?.key == "2026-09" && store.currentOtherMonth?.key == "2026-11")
        store.showReview(month: nil)
        #expect(store.currentMonth?.key == "2026-10")
        // A widget's link: the newest month, as the widget shows it.
        store.showNewestMonth()
        #expect(store.currentMonth?.key == "2026-11" && store.currentOtherMonth?.key == "2026-10")
    }

    @Test func withoutAClockCurrentIsTheNewestMonth() async throws {
        // Tests, the tour and previews pass no clock: whatever the day, as before brief 215.
        let (_, store) = try await dashboard(clock: nil)
        #expect(store.openedOn == nil && store.currentMonth?.key == "2026-11" && store.currentOtherMonth == nil)
    }

    @Test func theOtherMonthsWords() async throws {
        let (_, store) = try await dashboard(clock: TestClock("2026-11-02"))
        let november = try #require(store.dashboard?.months.last)
        let october = try #require(store.dashboard?.months.first { $0.key == "2026-10" })
        #expect(november.partial && !october.partial)
        #expect(CurrentMonthWording.other(november, language: .english) == "November so far")
        #expect(CurrentMonthWording.other(november, language: .german) == "November bisher")
        #expect(CurrentMonthWording.other(october, language: .english) == "October")
        #expect(CurrentMonthWording.other(october, language: .german) == "Oktober")
    }

    // MARK: finding 1: Done with nothing ticked

    @Test func doneWithNothingTickedAsksAndUseSortsIntoTheCategoriesThatFit() async throws {
        let (phone, store) = try await dashboard(chosen: [], clock: nil)
        let built = Counter()
        let picker = CategoryPickerModel(phone: phone) { built.value += 1; await store.reloadAfterTransactionChange() }
        await picker.load()
        #expect(picker.chosenCount == 0)
        // The rows' numbers: groceries and rent would get payments; those are the ones that fit.
        #expect(Set(picker.fitting) == ["groceries", "rent"])
        #expect(!(await picker.closes()), "Done asks first")
        #expect(picker.asksToUseFitting && picker.fittingAsked == 2)
        #expect(ChooseCategoriesWording.question(picker.fittingAsked, language: .english)
                == "Use the 2 categories that fit?")
        // Use: both ticked, the payments sorted, the dashboard built again; the picker may close.
        #expect(await picker.useFitting())
        #expect(Set(phone.summary.chosen.map(\.id)) == ["groceries", "rent"])
        #expect(try await phone.paymentCount(in: "groceries") == 3)
        #expect(try await phone.paymentCount(in: "rent") == 2)
        #expect(phone.summary.unsorted == 1 && built.value == 1)
        #expect(!store.waitsForCategories)
        // Now something is ticked: Done closes without asking.
        #expect(picker.fitting.isEmpty)
        #expect(await picker.closes())
    }

    @Test func notNowLeavesThemAndTheDashboardsCardLeadsBack() async throws {
        let (phone, store) = try await dashboard(chosen: [], clock: nil)
        let picker = CategoryPickerModel(phone: phone) { await store.reloadAfterTransactionChange() }
        await picker.load()
        #expect(!(await picker.closes()) && picker.asksToUseFitting)
        // Not now closes the list as it is (the alert's cancel only closes): every payment waits as Not sorted.
        picker.asksToUseFitting = false
        #expect(phone.summary.chosen.isEmpty && phone.summary.unsorted == 6)
        // The dashboard says so in one card (the start screen's, and Not sorted's list in the quick sort card's place),
        // and the quick sort waits: its cards could offer only Own transfers and New category.
        #expect(store.waitsForCategories)
        let notSorted = store.route(category: CategoryName.uncategorised, side: .expenses, scope: .current)
        #expect(store.offersCategoriesCard(on: notSorted))
        #expect(store.quickSortTally.hasRepeats && !store.offersQuickSort(on: notSorted))
        #expect(!store.offersCategoriesCard(on: store.route(category: CategoryName.uncategorised, side: .expenses,
                                                            scope: .overview)), "its months: no list yet")
        // One category chosen from the card's list: the card goes, the quick sort's card comes.
        let fromCard = CategoryPickerModel(phone: phone) { await store.reloadAfterTransactionChange() }
        await fromCard.load()
        await fromCard.toggle("rent")
        #expect(await fromCard.closes())
        #expect(!store.waitsForCategories && !store.offersCategoriesCard(on: notSorted))
        #expect(store.offersQuickSort(on: notSorted))
    }

    @Test func nothingThatFitsClosesWithoutAsking() async throws {
        let phone = try await PhoneTest.backend()
        _ = try await phone.importFiles([PhoneTest.vrBank([("03.10.2026", "Fiktiv Laden", "Einkauf", -500)])],
                                        auth: none)
        let picker = CategoryPickerModel(phone: phone) {}
        await picker.load()
        #expect(picker.fitting.isEmpty)
        #expect(await picker.closes() && !picker.asksToUseFitting)
    }

    @Test func noCardBeforeAnyPaymentOrInServerMode() async throws {
        let phone = try await PhoneTest.backend()
        let store = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), backend: phone)
        await store.reload()
        #expect(phone.waitsForCategories && !store.waitsForCategories, "no payments: the first screen shows instead")
        let server = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), sample: true)
        await server.reload()
        #expect(!server.waitsForCategories)
    }

    @Test func theQuickSortsOfferWaitsForACategory() async throws {
        let session = await PhoneTest.session(nil, transport: RoutedTransport())
        let phone = try await PhoneTest.backend()
        let store = DashboardStore(session: session, backend: phone)
        let imports = ImportStore(dashboard: store, background: PhoneActivity())
        func moment() -> QuickSortOffer.Moment {
            QuickSortOffer.Moment(imports: imports, store: store, tour: false, locked: false, window: false)
        }
        imports.debugImport([Self.threeMonths])
        await imports.importAndWait()
        await imports.categoriesClosed()?.value
        imports.close()
        // Not now on the question: the import's offer is pending, but waits while no category is chosen.
        #expect(imports.offersQuickSort && moment().categories && !QuickSortOffer.shows(moment()))
        #expect(!QuickSortOffer.expires(moment(), dashboardShown: true))
        try await phone.choose("salary")          // a category none of these payments fits
        await store.reloadAfterTransactionChange()
        #expect(!moment().categories && QuickSortOffer.shows(moment()))
        #expect(moment().tally.payments == 6)
        var blocked = moment()
        blocked.categories = true
        #expect(!QuickSortOffer.shows(blocked))
    }

    @Test func theCardsAndQuestionsWordsInBothLanguages() {
        #expect(ChooseCategoriesWording.question(12, language: .english) == "Use the 12 categories that fit?")
        #expect(ChooseCategoriesWording.question(12, language: .german) == "Die 12 passenden Kategorien verwenden?")
        #expect(ChooseCategoriesWording.question(1, language: .english) == "Use the category that fits?")
        #expect(ChooseCategoriesWording.question(1, language: .german) == "Die passende Kategorie verwenden?")
        #expect(ChooseCategoriesWording.questionLine(language: .english)
                == "Aresium sorts your payments right away. You can change your categories any time in Settings → Categories.")
        #expect(ChooseCategoriesWording.questionLine(language: .german)
                == "Aresium sortiert deine Buchungen sofort. Deine Kategorien kannst du jederzeit unter Einstellungen → Kategorien ändern.")
        #expect(ChooseCategoriesWording.use(language: .english) == "Use")
        #expect(ChooseCategoriesWording.use(language: .german) == "Verwenden")
        #expect(ChooseCategoriesWording.notNow(language: .german) == "Nicht jetzt")
        #expect(ChooseCategoriesWording.cardTitle(language: .english) == "Choose your categories")
        #expect(ChooseCategoriesWording.cardTitle(language: .german) == "Wähl deine Kategorien")
        #expect(ChooseCategoriesWording.cardLine(language: .english) == "Then Aresium sorts your payments.")
        #expect(ChooseCategoriesWording.cardLine(language: .german) == "Dann sortiert Aresium deine Buchungen.")
    }

    // MARK: finding 11: the messages' offer waits for the next opening

    /// A messages model on defaults of its own (`suite`, removed by the test), in phone mode.
    private func messages(_ suite: String) -> AresiumMessages {
        let model = AresiumMessages(defaults: UserDefaults(suiteName: suite)!, center: FakeMessageCenter())
        model.setContext(MessageContext(phone: true))
        return model
    }

    private func reminderOffers(_ model: AresiumMessages) -> Bool {
        ReminderOffer.shows(ReminderOffer.Moment(ready: model.shouldOfferReminder,
                                                 firstOpening: model.offerWaitsForNextOpening))
    }

    @Test func theRemindersOfferWaitsForTheNextOpening() async {
        let suite = "first-run-messages-" + UUID().uuidString
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let model = messages(suite)
        model.recordImport(accounts: ["fictional-account"], addedPayments: 74)
        // The first import: due, but not in this opening (the result and the quick sort's offer are enough).
        #expect(model.shouldOfferReminder && model.offerWaitsForNextOpening && !reminderOffers(model))
        // A second import in the same opening (a file confirmed in the file check is one too) does not end the wait.
        model.recordImport(accounts: ["fictional-account"], addedPayments: 4)
        #expect(!reminderOffers(model))
        // Back from the background: it may show.
        model.appOpenedAgain()
        #expect(reminderOffers(model))
        await model.idle()
    }

    @Test func aLaterLaunchOffersIt() async {
        let suite = "first-run-launch-" + UUID().uuidString
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let first = messages(suite)
        first.recordImport(accounts: ["fictional-account"], addedPayments: 74)
        #expect(!reminderOffers(first))
        await first.idle()
        // The next launch: a new model on the same defaults.
        let later = messages(suite)
        #expect(later.shouldOfferReminder && !later.offerWaitsForNextOpening && reminderOffers(later))
        await later.idle()
    }

    @Test func theDashboardTellsTheMessagesWhenTheAppIsOpenedAgain() async throws {
        let (_, store) = try await dashboard(clock: TestClock("2026-11-02"))
        let suite = "first-run-opened-" + UUID().uuidString
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let model = messages(suite)
        store.messages = model
        model.recordImport(accounts: ["fictional-account"], addedPayments: 74)
        store.appReturned()
        #expect(model.offerWaitsForNextOpening, "not left yet: not a new opening")
        store.appLeft()
        store.appReturned()
        #expect(!model.offerWaitsForNextOpening)
        await model.idle()
    }

    // MARK: finding 5: Settings' Ares account section

    @Test func theAresAccountSectionOnlyWithALogin() {
        // Aresium (works without an account, offers no sign-in): the section only while an Ares login exists.
        #expect(SettingsAccountSection.shown(accountOptional: true, offersSignIn: false, signedIn: false) == .hidden)
        #expect(SettingsAccountSection.shown(accountOptional: true, offersSignIn: false, signedIn: true) == .account)
        // An app that works without an account and offers it (none today): Sign in while signed out.
        #expect(SettingsAccountSection.shown(accountOptional: true, offersSignIn: true, signedIn: false) == .signIn)
        // Every other app: the account, as before (they show Settings only behind their login).
        for signedIn in [true, false] {
            for offers in [true, false] {
                #expect(SettingsAccountSection.shown(accountOptional: false, offersSignIn: offers, signedIn: signedIn)
                        == .account)
            }
        }
        #expect(EmpireAppIdentity.aresium.accountOptional && SettingsApp(name: "Other").offersSignIn)
    }

    // MARK: finding 12: the running month's stretch

    @Test func theRunningMonthsStretchIsItsOwn() async throws {
        let (_, store) = try await dashboard(clock: nil)
        let points = store.startChart(side: .expenses, scope: .overview)
        #expect(points.map(\.running) == [false, false, true])
        let stretches = ChartStretches(points)
        #expect(stretches.done.map(\.index) == [0, 1] && stretches.running.map(\.index) == [1, 2])
        // Without a running month (an older file), or with one point, all of it is done.
        let finished = [ChartPoint(index: 0, label: "Sep", value: 1), ChartPoint(index: 1, label: "Oct", value: 2)]
        #expect(ChartStretches(finished).done.count == 2 && ChartStretches(finished).running.isEmpty)
        let alone = [ChartPoint(index: 0, label: "Nov", value: 1, running: true)]
        #expect(ChartStretches(alone).done.count == 1 && ChartStretches(alone).running.isEmpty)
        // A category's months and a day graph: only month graphs mark it.
        #expect(store.categoryChart("Groceries", side: .expenses).last?.running == true)
        #expect(store.startChart(side: .expenses, scope: .month("2026-11")).allSatisfy { !$0.running })
    }

    // MARK: findings 3, 7, 14: the words

    @Test func theWordsInBothLanguages() {
        // The import result's button only closes the notice (Arestemis's "Dismiss" stays "Entfernen" there).
        #expect(AppLanguage.english.string("Close") == "Close")
        #expect(AppLanguage.german.string("Close") == "Schließen")
        // A month's payments say payments, as everywhere else.
        #expect(AppLanguage.english.string("\("Oct 2026") · payments") == "Oct 2026 · payments")
        #expect(AppLanguage.german.string("\("Okt. 2026") · payments") == "Okt. 2026 · Buchungen")
        #expect(AppLanguage.english.string("No payments") == "No payments")
        #expect(AppLanguage.german.string("No payments") == "Keine Buchungen")
        #expect(AppLanguage.german.string("No payments recorded.") == "Keine Buchungen erfasst.")
        // The Cash row in plain words.
        #expect(CashRowWording.line(unaccounted: 300, language: .english) == "€300.00 without receipts")
        #expect(CashRowWording.line(unaccounted: 300, language: .german)
                    .replacingOccurrences(of: "\u{00A0}", with: " ") == "300,00 € ohne Belege")
    }
}
