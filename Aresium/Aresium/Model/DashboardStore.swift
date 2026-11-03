import Foundation
import Observation

nonisolated enum DashboardSide: String, Codable, CaseIterable, Hashable, Sendable {
    case expenses, income
    var title: String { self == .expenses ? String(localized: "Expenses") : String(localized: "Income") }
    var caption: String { self == .expenses ? String(localized: "spent") : String(localized: "received") }
}

struct DisplayRow: Identifiable {
    let category: Category
    let total: Double
    var id: String { category.name }
}

struct MonthRow: Identifiable {
    let month: Month
    let total: Double
    var id: String { month.key }
}

struct TransactionRow: Identifiable {
    let transaction: Transaction
    let tagged: Bool
    var id: String { transaction.id }
}

/// What a page of the dashboard counts (brief 56): Current's month (this month, or the month a review message opened),
/// every month (Overview), or one month opened from Overview's graph (that month's own page, `DashboardRoute.monthPage`).
/// The start screen and a month's page are the same pieces over a scope.
enum DashboardScope: Hashable {
    case current, overview
    case month(String)

    /// The start screen's range picker: Current (true) or Overview (false).
    init(current: Bool) { self = current ? .current : .overview }

    /// A scope of one month (Current or a month's page): its graph is the days', a category opens that month's payments.
    var isMonth: Bool { self != .overview }
}

/// Where a tap on a category leads (Patrik, 2026-10-27): in the Current view straight to this month's payments of it,
/// since the row showed this month; in Overview to its months first. Without a known month, to its months.
enum CategoryRoute {
    static func route(category: String, side: DashboardSide, current: Bool, currentMonth: String?) -> DashboardRoute {
        guard current, let currentMonth else { return DashboardRoute(category: category, side: side) }
        return DashboardRoute(category: category, side: side, month: currentMonth)
    }
}

extension Transaction {
    /// A month's payment list's order: by day, oldest first; on one day the dashboard's order stays (a stable sort). A
    /// name's month page orders its rows the same way (brief 55, `NamePage`).
    nonisolated static func listOrder(_ first: Transaction, _ second: Transaction) -> Bool {
        first.day == second.day ? first.date < second.date : first.day < second.day
    }
}

struct ChartPoint: Identifiable {
    let index: Int
    /// The axis's label: the day ("14") or the month ("Sep").
    let label: String
    let value: Double
    /// What the chip names while a finger reads the graph (brief 56): the day written out ("Mon 14 Sep") or the month
    /// with its year ("Sep 2026"); the label when not given.
    let title: String
    /// A month still running (`Month.partial`, brief 215): the month graphs draw the stretch to it dashed, as its amount
    /// is not final yet.
    let running: Bool
    /// Lines with different segments never connect across an unknown balance.
    let segment: Int
    var id: Int { index }

    nonisolated init(index: Int, label: String, value: Double, title: String? = nil, running: Bool = false,
                     segment: Int = 0) {
        self.index = index
        self.label = label
        self.value = value
        self.title = title ?? label
        self.running = running
        self.segment = segment
    }
}

