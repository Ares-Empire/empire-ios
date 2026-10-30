import SwiftUI

// A payment list's rows and what they open (a month's payments, brief 41; a name's page, brief 44): the row as the
// website's `.txn`, its tap (its page), its long press (what its page offers, `DashboardStore.rowActions`) and its swipe
// left ("All from <name>"), and the windows these open. One place, so both lists behave alike.

/// What a list's rows have open: the windows their long press opens, the row swiped open, the name's page to show once
/// a payment's page has closed.
@MainActor @Observable
final class PaymentRowMenu {
    /// A payment's change sheet from its row's long press: the sheet its page's Change opens, on a store of its own.
    var changing: TransactionDetailStore?
    /// A payment's rename window from its row's long press (brief 44).
    var renaming: TransactionDetailStore?
    /// A receipt's or entry's Edit from its row's long press: the window its page's Edit opens.
    var receiptEdit: ReceiptPageModel?
    /// The row swiped open (one at a time).
    var openRow: String?
    /// The name's page asked for on a payment's page: shown once that page has closed.
    var pendingName: DashboardRoute?
    /// The payment whose page is open (or was, until it closed).
    var lastOpened: String?

    /// Change category: the change sheet at once; it fills as the payment loads, and its Save and the shop question work
    /// as from the page (the tour's switch step, the learned shop, the dashboard built again).
    func change(_ transaction: Transaction, in store: DashboardStore) {
        let detail = store.transactionDetailStore(for: transaction)
        changing = detail
        Task { await detail.beginRecategorisationFromRow() }
    }

    /// Rename: the rename window at once, filled as the payment loads.
    func rename(_ transaction: Transaction, in store: DashboardStore) {
        let detail = store.transactionDetailStore(for: transaction)
        renaming = detail
        lastOpened = transaction.id
        Task { await detail.beginRenameFromRow() }
    }

    /// Edit: the receipt's or entry's window, filled from what is stored. If it cannot open (the receipt is gone), the
    /// row's page opens instead and says why.
    func edit(_ transaction: Transaction, in store: DashboardStore, openPage: @escaping () -> Void) {
        guard let phone = store.phone, case let .receipt(id) = store.page(for: transaction) else { return }
        let page = ReceiptPageModel(id: id, phone: phone) { await store.reloadAfterTransactionChange() }
        receiptEdit = page
        Task {
            await page.beginEdit()
            if page.editing == nil {
                receiptEdit = nil
                openPage()
            }
        }
    }
}

/// One row of a payment list: the tap opens its page, the long press what its page offers, the swipe left the name's
/// page (`allFrom`; nil on a name's own page, whose rows all have that name).
struct PaymentRow: View {
    let row: TransactionRow
    let store: DashboardStore
    let palette: Palette
    @Bindable var menu: PaymentRowMenu
    /// The long press and the swipe (brief 41's shortcuts): off while the tour holds the screen.
    var shortcuts = true
    /// The name's page this row is on (its rows offer no "All from" of it).
    var namePage: String? = nil
    var allFrom: ((DashboardRoute) -> Void)? = nil
    /// Screenshots only: the row shown so far left, as halfway through a swipe.
    var shownAt: CGFloat? = nil
    let open: (Transaction) -> Void

    var body: some View {
        let transaction = row.transaction
        Button { open(transaction) } label: {
            PaymentRowLabel(transaction: transaction, tagged: row.tagged, store: store, palette: palette)
                // The lifted row in Apple's context menu: the row with rounded corners.
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu { if shortcuts { items(for: transaction) } }
        .tourAnchor(.payment(transaction.id))
        .rowSwipe(swipe(for: transaction), id: transaction.id, open: $menu.openRow, shownAt: shownAt)
    }

    private func nameRoute(for transaction: Transaction) -> DashboardRoute? {
        allFrom == nil ? nil : store.nameRoute(for: transaction, namePage: namePage)
    }

    /// "All from <name>": an icon and a short word on the swipe, the whole name for VoiceOver.
    private func swipe(for transaction: Transaction) -> RowSwipeAction? {
        guard shortcuts, let allFrom, let route = nameRoute(for: transaction) else { return nil }
        return RowSwipeAction(label: String(localized: "All"), systemImage: "rectangle.stack",
                              accessibilityName: NameWording.allFrom(transaction.place)) { allFrom(route) }
    }

    /// The long press: what the row's page offers, each opening the window that page's button opens. None (a covered
    /// row) shows no menu.
    @ViewBuilder private func items(for transaction: Transaction) -> some View {
        let actions = store.rowActions(for: transaction, namePage: namePage)
            .filter { $0 != .allFromName || allFrom != nil }
        ForEach(actions, id: \.self) { action in
            switch action {
            case .changeCategory:
                Button("Change category", systemImage: "tag") { menu.change(transaction, in: store) }
            case .rename:
                Button("Rename", systemImage: "pencil") { menu.rename(transaction, in: store) }
            case .allFromName:
                Button { if let route = nameRoute(for: transaction) { allFrom?(route) } } label: {
                    Label(NameWording.allFrom(transaction.place), systemImage: "rectangle.stack")
                }
            case .edit:
                Button("Edit", systemImage: "pencil") { menu.edit(transaction, in: store) { open(transaction) } }
            }
        }
    }
}

#if DEBUG
extension Array where Element == TransactionRow {
    /// Screenshots: `-sampleSwipe <points> -swipeRow <text>`: the first of these rows whose name contains the text
    /// (any row with `-swipeRow` left out), and how far left it shows.
    func debugSwipe() -> (id: String, points: CGFloat)? {
        guard let points = LaunchArguments.value("-sampleSwipe").flatMap(Double.init) else { return nil }
        let text = LaunchArguments.value("-swipeRow") ?? ""
        guard let row = first(where: { text.isEmpty || $0.transaction.place.localizedCaseInsensitiveContains(text) })
        else { return nil }
        return (row.id, CGFloat(points))
    }
}
#endif

/// A payment row as a month's list draws it (the website's `.txn`): the day, who (or the receipt's words) with its
/// marks, its second line, the amount.
struct PaymentRowLabel: View {
    let transaction: Transaction
    let tagged: Bool
    let store: DashboardStore
    let palette: Palette

