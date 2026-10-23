import Foundation
import Observation

enum DashboardSide: String, CaseIterable, Hashable {
    case expenses, income
    var title: String { self == .expenses ? "Expenses" : "Income" }
    var caption: String { self == .expenses ? "spent" : "received" }
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
    private let client: APIClient
    private(set) var generation = 0

    init(session: EmpireSession, client: APIClient = APIClient(), sample: Bool = false) {
        self.session = session
        self.client = client
        isSample = sample
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        let generation = generation
        defer { if generation == self.generation { isLoading = false } }
        do {
            let loaded: Dashboard
            if isSample { loaded = try Dashboard.sample() }
            else {
                guard let token = session.token else { throw HTTPError.unauthorized }
                loaded = try await client.dashboard(token: token) {
                    if generation == self.generation, self.session.token == token { self.session.logOut() }
                }
                guard session.token == token else { return }
            }
            guard generation == self.generation else { return }
            dashboard = loaded
            try session.widgetPublisher.publish(loaded)
        } catch {
            guard generation == self.generation else { return }
            self.error = error.localizedDescription
        }
    }

    func reloadAfterImport() async {
        // Supersede a fetch started before the import, preserving the visible dashboard meanwhile.
        generation += 1
        isLoading = false
        await reload()
    }

    func clear() {
        generation += 1
        isLoading = false
        dashboard = nil
        error = nil
        do { try session.widgetPublisher.clear() } catch { self.error = error.localizedDescription }
    }

    func setWidgetTheme(_ theme: AppTheme) {
        do { try session.widgetPublisher.setTheme(theme) } catch { self.error = error.localizedDescription }
    }

    func transactionDetailStore(for transaction: Transaction) -> TransactionDetailStore {
        TransactionDetailStore(transaction: transaction, dashboardStore: self, client: client)
    }

    // A refresh already in flight may predate the save. Supersede it so the new
    // dashboard always comes from a request made after the transaction changed.
    func reloadAfterTransactionChange() async {
        generation += 1
        isLoading = false
        await reload()
    }

    var currentMonth: Month? { dashboard?.months.last }

    func rangeLabel(current: Bool) -> String {
        guard let first = dashboard?.months.first, let last = currentMonth else { return "No activity" }
        return current ? last.label : "\(first.label) – \(last.label)"
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
            return ChartPoint(index: index, label: month.short, value: values[index])
        }
    }
}
