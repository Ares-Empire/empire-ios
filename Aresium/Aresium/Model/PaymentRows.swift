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
    /// The payment page's Rename (brief 44, phone mode, own names on): the rename window, and after a new name "Also the
    /// other payments from <bank name>?".
    case rename
    /// The payment page's "All from <name>" line (brief 44): the name's page.
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
    /// receipt's or entry's page always has Edit, the covered row's list has nothing to change.
    func rowActions(for transaction: Transaction, namePage: String? = nil) -> [PaymentRowAction] {
        switch page(for: transaction) {
        case .payment:
            let choices = dashboard?.recategorisationChoices(amount: transaction.amount) ?? []
            return (choices.isEmpty ? [] : [.changeCategory])
                + (offersRename(for: transaction) ? [.rename] : [])
                + (nameRoute(for: transaction, namePage: namePage) == nil ? [] : [.allFromName])
        case .receipt: return [.edit]
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
}
