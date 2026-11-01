import Foundation

/// A day's lists before any optional adding up of names. Covered rows retain their own ids and signed amounts.
struct DayPayments {
    struct Row: Identifiable {
        let row: TransactionRow
        /// The primary category on this side, else the first list it belongs to (e.g. server mode's Other).
        let category: Category
        var transaction: Transaction { row.transaction }
        var id: String { row.id }
    }

    struct Side {
        let rows: [Row]
        /// The graph's own number, including the covered-row adjustment on a withdrawal's booking day.
        let total: Double
    }

    let date: String
    let expenses: Side
    let income: Side

    subscript(_ side: DashboardSide) -> Side { side == .expenses ? expenses : income }

    init(date: String, dashboard: Dashboard?) {
        self.date = date
        let month = String(date.prefix(7))
        let day = Int(date.suffix(2)).map { $0 - 1 } ?? -1
        let valid = date.count == 10 && ReceiptDay.date(date).map { ReceiptDay.day($0) == date } == true
        let rows = valid ? (dashboard?.transactions ?? []).filter { $0.date == date && $0.month == month }
            .sorted(by: Transaction.listOrder) : []
        func side(_ side: DashboardSide) -> Side {
            let categories = side == .expenses ? dashboard?.categories : dashboard?.incomeBuckets
            let meta = Dictionary((categories ?? []).map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
            let values = side == .expenses ? dashboard?.byMonth[month]?.dayExpense : dashboard?.byMonth[month]?.dayIncome
            let total = valid && values?.indices.contains(day) == true ? values![day] : 0
            let listed = rows.compactMap { transaction -> Row? in
                let names = side == .expenses ? transaction.categoriesIn : transaction.incomeBuckets
                guard let name = names.contains(transaction.categoryName) && meta[transaction.categoryName] != nil
                        ? transaction.categoryName : names.first(where: { meta[$0] != nil }),
                      let category = meta[name] else { return nil }
                let tagged = side == .income ? transaction.incomeBuckets.first != name : transaction.categoryName != name
                return Row(row: TransactionRow(transaction: transaction, tagged: tagged), category: category)
            }
            return Side(rows: listed, total: total)
        }
        expenses = side(.expenses)
        income = side(.income)
    }
}

struct DayPaymentsCache {
    var revision = -1
    var days: [String: DayPayments] = [:]
}

extension DashboardStore {
    /// `date`: YYYY-MM-DD. Rows keep the month lists' order, with extra categories appearing only once.
    func day(_ date: String) -> DayPayments {
        if builtDays.revision != revision { builtDays = DayPaymentsCache(revision: revision) }
        if let day = builtDays.days[date] { return day }
        let day = DayPayments(date: date, dashboard: dashboard)
        builtDays.days[date] = day
        return day
    }

    /// Zero-based day point on Current or a month's graph. Month points and out-of-range points have no day.
    func dayDate(atChartIndex index: Int, scope: DashboardScope) -> String? {
        guard scope.isMonth, let key = monthKey(scope), let month = dashboard?.byMonth[key],
              month.dayExpense.indices.contains(index) || month.dayIncome.indices.contains(index) else { return nil }
        let date = key + String(format: "-%02d", index + 1)
        guard let parsed = ReceiptDay.date(date), ReceiptDay.day(parsed) == date else { return nil }
        return date
    }
}
