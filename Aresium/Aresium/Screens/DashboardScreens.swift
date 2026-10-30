import SwiftUI

struct DashboardRoute: Hashable {
    let category: String
    let side: DashboardSide
    var month: String? = nil
    /// The Cash page (brief 33): a month's (with `month`) or its months (Overview); `category` is unused.
    var cash = false
    /// A name's page (brief 44): every payment of one name; `category` is unused (`init(name:)`).
    var name: PaymentNameRoute? = nil
}

/// Where a dashboard is: the screens pushed, Current or Overview, the expenses or income page, the payment open. The
/// person's dashboard keeps it in `ContentView`, the tour's in `TourModel` (so the tour can move it). Whether the graph
/// shows is no part of it: that is a setting (`GraphSetting`, brief 42).
struct DashboardPlace {
    var path: [DashboardRoute] = []
    var current = true
    var side = DashboardSide.expenses
    /// The payment whose detail is open.
    var payment: Transaction?
}

/// The dashboard's navigation: the start screen (or what the owner shows in its place), a category's months and a month's
/// payments, each under the owner's header. The person's dashboard and the tour's are this same view on their own stores.
struct DashboardStack<Top: View, Root: View>: View {
    let store: DashboardStore
    let palette: Palette
    @Binding var place: DashboardPlace
    /// The graph on the category pages (Settings → Dashboard → Graph, `GraphSetting`); the start screen is the owner's.
    let graph: Bool
    let band: AresiumBand
    /// The shortcuts: the back swipe on a pushed screen (`.backSwipe`, brief 38), which does what the header's back arrow
    /// does, and the payment rows' long press (brief 41), which does what a payment's or receipt's page does. They are on
    /// wherever those take taps; the tour turns them off while it holds the screen (`TourModel.holdsTheScreen`).
    var shortcuts = true
    /// The header (and any line under it) of the start screen (nil) or a pushed screen.
    @ViewBuilder let top: (DashboardRoute?) -> Top
    /// The start screen.
    @ViewBuilder let root: () -> Root

    var body: some View {
        NavigationStack(path: $place.path) {
            VStack(spacing: 0) {
                top(nil)
                root()
            }
            .background { Wall(palette: palette) }
            .toolbar(.hidden, for: .navigationBar)
            .tourSpotlight()
            .navigationDestination(for: DashboardRoute.self) { route in
                VStack(spacing: 0) {
                    top(route)
                    if let name = route.name {
                        NameScreen(route: name, store: store, palette: palette, band: band, showsGraph: graph,
                                   shortcuts: shortcuts,
                                   pick: { place.path.append($0) }, replace: replaceTop)
                    } else if route.cash, let month = route.month {
                        CashScreen(month: month, store: store, palette: palette, band: band, shortcuts: shortcuts) {
                            place.path.append($0)
                        }
                    } else if route.cash {
                        CashMonthsScreen(store: store, palette: palette, band: band) { place.path.append($0) }
                    } else if route.month != nil {
                        TransactionsScreen(route: route, store: store, palette: palette, band: band,
                                           selection: $place.payment, rowMenus: shortcuts) { place.path.append($0) }
                    } else {
                        CategoryScreen(route: route, store: store, palette: palette, graph: graph,
                                       band: band) { place.path.append($0) }
                    }
                }
                .background { Wall(palette: palette) }
                .toolbar(.hidden, for: .navigationBar)
                // The bar is hidden (the header is the app's own); this keeps the system's back swipe, which a hidden
                // bar turns off. The edge swipe and the swipe from anywhere both: no pushed screen reads sideways drags
                // (the graph takes taps), and the start page's sideways swipe is on the root, which stays the system's.
                .backSwipe(shortcuts)
                .tourSpotlight()
            }
        }
        .task { if store.dashboard == nil { await store.reload() } }
    }

    /// The screen on top shows another page in its place, without the push animation (a name's page following a
    /// rename, `PaymentNameRoute.following`).
    private func replaceTop(_ route: DashboardRoute) {
        guard !place.path.isEmpty else { return }
        var quiet = SwiftUI.Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { place.path[place.path.count - 1] = route }
    }
}

