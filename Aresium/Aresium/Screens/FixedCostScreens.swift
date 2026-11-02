import SwiftUI

// Monthly average and fixed costs on screen (brief 209). The words are `Model/FixedCostPage.swift`; the numbers are
// brief 208's (`DashboardStore.monthlyAverage(side:)`, `fixedCosts(side:)`, `setNotFixed`).

/// The Overview's quiet line under a side's total, in the total's column: the average of the finished months, then what
/// of it is fixed (or regular), which opens the fixed costs page. One line while it fits; otherwise the fixed part takes
/// a second line of its own (never a smaller font). The fixed part takes taps over 44 pt and is a button for VoiceOver.
struct AverageLineView: View {
    let line: AverageLine
    let palette: Palette
    let open: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                average
                if line.fixed != nil {
                    Text(verbatim: " · ").font(AppFont.text(12.5)).foregroundStyle(palette.muted)
                        .accessibilityHidden(true)
                    fixed
                }
            }
            VStack(alignment: .trailing, spacing: 4) {
                average
                fixed
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var average: some View {
        Text(verbatim: line.average).font(AppFont.text(12.5)).foregroundStyle(palette.muted)
            .lineLimit(1)
            .accessibilityLabel(Text(verbatim: line.averageSpoken))
    }

    @ViewBuilder private var fixed: some View {
        if let words = line.fixed {
            Button(action: open) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: words).font(AppFont.text(12.5)).foregroundStyle(palette.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right").font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(palette.muted)
                }
                .minimumTapArea()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: line.fixedSpoken ?? words))
            .accessibilityIdentifier("fixedCostsLine")
        }
    }
}

