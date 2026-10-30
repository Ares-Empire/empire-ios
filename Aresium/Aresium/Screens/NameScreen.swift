import SwiftUI

/// A name's page (brief 44): every payment of one name over all months, from a payment's "All from <name>" line, its
/// row's swipe left or its long press. Pushed on the dashboard's stack (`DashboardRoute.name`), under the header with the
/// name as its title, so the header's arrow and the back swipe go back. The totals (money out; in only when there is
/// any) and the count, the switch that adds the name up in every category (brief 53), the graph above the months as on a
/// category's page, the months with payments as the category page's bars (a tap shows that month's payments below), then
/// the payments newest first under their months, each opening its page as on a month's list. The numbers come from
/// `NamePage`.
struct NameScreen: View {
    let route: PaymentNameRoute
    let store: DashboardStore
    let palette: Palette
    let band: AresiumBand
    /// The graph above the months, drawn as a category's page draws it (Settings → Dashboard → Graph, `GraphSetting`).
    var showsGraph = true
    /// The rows' long press (`DashboardStack.shortcuts`).
    var shortcuts = true
    let pick: (DashboardRoute) -> Void
    /// Shows another page in this one's place (`DashboardStack`): after a rename this page follows its name.
    let replace: (DashboardRoute) -> Void
    @State private var opened: Transaction?
    @State private var menu = PaymentRowMenu()

    var body: some View {
        let shown = shownRoute
        VStack(spacing: 0) {
            DashboardStatus(store: store, palette: palette)
            ScrollViewReader { proxy in
                WordmarkScrollView {
                    if let dashboard = store.dashboard, let group = dashboard.nameGroups?[shown.key] {
                        content(NamePage(group: group, dashboard: dashboard), key: shown.key, proxy: proxy)
                    } else if store.dashboard != nil {
                        EmptyMessage(text: String(localized: "No payments with this name any more."), palette: palette)
                    }
                } band: { _ in band }
                .refreshable { await store.reload() }.scrollBounceBehavior(.always)
                .closesRowSwipe($menu.openRow)          // as the month's list: a scroll closes an open row
            }
        }
        .paymentListSheets(menu, store: store, palette: palette, selection: $opened, namePage: shown.key, pick: pick,
                           closed: follow)
    }

    /// While a payment opened here has just taken the whole name elsewhere (its shop renamed), this page already shows
    /// the new name's payments under the open window; the header follows once it closes (`follow`).
    private var shownRoute: PaymentNameRoute {
        guard let dashboard = store.dashboard, dashboard.nameGroups?[route.key] == nil, let id = menu.lastOpened,
              let next = route.following(dashboard.transactions.first { $0.id == id }, groups: dashboard.nameGroups)
        else { return route }
        return next
    }

    /// A payment's page or rename window closed: the page follows a rename that moved its name.
    private func follow(_ id: String) {
        let payment = store.dashboard?.transactions.first { $0.id == id }
        if let next = route.following(payment, groups: store.dashboard?.nameGroups) { replace(DashboardRoute(name: next)) }
    }

    private func content(_ page: NamePage, key: String, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            totals(page).padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 8)
            // Brief 53: this name added up in every category's payments (phone mode, where names are).
            if store.offersSums {
                NameSumSwitch(key: key, sums: store.sums, palette: palette)
                    .padding(.horizontal, 12).padding(.top, 2).padding(.bottom, 6)
            }
            if showsGraph {
                SeriesChart(points: page.chart, color: Color(hex: page.category.color), palette: palette,
                            xTitle: String(localized: "Month")) { index in
                    guard let months = store.dashboard?.months, months.indices.contains(index) else { return }
                    show(months[index].key, page: page, proxy: proxy)
                }
                .frame(height: SeriesChart.dashboardHeight)
            }
            LazyVStack(spacing: 0) {
                let maximum = page.months.map(\.total).max() ?? 0
                ForEach(page.months) { row in
                    Button { show(row.month.key, page: page, proxy: proxy) } label: {
                        ValueRow(title: row.month.title(), category: page.category, total: row.total, maximum: maximum,
                                 palette: palette, accessory: "chevron.down")
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Shows this month's payments below"))
                }
            }
            .padding(.horizontal, 12).padding(.top, 8)
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(page.sections) { section in
                    Text(verbatim: section.title.uppercased()).font(AppFont.text(11, weight: .semibold)).tracking(1.3)
                        .foregroundStyle(palette.muted)
                        .padding(.horizontal, 12).padding(.top, 18).padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)
                        .id(Self.sectionID(section.month))
                    ForEach(section.rows) { transaction in
                        PaymentRow(row: TransactionRow(transaction: transaction, tagged: false), store: store,
                                   palette: palette, menu: menu, shortcuts: shortcuts, namePage: key, allFrom: pick) {
                            opened = $0
                        }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.top, 4)
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

    /// A month's bar or graph point: its payments below come into view (a month without payments has nothing to show).
    private func show(_ month: String, page: NamePage, proxy: ScrollViewProxy) {
        guard page.sections.contains(where: { $0.month == month }) else { return }
        withAnimation { proxy.scrollTo(Self.sectionID(month), anchor: .top) }
    }

    private static func sectionID(_ month: String) -> String { "name-month:" + month }
}
