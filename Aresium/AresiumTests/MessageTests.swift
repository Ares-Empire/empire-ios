import Foundation
import Testing
import UserNotifications
import Synchronization
@testable import Aresium

actor FakeMessageCenter: MessageNotificationCenter {
    var status: MessageAuthorization = .allowed
    var permissionAnswer = true
    var permissionRequests = 0
    var pending: [String: PlannedMessage] = [:]
    var delivered: [String] = []
    var offMainThread = true

    func authorization() async -> MessageAuthorization { offMainThread = offMainThread && !Thread.isMainThread; return status }
    func requestPermission() async throws -> Bool {
        permissionRequests += 1
        status = permissionAnswer ? .allowed : .denied
        return permissionAnswer
    }
    func pendingIdentifiers() async -> [String] { Array(pending.keys) }
    func deliveredIdentifiers() async -> [String] { delivered }
    func removePending(_ identifiers: [String]) async { for id in identifiers { pending[id] = nil } }
    func removeDelivered(_ identifiers: [String]) async { delivered.removeAll { identifiers.contains($0) } }
    func add(_ message: PlannedMessage, calendar: Calendar) async throws {
        offMainThread = offMainThread && !Thread.isMainThread
        pending[message.identifier] = message
    }
    func seed(_ message: PlannedMessage) { pending[message.identifier] = message }
    func seedDelivered(_ identifiers: [String]) { delivered = identifiers }
    func permission(_ status: MessageAuthorization, answer: Bool) { self.status = status; permissionAnswer = answer }
    func requests() -> [PlannedMessage] { pending.values.sorted { $0.date < $1.date } }
}