struct StartScreen: View {
    let store: DashboardStore
    let imports: ImportStore
    let palette: Palette
    @Binding var current: Bool
    @Binding var side: DashboardSide
    /// The graph above the pages (Settings → Dashboard → Graph, `GraphSetting`).
    let graph: Bool
    let band: AresiumBand
    /// Phone mode and the tour: Import's menu (Choose file, Scan receipt, Choose photo; in the tour each only answers
    /// its step, `TourModel.importTapped`). Nil: server mode's import button.
    var importChoices: ImportChoices? = nil
    /// "How do I get my file?" under an empty page (nil: not offered).
    var openGuide: (() -> Void)? = nil
    let pick: (DashboardRoute) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Range", selection: $current) {
                    Text("Current").tag(true)
                    Text("Overview").tag(false)
                }.pickerStyle(.segmented).frame(maxWidth: 235)
                    .tourAnchor(.range)
                Spacer()
                ImportButton(store: imports, sample: store.isSample, palette: palette, choices: importChoices)
                    .tourAnchor(.importButton)
            }.padding(.horizontal, 14).padding(.bottom, 8)
            DashboardStatus(store: store, palette: palette)
            if graph {
                SeriesChart(points: store.startChart(side: side, current: current),
                            color: side == .income ? palette.income : palette.expense,
                            palette: palette, xTitle: current ? String(localized: "Day") : String(localized: "Month"))
                    .frame(height: SeriesChart.dashboardHeight)
                    .tourAnchor(.graph)
            }
            // The page dots: each takes taps over 44 × 44 pt (brief 41; they were 30 × 24) while the row keeps its height
            // in the layout (24 pt and its padding); the area reaching over the pages below lies above them (`zIndex`).
            HStack(spacing: 0) {
                ForEach(DashboardSide.allCases, id: \.self) { page in
                    Button { withAnimation(reduceMotion ? nil : .default) { side = page } } label: {
                        Circle().fill(page == side ? palette.ink : palette.muted.opacity(0.5))
                            .frame(width: page == side ? 8 : 7, height: page == side ? 8 : 7)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(page.title)
                        .accessibilityAddTraits(page == side ? .isSelected : [])
                }
            }.padding(.vertical, -10).tourAnchor(.pageDots).padding(.vertical, 2).zIndex(1)
            TabView(selection: $side) {
                ForEach(DashboardSide.allCases, id: \.self) { page in
                    StartPage(store: store, palette: palette, side: page, current: current, band: band,
                              openGuide: openGuide, pick: pick).tag(page)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
        }
    }
}

private struct StartPage: View {
    let store: DashboardStore
    let palette: Palette
    let side: DashboardSide
    let current: Bool
    let band: AresiumBand
    var openGuide: (() -> Void)?
    let pick: (DashboardRoute) -> Void
    private var rows: [DisplayRow] { store.rows(side: side, current: current) }
    var body: some View {
        ScrollViewReader { proxy in
            WordmarkScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.rangeLabel(current: current).uppercased()).font(AppFont.text(11, weight: .semibold))
                            .tracking(1.3).foregroundStyle(palette.muted)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(side.title).font(AppFont.text(21, weight: .bold))
                                .foregroundStyle(side == .income ? palette.income : palette.expenseText)
                            Spacer(minLength: 4)
                            if let totals = store.totals(current: current) {
                                Text(Money.total(side == .income ? totals.income : totals.expense))
                                    .font(AppFont.number(21, weight: .bold)).minimumScaleFactor(0.7).lineLimit(1)
                                Text(side.caption).font(AppFont.text(11)).foregroundStyle(palette.muted)
                            }
                        }
                    }.padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 8)
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            // Current: this month's payments of the category at once; Overview: its months.
                            Button { pick(store.route(category: row.category.name, side: side, current: current)) } label: {
                                ValueRow(title: row.category.shownName, category: row.category, total: row.total,
                                         maximum: rows.map(\.total).max() ?? 0, palette: palette)
                            }.buttonStyle(.plain)
                                .tourAnchor(.category(row.category.name))
                        }
                        if rows.isEmpty && !store.isLoading {
                            EmptyMessage(text: side == .income ? String(localized: "No income recorded.")
                                                                       : String(localized: "No spending recorded."),
                                         palette: palette)
                            if let openGuide { GuideLink(tint: palette.secondary, action: openGuide).padding(.top, -14) }
                        }
                        // The Cash page (brief 33): below the categories, only when there is any cash movement. It
                        // counts in no total, so a hairline sets it apart from the categories above.
                        if store.hasCash {
                            Rectangle().fill(palette.grid).frame(height: 1).padding(.horizontal, 12).padding(.vertical, 6)
                            Button { pick(store.cashRoute(current: current)) } label: {
                                CashRow(store: store, palette: palette, current: current)
                            }
                            .buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 12).padding(.top, 8)
                }
            } band: { _ in band }
            .refreshable { await store.reload() }.scrollBounceBehavior(.always)
            .tourScrollsToTarget()
            #if DEBUG
            .task(id: store.dashboard == nil) {
                // Screenshots: `-scrollToEnd` shows the band.
                guard store.dashboard != nil, LaunchArguments.current.contains("-scrollToEnd") else { return }
                try? await Task.sleep(for: .milliseconds(300))
                proxy.scrollToWordmark()
            }
            #endif
        }
    }
}

