import SwiftUI

struct DashboardRoute: Hashable {
    let category: String
    let side: DashboardSide
    var month: String? = nil
    /// The Cash page (brief 33): a month's (with `month`) or its months (Overview); `category` is unused.
    var cash = false
    /// A name's page (brief 44): every payment of one name; `category` is unused (`init(name:)`). With `month`, that
    /// month's payments of the name (brief 55, `init(name:month:)`).
    var name: PaymentNameRoute? = nil
    /// A month's page (brief 56): that month (`YYYY-MM`) as Current shows this month, opened from Overview's graph;
    /// `side` is the page it opens on, `category` is unused (`init(monthPage:side:)`).
    var monthPage: String? = nil
    /// The search (brief 77): its field and the names it finds; `category` and `side` are unused (`.search`).
    var search = false
}

extension DashboardRoute {
    /// A month's page (brief 56), opening on `side` (the page Overview showed).
    init(monthPage key: String, side: DashboardSide) {
        self.init(category: "", side: side, monthPage: key)
    }

    /// The search (brief 77), from the magnifying glass in the start screen's header.
    static let search = DashboardRoute(category: "", side: .expenses, search: true)
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
    /// The day whose page is open (brief 77): a sheet over the dashboard, from a tap on a day of a day graph.
    var day: DayRoute?

    /// Shows a page: pushed on the stack, or, for a name's page already on it, back to that page (brief 55: All on a
    /// name's month's rows goes back to the name's page below rather than stacking a second copy of it).
    mutating func open(_ route: DashboardRoute) {
        if let name = route.name, route.month == nil,
           let index = path.lastIndex(where: { $0.name?.key == name.key && $0.month == nil }) {
            path.removeSubrange((index + 1)...)
        } else {
            path.append(route)
        }
    }

    /// A name renamed from one of its pages (`NamePageStep.follow`): every page of the name on the stack (the name's
    /// page and its month's) shows the new name in its place.
    mutating func follow(_ old: PaymentNameRoute, to new: PaymentNameRoute) {
        for index in path.indices where path[index].name?.key == old.key {
            path[index] = path[index].month.map { DashboardRoute(name: new, month: $0) } ?? DashboardRoute(name: new)
        }
    }

    /// One page back, as the header's arrow.
    mutating func back() {
        if !path.isEmpty { path.removeLast() }
    }
}

