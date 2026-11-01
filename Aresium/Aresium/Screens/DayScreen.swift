import SwiftUI

/// A day's page (brief 77): a sheet from a tap on a day of a day graph (the start screen's Current, a month's page), so
/// a sideways swipe turns its two sides and a swipe down closes it (on a pushed page a swipe right is the back swipe).
/// The day written out as its title, the Expenses/Income dots as the start screen has them, and the two sides side by
/// side as its pages: each the day's total in the start screen's heading and the day's rows as a month's list draws
/// them, with the category in the day's place (`PaymentRow(day:)`: the tap opens the payment's page, the long press
/// what that page offers; no swipe of their own, since a swipe left turns to Income here). It opens on the side that
/// was tapped. The rows come from `DashboardStore.day(_:)`, built once per dashboard and read in `body`, so after a
/// payment's page or change window closes the page shows the store as it is now.
struct DaySheet: View {
    let day: DayRoute
    let store: DashboardStore
    let palette: Palette
    /// The rows' long press (off while the tour holds the screen, `DashboardStack.shortcuts`).
    var shortcuts = true
    /// A name's page (a row's "All with this name", a payment page's "All from"): the sheet closes, then it is pushed
    /// on the dashboard's stack.
    let pick: (DashboardRoute) -> Void
    @State private var side: DashboardSide
    /// The payment whose page is open over this one.
    @State private var opened: Transaction?
    @State private var menu = PaymentRowMenu()
    @Environment(\.dismiss) private var dismiss

    init(day: DayRoute, store: DashboardStore, palette: Palette, shortcuts: Bool = true,
         pick: @escaping (DashboardRoute) -> Void) {
        self.day = day
        self.store = store
        self.palette = palette
        self.shortcuts = shortcuts
        self.pick = pick
        _side = State(initialValue: day.side)
    }

    var body: some View {
        let payments = store.day(day.date)
        NavigationStack {
            VStack(spacing: 0) {
                Text(verbatim: DayPageWording.title(day.date))
                    .font(AppFont.text(22, weight: .bold)).foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 18).padding(.top, 2)
                // The dots' tap area reaching over the pages lies above them (`zIndex`), as on the start screen.
                PageDots(side: $side, palette: palette).padding(.top, 12).padding(.vertical, 2).zIndex(1)
                TabView(selection: $side) {
                    ForEach(DashboardSide.allCases, id: \.self) { page in
                        DaySidePage(side: page, payments: payments[page], store: store, palette: palette, menu: menu,
                                    shortcuts: shortcuts, pick: pick) { opened = $0 }
                            .tag(page)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background { Wall(palette: palette) }
            .tourSpotlight()
            .tourCard()
            .navigationTitle(Text("Day")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .font(AppFont.text(14)).foregroundStyle(palette.ink).tint(palette.ink)
        .paymentListSheets(menu, store: store, palette: palette, selection: $opened, pick: pick)
    }
}

/// One side of a day: its total under the side's word, as the start screen heads a page, then its rows, or one quiet
/// line when it has none.
private struct DaySidePage: View {
    let side: DashboardSide
    let payments: DayPayments.Side
    let store: DashboardStore
    let palette: Palette
    let menu: PaymentRowMenu
    let shortcuts: Bool
    let pick: (DashboardRoute) -> Void
    let open: (Transaction) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SideTotal(side: side, total: Money.precise(payments.total), palette: palette)
                    .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 8)
                LazyVStack(spacing: 0) {
                    ForEach(payments.rows) { row in
                        PaymentRow(day: row, store: store, palette: palette, menu: menu, shortcuts: shortcuts,
                                   allFrom: pick, open: open)
                    }
                    if payments.rows.isEmpty {
                        EmptyMessage(text: DayPageWording.empty(side), palette: palette)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 8)
            }
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .tourScrollsToTarget()
    }
}