struct CategoryScreen: View {
    let route: DashboardRoute
    let store: DashboardStore
    let palette: Palette
    /// The graph above the months (Settings → Dashboard → Graph, `GraphSetting`).
    let graph: Bool
    let band: AresiumBand
    let pick: (DashboardRoute) -> Void
    private var category: Category? { store.category(route.category, side: route.side) }
    private var months: [MonthRow] { store.months(category: route.category, side: route.side) }

    var body: some View {
        let category = category
        let months = months
        VStack(spacing: 0) {
            DashboardStatus(store: store, palette: palette)
            if graph, let category, !months.isEmpty {
                // Above the months, as on the start screen and at its height: about eight months show below it on an
                // iPhone 17. A tap on a month's point opens that month, as its row does; VoiceOver reads the rows.
                SeriesChart(points: store.categoryChart(route.category, side: route.side),
                            color: Color(hex: category.color), palette: palette, xTitle: String(localized: "Month")) { index in
                    guard let allMonths = store.dashboard?.months, allMonths.indices.contains(index) else { return }
                    open(allMonths[index].key)
                }
                .frame(height: SeriesChart.dashboardHeight)
            }
            WordmarkScrollView {
                if let category {
                    LazyVStack(spacing: 0) {
                        ForEach(months) { row in
                            Button { open(row.month.key) } label: {
                                ValueRow(title: row.month.title(), category: category, total: row.total,
                                         maximum: months.map(\.total).max() ?? 0, palette: palette)
                            }.buttonStyle(.plain)
                        }
                        if months.isEmpty { EmptyMessage(text: String(localized: "No activity recorded."), palette: palette) }
                    }.padding(.horizontal, 12).padding(.top, 8)
                } else { EmptyMessage(text: String(localized: "This category is no longer available."), palette: palette) }
            } band: { _ in band }
            .refreshable { await store.reload() }.scrollBounceBehavior(.always)
        }
    }

    /// A month of this category: its payments.
    private func open(_ month: String) {
        pick(DashboardRoute(category: route.category, side: route.side, month: month))
    }
}