/// The dashboard's navigation: the start screen (or what the owner shows in its place), a category's months and a month's
/// payments, each under the owner's header. The person's dashboard and the tour's are this same view on their own stores.
struct DashboardStack<Top: View, Root: View>: View {
    let store: DashboardStore
    let palette: Palette
    @Binding var place: DashboardPlace
    /// The graph on the category pages (Settings → Dashboard → Graph, `GraphSetting`); the start screen is the owner's.
    let graph: Bool
    /// Whether the graph moves away while its list scrolls (Settings → Dashboard, `GraphMotionSetting`, brief 56).
    let graphMoves: Bool
    let band: AresiumBand
    /// The shortcuts: the back swipe on a pushed screen (`.backSwipe`, brief 38), which does what the header's back arrow
    /// does, and the payment rows' long press (brief 41), which does what a payment's or receipt's page does. They are on
    /// wherever those take taps; the tour turns them off while it holds the screen (`TourModel.holdsTheScreen`).
    var shortcuts = true
    /// The rows' long press and swipe on their own (nil: as `shortcuts`): the tour lets them work at its swipe steps,
    /// on the row its ring is on, while the back swipe stays off (`TourModel.rowShortcuts`, brief 59).
    var rowShortcuts: Bool? = nil
    private var rows: Bool { rowShortcuts ?? shortcuts }
    /// The header (and any line under it) of the start screen (nil) or a pushed screen.
    @ViewBuilder let top: (DashboardRoute?) -> Top
    /// The start screen.
    @ViewBuilder let root: () -> Root
    /// A name's page asked for in the day's sheet (a row's All, a payment's "All from"): pushed once the sheet has
    /// gone, so it is one on the dashboard's stack with the arrow and the back swipe.
    @State private var afterDay: DashboardRoute?

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
                    if route.search {
                        SearchScreen(store: store, palette: palette, band: band, pick: open)
                    } else if let month = route.monthPage {
                        MonthScreen(month: month, opensOn: route.side, store: store, palette: palette, graph: graph,
                                    graphMoves: graphMoves, band: band, openDay: openDay, pick: open)
                    } else if let name = route.name, let month = route.month {
                        NameMonthScreen(route: name, month: month, store: store, palette: palette, band: band,
                                        shortcuts: rows, pick: open, follow: follow, back: back)
                    } else if let name = route.name {
                        NameScreen(route: name, store: store, palette: palette, band: band, showsGraph: graph, pick: open)
                    } else if route.cash, let month = route.month {
                        CashScreen(month: month, store: store, palette: palette, band: band, shortcuts: rows,
                                   pick: open)
                    } else if route.cash {
                        CashMonthsScreen(store: store, palette: palette, band: band, pick: open)
                    } else if route.month != nil {
                        TransactionsScreen(route: route, store: store, palette: palette, band: band,
                                           selection: $place.payment, rowMenus: rows, pick: open)
                    } else {
                        CategoryScreen(route: route, store: store, palette: palette, graph: graph,
                                       graphMoves: graphMoves, band: band, pick: open)
                    }
                }
                .background { Wall(palette: palette) }
                .toolbar(.hidden, for: .navigationBar)
                // The bar is hidden (the header is the app's own); this keeps the system's back swipe, which a hidden
                // bar turns off. The edge swipe and the swipe from anywhere both: a graph reads only after a hold
                // (`SeriesChart`), and the start page's sideways swipe is on the root, which stays the system's. A
                // month's page turns its pages only with its dots (`DashboardPages.swipesPages`).
                .backSwipe(shortcuts)
                .tourSpotlight()
            }
        }
        .task { if store.dashboard == nil { await store.reload() } }
        // A day's page (brief 77): a sheet, so a sideways swipe turns its sides and a swipe down closes it. It opens at
        // medium height: a day has a few rows, and the graph that was tapped stays in view above it.
        .sheet(item: $place.day, onDismiss: dayClosed) { day in
            DaySheet(day: day, store: store, palette: palette, shortcuts: rows) { route in
                afterDay = route
                place.day = nil
            }
            .presentationDetents([.medium, .large])
        }
    }

    /// A page pushed (`DashboardPlace.open`).
    private func open(_ route: DashboardRoute) { place.open(route) }

    /// A day's page opened (a tap on a day of a month's page; the start screen's owner opens its own the same way).
    private func openDay(_ day: DayRoute) { place.day = day }

    /// The day's sheet closed: the name's page asked for in it, if any.
    private func dayClosed() {
        guard let route = afterDay else { return }
        afterDay = nil
        open(route)
    }

    /// A name's pages following a rename (`DashboardPlace.follow`), in place, without the push animation.
    private func follow(_ old: PaymentNameRoute, to new: PaymentNameRoute) {
        var quiet = SwiftUI.Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { place.follow(old, to: new) }
    }

    /// One page back (a name's month page whose month has no payments of the name left).
    private func back() { place.back() }
}

