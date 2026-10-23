import SwiftUI

struct DashboardRoute: Hashable {
    let category: String
    let side: DashboardSide
    var month: String? = nil
}

struct StartScreen: View {
    let store: DashboardStore
    let imports: ImportStore
    let palette: Palette
    @Binding var current: Bool
    @Binding var side: DashboardSide
    @Binding var graph: Bool
    let pick: (DashboardRoute) -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Range", selection: $current) {
                    Text("Current").tag(true)
                    Text("Overview").tag(false)
                }.pickerStyle(.segmented).frame(maxWidth: 235)
                Spacer()
                ImportButton(store: imports, sample: store.isSample, palette: palette)
                IconButton(symbol: "chart.line.uptrend.xyaxis", label: "Toggle graph", palette: palette, active: graph) {
                    withAnimation(.easeInOut(duration: 0.3)) { graph.toggle() }
                }
            }.padding(.horizontal, 14).padding(.bottom, 8)
            DashboardStatus(store: store, palette: palette)
            if graph {
                SeriesChart(points: store.startChart(side: side, current: current),
                            color: side == .income ? palette.income : palette.expense,
                            palette: palette, xTitle: current ? "Day" : "Month")
                    .frame(height: 235).transition(.opacity.combined(with: .move(edge: .top)))
            }
            HStack(spacing: 9) {
                ForEach(DashboardSide.allCases, id: \.self) { page in
                    Button { withAnimation { side = page } } label: {
                        Circle().fill(page == side ? palette.ink : palette.muted.opacity(0.5))
                            .frame(width: page == side ? 8 : 7, height: page == side ? 8 : 7)
                            .frame(width: 30, height: 24)
                    }.buttonStyle(.plain).accessibilityLabel(page.title)
                        .accessibilityAddTraits(page == side ? .isSelected : [])
                }
            }.padding(.vertical, 2)
            TabView(selection: $side) {
                ForEach(DashboardSide.allCases, id: \.self) { page in
                    StartPage(store: store, palette: palette, side: page, current: current, pick: pick).tag(page)
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
    let pick: (DashboardRoute) -> Void
    private var rows: [DisplayRow] { store.rows(side: side, current: current) }
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.rangeLabel(current: current).uppercased()).font(AppFont.text(11, weight: .semibold))
                        .tracking(1.3).foregroundStyle(palette.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(side.title).font(AppFont.text(21, weight: .bold))
                            .foregroundStyle(side == .income ? palette.income : palette.expense)
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
                        Button { pick(DashboardRoute(category: row.category.name, side: side)) } label: {
                            ValueRow(title: row.category.name, category: row.category, total: row.total,
                                     maximum: rows.map(\.total).max() ?? 0, palette: palette)
                        }.buttonStyle(.plain)
                    }
                    if rows.isEmpty && !store.isLoading {
                        EmptyMessage(text: "No \(side == .income ? "income" : "spending") recorded.", palette: palette)
                    }
                }.padding(.horizontal, 12).padding(.top, 8)
            }
        }.refreshable { await store.reload() }.scrollBounceBehavior(.always)
    }
}

struct CategoryScreen: View {
    let route: DashboardRoute
    let store: DashboardStore
    let palette: Palette
    @Binding var graph: Bool
    let pick: (DashboardRoute) -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                IconButton(symbol: "chart.line.uptrend.xyaxis", label: "Toggle graph", palette: palette, active: graph) {
                    withAnimation { graph.toggle() }
                }
            }.padding(.horizontal, 14).padding(.bottom, 8)
            DashboardStatus(store: store, palette: palette)
            ScrollView {
                if let category = store.category(route.category, side: route.side) {
                    let months = store.months(category: route.category, side: route.side)
                    if graph {
                        SeriesChart(points: store.categoryChart(route.category, side: route.side),
                                    color: Color(hex: category.color), palette: palette, xTitle: "Month") { index in
                            guard let allMonths = store.dashboard?.months, allMonths.indices.contains(index) else { return }
                            pick(DashboardRoute(category: route.category, side: route.side, month: allMonths[index].key))
                        }.frame(height: 420)
                        .accessibilityRepresentation {
                            VStack {
                                ForEach(months) { row in
                                    Button("\(row.month.label) · \(Money.total(row.total))") {
                                        pick(DashboardRoute(category: route.category, side: route.side, month: row.month.key))
                                    }
                                }
                            }
                        }
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(months) { row in
                                Button { pick(DashboardRoute(category: route.category, side: route.side, month: row.month.key)) } label: {
                                    ValueRow(title: row.month.label, category: category, total: row.total,
                                             maximum: months.map(\.total).max() ?? 0, palette: palette)
                                }.buttonStyle(.plain)
                            }
                            if months.isEmpty { EmptyMessage(text: "No activity recorded.", palette: palette) }
                        }.padding(.horizontal, 12).padding(.top, 8)
                    }
                } else { EmptyMessage(text: "This category is no longer available.", palette: palette) }
            }.refreshable { await store.reload() }.scrollBounceBehavior(.always)
        }
    }
}

struct TransactionsScreen: View {
    let route: DashboardRoute
    let store: DashboardStore
    let palette: Palette
    var body: some View {
        VStack(spacing: 0) {
            DashboardStatus(store: store, palette: palette)
            ScrollView {
                let rows = store.transactions(category: route.category, month: route.month ?? "", side: route.side)
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        let transaction = row.transaction
                        HStack(spacing: 12) {
                            Text(String(transaction.day)).font(AppFont.number(15))
                                .foregroundStyle(palette.secondary).frame(width: 38, height: 38)
                                .background(palette.card2, in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.line))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text(transaction.place).font(AppFont.text(14.5, weight: .semibold)).lineLimit(1)
                                    if row.tagged {
                                        Text("tag").font(AppFont.text(9, weight: .semibold)).foregroundStyle(palette.secondary)
                                            .padding(.horizontal, 4).padding(.vertical, 2)
                                            .background(palette.card2, in: RoundedRectangle(cornerRadius: 4))
                                            .accessibilityLabel("Added here by tag; primary category \(transaction.categoryName)")
                                    }
                                }
                                Text(transaction.city).font(AppFont.text(12.5)).foregroundStyle(palette.muted).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Text(Money.transaction(transaction.amount)).font(AppFont.number(14))
                                .foregroundStyle(transaction.amount < 0 ? palette.expense : palette.income).fixedSize()
                        }.padding(.horizontal, 12).padding(.vertical, 11)
                    }
                    if rows.isEmpty { EmptyMessage(text: "No transactions this month.", palette: palette) }
                }.padding(.horizontal, 12).padding(.top, 8)
            }.refreshable { await store.reload() }.scrollBounceBehavior(.always)
        }
    }
}
