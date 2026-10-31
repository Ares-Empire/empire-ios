import SwiftUI

// A payment list's rows and what they open (a month's payments, brief 41; a name's page, brief 44; the Cash page's
// movements, brief 47): the row (the website's `.txn`, or the Cash page's movement), its tap (its page), its long press
// (what its page offers, `DashboardStore.rowActions`) and its swipe left ("All from <name>"), and the windows these
// open. One place, so every list behaves alike. A category's list also adds up names (brief 53): the summed row
// (`SummedPaymentRow`), and Add up on the rows of a name with more payments there.

/// What a list's rows have open: the windows their long press opens, the row swiped open, the name's page to show once
/// a payment's page has closed.
@MainActor @Observable
final class PaymentRowMenu {
    /// A payment's change sheet from its row's long press: the sheet its page's Change opens, on a store of its own.
    var changing: TransactionDetailStore?
    /// The payment whose page opens with its name's field ready (the row's long press → Rename, brief 47).
    var renamesPage: String?
    /// A receipt's or entry's Edit from its row's long press: the window its page's Edit opens.
    var receiptEdit: ReceiptPageModel?
    /// The row swiped open (one at a time).
    var openRow: String?
    /// The name's page asked for on a payment's page: shown once that page has closed.
    var pendingName: DashboardRoute?
    /// The row whose page, change sheet or Edit window is open (or was, until it closed).
    var lastOpened: String?
    /// The summed rows shown open, their payments below them (brief 53), by name key. While the list is shown only.
    var openSums: Set<String> = []

    /// Change category: the change sheet at once; it fills as the payment loads, and its Save and the shop question work
    /// as from the page (the tour's switch step, the learned shop, the dashboard built again).
    func change(_ transaction: Transaction, in store: DashboardStore) {
        let detail = store.transactionDetailStore(for: transaction)
        lastOpened = transaction.id
        changing = detail
        Task { await detail.beginRecategorisationFromRow() }
    }

    /// Rename: the payment's page, with the name's field ready once it has loaded (brief 47: the name is edited where
    /// it stands; there is no rename window any more).
    func rename(_ transaction: Transaction, open: (Transaction) -> Void) {
        renamesPage = transaction.id
        open(transaction)
    }

