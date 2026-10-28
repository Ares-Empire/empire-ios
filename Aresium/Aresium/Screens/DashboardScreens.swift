import SwiftUI

struct DashboardRoute: Hashable {
    let category: String
    let side: DashboardSide
    var month: String? = nil
    /// The Cash page (brief 33): a month's (with `month`) or its months (Overview); `category` is unused.
    var cash = false
}

/// Where a dashboard is: the screens pushed, Current or Overview, the expenses or income page, the graph, the payment
/// open. The person's dashboard keeps it in `ContentView`, the tour's in `TourModel` (so the tour can move it).
struct DashboardPlace {
    var path: [DashboardRoute] = []
    var current = true
    var side = DashboardSide.expenses
    var graph = false
    /// The payment whose detail is open.
    var payment: Transaction?
}

/// The dashboard's navigation: the start screen (or what the owner shows in its place), a category's months and a month's
/// payments, each under the owner's header. The person's dashboard and the tour's are this same view on their own stores.
struct DashboardStack<Top: View, Root: View>: View {
    let store: DashboardStore
    let palette: Palette
    @Binding var place: DashboardPlace
    let band: AresiumBand
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
                    if route.cash, let month = route.month {
                        CashScreen(month: month, store: store, palette: palette, band: band)
                    } else if route.cash {
                        CashMonthsScreen(store: store, palette: palette, band: band) { place.path.append($0) }
                    } else if route.month != nil {
                        TransactionsScreen(route: route, store: store, palette: palette, band: band,
                                           selection: $place.payment)
                    } else {
                        CategoryScreen(route: route, store: store, palette: palette, graph: $place.graph,
                                       band: band) { place.path.append($0) }
                    }
                }
                .background { Wall(palette: palette) }
                .toolbar(.hidden, for: .navigationBar)
                .tourSpotlight()
            }
        }
        .task { if store.dashboard == nil { await store.reload() } }
    }
}

struct StartScreen: View {
    let store: DashboardStore
    let imports: ImportStore
    let palette: Palette
    @Binding var current: Bool
    @Binding var side: DashboardSide
    @Binding var graph: Bool
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
                IconButton(symbol: "chart.line.uptrend.xyaxis", label: String(localized: "Toggle graph"), palette: palette, active: graph) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { graph.toggle() }
                }
                .tourAnchor(.graph)
            }.padding(.horizontal, 14).padding(.bottom, 8)
            DashboardStatus(store: store, palette: palette)
            if graph {
                SeriesChart(points: store.startChart(side: side, current: current),
                            color: side == .income ? palette.income : palette.expense,
                            palette: palette, xTitle: current ? String(localized: "Day") : String(localized: "Month"))
                    .frame(height: 235).transition(.opacity.combined(with: .move(edge: .top)))
            }
            HStack(spacing: 9) {
                ForEach(DashboardSide.allCases, id: \.self) { page in
                    Button { withAnimation(reduceMotion ? nil : .default) { side = page } } label: {
                        Circle().fill(page == side ? palette.ink : palette.muted.opacity(0.5))
                            .frame(width: page == side ? 8 : 7, height: page == side ? 8 : 7)
                            .frame(width: 30, height: 24)
                    }.buttonStyle(.plain).accessibilityLabel(page.title)
                        .accessibilityAddTraits(page == side ? .isSelected : [])
                }
            }.tourAnchor(.pageDots).padding(.vertical, 2)
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
    @Binding var graph: Bool
    let band: AresiumBand
    let pick: (DashboardRoute) -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                IconButton(symbol: "chart.line.uptrend.xyaxis", label: String(localized: "Toggle graph"), palette: palette, active: graph) {
                    withAnimation { graph.toggle() }
                }
            }.padding(.horizontal, 14).padding(.bottom, 8)
            DashboardStatus(store: store, palette: palette)
            WordmarkScrollView {
                if let category = store.category(route.category, side: route.side) {
                    let months = store.months(category: route.category, side: route.side)
                    if graph {
                        SeriesChart(points: store.categoryChart(route.category, side: route.side),
                                    color: Color(hex: category.color), palette: palette, xTitle: String(localized: "Month")) { index in
                            guard let allMonths = store.dashboard?.months, allMonths.indices.contains(index) else { return }
                            pick(DashboardRoute(category: route.category, side: route.side, month: allMonths[index].key))
                        }.frame(height: 420)
                        .accessibilityRepresentation {
                            VStack {
                                ForEach(months) { row in
                                    Button("\(row.month.title()) · \(Money.total(row.total))") {
                                        pick(DashboardRoute(category: route.category, side: route.side, month: row.month.key))
                                    }
                                }
                            }
                        }
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(months) { row in
                                Button { pick(DashboardRoute(category: route.category, side: route.side, month: row.month.key)) } label: {
                                    ValueRow(title: row.month.title(), category: category, total: row.total,
                                             maximum: months.map(\.total).max() ?? 0, palette: palette)
                                }.buttonStyle(.plain)
                            }
                            if months.isEmpty { EmptyMessage(text: String(localized: "No activity recorded."), palette: palette) }
                        }.padding(.horizontal, 12).padding(.top, 8)
                    }
                } else { EmptyMessage(text: String(localized: "This category is no longer available."), palette: palette) }
            } band: { _ in band }
            .refreshable { await store.reload() }.scrollBounceBehavior(.always)
        }
    }
}

struct TransactionsScreen: View {
    let route: DashboardRoute
    let store: DashboardStore
    let palette: Palette
    let band: AresiumBand
    /// The payment whose detail is open (the dashboard's place).
    @Binding var selection: Transaction?
    var body: some View {
        VStack(spacing: 0) {
            DashboardStatus(store: store, palette: palette)
            WordmarkScrollView {
                let rows = store.transactions(category: route.category, month: route.month ?? "", side: route.side)
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        let transaction = row.transaction
                        Button { selection = transaction } label: {
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
                                        if row.tagged {
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
                        }.buttonStyle(.plain)
                            .tourAnchor(.payment(transaction.id))
                    }
                    if rows.isEmpty { EmptyMessage(text: String(localized: "No transactions this month."), palette: palette) }
                }.padding(.horizontal, 12).padding(.top, 8)
            } band: { _ in band }
            .refreshable { await store.reload() }.scrollBounceBehavior(.always)
            .tourScrollsToTarget()
        }
        .sheet(item: $selection) { transaction in
            // Phone mode's receipt rows open the receipt, a withdrawal's covered row the receipts that took its cash.
            if let phone = store.phone, let receiptID = transaction.receiptId {
                ReceiptPageSheet(model: ReceiptPageModel(id: receiptID, phone: phone) {
                    await store.reloadAfterTransactionChange()
                }, palette: palette)
            } else if let phone = store.phone, let receiptIDs = transaction.coveredBy {
                CoveredReceiptsSheet(phone: phone, receiptIDs: receiptIDs, palette: palette) {
                    await store.reloadAfterTransactionChange()
                }
            } else {
                TransactionDetailSheet(store: store.transactionDetailStore(for: transaction), palette: palette)
            }
        }
        .task {
            #if DEBUG
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
            #endif
        }
    }
}