@MainActor @Observable
final class DashboardStore {
    private(set) var dashboard: Dashboard? {
        didSet { revision &+= 1 }
    }
    /// Counts every change of `dashboard`, so what is built from it (a category's payment list with its sums, brief 53)
    /// is kept until it changes.
    private(set) var revision = 0
    /// Which names add up in a category's payment list (brief 53): the person's, kept in the app's defaults; the tour,
    /// tests and the samples have their own in memory.
    let sums: PaymentSums
    /// The payment lists built since the dashboard or the choices last changed (`paymentList(category:month:side:)`).
    @ObservationIgnored var builtLists = PaymentListCache()
    /// The name's pages built since the dashboard last changed (`namePage(_:)`, brief 55).
    @ObservationIgnored var builtNamePages = NamePageCache()
    @ObservationIgnored var builtNameSearch = NameSearchCache()
    @ObservationIgnored var builtDays = DayPaymentsCache()
    /// The names of the expenses payments in pay back (brief 203), for the rows' lines (`paybackName`).
    @ObservationIgnored var builtPaybackNames = PaybackNamesCache()
    /// The quick sort's groups (brief 99), built with each phone dashboard and published in the same turn as it, so the
    /// card on Not sorted's list, the offer and the flow never read groups of another dashboard.
    private(set) var builtQuickSort = QuickSortCache()
    private(set) var builtFixedCosts = FixedCostsCache()
    @ObservationIgnored private var averageEngine: AresiumEngine?
    /// Installed by the live app (`installMessages`); in DEBUG the phone sample gets a pretend one
    /// (`installSampleMessages`, brief 46); never a test store.
    var messages: AresiumMessages?
    /// What Current shows besides its rule (`CurrentMonth`), until the app goes to the background: a month chosen (a
    /// month review's message, brief 46; the range line's other month, brief 215) or the newest (a widget's link: the
    /// widget shows the newest month).
    enum CurrentChoice: Equatable {
        case month(String)
        case newest
    }
    private(set) var currentChoice: CurrentChoice?
    /// The day this look at the app began (`YYYY-MM-DD`), which Current's month is read with (`CurrentMonth`): at
    /// launch and on coming back from the background (`appReturned`), never while the app is open, so the start screen
    /// never changes its month under the person (brief 215). nil without a clock: Current shows the newest month.
    private(set) var openedOn: String?
    /// The clock `openedOn` is read from: the live app's (`ContentView`). nil (tests, the tour, previews): Current shows
    /// the newest month as before, whatever the day.
    @ObservationIgnored private let clock: (() -> Date)?
    @ObservationIgnored private var leftApp = false
    private(set) var isLoading = false
    private(set) var error: String?
    let session: EmpireSession
    let isSample: Bool
    /// Aresium's widget snapshot (App Group). The default writes to a temporary folder (tests, previews); the app
    /// passes the real one.
    let widgetPublisher: WidgetSnapshotPublisher
    /// Where the data comes from: the server or the phone's own store (`AresiumBackend`); nil while the phone's store
    /// opens (`ModeStore`), so nothing is asked of the wrong one.
    private(set) var backend: (any AresiumBackend)?
    /// Phone mode's backend (receipts are phone mode's); nil in server mode.
    var phone: PhoneBackend? { backend as? PhoneBackend }
    var generation: Int { session.generation }
    private var fetchGeneration = 0
    private(set) var lastSuccessfulLoad: Date?
    /// Phone mode: the person's categories the shown dashboard was built with (`reloadIfCategoriesChanged`).
    @ObservationIgnored private var builtChosen: [ChosenCategory]?
    private var foregroundRefreshing = false
    /// Told when a payment's category change is finished: its sheet closed after Switch or Add, the shop question
    /// answered (the tour moves on with it).
    @ObservationIgnored var onRecategorised: (() -> Void)?
    /// Told when a payment's name was saved on its page (brief 59: the tour moves on with it). Nil outside the tour.
    @ObservationIgnored var onRenamed: (() -> Void)?

    /// Server mode from the start (tests, the server sample).
    convenience init(session: EmpireSession, client: APIClient = APIClient(), sample: Bool = false,
                     widgetPublisher: WidgetSnapshotPublisher = .temporary(), sums: PaymentSums = PaymentSums(),
                     clock: (() -> Date)? = nil) {
        self.init(session: session, backend: ServerBackend(client: client), sample: sample, widgetPublisher: widgetPublisher,
                  sums: sums, clock: clock)
    }

    /// `sums`: the person's choices (`PaymentSums(defaults:)`) only for the app's own dashboard; by default an empty set in
    /// memory (the tour, tests).
    /// `clock`: the day Current's month is read with (brief 215, `CurrentMonth`); only the app's own dashboard passes
    /// one.
    init(session: EmpireSession, backend: (any AresiumBackend)?, sample: Bool = false,
         widgetPublisher: WidgetSnapshotPublisher = .temporary(), sums: PaymentSums = PaymentSums(),
         clock: (() -> Date)? = nil) {
        self.session = session
        self.backend = backend
        self.widgetPublisher = widgetPublisher
        self.sums = sums
        self.clock = clock
        openedOn = clock.map { ReceiptDay.day($0()) }
        isSample = sample
        // The login ended (here or in another app), or the server refused it: server mode's dashboard and its widget
        // numbers go with it (`ModeStore` then shows the phone's store). Phone mode's belong to the iPhone and stay.
        session.onAppDataReset { [weak self] in
            if let self, self.backend?.mode == .server { self.clear() }
        }
    }

    /// Switches to another backend (the account's mode is known, or changed): the old one's dashboard goes, and a load
    /// still running for it is superseded.
    func use(_ backend: (any AresiumBackend)?) {
        guard backend !== self.backend else { return }
        self.backend = backend
        currentChoice = nil
        messages?.setPhoneMode(backend?.mode == .phone, ledger: (backend as? PhoneBackend)?.ledger)
        fetchGeneration += 1
        isLoading = false
        dashboard = nil
        lastSuccessfulLoad = nil
        error = nil
    }