/// The start screen (brief 56): the range picker on its own row under the header (the import button moved up beside the
/// gear), then the pages of the range chosen.
struct StartScreen: View {
    let store: DashboardStore
    let palette: Palette
    @Binding var current: Bool
    @Binding var side: DashboardSide
    /// The graph on the pages (Settings → Dashboard → Graph, `GraphSetting`).
    let graph: Bool
    /// Whether it moves away while the categories scroll (Settings → Dashboard, `GraphMotionSetting`).
    let graphMoves: Bool
    let band: AresiumBand
    /// "How do I get my file?" under an empty page (nil: not offered).
    var openGuide: (() -> Void)? = nil
    /// A tap on a day of Current's graph: that day's page (brief 77; nil: the days open nothing).
    var openDay: ((DayRoute) -> Void)? = nil
    let pick: (DashboardRoute) -> Void
    var body: some View {
        VStack(spacing: 0) {
            Picker("Range", selection: $current) {
                Text("Current").tag(true)
                Text("Overview").tag(false)
            }
            .pickerStyle(.segmented).frame(maxWidth: 260)
            .tourAnchor(.range)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14).padding(.bottom, 2)
            DashboardStatus(store: store, palette: palette)
            DashboardPages(store: store, palette: palette, scope: DashboardScope(current: current), side: $side,
                           graph: graph, graphMoves: graphMoves, band: band, openGuide: openGuide, openDay: openDay,
                           pick: pick)
        }
    }
}

/// A month's page (brief 56, as the website's): opened from a month of Overview's graph and pushed on the dashboard's
/// stack, that month as Current shows this month: its days' graph, the range line with the month, Expenses and Income
/// with the dots, its categories (each opens that month's payments) and its Cash row. The start screen's pages over the
/// month's scope; it opens on the page Overview showed.
struct MonthScreen: View {
    let month: String
    let store: DashboardStore
    let palette: Palette
    let graph: Bool
    let graphMoves: Bool
    let band: AresiumBand
    /// A tap on a day of its graph: that day's page (brief 77).
    let openDay: (DayRoute) -> Void
    let pick: (DashboardRoute) -> Void
    @State private var side: DashboardSide

    init(month: String, opensOn side: DashboardSide, store: DashboardStore, palette: Palette, graph: Bool,
         graphMoves: Bool, band: AresiumBand, openDay: @escaping (DayRoute) -> Void,
         pick: @escaping (DashboardRoute) -> Void) {
        self.month = month
        self.store = store
        self.palette = palette
        self.graph = graph
        self.graphMoves = graphMoves
        self.band = band
        self.openDay = openDay
        self.pick = pick
        _side = State(initialValue: side)
    }

    var body: some View {
        VStack(spacing: 0) {
            DashboardStatus(store: store, palette: palette)
            DashboardPages(store: store, palette: palette, scope: .month(month), side: $side, graph: graph,
                           graphMoves: graphMoves, band: band, swipesPages: false, openDay: openDay, pick: pick)
        }
    }
}

