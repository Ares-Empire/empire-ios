import Foundation
import Observation

enum DashboardSide: String, CaseIterable, Hashable {
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

/// Where a tap on a category leads (Patrik, 2026-10-27): in the Current view straight to this month's payments of it,
/// since the row showed this month; in Overview to its months first. Without a known month, to its months.
enum CategoryRoute {
    static func route(category: String, side: DashboardSide, current: Bool, currentMonth: String?) -> DashboardRoute {
        guard current, let currentMonth else { return DashboardRoute(category: category, side: side) }
        return DashboardRoute(category: category, side: side, month: currentMonth)
    }
}

struct ChartPoint: Identifiable {
    let index: Int
    let label: String
    let value: Double
    var id: Int { index }
}

@MainActor @Observable
final class DashboardStore {
    private(set) var dashboard: Dashboard?
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
    var generation: Int { session.generation }
    private var fetchGeneration = 0
    private(set) var lastSuccessfulLoad: Date?
    private var foregroundRefreshing = false

    /// Server mode from the start (tests, the server sample).
    convenience init(session: EmpireSession, client: APIClient = APIClient(), sample: Bool = false,
                     widgetPublisher: WidgetSnapshotPublisher = .temporary()) {
        self.init(session: session, backend: ServerBackend(client: client), sample: sample, widgetPublisher: widgetPublisher)
    }

    init(session: EmpireSession, backend: (any AresiumBackend)?, sample: Bool = false,
         widgetPublisher: WidgetSnapshotPublisher = .temporary()) {
        self.session = session
        self.backend = backend
        self.widgetPublisher = widgetPublisher
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
            dashboard = loaded
            lastSuccessfulLoad = .now
            try publishWidget(loaded)
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

    /// Coming to the foreground: the dashboard is built again when it is older than 5 minutes (a new day, a new month).
    /// Server mode also renews its login every 12 hours first, as before.
    func refreshOnForeground(now: Date = .now) async {
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

    /// Where a tap on a category in the start screen leads (`CategoryRoute`).
    func route(category: String, side: DashboardSide, current: Bool) -> DashboardRoute {
        CategoryRoute.route(category: category, side: side, current: current, currentMonth: currentMonth?.key)
    }

    var currentMonth: Month? { dashboard?.months.last }

    func rangeLabel(current: Bool) -> String {
        guard let first = dashboard?.months.first, let last = currentMonth else { return String(localized: "No activity") }
        return current ? last.title() : "\(first.title()) – \(last.title())"
    }

    func totals(current: Bool) -> Totals? {
        guard let dashboard else { return nil }
        if !current { return dashboard.total }
        guard let key = currentMonth?.key else { return nil }
        return dashboard.byMonth[key]?.totals
    }

    func rows(side: DashboardSide, current: Bool) -> [DisplayRow] {
        guard let dashboard, let totals = totals(current: current) else { return [] }
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
        }.sorted {
            $0.day == $1.day ? $0.date < $1.date : $0.day < $1.day
        }.map {
            TransactionRow(transaction: $0, tagged: side == .income
                           ? $0.incomeBuckets.first != category : $0.categoryName != category)
        }
    }

    func startChart(side: DashboardSide, current: Bool) -> [ChartPoint] {
        guard let dashboard else { return [] }
        if current {
            guard let key = currentMonth?.key, let month = dashboard.byMonth[key] else { return [] }
            return (side == .income ? month.dayIncome : month.dayExpense).enumerated().map {
                ChartPoint(index: $0.offset, label: String($0.offset + 1), value: $0.element)
            }
        }
        return monthPoints(side == .income ? dashboard.overview.income : dashboard.overview.expense)
    }

    func categoryChart(_ name: String, side: DashboardSide) -> [ChartPoint] {
        monthPoints(series(name, side: side)?.months ?? [])
    }

    private func monthPoints(_ values: [Double]) -> [ChartPoint] {
        (dashboard?.months ?? []).enumerated().compactMap { index, month in
            guard values.indices.contains(index) else { return nil }
            return ChartPoint(index: index, label: month.shortTitle(), value: values[index])
        }
    }
}