@MainActor
struct MessageTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return value
    }

    private func date(_ value: String) -> Date {
        let parts = value.split(separator: " ")
        let day = parts[0].split(separator: "-").map { Int($0)! }
        let time = parts.count > 1 ? parts[1].split(separator: ":").map { Int($0)! } : [12, 0]
        return calendar.date(from: DateComponents(year: day[0], month: day[1], day: day[2], hour: time[0], minute: time[1]))!
    }

    private func preferences(interval: MessageInterval = .fortnight) -> MessagePreferences {
        MessagePreferences(enabled: true, interval: interval)
    }

    private func plan(now: Date, history: MessageHistory, preferences: MessagePreferences? = nil,
                      locked: Bool = false, dashboard: Dashboard? = nil,
                      accounts: [String: Set<String>] = [:]) -> [PlannedMessage] {
        MessagePlan.requests(preferences: preferences ?? self.preferences(), history: history,
                             context: MessageContext(phone: true, locked: locked, language: .english),
                             dashboard: dashboard, accountsByMonth: accounts, now: now, calendar: calendar)
    }

    private func dashboard(payments: Bool = true, spending: Bool = true) -> Dashboard {
        let categories = [CategoryTotal(name: "Books", total: 40), CategoryTotal(name: "Groceries", total: 320)]
        let month = MonthData(expense: spending ? 1234 : 0, income: 2100, categories: spending ? categories : [],
                              incomeBuckets: [], endBalance: 866, dayExpense: [], dayExpenseRunning: [],
                              dayIncome: [], dayBalance: [])
        let transaction = Transaction(id: "made-up-payment", date: "2026-10-12", day: 12, month: "2026-10",
                                      amount: -320, categoryName: "Groceries", tags: [], place: "Sample shop", city: "",
                                      categoriesIn: ["Groceries"], incomeBuckets: [])
        return Dashboard(version: 2,
                         months: [Month(key: "2026-10", label: "October 2026", short: "Oct", year: 2026,
                                        month: 9, days: 31, partial: false)], categories: [], incomeBuckets: [],
                         transactions: payments ? [transaction] : [],
                         overview: Overview(expense: [], income: [], balance: []), total: month.totals,
                         byMonth: ["2026-10": month], spend: [:], income: [:], pick: CategoryChoices(spend: [], income: []))
    }

    private func model(now: Date, center: FakeMessageCenter = FakeMessageCenter()) -> (AresiumMessages, UserDefaults) {
        let defaults = UserDefaults(suiteName: "message-tests-" + UUID().uuidString)!
        let calendar = calendar
        let model = AresiumMessages(defaults: defaults, center: center, now: { now }, calendar: { calendar })
        model.setContext(MessageContext(phone: true, language: .english))
        return (model, defaults)
    }

    @Test func defaultsAndSettingsPersistWithoutLosingDenial() async {
        let center = FakeMessageCenter()
        await center.permission(.notAsked, answer: false)
        let (model, defaults) = model(now: date("2026-10-20"), center: center)
        #expect(model.preferences == MessagePreferences())
        #expect(!model.shouldOfferReminder)
        model.setEnabled(true)
        await model.idle()
        #expect(model.preferences.enabled)
        #expect(model.authorization == .denied)
        #expect(await center.permissionRequests == 1)
        model.setEnabled(false)
        model.setEnabled(true)
        await model.idle()
        #expect(await center.permissionRequests == 1)
        let restored = AresiumMessages(defaults: defaults, center: center)
        #expect(restored.preferences.enabled)
        #expect(LocalMessageCenter.permissionOptions == [.alert, .sound])
    }

    @Test func reminderUsesCalendarDaysAcrossDaylightSavingAndChosenTime() {
        let imported = date("2026-10-20 09:15")
        var prefs = preferences()
        prefs.hour = 18; prefs.minute = 35
        let requests = plan(now: imported, history: MessageHistory(lastImport: imported), preferences: prefs)
        #expect(requests.map(\.date) == [date("2026-11-03 18:35"), date("2026-11-17 18:35"), date("2026-12-01 18:35")])
        #expect(requests[0].body == "Your last import was 14 days ago.")
        #expect(requests[1].body == "Your last import was 28 days ago.")
        #expect(requests[2].body == "Your last import was 42 days ago.")
        #expect(requests.allSatisfy { $0.title == "Time for new statements" && $0.url == AresiumURL.importData.url })
        #expect(!requests[0].body.contains("Sample bank"))
    }

    @Test func everyIntervalAndMonthEnd() {
        let imported = date("2026-01-31 23:00")
        let history = MessageHistory(lastImport: imported)
        #expect(plan(now: imported, history: history, preferences: preferences(interval: .week)).first?.date == date("2026-02-07 18:00"))
        #expect(plan(now: imported, history: history, preferences: preferences(interval: .fortnight)).first?.date == date("2026-02-14 18:00"))
        let monthly = plan(now: imported, history: history, preferences: preferences(interval: .month))
        #expect(monthly.first?.date == date("2026-02-28 18:00"))
        #expect(monthly.first?.body == "Your last import was 28 days ago.")
    }

    @Test func springDSTAndNonexistentTime() {
        let imported = date("2026-03-22 12:00")
        var prefs = preferences(interval: .week)
        prefs.hour = 2; prefs.minute = 30
        let first = plan(now: imported, history: MessageHistory(lastImport: imported), preferences: prefs).first!
        #expect(calendar.component(.day, from: first.date) == 29)
        #expect(calendar.component(.hour, from: first.date) == 3)
        #expect(first.body == "Your last import was 7 days ago.")
    }

    @Test func threeRequestsSurviveRelaunchAndThenStop() {
        let history = MessageHistory(lastImport: date("2026-10-01"))
        #expect(plan(now: date("2026-10-01"), history: history).count == 3)
        #expect(plan(now: date("2026-10-15 18:01"), history: history).count == 2)
        #expect(plan(now: date("2026-10-29 18:01"), history: history).count == 1)
        #expect(plan(now: date("2026-11-12 18:01"), history: history).isEmpty)
    }

    @Test func beforeFirstImportUsesEnableDateAndGenericText() async {
        let center = FakeMessageCenter()
        let (model, _) = model(now: date("2026-10-20"), center: center)
        model.setEnabled(true)
        await model.idle()
        let requests = await center.requests()
        #expect(requests.first?.date == date("2026-11-03 18:00"))
        #expect(requests.first?.body == "Import your statements to keep your dashboard up to date.")
    }

    @Test func anImportMovesReminderAndNoNewPaymentsDoNotMoveIt() async {
        let center = FakeMessageCenter()
        let (model, _) = model(now: date("2026-10-20"), center: center)
        model.setEnabled(true)
        model.recordImport(accounts: ["account-a"], addedPayments: 2, at: date("2026-10-25"))
        await model.idle()
        #expect(await center.requests().first?.date == date("2026-11-08 18:00"))
        model.recordImport(accounts: ["account-a"], addedPayments: 0, at: date("2026-11-01"))
        await model.idle()
        #expect(await center.requests().first?.date == date("2026-11-08 18:00"))
    }

    @Test func reviewUsesDashboardTotalsAndTopCategoryOnThird() throws {
        let history = MessageHistory(accountImports: ["account-a": date("2026-11-02")])
        let requests = plan(now: date("2026-11-02"), history: history, dashboard: dashboard(), accounts: ["2026-10": ["account-a"]])
        let review = try #require(requests.first)
        #expect(review.date == date("2026-11-03 18:00"))
        #expect(review.body == "October: 1,234 € spent, 2,100 € in. Most on Groceries: 320 €.")
        #expect(review.url == AresiumURL.review("2026-10").url)
    }

    @Test func completenessRequiresEveryParticipatingAccountAfterMonthEnd() {
        let membership: [String: Set<String>] = ["2026-10": ["account-a", "account-b"]]
        var history = MessageHistory(accountImports: ["account-a": date("2026-11-01 00:00"), "account-b": date("2026-10-31 23:59")])
        let now = date("2026-11-02")
        #expect(plan(now: now, history: history, dashboard: dashboard(), accounts: membership).first?.body == "Import your statements to complete October.")
        history.accountImports["account-b"] = date("2026-11-02")
        // An account that has no October payment need not be imported again.
        history.accountImports["account-unused"] = date("2026-09-01")
        #expect(plan(now: now, history: history, dashboard: dashboard(), accounts: membership).first?.body.contains("1,234 €") == true)
        history.accountImports["account-b"] = nil
        #expect(plan(now: now, history: history, dashboard: dashboard(), accounts: membership).first?.body == "Import your statements to complete October.")
    }

    @Test func noPaymentsMeansNoReviewAndNoStaleMonthReviewAfterThird() {
        #expect(plan(now: date("2026-11-02"), history: MessageHistory(), dashboard: dashboard(payments: false)).isEmpty)
        #expect(plan(now: date("2026-11-04"), history: MessageHistory(), dashboard: dashboard()).isEmpty)
    }

    @Test func incomeOnlyReviewHasNoInventedTopCategory() {
        let result = plan(now: date("2026-11-02"), history: MessageHistory(), dashboard: dashboard(spending: false))
        #expect(result.first?.body == "October: 0 € spent, 2,100 € in.")
    }

    @Test func lockHidesAmountsCategoriesAndReminderDayCount() {
        let history = MessageHistory(lastImport: date("2026-10-20"), accountImports: ["account-a": date("2026-11-01")])
        let requests = plan(now: date("2026-11-02"), history: history, locked: true, dashboard: dashboard(), accounts: ["2026-10": ["account-a"]])
        #expect(requests.last?.body == "Your October review is ready.")
        #expect(requests.allSatisfy { !$0.body.contains(where: \.isNumber) && !$0.body.contains("Groceries") })
    }

    @Test func offAndDeleteRemoveOnlyOwnedPendingAndDelivered() async {
        let center = FakeMessageCenter()
        let (model, defaults) = model(now: date("2026-10-20"), center: center)
        let other = PlannedMessage(identifier: "unrelated.message", date: date("2026-11-03"), title: "Other", body: "Other", url: AresiumURL.start.url)
        await center.seed(other)
        await center.seedDelivered(["aresium.reminder.1", "aresium.review.2026-09", other.identifier])
        model.setEnabled(true)
        model.setEnabled(false)
        await model.idle()
        #expect(await center.requests() == [other])
        #expect(await center.delivered == [other.identifier])
        model.recordImport(accounts: ["account-a"], addedPayments: 1)
        model.finishReminderOffer()
        model.setEnabled(true)
        await model.deleteAll()
        #expect(await center.requests() == [other])
        #expect(model.preferences == MessagePreferences())
        #expect(!model.shouldOfferReminder)
        #expect(defaults.data(forKey: AresiumMessages.historyKey) == nil)
        #expect(await center.offMainThread)
    }

    @Test func samplesTourServerAndTestContextNeverScheduleOrAskPermission() async {
        let contexts = [MessageContext(phone: true, sample: true), MessageContext(phone: true, tour: true),
                        MessageContext(phone: false), MessageContext(phone: true, testing: true)]
        for context in contexts {
            let center = FakeMessageCenter()
            await center.permission(.notAsked, answer: true)
            let (model, _) = model(now: date("2026-10-20"), center: center)
            model.setContext(context)
            model.setEnabled(true)
            model.recordImport(accounts: ["account-a"], addedPayments: 2)
            await model.idle()
            #expect(await center.requests().isEmpty)
            #expect(await center.permissionRequests == 0)
            #expect(!model.shouldOfferReminder)
        }
    }

    @Test func offerIsReadyOnlyAfterAddedPaymentsAndAnswerPersists() async {
        let (model, defaults) = model(now: date("2026-10-20"))
        model.recordImport(accounts: [], addedPayments: 0)
        #expect(!model.shouldOfferReminder)
        model.recordImport(accounts: ["account-a"], addedPayments: 2)
        #expect(model.shouldOfferReminder)
        model.finishReminderOffer()
        #expect(!model.shouldOfferReminder)
        model.recordImport(accounts: ["account-a"], addedPayments: 2)
        #expect(!model.shouldOfferReminder)
        await model.idle()
        let restored = AresiumMessages(defaults: defaults, center: FakeMessageCenter())
        restored.setContext(MessageContext(phone: true))
        #expect(!restored.shouldOfferReminder)
        await restored.idle()
    }

    @Test func importAndDashboardHooksUseLedgerAccountIDsAndRebuildReview() async throws {
        let center = FakeMessageCenter()
        let now = date("2026-11-02")
        let (model, defaults) = model(now: now, center: center)
        let phone = try await PhoneTest.backend(chosen: ["groceries"])
        phone.today = { "2026-11-02" }
        let session = await PhoneTest.session(transport: RoutedTransport())
        let store = DashboardStore(session: session, backend: phone)
        store.messages = model
        model.setPhoneMode(true, ledger: phone.ledger)
        model.setEnabled(true)
        let imports = ImportStore(dashboard: store, background: PhoneActivity())
        let file = PhoneTest.vrBank([("12.10.2026", "Sample shop", "Sample groceries", -32000),
                                     ("01.11.2026", "Another sample shop", "Sample books", -4000)])
        let directory = PhoneTest.storage().root
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "made-up.csv")
        try file.data.write(to: url)
        await imports.receive([url])
        await imports.importPendingFiles()
        await model.idle()
        let accounts = try await phone.ledger.messageAccountsByMonth()
        #expect(accounts["2026-10"]?.count == 1)
        let history = try JSONDecoder().decode(MessageHistory.self, from: #require(defaults.data(forKey: AresiumMessages.historyKey)))
        #expect(Set(history.accountImports.keys) == accounts["2026-10"])
        #expect(history.lastImport == now)
        let review = try #require(await center.requests().first { $0.identifier == "aresium.review.2026-10" })
        #expect(!review.body.contains("complete"))
        await center.seedDelivered([review.identifier])
        model.setLocked(true)
        await model.idle()
        #expect(await center.delivered.isEmpty)
        #expect(await center.requests().first { $0.identifier == review.identifier }?.body == "Your October review is ready.")
        store.showReview(month: "2026-10")
        #expect(store.currentMonth?.key == "2026-10")
        #expect(store.totals(current: true)?.expense == store.dashboard?.byMonth["2026-10"]?.expense)
        #expect(store.rangeLabel(current: false) == "Oct 2026 – Nov 2026")
    }

    @Test func languageSwitchReplacesScheduledContentAndTurningOnBeforeStoreOpensAsksLater() async {
        let center = FakeMessageCenter()
        await center.permission(.notAsked, answer: true)
        let (model, _) = model(now: date("2026-11-02"), center: center)
        model.setPhoneMode(false, ledger: nil)
        model.setEnabled(true)
        await model.idle()
        #expect(await center.permissionRequests == 0)
        model.setPhoneMode(true, ledger: nil)
        model.dashboardBuilt(dashboard())
        await model.idle()
        #expect(await center.permissionRequests == 1)
        #expect(model.authorization == .allowed)
        await AppLanguage.$scoped.withValue(.german) {
            model.refresh()
            await model.idle()
        }
        // German copy is supplied by Claude; the scheduled month already follows the switched locale.
        let review = await center.requests().first { $0.identifier == "aresium.review.2026-10" }
        #expect(review?.body.contains("Oktober") == true)
    }

    @Test func intervalOrTimeChangesAndRelaunchCannotRestartConsumedReminderSlots() async throws {
        let clock = Mutex(date("2026-10-01 12:00"))
        let calendar = calendar
        let defaults = UserDefaults(suiteName: "message-progress-" + UUID().uuidString)!
        let center = FakeMessageCenter()
        let model = AresiumMessages(defaults: defaults, center: center, now: { clock.withLock { $0 } }, calendar: { calendar })
        model.setContext(MessageContext(phone: true))
        model.setPreferences(preferences(interval: .week))
        await model.idle()
        clock.withLock { $0 = date("2026-10-15 18:01") }
        model.setPreferences(preferences(interval: .month))
        await model.idle()
        let remaining = await center.requests()
        #expect(remaining.count == 1)
        #expect(remaining.first?.identifier == "aresium.reminder.3")
        #expect(remaining.first?.date == date("2027-01-01 18:00"))
        let restored = AresiumMessages(defaults: defaults, center: center, now: { clock.withLock { $0 } }, calendar: { calendar })
        restored.setContext(MessageContext(phone: true))
        var prefs = restored.preferences
        prefs.hour = 19
        restored.setPreferences(prefs)
        await restored.idle()
        #expect(await center.requests().map(\.identifier) == ["aresium.reminder.3"])
        clock.withLock { $0 = date("2027-01-01 19:01") }
        prefs.hour = 20
        restored.setPreferences(prefs)
        await restored.idle()
        #expect(await center.requests().isEmpty)
        restored.recordImport(accounts: ["account-a"], addedPayments: 1)
        await restored.idle()
        #expect(await center.requests().count == 3)
    }

    @Test func tapURLsRoundTripAndDismissOrUnrelatedURLsDoNotRoute() {
        for route in [AresiumURL.importData, .review("2026-10")] { #expect(AresiumURL(url: route.url) == route) }
        for invalid in ["aresium://review/2026-13", "aresium://review/2026-1", "aresium://review/2026-10/extra", "aresium://review/2026-10?x=1"] {
            #expect(AresiumURL(url: URL(string: invalid)!) == nil)
        }
        let router = MessageTapRouter()
        router.open(action: UNNotificationDismissActionIdentifier, url: AresiumURL.importData.url)
        #expect(router.take() == nil)
        router.open(action: UNNotificationDefaultActionIdentifier, url: URL(string: "https://example.invalid"))
        #expect(router.take() == nil)
        router.open(action: UNNotificationDefaultActionIdentifier, url: AresiumURL.review("2026-10").url)
        #expect(router.take() == AresiumURL.review("2026-10").url)
        #expect(router.take() == nil)
    }
}