    func reload() async {
        guard !isLoading else { return }
        // Nothing to ask yet: the phone's store is opening, or server mode waits for its login (offline at launch).
        guard isSample || backend?.isReady(session) == true else { return }
        isLoading = true
        error = nil
        let generation = generation
        let fetch = fetchGeneration
        let token = session.token          // the login this request goes with; a refusal names it
        let backend = backend
        // The server's answer belongs to the login it was asked with; the phone's store does not depend on a login.
        let current = { fetch == self.fetchGeneration && (backend?.mode == .phone || generation == self.generation) }
        defer { if fetch == self.fetchGeneration { isLoading = false } }
        // Read before building: a category made meanwhile leaves this older, so the next check builds again.
        let chosen = (backend as? PhoneBackend)?.summary.chosen
        do {
            let loaded: Dashboard
            if isSample { loaded = try Dashboard.sample() }
            else {
                guard let backend else { return }
                loaded = try await backend.dashboard(auth: BackendAuth(token: token) {
                    if fetch == self.fetchGeneration {
                        self.session.handleAuthFailure(HTTPError.unauthorized, generation: generation, token: token)
                    }
                })
            }
            guard current() else { return }
            // Brief 99: what is Not sorted, grouped by name, off the main thread before the dashboard shows.
            let groups = backend?.mode == .phone ? await QuickSortCache.build(loaded) : []
            let marks = try await (backend as? PhoneBackend)?.ledger.fixedCostMarks() ?? []
            let engine: AresiumEngine
            if let phone = backend as? PhoneBackend { engine = phone.engine }
            else if let averageEngine { engine = averageEngine }
            else {
                engine = try await Task.detached(priority: .userInitiated) { try AresiumEngine.bundled() }.value
                averageEngine = engine
            }
            let fixed = try await FixedCostsCache.build(loaded, marks: marks, engine: engine,
                                                        includeFixedCosts: backend?.mode == .phone)
            guard current() else { return }
            try PickerTiming.measure("dashboard.publish") {
                dashboard = loaded
                builtQuickSort = QuickSortCache(revision: revision, groups: groups)
                builtFixedCosts = FixedCostsCache(revision: revision, analysis: fixed)
                builtChosen = chosen
                lastSuccessfulLoad = .now
                try publishWidget(loaded)
            }
            messages?.dashboardBuilt(loaded)
        } catch {
            guard current() else { return }
            if backend?.mode != .phone { session.handleAuthFailure(error, generation: generation, token: token) }
            guard current() else { return }
            self.error = error.localizedDescription
        }
    }

    /// The widgets' numbers: phone mode's as the iPhone's own, server mode's with their account.
    private func publishWidget(_ dashboard: Dashboard) throws {
        if backend?.mode == .phone { try widgetPublisher.publish(dashboard, phone: true) }
        else { try widgetPublisher.publish(dashboard, account: session.accountID) }
    }

    /// The lock turned off: the widgets get the numbers shown now again (the lock kept none for them).
    func republishWidget() {
        guard let dashboard else { return }
        do { try publishWidget(dashboard) } catch { self.error = error.localizedDescription }
    }

    func reloadAfterImport() async {
        // Supersede a fetch started before the import, preserving the visible dashboard meanwhile.
        fetchGeneration += 1
        isLoading = false
        await reload()
    }

    func clear(clearWidget: Bool = true) {
        fetchGeneration += 1
        isLoading = false
        dashboard = nil
        messages?.dashboardBuilt(nil)
        lastSuccessfulLoad = nil
        error = nil
        if clearWidget {
            do { try widgetPublisher.clear() } catch { self.error = error.localizedDescription }
        }
    }

    /// Tells the widgets whether red mode is on (otherwise they follow the home screen's light or dark).
    func setWidgetRedMode(_ red: Bool) {
        do { try widgetPublisher.setRedMode(red) } catch { self.error = error.localizedDescription }
    }

    func transactionDetailStore(for transaction: Transaction) -> TransactionDetailStore {
        TransactionDetailStore(transaction: transaction, dashboardStore: self)
    }

    // A refresh already in flight may predate the save. Supersede it so the new
    // dashboard always comes from a request made after the transaction changed.
    func reloadAfterTransactionChange() async {
        fetchGeneration += 1
        isLoading = false
        await reload()
    }

