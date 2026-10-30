import Foundation

/// What a row of a month's payment list opens with a tap (its page), and what its long press offers (brief 41). Both
/// come from here, so the menu never offers what the row's page does not.
enum PaymentRowPage: Equatable {
    /// A bank payment's page (`TransactionDetailSheet`): Change, while the dashboard has categories to change to.
    case payment
    /// Phone mode: a receipt's or cash entry's page (`ReceiptPageSheet`), with Edit.
    case receipt(id: String)
    /// Phone mode: a withdrawal's covered row, the receipts that took its cash (a list: nothing to change on it).
    case covered(receiptIDs: [String])
}

/// An item of a payment row's long press: the same as a button on the row's page, opening the same window.
enum PaymentRowAction: Hashable {
    /// The payment page's Change: the change sheet (Switch or Add), and after a Switch "Also the other payments from
    /// <shop>?".
    case changeCategory
    /// The payment page's name, tapped (brief 44; edited where it stands since brief 47, phone mode, own names on): the
    /// page opens with the name's field ready, and after a new name "Also the other payments from <bank name>?".
    case rename
    /// The "All from <name>" card of a payment's page (brief 44) or of a receipt's or entry's page (brief 47): the name's
    /// page.
    case allFromName
    /// The receipt's or entry's page's Edit: the check window, or Add cash's window, filled from it.
    case edit
}

extension DashboardStore {
    /// The page a payment row opens. Receipts and covered rows are phone mode's (the server sends neither).
    func page(for transaction: Transaction) -> PaymentRowPage {
        if phone != nil, let id = transaction.receiptId { return .receipt(id: id) }
        if phone != nil, let ids = transaction.coveredBy { return .covered(receiptIDs: ids) }
        return .payment
    }

    /// The long press's items for a payment row: what its page offers. The payment page shows Change when there are
    /// categories to change to for its amount (`TransactionDetailStore.choices`, from the same list), Rename in phone
    /// mode while own names are on (`TransactionDetailStore.offersRename`), and "All from <name>" while the name has
    /// other payments, except on that name's own page (`namePage`: the key of the name's page the row is on); a
    /// receipt's or entry's page always has Edit, and "All from <name>" as a payment's page (brief 47); the covered
    /// row's list has nothing to change.
    func rowActions(for transaction: Transaction, namePage: String? = nil) -> [PaymentRowAction] {
        let allFrom: [PaymentRowAction] = nameRoute(for: transaction, namePage: namePage) == nil ? [] : [.allFromName]
        switch page(for: transaction) {
        case .payment:
            let choices = dashboard?.recategorisationChoices(amount: transaction.amount) ?? []
            return (choices.isEmpty ? [] : [.changeCategory])
                + (offersRename(for: transaction) ? [.rename] : [])
                + allFrom
        case .receipt: return [.edit] + allFrom
        case .covered: return []
        }
    }

    // MARK: own names (brief 44)

    /// A bank payment's page offers Rename in phone mode while own names show (off, the bank's names show and a rename
    /// would not be seen). Receipts and cash entries keep their Shop (their Edit).
    func offersRename(for transaction: Transaction) -> Bool {
        phone != nil && ownNames && page(for: transaction) == .payment
    }

    /// The payments of a row's name, when it has more than this one and counts among them (a payment that counts in
    /// no total, such as an own transfer, carries a key but is in no group).
    func shownNameGroup(id: String, key: String?) -> PaymentNameGroup? {
        guard let key, let group = dashboard?.nameGroups?[key], group.count > 1,
              group.rows.contains(where: { $0.id == id }) else { return nil }
        return group
    }

    /// The name's page a row opens with its swipe, its long press and its page's line; nil without other payments of
    /// its name, for a covered row, in server mode, or on that name's own page.
    func nameRoute(for transaction: Transaction, namePage: String? = nil) -> DashboardRoute? {
        guard transaction.coveredBy == nil, let key = transaction.nameKey, key != namePage,
              shownNameGroup(id: transaction.id, key: key) != nil else { return nil }
        return DashboardRoute(name: PaymentNameRoute(key: key, title: transaction.place))
    }

    /// A receipt's or entry's page's "All from <name>" card (brief 47), as a payment's page has it: the receipt's row as
    /// the dashboard has it now (an Edit may have changed its shop), its name's page and group; nil as for its row's
    /// long press (`nameRoute`).
    func receiptNameLine(receiptID: String, namePage: String? = nil) -> NameLine? {
        guard let row = dashboard?.transactions.first(where: { $0.receiptId == receiptID }),
              let route = nameRoute(for: row, namePage: namePage), let name = route.name,
              let group = shownNameGroup(id: row.id, key: name.key) else { return nil }
        return NameLine(route: route, name: name.title, group: group)
    }

    // MARK: the Cash page's rows (brief 47)

    /// The Cash page's movements with the dashboard row each stands for (a withdrawal's payment, a receipt's or entry's
    /// row), so they open, long-press and swipe as a month's list does. Nil for a movement the dashboard lists nowhere
    /// (its row opens the receipt's page, without the shortcuts).
    func cashRows(_ movements: [CashMovement]) -> [CashMovementLine] {
        let transactions = dashboard?.transactions ?? []
        var payments: [String: Transaction] = [:], receipts: [String: Transaction] = [:]
        for row in transactions where row.coveredBy == nil {
            if let id = row.receiptId { receipts[id] = receipts[id] ?? row }
            else { payments[row.id] = payments[row.id] ?? row }
        }
        return movements.map { movement in
            CashMovementLine(movement: movement,
                             transaction: movement.kind == .withdrawal ? payments[movement.id] : receipts[movement.id])
        }
    }
}

/// A page's "All from <name>" card: the name's page it opens, the name it shows and its payments.
struct NameLine {
    let route: DashboardRoute
    let name: String
    let group: PaymentNameGroup
}

/// One row of the Cash page: the movement, and the dashboard's row for it (nil when the dashboard lists none).
struct CashMovementLine: Identifiable {
    let movement: CashMovement
    let transaction: Transaction?
    var id: String { movement.id }
}