    var body: some View {
        HStack(spacing: 12) {
            DayTile(palette: palette) { Text(String(transaction.day)) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(verbatim: ReceiptRowWording.title(transaction, movement: store.cashMovement(transaction.receiptId)))
                        .font(AppFont.text(14.5, weight: .semibold)).lineLimit(1)
                    if transaction.isWaitingReceipt {
                        // A card receipt counted until its bank payment comes: a quiet mark.
                        Image(systemName: "clock").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.muted)
                            .accessibilityLabel(Text("Waiting for the bank statement"))
                    }
                    if tagged {
                        Text("tag").font(AppFont.text(9, weight: .semibold)).foregroundStyle(palette.secondary)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(palette.card2, in: RoundedRectangle(cornerRadius: 4))
                            .accessibilityLabel("Added here by tag; primary category \(CategoryName.shown(transaction.categoryName))")
                    }
                }
                Text(verbatim: ReceiptRowWording.line(transaction, movement: store.cashMovement(transaction.receiptId))).font(AppFont.text(12.5))
                    .foregroundStyle(palette.muted).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(Money.transaction(transaction.amount)).font(AppFont.number(14))
                .foregroundStyle(transaction.amount < 0 ? palette.expenseText : palette.income).fixedSize()
        }.padding(.horizontal, 12).padding(.vertical, 11).contentShape(Rectangle())
    }
}

/// A row's page: a bank payment's (`TransactionDetailSheet`), or in phone mode a receipt's or entry's, or a covered
/// row's receipts.
struct PaymentPageSheet: View {
    let transaction: Transaction
    let store: DashboardStore
    let palette: Palette
    var namePage: String? = nil
    var openName: ((DashboardRoute) -> Void)? = nil

    var body: some View {
        switch store.page(for: transaction) {
        case let .receipt(id):
            // Phone mode's receipt and cash entry rows open the receipt's page.
            if let phone = store.phone {
                ReceiptPageSheet(model: ReceiptPageModel(id: id, phone: phone) {
                    await store.reloadAfterTransactionChange()
                }, palette: palette)
            }
        case let .covered(receiptIDs):
            // A withdrawal's covered row: the receipts that took its cash.
            if let phone = store.phone {
                CoveredReceiptsSheet(phone: phone, receiptIDs: receiptIDs, palette: palette) {
                    await store.reloadAfterTransactionChange()
                }
            }
        case .payment:
            TransactionDetailSheet(store: store.transactionDetailStore(for: transaction), palette: palette,
                                   namePage: namePage, openName: openName)
        }
    }
}

extension View {
    /// A payment list's windows: the open row's page (`selection`), and the change, rename and Edit windows of its
    /// rows' long press. "All from <name>" on a payment's page closes the page, then shows the name's page (`pick`), so
    /// the name's page is always one on the dashboard's stack, with the header's arrow and the back swipe. `closed` is
    /// told which payment's page or rename window closed (the name's page follows a rename).
    func paymentListSheets(_ menu: PaymentRowMenu, store: DashboardStore, palette: Palette,
                           selection: Binding<Transaction?>, namePage: String? = nil,
                           pick: @escaping (DashboardRoute) -> Void,
                           closed: @escaping (String) -> Void = { _ in }) -> some View {
        modifier(PaymentListSheets(menu: menu, store: store, palette: palette, selection: selection, namePage: namePage,
                                   pick: pick, closed: closed))
    }
}

private struct PaymentListSheets: ViewModifier {
    @Bindable var menu: PaymentRowMenu
    let store: DashboardStore
    let palette: Palette
    @Binding var selection: Transaction?
    let namePage: String?
    let pick: (DashboardRoute) -> Void
    let closed: (String) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(get: { menu.changing?.showsRecategorisation == true },
                                        set: { if !$0 { menu.changing?.showsRecategorisation = false } }),
                   onDismiss: { menu.changing = nil }) {
                if let changing = menu.changing { RecategoriseSheet(store: changing, palette: palette) }
            }
            .sheet(isPresented: Binding(get: { menu.renaming?.showsRename == true },
                                        set: { if !$0 { menu.renaming?.showsRename = false } }),
                   onDismiss: {
                       if let id = menu.renaming?.paymentID { closed(id) }
                       menu.renaming = nil
                   }) {
                if let renaming = menu.renaming { RenameSheet(store: renaming, palette: palette) }
            }
            .sheet(isPresented: Binding(get: { menu.receiptEdit?.editing != nil },
                                        set: { if !$0 { menu.receiptEdit?.endEdit() } }),
                   onDismiss: { menu.receiptEdit = nil }) {
                if let receiptEdit = menu.receiptEdit { ReceiptEditSheet(page: receiptEdit, palette: palette) }
            }
            .sheet(item: $selection, onDismiss: pageClosed) { transaction in
                PaymentPageSheet(transaction: transaction, store: store, palette: palette, namePage: namePage) { route in
                    menu.pendingName = route
                    selection = nil
                }
            }
            .onChange(of: selection?.id, initial: true) { _, id in
                if let id { menu.lastOpened = id }
            }
    }

    private func pageClosed() {
        if let id = menu.lastOpened { closed(id) }
        guard let route = menu.pendingName else { return }
        menu.pendingName = nil
        pick(route)
    }
}
