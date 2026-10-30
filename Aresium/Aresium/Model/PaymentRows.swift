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
    /// categories to change to for its amount (`TransactionDetailStore.choices`, from the same list), a receipt's or
    /// entry's page always has Edit, the covered row's list has nothing to change.
    func rowActions(for transaction: Transaction) -> [PaymentRowAction] {
        switch page(for: transaction) {
        case .payment:
            let choices = dashboard?.recategorisationChoices(amount: transaction.amount) ?? []
            return choices.isEmpty ? [] : [.changeCategory]
        case .receipt: return [.edit]
        case .covered: return []
        }
    }
}