/// The pages of a scope (the start screen's Current or Overview, a month's page): the Expenses/Income dots, then the two
/// pages side by side, each with its graph, its heading and its categories. The dots stay above the pages, so they are
/// always in reach, also while the graph is away (brief 56); a swipe sideways moves a whole page, graph and all.
struct DashboardPages: View {
    let store: DashboardStore
    let palette: Palette
    let scope: DashboardScope
    @Binding var side: DashboardSide
    let graph: Bool
    let graphMoves: Bool
    let band: AresiumBand
    var openGuide: (() -> Void)? = nil
    /// Whether a sideways swipe turns the pages (the start screen). A month's page is pushed, and there a swipe right
    /// goes back as on every pushed page, so its pages turn only with the dots (they still slide): with a pager there,
    /// the edge swipe and the pages raced (real touches, brief 56: the edge swipe was lost now and then).
    var swipesPages = true
    /// A tap on a day of a day graph (Current, a month's page): that day's page (brief 77; nil: the days open nothing).
    var openDay: ((DayRoute) -> Void)? = nil
    /// The pages' width, for the dots' slide when they do not swipe.
    @State private var width: CGFloat = 0
    let pick: (DashboardRoute) -> Void
    /// How far the graph has gone up on the page shown, as its scroll last came to rest (0 at rest up to the graph's
    /// height): the other page takes the same place while it is out of sight, so switching pages never makes the graph
    /// jump (`GraphMotion`).
    @State private var graphAway: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // The area of the dots reaching over the pages below lies above them (`zIndex`).
            PageDots(side: $side, palette: palette).tourAnchor(.pageDots).padding(.vertical, 2).zIndex(1)
            if swipesPages {
                TabView(selection: $side) {
                    ForEach(DashboardSide.allCases, id: \.self) { page in
                        self.page(page).tag(page)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
                .coordinateSpace(.named(GraphMotion.pages))
            } else {
                // Side by side as the pager lays them, the one shown in place; the dots slide them (no sideways pan).
                ZStack {
                    ForEach(Array(DashboardSide.allCases.enumerated()), id: \.element) { index, page in
                        let shown = DashboardSide.allCases.firstIndex(of: side) ?? 0
                        self.page(page)
                            .offset(x: CGFloat(index - shown) * width)
                            .allowsHitTesting(page == side)
                            .accessibilityHidden(page != side)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                .clipped()
                .coordinateSpace(.named(GraphMotion.pages))
            }
        }
    }
}

extension DashboardPages {
    /// One side's page, knowing whether it is the one shown.
    fileprivate func page(_ page: DashboardSide) -> some View {
        StartPage(store: store, palette: palette, side: page, scope: scope, shown: page == side, graph: graph,
                  graphMoves: graphMoves, graphAway: $graphAway, band: band, openGuide: openGuide, openDay: openDay,
                  pick: pick)
    }
}

/// The Expenses/Income dots over a page pair (the start screen, a month's page, a day's page): the side shown in full
/// ink, the other muted; a tap turns to its side (sliding, not with Reduce Motion). Each takes taps over 44 × 44 pt
/// (brief 41) while the row keeps its height in the layout (24 pt); VoiceOver reads "Expenses" and "Income".
struct PageDots: View {
    @Binding var side: DashboardSide
    let palette: Palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
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
        }.padding(.vertical, -10)
    }
}

/// A page's side and total, as the start screen heads its pages: "Expenses" in its colour, the amount in the numbers'
/// font and "spent" (or "Income", "received"). The start screen writes whole euros, a day's page the cents.
struct SideTotal: View {
    let side: DashboardSide
    /// The amount written out; nil while there is none (the dashboard is loading).
    let total: String?
    let palette: Palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(side.title).font(AppFont.text(21, weight: .bold))
                .foregroundStyle(side == .income ? palette.income : palette.expenseText)
            Spacer(minLength: 4)
            if let total {
                Text(verbatim: total)
                    .font(AppFont.number(21, weight: .bold)).minimumScaleFactor(0.7).lineLimit(1)
                Text(side.caption).font(AppFont.text(11)).foregroundStyle(palette.muted)
            }
        }
    }
}

/// One page: the graph (at the top of the list while it moves away, else fixed above it), the range line and the side's
/// total, the categories, and the Cash row.
private struct StartPage: View {
    let store: DashboardStore
    let palette: Palette
    let side: DashboardSide
    let scope: DashboardScope
    /// The page in view (the other waits beside it).
    let shown: Bool
    let graph: Bool
    let graphMoves: Bool
    @Binding var graphAway: CGFloat
    let band: AresiumBand
    var openGuide: (() -> Void)?
    var openDay: ((DayRoute) -> Void)?
    let pick: (DashboardRoute) -> Void
    @State private var position = ScrollPosition(edge: .top)
    /// Where this page's list last came to rest (how far it is scrolled).
    @State private var restingAt: CGFloat = 0
    /// The list's visible height: with the graph moving, a short list still scrolls far enough to take it away.
    @State private var visibleHeight: CGFloat = 0
    private var rows: [DisplayRow] { store.rows(side: side, scope: scope) }
    private var moves: Bool { graph && graphMoves }

