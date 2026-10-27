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
    /// Where the data comes from: the server or the phone's own store (`AresiumBackend`); nil until the app knows the
    /// account's mode (`ModeStore`), so nothing is asked of the wrong one.
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
        // Logout, or no access to Aresium with this login: forget the dashboard and the widget's numbers. (In phone mode
        // the data itself stays on the phone; `ModeStore` only closes its store.)
        session.onAppDataReset { [weak self] in self?.clear() }
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
        isLoading = true
        error = nil
        let generation = generation
        let fetch = fetchGeneration
        let token = session.token          // the login this request goes with; a refusal names it
        defer { if fetch == self.fetchGeneration { isLoading = false } }
        do {
            let loaded: Dashboard
            if isSample { loaded = try Dashboard.sample() }
            else {
                guard let backend else { return }          // the account's mode is not known yet
                loaded = try await backend.dashboard(auth: BackendAuth(token: token) {
                    if fetch == self.fetchGeneration {
                        self.session.handleAuthFailure(HTTPError.unauthorized, generation: generation, token: token)
                    }
                })
                guard generation == self.generation else { return }
            }
            guard generation == self.generation, fetch == fetchGeneration else { return }
            dashboard = loaded
            lastSuccessfulLoad = .now
            // Phone mode without the account server (offline at launch): the store's account names the snapshot.
            try widgetPublisher.publish(loaded, account: session.accountID ?? backend?.account)
        } catch {
            guard generation == self.generation, fetch == fetchGeneration else { return }
            session.handleAuthFailure(error, generation: generation, token: token)
            guard generation == self.generation else { return }
            self.error = error.localizedDescription
        }
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

    func refreshOnForeground(now: Date = .now) async {
        guard !isSample, session.token != nil, !session.isBusy, !foregroundRefreshing, !isLoading else { return }
        foregroundRefreshing = true
        defer { foregroundRefreshing = false }
        let generation = generation
        if session.lastRenewedAt.map({ now.timeIntervalSince($0) > 12 * 60 * 60 }) ?? true {
            await session.restore()
            guard generation == self.generation, session.token != nil else { return }
            if session.needsRestoreRetry { return }
        }
        if lastSuccessfulLoad.map({ now.timeIntervalSince($0) > 5 * 60 }) ?? true { await reload() }
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