    /// Edit: the receipt's or entry's window, filled from what is stored. If it cannot open (the receipt is gone), the
    /// row's page opens instead and says why.
    func edit(_ transaction: Transaction, in store: DashboardStore, openPage: @escaping () -> Void) {
        guard let phone = store.phone, case let .receipt(id) = store.page(for: transaction) else { return }
        let page = ReceiptPageModel(id: id, phone: phone) { await store.reloadAfterTransactionChange() }
        lastOpened = transaction.id
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
/// page (`allFrom`; nil on a name's own page, whose rows all have that name). The label is a month's row
/// (`PaymentRowLabel`) or, on the Cash page, a movement's (`CashMovementRow`).
struct PaymentRow<Label: View>: View {
    let transaction: Transaction
    let store: DashboardStore
    @Bindable var menu: PaymentRowMenu
    /// The long press and the swipe (brief 41's shortcuts): off while the tour holds the screen.
    var shortcuts = true
    /// The name's page this row is on (its rows offer no "All from" of it).
    var namePage: String? = nil
    var allFrom: ((DashboardRoute) -> Void)? = nil
    /// A category's list (brief 53): this row's name has more payments there and is not added up; Add up does it.
    var addUp: (() -> Void)? = nil
    /// Screenshots only: the row shown so far left, as halfway through a swipe.
    var shownAt: CGFloat? = nil
    let open: (Transaction) -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button { open(transaction) } label: {
            label()
                // The lifted row in Apple's context menu: the row with rounded corners.
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu { if shortcuts { items } }
        .tourAnchor(.payment(transaction.id))
        .rowSwipe(swipes, id: transaction.id, open: $menu.openRow, shownAt: shownAt)
    }

    private var nameRoute: DashboardRoute? {
        allFrom == nil ? nil : store.nameRoute(for: transaction, namePage: namePage)
    }

    /// The swipe: Add up (in a category's list, when the name has more payments there), then "All from <name>" at the
    /// edge, which a full swipe does; each an icon and a short word, the whole name for VoiceOver.
    private var swipes: [RowSwipeAction] {
        guard shortcuts else { return [] }
        var actions: [RowSwipeAction] = []
        if let addUp { actions.append(.addUp(addUp)) }
        if let allFrom, let route = nameRoute { actions.append(.all(route, name: transaction.place, open: allFrom)) }
        return actions
    }

    /// The long press: what the row's page offers, each opening the window that page's button opens, each entry a short
    /// verb or phrase (the row itself, lifted above the menu, shows the name), with Add up as the swipe has it. None (a
    /// covered row) shows no menu.
    @ViewBuilder private var items: some View {
        let actions = (addUp == nil ? store.rowActions(for: transaction, namePage: namePage)
                                    : store.rowActions(for: .payment(TransactionRow(transaction: transaction, tagged: false),
                                                                     addsUp: true)))
            .filter { $0 != .allFromName || allFrom != nil }
        ForEach(actions, id: \.self) { action in
            switch action {
            case .changeCategory:
                Button("Change category", systemImage: "tag") { menu.change(transaction, in: store) }
            case .rename:
                Button("Rename", systemImage: "pencil") { menu.rename(transaction, open: open) }
            case .allFromName:
                // Short whatever the name (brief 47, Patrik: "Alle von MGP Vinted - Kleiderkreisel …" could not be read):
                // the lifted row above the menu already shows the name.
                Button("All with this name", systemImage: "rectangle.stack") {
                    if let route = nameRoute { allFrom?(route) }
                }
            case .edit:
                Button("Edit", systemImage: "pencil") { menu.edit(transaction, in: store) { open(transaction) } }
            case .addUp:
                Button(SumWording.addUp(), systemImage: SumSymbol.addUp) { addUp?() }
            case .separate:
                EmptyView()                   // a summed row's (`SummedPaymentRow`)
            }
        }
    }
}

extension RowSwipeAction {
    /// "All": the name's page ("All from <name>" for VoiceOver), quiet grey at the row's edge (brief 44).
    static func all(_ route: DashboardRoute, name: String, open: @escaping (DashboardRoute) -> Void) -> RowSwipeAction {
        RowSwipeAction(label: String(localized: "All"), systemImage: "rectangle.stack",
                       accessibilityName: NameWording.allFrom(route.name?.title ?? name)) { open(route) }
    }

    /// Add up (brief 53): the name's payments in this category as one row.
    static func addUp(_ perform: @escaping () -> Void) -> RowSwipeAction {
        RowSwipeAction(label: SumWording.addUp(), systemImage: SumSymbol.addUp, accessibilityName: SumWording.addUp(),
                       quiet: true, perform: perform)
    }

    /// Separate (brief 53): a summed row's payments as single rows again.
    static func separate(_ perform: @escaping () -> Void) -> RowSwipeAction {
        RowSwipeAction(label: SumWording.separate(), systemImage: SumSymbol.separate,
                       accessibilityName: SumWording.separate(), quiet: true, perform: perform)
    }
}

extension PaymentRow where Label == PaymentRowLabel {
    /// A month's or a name's page's row.
    init(row: TransactionRow, store: DashboardStore, palette: Palette, menu: PaymentRowMenu, shortcuts: Bool = true,
         namePage: String? = nil, allFrom: ((DashboardRoute) -> Void)? = nil, addUp: (() -> Void)? = nil,
         shownAt: CGFloat? = nil, open: @escaping (Transaction) -> Void) {
        self.init(transaction: row.transaction, store: store, menu: menu, shortcuts: shortcuts, namePage: namePage,
                  allFrom: allFrom, addUp: addUp, shownAt: shownAt, open: open) {
            PaymentRowLabel(transaction: row.transaction, tagged: row.tagged, store: store, palette: palette)
        }
    }
}

#if DEBUG
extension PaymentList {
    /// Screenshots: `-sampleSwipe <points> -swipeRow <text>` on a category's list: the first row whose name contains the
    /// text, a summed row too (any row with `-swipeRow` left out), and how far left it shows.
    func debugSwipe() -> (id: String, points: CGFloat)? {
        guard let points = LaunchArguments.value("-sampleSwipe").flatMap(Double.init) else { return nil }
        let text = LaunchArguments.value("-swipeRow") ?? ""
        guard let entry = entries.first(where: { text.isEmpty || $0.title.localizedCaseInsensitiveContains(text) })
        else { return nil }
        return (entry.id, CGFloat(points))
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
            DayTile(palette: palette) { Text(verbatim: DayWording.alone(transaction.day)) }
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
    /// A bank payment's page opens with its name's field ready (the row's long press → Rename).
    var renames = false
    var openName: ((DashboardRoute) -> Void)? = nil

    var body: some View {
        switch store.page(for: transaction) {
        case let .receipt(id):
            // Phone mode's receipt and cash entry rows open the receipt's page, with its "All from" card (brief 47).
            if let phone = store.phone {
                ReceiptPageSheet(model: ReceiptPageModel(id: id, phone: phone) {
                    await store.reloadAfterTransactionChange()
                }, palette: palette, nameLine: openName == nil ? nil : { store.receiptNameLine(receiptID: id, namePage: namePage) },
                openName: openName)
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
                                   namePage: namePage, startsRenaming: renames, openName: openName)
        }
    }
}

extension View {
    /// A payment list's windows: the open row's page (`selection`; with the name's field ready after the long press's
    /// Rename), and the change and Edit windows of its rows' long press. "All from <name>" on a payment's, receipt's or
    /// entry's page closes the page, then shows the name's page (`pick`), so the name's page is always one on the
    /// dashboard's stack, with the header's arrow and the back swipe. `closed` is told which row's page, change sheet or
    /// Edit window closed (a name's pages follow a rename; a name's month page goes back when the month has none of the
    /// name left, brief 55).
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
                   onDismiss: { menu.changing = nil; windowClosed() }) {
                if let changing = menu.changing { RecategoriseSheet(store: changing, palette: palette) }
            }
            .sheet(isPresented: Binding(get: { menu.receiptEdit?.editing != nil },
                                        set: { if !$0 { menu.receiptEdit?.endEdit() } }),
                   onDismiss: { menu.receiptEdit = nil; windowClosed() }) {
                if let receiptEdit = menu.receiptEdit { ReceiptEditSheet(page: receiptEdit, palette: palette) }
            }
            .sheet(item: $selection, onDismiss: pageClosed) { transaction in
                PaymentPageSheet(transaction: transaction, store: store, palette: palette, namePage: namePage,
                                 renames: menu.renamesPage == transaction.id) { route in
                    menu.pendingName = route
                    selection = nil
                }
            }
            .onChange(of: selection?.id, initial: true) { _, id in
                if let id { menu.lastOpened = id }
            }
    }

    private func windowClosed() {
        if let id = menu.lastOpened { closed(id) }
    }

    private func pageClosed() {
        menu.renamesPage = nil
        windowClosed()
        guard let route = menu.pendingName else { return }
        menu.pendingName = nil
        pick(route)
    }
}