    var body: some View {
        VStack(spacing: 0) {
            if graph && !graphMoves { chart }
            ScrollViewReader { proxy in
                WordmarkScrollView {
                    VStack(spacing: 0) {
                        if moves { chart }
                        list
                    }
                    // The graph's height more than the screen, so even two rows can scroll it away as on the other page.
                    .frame(minHeight: moves ? GraphMotion.leastContent(visible: visibleHeight) : nil, alignment: .top)
                } band: { _ in band }
                .refreshable { await store.reload() }.scrollBounceBehavior(.always)
                .scrollPosition($position)
                .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { _, height in
                    visibleHeight = height
                }
                // Only when the scroll comes to rest, never per frame: the graph is part of the list and moves with it.
                .onScrollPhaseChange { _, phase, context in
                    guard phase == .idle else { return }
                    restingAt = GraphMotion.offset(context.geometry)
                    if shown && moves { graphAway = GraphMotion.away(restingAt) }
                }
                .onChange(of: graphAway) { _, away in follow(away) }
                .tourScrollsToTarget()
                // A page out of sight may not take a scroll (the pages lay out only what shows): it lines up again as
                // its first sliver comes into view. Only when that changes, not per frame of the swipe.
                .onGeometryChange(for: Bool.self) { proxy in
                    proxy.frame(in: .named(GraphMotion.pages)).minX.magnitude < proxy.size.width - 0.5
                } action: { _, inView in
                    if inView { follow(graphAway) }
                }
                #if DEBUG
                .task(id: store.dashboard == nil) {
                    guard store.dashboard != nil, shown else { return }
                    // Screenshots: `-scrollToEnd` shows the band; `-scrollGraph <points>` scrolls the list that far
                    // (the graph halfway or wholly away).
                    try? await Task.sleep(for: .milliseconds(300))
                    if LaunchArguments.current.contains("-scrollToEnd") { proxy.scrollToWordmark() }
                    if let points = LaunchArguments.value("-scrollGraph").flatMap(Double.init) {
                        position.scrollTo(y: points)
                    }
                }
                #endif
            }
        }
    }

    /// The other page's list came to rest with the graph `away`: this page, out of sight, takes the same place.
    private func follow(_ away: CGFloat) {
        guard !shown, moves, let target = GraphMotion.follow(restingAt: restingAt, away: away) else { return }
        position.scrollTo(y: target)
        restingAt = target
    }

    /// The graph: the days of the scope's month, or Overview's months; a tap on a month opens its page, on a day that
    /// day's page (brief 77), on this page's side.
    private var chart: some View {
        SeriesChart(points: store.startChart(side: side, scope: scope),
                    color: side == .income ? palette.income : palette.expense, palette: palette,
                    xTitle: scope.isMonth ? String(localized: "Day") : String(localized: "Month"),
                    onPick: pickPoint)
        .frame(height: SeriesChart.dashboardHeight)
        .tourAnchor(shown ? .graph : nil)
    }

    /// What a short tap on the graph's point opens: a month's page on Overview, a day's page on a month's days.
    private var pickPoint: ((Int) -> Void)? {
        guard scope.isMonth else {
            return { index in if let route = store.monthPage(atChartIndex: index, side: side) { pick(route) } }
        }
        guard let openDay else { return nil }
        return { index in if let day = store.dayRoute(atChartIndex: index, side: side, scope: scope) { openDay(day) } }
    }

    private var list: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.rangeLabel(scope).uppercased()).font(AppFont.text(11, weight: .semibold))
                    .tracking(1.3).foregroundStyle(palette.muted)
                let total = store.totals(scope).map { Money.total(side == .income ? $0.income : $0.expense) }
                SideTotal(side: side, total: total, palette: palette)
            }.padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 8)
            LazyVStack(spacing: 0) {
                let rows = rows
                ForEach(rows) { row in
                    // A month (Current, a month's page): that month's payments of the category at once; Overview: its
                    // months.
                    Button { pick(store.route(category: row.category.name, side: side, scope: scope)) } label: {
                        ValueRow(title: row.category.shownName, category: row.category, total: row.total,
                                 maximum: rows.map(\.total).max() ?? 0, palette: palette)
                    }.buttonStyle(.plain)
                        .tourAnchor(shown ? .category(row.category.name) : nil)
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
                    Button { pick(store.cashRoute(scope)) } label: {
                        CashRow(store: store, palette: palette, scope: scope)
                    }
                    .buttonStyle(.plain)
                }
            }.padding(.horizontal, 12).padding(.top, 8)
        }
    }
}