    /// Phone mode: the dashboard is built again when the person's categories changed since it was built. A category made
    /// in the receipt window or Add cash whose window was then cancelled (brief 60) changes no payment, so nothing else
    /// builds it again; the change window's choices come from the dashboard and would miss it.
    func reloadIfCategoriesChanged() async {
        guard let phone, dashboard != nil, builtChosen != phone.summary.chosen else { return }
        await reloadAfterTransactionChange()
    }

    /// Coming to the foreground: the dashboard is built again when it is older than 5 minutes (a new day, a new month).
    /// Server mode also renews its login every 12 hours first, as before.
    func refreshOnForeground(now: Date = .now) async {
        messages?.refresh()
        guard !isSample, let backend, !foregroundRefreshing, !isLoading else { return }
        foregroundRefreshing = true
        defer { foregroundRefreshing = false }
        if backend.mode == .server {
            guard session.token != nil, !session.isBusy else { return }
            let generation = generation
            if session.lastRenewedAt.map({ now.timeIntervalSince($0) > 12 * 60 * 60 }) ?? true {
                await session.restore()
                guard generation == self.generation, session.token != nil else { return }
                if session.needsRestoreRetry { return }
            }
        }
        if lastSuccessfulLoad.map({ now.timeIntervalSince($0) > 5 * 60 }) ?? true { await reload() }
    }

    /// Widget category links carry a shown name. An old name after rename/removal opens the dashboard.
    func widgetCategoryRoute(_ name: String) -> DashboardRoute? {
        if let phone, let catalog = phone.catalog {
            let list = PhoneCategoryList(catalog: catalog, chosen: phone.summary.chosen)
            if list.id(named: name) == nil {
                let built = PhoneCategoryList(catalog: catalog, chosen: builtChosen ?? [])
                // Engine-only buckets may still be linked; a category from the older dashboard must not be.
                guard built.id(named: name) == nil,
                      dashboard?.categories.contains(where: { $0.name == name }) == true else { return nil }
            }
        }
        return route(category: name, side: .expenses, current: true)
    }

    /// Where a tap on a category in the start screen leads (`CategoryRoute`).
    func route(category: String, side: DashboardSide, current: Bool) -> DashboardRoute {
        route(category: category, side: side, scope: DashboardScope(current: current))
    }

    /// Where a tap on a category of a page leads: that month's payments for a month's scope, its months in Overview.
    func route(category: String, side: DashboardSide, scope: DashboardScope) -> DashboardRoute {
        var route = CategoryRoute.route(category: category, side: side, current: scope.isMonth, currentMonth: monthKey(scope))
        if let phone, let catalog = phone.catalog {
            route.categoryID = PhoneCategoryList(catalog: catalog, chosen: phone.summary.chosen).id(named: category)
        }
        return route
    }

    /// The month a scope counts (`YYYY-MM`): Current's (`currentMonth`) or a month page's own; nil for Overview.
    func monthKey(_ scope: DashboardScope) -> String? {
        switch scope {
        case .current: currentMonth?.key
        case .overview: nil
        case let .month(key): key
        }
    }

    /// The month a graph's point stands for, on a graph over every month (Overview's, a category's, a name's): its key.
    func monthKey(atChartIndex index: Int) -> String? {
        guard let months = dashboard?.months, months.indices.contains(index) else { return nil }
        return months[index].key
    }

    /// A tap on a month of Overview's graph (brief 56, as the website): that month's page, on the side shown.
    func monthPage(atChartIndex index: Int, side: DashboardSide) -> DashboardRoute? {
        monthKey(atChartIndex: index).map { DashboardRoute(monthPage: $0, side: side) }
    }

    /// The month Current shows: one chosen (`currentChoice`) while it is in the data, else the rule's (`CurrentMonth`:
    /// in a month's first days the month before), else the newest.
    var currentMonth: Month? {
        guard let months = dashboard?.months, let newest = months.last else { return nil }
        switch currentChoice {
        case let .month(key)?: if let month = months.first(where: { $0.key == key }) { return month }
        case .newest?: return newest
        case nil: break
        }
        guard let openedOn, let key = CurrentMonth.opening(months: months.map(\.key), openedOn: openedOn) else {
            return newest
        }
        return months.first { $0.key == key } ?? newest
    }