/// The fixed costs page (brief 209; Regular income on the income side), pushed on the dashboard's stack from the
/// Overview's line, under the header with its arrow and gear (the back swipe works). The monthly total in the start
/// screen's heading with what it makes a year under it, the running entries as list rows (biggest share a month first),
/// then Ended and Not counted, then one quiet line on how they are found. A row opens its name's page; its long press
/// takes it out (Not fixed / Not regular) or counts it again, with the undo bar.
struct FixedCostsScreen: View {
    let side: DashboardSide
    let store: DashboardStore
    let palette: Palette
    let band: AresiumBand
    /// The rows' long press (`DashboardStack.shortcuts`).
    var shortcuts = true
    let pick: (DashboardRoute) -> Void
    @State private var undo: UndoOffer?
    /// A change on its way (the save and the rebuild): a second long press waits.
    @State private var changing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if DEBUG
    @State private var launchActionsDone = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            DashboardStatus(store: store, palette: palette)
            ScrollViewReader { proxy in
                WordmarkScrollView {
                    content
                } band: { _ in band }
                .refreshable { await store.reload() }.scrollBounceBehavior(.always)
                #if DEBUG
                .task { await debugLaunch(proxy) }
                #endif
            }
        }
        .undoBar($undo, accent: nil)
    }

    @ViewBuilder private var content: some View {
        if let list = store.fixedCosts(side: side) {
            let page = FixedCostPage(list: list, side: side)
            if page.isEmpty {
                Text(verbatim: FixedCostWords.empty(side)).font(AppFont.text(14)).foregroundStyle(palette.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity).padding(.horizontal, 30).padding(.vertical, 40)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    total(page).padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 8)
                    LazyVStack(alignment: .leading, spacing: 0) {
                        rows(page.running)
                        section(FixedCostWords.endedHeading(), page.ended)
                        section(FixedCostWords.takenOutHeading(), page.takenOut)
                    }
                    .padding(.horizontal, 12).padding(.top, 8)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: store.revision)
                    Text(verbatim: FixedCostWords.howFound()).font(AppFont.text(12.5)).foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24).padding(.top, 18)
                }
            }
        }
    }

    /// The start screen's heading for this page: the side's word, the monthly total and "a month"; under it, in the
    /// total's column, what it makes a year. VoiceOver reads it as one.
    private func total(_ page: FixedCostPage) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            SideTotal(side: side, total: page.total, palette: palette, caption: FixedCostWords.perMonth())
            Text(verbatim: page.year).font(AppFont.text(12.5)).foregroundStyle(palette.muted)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func section(_ heading: String, _ rows: [FixedCostPage.Row]) -> some View {
        if !rows.isEmpty {
            Text(verbatim: heading.uppercased()).font(AppFont.text(11, weight: .semibold)).tracking(1.3)
                .foregroundStyle(palette.muted)
                .padding(.horizontal, 12).padding(.top, 22).padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            self.rows(rows)
        }
    }

    private func rows(_ rows: [FixedCostPage.Row]) -> some View {
        ForEach(rows) { row in
            Button { open(row) } label: {
                FixedCostRow(row: row, side: side, palette: palette)
                    // The lifted row in Apple's context menu: the row with rounded corners, as a payment's.
                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .contextMenu {
                if shortcuts {
                    Button(FixedCostWords.change(row.change, side: side),
                           systemImage: row.change == .takeOut ? "minus.circle" : "plus.circle") { change(row) }
                }
            }
            .accessibilityLabel(Text(verbatim: row.spoken))
            .accessibilityAction(named: Text(verbatim: FixedCostWords.change(row.change, side: side))) { change(row) }
            .transition(.opacity)
        }
    }

    /// A row's tap: the name's page of its newest payment, as "All with this name" opens it.
    private func open(_ row: FixedCostPage.Row) {
        let newest = row.entry.newest
        if let route = store.nameRoute(for: newest) {
            pick(route)
        } else if let key = newest.nameKey {
            pick(DashboardRoute(name: PaymentNameRoute(key: key, title: newest.place)))
        }
    }

    /// The long press: taken out (or counted again) at once, one save and one rebuild; the undo bar says it with Undo.
    private func change(_ row: FixedCostPage.Row) {
        guard !changing else { return }
        changing = true
        Task {
            defer { changing = false }
            do {
                let batch = try await store.setNotFixed(row.entry, row.change == .takeOut)
                undo = UndoOffer(message: FixedCostWords.done(row.change, name: row.name, side: side)) {
                    do {
                        let outcome = try await batch.perform()
                        if outcome == .unavailable { undo = UndoOffer(message: outcome.message) }
                    } catch {
                        undo = UndoOffer(message: error.localizedDescription)
                    }
                }
            } catch is BatchChangeError {
                undo = UndoOffer(message: FixedCostWords.changedMeanwhile())
            } catch {
                undo = UndoOffer(message: error.localizedDescription)
            }
        }
    }

    #if DEBUG
    /// Screenshots (with `-samplePhone -openFixedCosts expenses|income`): `-fixedCostOut <text>` takes the first running
    /// or ended entry whose name contains the text out, as its long press does (the undo bar shows it); `-scrollToEnd`
    /// shows the page's end (Ended, Not counted, the line on how they are found).
    private func debugLaunch(_ proxy: ScrollViewProxy) async {
        guard !launchActionsDone else { return }
        launchActionsDone = true
        for _ in 0..<80 where store.fixedCosts(side: side) == nil { try? await Task.sleep(for: .milliseconds(100)) }
        try? await Task.sleep(for: .milliseconds(600))
        if LaunchArguments.current.contains("-scrollToEnd") { proxy.scrollToWordmark() }
        guard let text = LaunchArguments.value("-fixedCostOut"), let list = store.fixedCosts(side: side) else { return }
        let page = FixedCostPage(list: list, side: side)
        if let row = (page.running + page.ended).first(where: { $0.name.localizedCaseInsensitiveContains(text) }) {
            change(row)
        }
    }
    #endif
}

/// One fixed cost as the lists draw a row: the category's tile, the name with the amount as a payment shows it, the quiet
/// line with how often and the next day due (or the last, once ended) and, for one that is not monthly, its share a
/// month, on one line where it fits, else on a second; the chevron, as rows that open a page. Ended and taken-out rows
/// are quieter: the tile faded, the name in the second ink, the amount in the muted one.
private struct FixedCostRow: View {
    let row: FixedCostPage.Row
    let side: DashboardSide
    let palette: Palette

    var body: some View {
        HStack(spacing: 12) {
            CategoryTile(icon: row.entry.category.icon, color: row.entry.category.color)
                .opacity(row.quiet ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: row.name).font(AppFont.text(14.5, weight: .semibold))
                        .foregroundStyle(row.quiet ? palette.secondary : palette.ink).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(verbatim: row.amount).font(AppFont.number(14))
                        .foregroundStyle(row.quiet ? palette.muted : side == .income ? palette.income : palette.expenseText)
                        .fixedSize()
                }
                ViewThatFits(in: .horizontal) {
                    Text(verbatim: row.oneLine).lineLimit(1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.line).lineLimit(1)
                        if let share = row.share { Text(verbatim: share).lineLimit(1) }
                    }
                }
                .font(AppFont.text(12.5)).foregroundStyle(palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).foregroundStyle(palette.muted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}
