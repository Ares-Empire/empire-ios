import SwiftUI

/// A name's page (brief 44): every payment of one name over all months, from a payment's "All from <name>" line, its
/// row's swipe left or its long press. Pushed on the dashboard's stack (`DashboardRoute.name`), under the header with the
/// name as its title, so the header's arrow and the back swipe go back. The totals (money out; in only when there is
/// any) and the count, the switch that adds the name up in every category (brief 53), the graph above the months as on a
/// category's page, then the months with payments as a category's months (brief 55, Patrik: "make each month just as
/// the other months"): a month's row or its point on the graph opens that month's payments of the name
/// (`NameMonthScreen`). The numbers come from `NamePage`, built once per dashboard (`DashboardStore.namePage`).
struct NameScreen: View {
    let route: PaymentNameRoute
    let store: DashboardStore
    let palette: Palette
    let band: AresiumBand
    /// The graph above the months, drawn as a category's page draws it (Settings → Dashboard → Graph, `GraphSetting`).
    var showsGraph = true
    let pick: (DashboardRoute) -> Void

    var body: some View {
        VStack(spacing: 0) {
            DashboardStatus(store: store, palette: palette)
            WordmarkScrollView {
                if let page = store.namePage(route.key) {
                    content(page)
                } else if store.dashboard != nil {
                    EmptyMessage(text: String(localized: "No payments with this name any more."), palette: palette)
                }
            } band: { _ in band }
            .refreshable { await store.reload() }.scrollBounceBehavior(.always)
        }
    }

    private func content(_ page: NamePage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            totals(page).padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 8)
            // Brief 53: this name added up in every category's payments (phone mode, where names are).
            if store.offersSums {
                NameSumSwitch(key: route.key, sums: store.sums, palette: palette)
                    .padding(.horizontal, 12).padding(.top, 2).padding(.bottom, 6)
            }
            if showsGraph {
                SeriesChart(points: page.chart, color: Color(hex: page.category.color), palette: palette,
                            xTitle: String(localized: "Month")) { index in
                    guard let months = store.dashboard?.months, months.indices.contains(index) else { return }
                    open(months[index].key, page: page)
                }
                .frame(height: SeriesChart.dashboardHeight)
            }
            LazyVStack(spacing: 0) {
                let maximum = page.months.map(\.total).max() ?? 0
                ForEach(page.months) { row in
                    Button { open(row.month.key, page: page) } label: {
                        ValueRow(title: row.month.title(), category: page.category, total: row.total, maximum: maximum,
                                 palette: palette, amount: otherSide(row, page: page))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.top, 8)
        }
    }

    /// The count and the time span over the money out (and in, when there is any), as the start screen's heading.
    private func totals(_ page: NamePage) -> some View {
        let both = page.moneyOut > 0 && page.moneyIn > 0
        return VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: NameWording.pageLine(count: page.count, range: page.range).uppercased())
                .font(AppFont.text(11, weight: .semibold)).tracking(1.3).foregroundStyle(palette.muted)
            if page.moneyOut > 0 || page.moneyIn == 0 {
                amount(Text("Spent"), page.moneyOut, color: palette.expenseText, size: 21)
            }
            if page.moneyIn > 0 {
                amount(Text("Received"), page.moneyIn, color: palette.income, size: both ? 17 : 21)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func amount(_ title: Text, _ value: Double, color: Color, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            title.font(AppFont.text(size, weight: .bold)).foregroundStyle(color)
            Spacer(minLength: 4)
            Text(Money.precise(value)).font(AppFont.number(size, weight: .bold)).minimumScaleFactor(0.7).lineLimit(1)
        }
    }

    /// A month with only money the other way (a refund of a name that spends): its row writes that money, signed and
    /// coloured as its payment's row, where the empty bar would say nothing.
    private func otherSide(_ row: NamePage.MonthAmount, page: NamePage) -> Text? {
        guard row.total == 0, row.other > 0 else { return nil }
        return Text(verbatim: NameWording.otherSide(row.other, spends: page.spends))
            .foregroundStyle(page.spends ? palette.income : palette.expenseText)
    }

    /// A month's row or graph point: that month's payments of the name, on a page of their own (a month without any
    /// has no row, and its point opens nothing).
    private func open(_ month: String, page: NamePage) {
        guard page.month(month) != nil else { return }
        pick(DashboardRoute(name: route, month: month))
    }
}

/// A name's payments in one month (brief 55): pushed from a month's row or the graph on the name's page, under the
/// header with the name as its title and the month as the line under it ("Oct 2026 · activities", as a category's month
/// list), so the arrow and the back swipe go back to the name's page. Its rows are a category's month list's
/// (`PaymentRow`: the tap opens the payment's page, the long press, the swipe with All, which goes back to the name's
/// page below), without Add up: every row has the same name. The rows come from `NamePage`, built once per dashboard.
/// A payment renamed or moved from here: the name's pages follow a rename that takes the name along
/// (`NamePageStep`), and the page goes back one page when the month has no payments of the name left.
struct NameMonthScreen: View {
    let route: PaymentNameRoute
    /// `YYYY-MM`.
    let month: String
    let store: DashboardStore
    let palette: Palette
    let band: AresiumBand
    /// The rows' long press and swipe (`DashboardStack.shortcuts`).
    var shortcuts = true
    let pick: (DashboardRoute) -> Void
    /// The name's pages on the stack show another name in place (`DashboardStack.follow`).
    let follow: (_ from: PaymentNameRoute, _ to: PaymentNameRoute) -> Void
    /// One page back: the month has no payments of the name left.
    let back: () -> Void
    @State private var opened: Transaction?
    @State private var menu = PaymentRowMenu()

    var body: some View {
        let rows = store.namePage(shownRoute.key)?.month(month)?.rows ?? []
        VStack(spacing: 0) {
            DashboardStatus(store: store, palette: palette)
            WordmarkScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        PaymentRow(row: row, store: store, palette: palette, menu: menu, shortcuts: shortcuts,
                                   allFrom: pick) {
                            opened = $0
                        }
                    }
                    if rows.isEmpty && store.dashboard != nil {
                        EmptyMessage(text: String(localized: "No transactions this month."), palette: palette)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 8)
            } band: { _ in band }
            .refreshable { await store.reload() }.scrollBounceBehavior(.always)
            .closesRowSwipe($menu.openRow)          // as the month's list: a scroll closes an open row
        }
        .paymentListSheets(menu, store: store, palette: palette, selection: $opened, pick: pick, closed: settle)
    }

    /// While a payment opened here has just taken the whole name elsewhere (its shop renamed), the page already shows
    /// the new name's payments under the open window; the stack follows once it closes (`settle`).
    private var shownRoute: PaymentNameRoute {
        guard let dashboard = store.dashboard, dashboard.nameGroups?[route.key] == nil, let id = menu.lastOpened,
              let next = route.following(dashboard.transactions.first { $0.id == id }, groups: dashboard.nameGroups)
        else { return route }
        return next
    }

    /// A row's page, change sheet or Edit window closed: follow a rename that took the name along, and go back when the
    /// month has no payments of the name left.
    private func settle(_ id: String) {
        let payment = store.dashboard?.transactions.first { $0.id == id }
        let step = NamePageStep(after: payment, route: route, month: month, groups: store.dashboard?.nameGroups)
        if let next = step.follow { follow(route, next) }
        if step.back { back() }
    }
}