    /// The range line's other month on Current, one tap away (brief 215): the newest while Current shows an older
    /// month; in a month's first days, while it shows the running month, the month before. nil: none.
    var currentOtherMonth: Month? {
        guard let months = dashboard?.months, let shown = currentMonth,
              let key = CurrentMonth.other(months: months.map(\.key), shown: shown.key, openedOn: openedOn) else {
            return nil
        }
        return months.first { $0.key == key }
    }

    /// A notification opens this month's totals, categories and graph on the existing dashboard root; nil: Current's
    /// own month again (`CurrentMonth`).
    func showReview(month: String?) { currentChoice = month.map(CurrentChoice.month) }

    /// The range line's other month tapped (brief 215): Current shows it until the app goes to the background.
    func showCurrent(month key: String) { currentChoice = .month(key) }

    /// A widget's link: the newest month, as the widget shows it.
    func showNewestMonth() { currentChoice = .newest }

    /// The app went to the background: a month chosen for Current goes (a review read, the other month), so it never
    /// quietly shows an old month later, and the day is read again when the person comes back.
    func appLeft() {
        currentChoice = nil
        leftApp = true
    }

    /// Back from the background (a new look at the app): Current's month follows today's date again, and the messages'
    /// offer that waited for this may show (brief 215, `AresiumMessages.offerWaitsForNextOpening`).
    func appReturned() {
        guard leftApp else { return }
        leftApp = false
        if let clock { openedOn = ReceiptDay.day(clock()) }
        messages?.appOpenedAgain()
    }

    /// Phone mode with payments and no category chosen yet (brief 215, the first-run review's finding 1): the start
    /// screen (and Not sorted's list) shows the card that opens the category list, and the quick sort waits, as its
    /// cards could offer only Own transfers and New category.
    var waitsForCategories: Bool {
        guard let phone, phone.waitsForCategories else { return false }
        return dashboard?.transactions.isEmpty == false
    }

    /// The card that opens the category list in Not sorted's month list, where the quick sort's card stands once a
    /// category is chosen.
    func offersCategoriesCard(on route: DashboardRoute) -> Bool {
        waitsForCategories && route.isCategoryList && route.category == CategoryName.uncategorised
    }

    // MARK: the Cash page (brief 33)

    /// Phone mode with any cash movement: the dashboard shows the Cash row.
    var hasCash: Bool { dashboard?.cash?.movements.isEmpty == false }

    /// Where the Cash row leads: as a category, this month's page in Current, its months in Overview.
    func cashRoute(current: Bool) -> DashboardRoute { cashRoute(DashboardScope(current: current)) }

    /// Where a page's Cash row leads: that month's Cash page for a month's scope, its months in Overview.
    func cashRoute(_ scope: DashboardScope) -> DashboardRoute {
        DashboardRoute(category: "", side: .expenses, month: monthKey(scope), cash: true)
    }

    /// What the Cash row's line counts: this month's cash not accounted for (Current), or every month's (Overview).
    func cashUnaccounted(current: Bool) -> Double { cashUnaccounted(DashboardScope(current: current)) }

    /// The cash not accounted for in a scope's month, or in every month (Overview).
    func cashUnaccounted(_ scope: DashboardScope) -> Double {
        guard let cash = dashboard?.cash else { return 0 }
        guard scope.isMonth else { return cash.months.values.reduce(0) { $0 + $1.unaccounted } }
        return monthKey(scope).flatMap { cash.months[$0]?.unaccounted } ?? 0
    }

    /// A receipt row's cash movement (which tells a hand entry from a cash receipt).
    func cashMovement(_ receiptID: String?) -> CashMovement? {
        guard let receiptID else { return nil }
        return dashboard?.cash?.movements.first { $0.id == receiptID }
    }

    /// A month's name, from the dashboard's months, else from its key.
    func monthTitle(_ key: String) -> String {
        if let month = dashboard?.months.first(where: { $0.key == key }) { return month.title() }
        guard let date = ReceiptDay.date(key + "-01") else { return key }
        let calendar = ReceiptDay.calendar
        return date.formatted(Date.FormatStyle(date: .omitted, time: .omitted, locale: AppLanguage.current.locale,
                                               calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).year())
    }

    func rangeLabel(current: Bool) -> String { rangeLabel(DashboardScope(current: current)) }

    /// The line above a page's heading: the scope's month, or Overview's first to last month.
    func rangeLabel(_ scope: DashboardScope) -> String {
        guard let first = dashboard?.months.first, let last = dashboard?.months.last else {
            return String(localized: "No payments")
        }
        guard scope.isMonth else {
            // One month of data: "February 2026", not "February 2026 – February 2026".
            return first.key == last.key ? last.title() : "\(first.title()) – \(last.title())"
        }
        return monthKey(scope).map { monthTitle($0) } ?? String(localized: "No payments")
    }