struct TransactionsScreen: View {
    let route: DashboardRoute
    let store: DashboardStore
    let palette: Palette
    let band: AresiumBand
    /// The payment whose detail is open (the dashboard's place).
    @Binding var selection: Transaction?
    /// The rows' long press (brief 41) and swipe (brief 44); off while the tour holds the screen
    /// (`DashboardStack.shortcuts`).
    var rowMenus = true
    /// Shows a name's page on the dashboard's stack (the rows' swipe and long press, a payment page's line).
    var pick: (DashboardRoute) -> Void = { _ in }
    /// The rows' windows, the row swiped open and the summed rows shown open (`PaymentList.swift`).
    @State private var menu = PaymentRowMenu()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if DEBUG
    /// The launch arguments below act once: `.task` runs again whenever the list shows again (back from a pushed name's
    /// page), which reopened the page each time (brief 47 measured the back swipe against it).
    @State private var launchActionsDone = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            DashboardStatus(store: store, palette: palette)
            WordmarkScrollView {
                // Built once per change of the dashboard or the choices (brief 53), not here.
                let list = store.paymentList(category: route.category, month: route.month ?? "", side: route.side)
                #if DEBUG
                let swiped = list.debugSwipe()
                #else
                let swiped: (id: String, points: CGFloat)? = nil
                #endif
                LazyVStack(spacing: 0) {
                    ForEach(list.entries) { entry in
                        switch entry {
                        case let .payment(row, addsUp):
                            PaymentRow(row: row, store: store, palette: palette, menu: menu, shortcuts: rowMenus,
                                       allFrom: pick, addUp: addsUp && store.offersSums ? { addUp(row) } : nil,
                                       shownAt: swiped?.id == row.id ? swiped?.points : nil) {
                                selection = $0
                            }
                            .transition(.opacity)
                        case let .summed(sum):
                            SummedPaymentGroup(sum: sum, store: store, palette: palette, menu: menu, shortcuts: rowMenus,
                                               separate: { separate(sum) }, allFrom: pick,
                                               shownAt: swiped?.id == sum.id ? swiped?.points : nil) {
                                selection = $0
                            }
                            .transition(.opacity)
                        }
                    }
                    if list.rows.isEmpty {
                        EmptyMessage(text: String(localized: "No transactions this month."), palette: palette)
                    }
                }.padding(.horizontal, 12).padding(.top, 8)
            } band: { _ in band }
            .refreshable { await store.reload() }.scrollBounceBehavior(.always)
            .closesRowSwipe($menu.openRow)
            .tourScrollsToTarget()
        }
        .paymentListSheets(menu, store: store, palette: palette, selection: $selection, pick: pick)
        .task {
            #if DEBUG
            guard !launchActionsDone else { return }
            launchActionsDone = true
            let arguments = LaunchArguments.current
            if store.isSample, let index = arguments.firstIndex(of: "-sampleTransaction"),
               arguments.indices.contains(index + 1) {
                selection = store.dashboard?.transactions.first { $0.id == arguments[index + 1] }
            }
            // Phone sample (ids are made on import): the first payment of this list whose place contains the text.
            if !store.isSample, let index = arguments.firstIndex(of: "-samplePhoneTransaction"),
               arguments.indices.contains(index + 1) {
                for _ in 0..<40 where store.dashboard == nil { try? await Task.sleep(for: .milliseconds(100)) }
                selection = store.transactions(category: route.category, month: route.month ?? "", side: route.side)
                    .first { $0.transaction.place.localizedCaseInsensitiveContains(arguments[index + 1]) }?.transaction
            }
            // Phone sample: `-openName <text>` shows the name's page of the first payment here whose name contains it.
            if !store.isSample, let text = LaunchArguments.value("-openName") {
                for _ in 0..<40 where store.dashboard == nil { try? await Task.sleep(for: .milliseconds(100)) }
                if let row = store.transactions(category: route.category, month: route.month ?? "", side: route.side)
                    .first(where: { $0.transaction.place.localizedCaseInsensitiveContains(text) }),
                   let name = store.nameRoute(for: row.transaction) {
                    pick(name)
                }
            }
            // Phone sample: `-sampleSumOpen <text>` opens the summed row whose name contains the text (brief 53), after
            // `-sumsDelay <seconds>` (default at once; a delay shows the motion).
            if !store.isSample, let text = LaunchArguments.value("-sampleSumOpen") {
                for _ in 0..<40 where store.dashboard == nil { try? await Task.sleep(for: .milliseconds(100)) }
                if let delay = LaunchArguments.value("-sumsDelay").flatMap(Double.init) {
                    try? await Task.sleep(for: .seconds(delay))
                }
                let list = store.paymentList(category: route.category, month: route.month ?? "", side: route.side)
                for case let .summed(sum) in list.entries where sum.title.localizedCaseInsensitiveContains(text) {
                    withAnimation(SumMotion.animation(reduceMotion: reduceMotion)) { _ = menu.openSums.insert(sum.key) }
                    break
                }
            }
            #endif
        }
    }

    /// Add up (the swipe, the long press): this name's payments in this category as one row, every month.
    private func addUp(_ row: TransactionRow) {
        guard let name = PaymentList.nameKey(row.transaction) else { return }
        let category = store.sumCategoryKey(route.category)
        withAnimation(SumMotion.animation(reduceMotion: reduceMotion)) {
            store.sums.setName(name, in: category, sums: true)
        }
    }

    /// Separate: the summed row's payments single again in this category, every month.
    private func separate(_ sum: SummedPayments) {
        let category = store.sumCategoryKey(route.category)
        withAnimation(SumMotion.animation(reduceMotion: reduceMotion)) {
            menu.openSums.remove(sum.key)
            store.sums.setName(sum.key, in: category, sums: false)
        }
    }
}

// MARK: - Settings → Dashboard

/// Aresium's own Settings, in both modes: the dashboard's graph (brief 42; `GraphSetting`), a switch in the Lock
/// section's look (Settings pieces; its on colour is Settings' own, `EmpireSwitchStyle`). It changes the dashboard under the sheet at once.
/// In phone mode also Add up same names (brief 53, `sums`): every name with several payments in a month's list of a
/// category as one row, unless a category, a name or a name in a category is chosen otherwise.
struct DashboardSettingsSection: View {
    /// The person's choices of adding up; nil in server mode (its payments have no names to add up).
    var sums: PaymentSums? = nil
    @AppStorage(GraphSetting.key) private var showsGraph = GraphSetting.shownByDefault

    var body: some View {
        SettingsSection(String(localized: "Dashboard")) {
            Toggle(isOn: $showsGraph) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Graph").font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                    Text("Above the categories and months").font(AppFont.text(12)).foregroundStyle(Ink.muted)
                }
            }
            .padding(.horizontal, 16).frame(minHeight: 58)
            if let sums {
                SettingsDivider()
                Toggle(isOn: Binding(get: { sums.choices.everywhere }, set: { sums.setEverywhere($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add up same names").font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                        Text("One row with the sum per name and month").font(AppFont.text(12))
                            .foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 58)
                .accessibilityIdentifier("sumEverywhere")
            }
        }
        #if DEBUG
        .task {
            // Screenshots and the relaunch check: `-toggleGraph` turns the switch once as it opens, as a tap does.
            if LaunchArguments.current.contains("-toggleGraph") { showsGraph.toggle() }
        }
        #endif
    }
}