/// The graph moving away (brief 56): it stands at the top of its list and scrolls up with it, so nothing happens per
/// frame; these numbers only line the two pages up when a scroll comes to rest (pure, so tests pin them).
enum GraphMotion {
    /// The pages' own space: a page beside the one shown stands a page's width away in it.
    static let pages = "dashboard-pages"

    /// How far a list is scrolled, from its scroll geometry (never below its top while it is pulled to refresh).
    static func offset(_ geometry: ScrollGeometry) -> CGFloat {
        max(0, geometry.contentOffset.y + geometry.contentInsets.top)
    }

    /// How far the graph is away at that place: up to its height, after which the rows go on alone.
    static func away(_ offset: CGFloat, graph height: CGFloat = SeriesChart.dashboardHeight) -> CGFloat {
        min(max(0, offset), height)
    }

    /// Where a page out of sight scrolls when the page shown came to rest with the graph `away`: to the same place while
    /// the graph is partly there; with it wholly away, at least to where its own graph is gone (a page further down
    /// stays). nil when it already shows the graph as far away.
    static func follow(restingAt offset: CGFloat, away: CGFloat,
                       graph height: CGFloat = SeriesChart.dashboardHeight) -> CGFloat? {
        guard abs(Self.away(offset, graph: height) - away) > 0.5 else { return nil }
        return away >= height ? max(offset, height) : away
    }

    /// The least height of a page's content while the graph moves: the screen and the graph's height, so a short list
    /// can still take the graph away (only empty wall shows below its rows then, before the band).
    static func leastContent(visible: CGFloat, graph height: CGFloat = SeriesChart.dashboardHeight) -> CGFloat {
        visible + height
    }
}

struct CategoryScreen: View {
    let route: DashboardRoute
    let store: DashboardStore
    let palette: Palette
    /// The graph above the months (Settings → Dashboard → Graph, `GraphSetting`).
    let graph: Bool
    /// Whether it moves away while the months scroll (brief 56, `GraphMotionSetting`): it is then the list's first part.
    let graphMoves: Bool
    let band: AresiumBand
    let pick: (DashboardRoute) -> Void
    private var category: Category? { store.category(route.category, side: route.side) }
    private var months: [MonthRow] { store.months(category: route.category, side: route.side) }

    var body: some View {
        let category = category
        let months = months
        let showsChart = graph && category != nil && !months.isEmpty
        VStack(spacing: 0) {
            DashboardStatus(store: store, palette: palette)
            if showsChart && !graphMoves, let category { chart(category) }
            WordmarkScrollView {
                if let category {
                    VStack(spacing: 0) {
                        if showsChart && graphMoves { chart(category) }
                        LazyVStack(spacing: 0) {
                            ForEach(months) { row in
                                Button { open(row.month.key) } label: {
                                    ValueRow(title: row.month.title(), category: category, total: row.total,
                                             maximum: months.map(\.total).max() ?? 0, palette: palette)
                                }.buttonStyle(.plain)
                            }
                            if months.isEmpty {
                                EmptyMessage(text: String(localized: "No activity recorded."), palette: palette)
                            }
                        }.padding(.horizontal, 12).padding(.top, 8)
                    }
                } else { EmptyMessage(text: String(localized: "This category is no longer available."), palette: palette) }
            } band: { _ in band }
            .refreshable { await store.reload() }.scrollBounceBehavior(.always)
        }
    }