    func totals(current: Bool) -> Totals? { totals(DashboardScope(current: current)) }

    /// A scope's totals: its month's, or every month's (Overview).
    func totals(_ scope: DashboardScope) -> Totals? {
        guard let dashboard else { return nil }
        guard scope.isMonth else { return dashboard.total }
        guard let key = monthKey(scope) else { return nil }
        return dashboard.byMonth[key]?.totals
    }

    func rows(side: DashboardSide, current: Bool) -> [DisplayRow] { rows(side: side, scope: DashboardScope(current: current)) }

    /// A page's categories (expenses) or income buckets, with the scope's totals, largest first as the engine counted.
    func rows(side: DashboardSide, scope: DashboardScope) -> [DisplayRow] {
        guard let dashboard, let totals = totals(scope) else { return [] }
        let meta = side == .income ? dashboard.incomeBuckets : dashboard.categories
        let rows = side == .income ? totals.incomeBuckets : totals.categories
        return rows.compactMap { row in
            guard let category = meta.first(where: { $0.name == row.name }) else { return nil }
            return DisplayRow(category: category, total: row.total)
        }
    }

    func category(_ name: String, side: DashboardSide) -> Category? {
        (side == .income ? dashboard?.incomeBuckets : dashboard?.categories)?.first { $0.name == name }
    }

    func series(_ name: String, side: DashboardSide) -> Series? {
        side == .income ? dashboard?.income[name] : dashboard?.spend[name]
    }

    func months(category: String, side: DashboardSide) -> [MonthRow] {
        guard let dashboard, let values = series(category, side: side)?.months else { return [] }
        return dashboard.months.enumerated().compactMap { index, month in
            guard values.indices.contains(index), values[index] > 0 else { return nil }
            return MonthRow(month: month, total: values[index])
        }
    }

    func transactions(category: String, month: String, side: DashboardSide) -> [TransactionRow] {
        (dashboard?.transactions ?? []).filter {
            $0.month == month && (side == .income ? $0.incomeBuckets : $0.categoriesIn).contains(category)
        }.sorted(by: Transaction.listOrder).map {
            TransactionRow(transaction: $0, tagged: side == .income
                           ? $0.incomeBuckets.first != category : $0.categoryName != category)
        }
    }

    func startChart(side: DashboardSide, current: Bool) -> [ChartPoint] {
        startChart(side: side, scope: DashboardScope(current: current))
    }

    /// A page's graph: its month's days (Current, a month's page), or every month (Overview).
    func startChart(side: DashboardSide, scope: DashboardScope) -> [ChartPoint] {
        guard let dashboard else { return [] }
        guard scope.isMonth else {
            return monthPoints(side == .income ? dashboard.overview.income : dashboard.overview.expense)
        }
        guard let key = monthKey(scope), let month = dashboard.byMonth[key] else { return [] }
        let values = side == .income ? month.dayIncome : month.dayExpense
        let titles = ChartReading.dayTitles(month: key, count: values.count)
        return values.enumerated().map {
            ChartPoint(index: $0.offset, label: String($0.offset + 1), value: $0.element, title: titles[$0.offset])
        }
    }

    /// The engine's account balances, with their original indices and gaps before any account is known.
    func balanceChart(_ scope: DashboardScope) -> [ChartPoint] {
        guard let dashboard else { return [] }
        guard scope.isMonth else { return monthPoints(dashboard.overview.balance) }
        guard let key = monthKey(scope), let month = dashboard.byMonth[key] else { return [] }
        let titles = ChartReading.dayTitles(month: key, count: month.dayBalance.count)
        return ChartBalances.points(month.dayBalance) { index, value, segment in
            ChartPoint(index: index, label: String(index + 1), value: value, title: titles[index], segment: segment)
        }
    }

    func categoryChart(_ name: String, side: DashboardSide) -> [ChartPoint] {
        monthPoints(series(name, side: side)?.months ?? [])
    }

    private func monthPoints(_ values: [Double?]) -> [ChartPoint] {
        let months = dashboard?.months ?? []
        return ChartBalances.points(Array(values.prefix(months.count))) { index, value, segment in
            let month = months[index]
            return ChartPoint(index: index, label: month.shortTitle(), value: value, title: month.title(),
                              running: month.partial, segment: segment)
        }
    }
}