    /// Above the months, as on the start screen and at its height: about eight months show below it on an iPhone 17. A
    /// tap on a month's point opens that month, as its row does; VoiceOver reads the rows.
    private func chart(_ category: Category) -> some View {
        SeriesChart(points: store.categoryChart(route.category, side: route.side),
                    color: Color(hex: category.color), palette: palette, xTitle: String(localized: "Month")) { index in
            if let month = store.monthKey(atChartIndex: index) { open(month) }
        }
        .frame(height: SeriesChart.dashboardHeight)
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
            // Phone sample: `-openName <text>` shows the name's page of the first payment here whose name contains it;
            // with `-openNameMonth <YYYY-MM>` that month's page of the name over it (brief 55).
            if !store.isSample, let text = LaunchArguments.value("-openName") {
                for _ in 0..<40 where store.dashboard == nil { try? await Task.sleep(for: .milliseconds(100)) }
                if let row = store.transactions(category: route.category, month: route.month ?? "", side: route.side)
                    .first(where: { $0.transaction.place.localizedCaseInsensitiveContains(text) }),
                   let name = store.nameRoute(for: row.transaction) {
                    pick(name)
                    if let month = LaunchArguments.value("-openNameMonth"), let page = name.name {
                        pick(DashboardRoute(name: page, month: month))
                    }
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

/// Aresium's own Settings, in both modes: the dashboard's graph (brief 42; `GraphSetting`) and, while it shows, whether it
/// moves away while its list scrolls (brief 56; `GraphMotionSetting`), switches in the Lock
/// section's look (Settings pieces; its on colour is Settings' own, `EmpireSwitchStyle`). It changes the dashboard under the sheet at once.
/// In phone mode also Add up same names (brief 53, `sums`): every name with several payments in a month's list of a
/// category as one row, unless a category, a name or a name in a category is chosen otherwise.
struct DashboardSettingsSection: View {
    /// The person's choices of adding up; nil in server mode (its payments have no names to add up).
    var sums: PaymentSums? = nil
    @AppStorage(GraphSetting.key) private var showsGraph = GraphSetting.shownByDefault
    @AppStorage(GraphMotionSetting.key) private var graphMoves = GraphMotionSetting.movesByDefault

    var body: some View {
        SettingsSection(String(localized: "Dashboard")) {
            DashboardSettingsRows(showsGraph: $showsGraph, graphMoves: $graphMoves,
                                  sumsEverywhere: sums.map { sums in
                                      Binding(get: { sums.choices.everywhere }, set: { sums.setEverywhere($0) })
                                  })
        }
        #if DEBUG
        .task {
            // Screenshots and the relaunch check: `-toggleGraph` turns the switch once as it opens, as a tap does.
            if LaunchArguments.current.contains("-toggleGraph") { showsGraph.toggle() }
        }
        #endif
    }
}

/// Settings → Dashboard's switches (one place for their words and look): Graph, Graph moves away (under it, while the
/// graph shows) and Add up same names (phone mode). The person's Settings binds them to the saved settings; the tour's
/// Settings shows them as a picture of its own state (constant values, `TourSettingsSheet`).
struct DashboardSettingsRows: View {
    @Binding var showsGraph: Bool
    @Binding var graphMoves: Bool
    /// Add up same names everywhere; nil: not offered (server mode).
    var sumsEverywhere: Binding<Bool>? = nil

    var body: some View {
        Toggle(isOn: $showsGraph) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Graph").font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                Text("Above the categories and months").font(AppFont.text(12)).foregroundStyle(Ink.muted)
            }
        }
        .padding(.horizontal, 16).frame(minHeight: 58)
        // Brief 56: under the Graph it belongs to, and only while there is a graph to move.
        if showsGraph {
            SettingsDivider()
            Toggle(isOn: $graphMoves) {
                // One line that says what it does (the brief's words).
                Text("Graph moves away when scrolling").font(AppFont.text(15, weight: .medium))
                    .foregroundStyle(Ink.primary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 58)
            .accessibilityIdentifier("graphMoves")
        }
        if let sumsEverywhere {
            SettingsDivider()
            Toggle(isOn: sumsEverywhere) {
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
}
