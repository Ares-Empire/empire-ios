import SwiftUI

// The quick sort's look (brief 99; the logic is `Model/QuickSort.swift` and `Model/QuickSortFlow.swift`), made from the
// app's own pieces: the payment page's title and amount, a category's month list's card and tiles, the change window's
// grid, the selection's bottom bar, the import result's offer card. Ink only, from the palette, in light, dark and red
// mode.

/// The flow: a sheet at full height. The bar: "Not sorted" with the progress under it ("3 of 12 · 41 sorted") and Done;
/// a thin line shows how far through the cards. One card at a time: its name, money, months and example lines, then its
/// side's tiles; a tap sorts and the next card slides in (Reduce Motion: a fade). Undo and Skip in the bar at the
/// bottom. At the end, what was sorted and Done.
struct QuickSortSheet: View {
    let flow: QuickSortFlow
    let palette: Palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                QuickSortProgress(fraction: flow.fraction, palette: palette)
                    .padding(.horizontal, 20).padding(.top, 4)
                ZStack(alignment: .top) {
                    if let card = flow.card {
                        QuickSortCardPage(card: card, flow: flow, palette: palette)
                            .id(card.id)
                            .transition(cardTransition)
                    } else {
                        QuickSortEnd(flow: flow, palette: palette) { dismiss() }
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.38, bounce: 0),
                           value: flow.position)
            }
            .background { Wall(palette: palette) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if flow.card != nil || flow.canUndo {
                    BottomBar(palette: palette) {
                        BarItem(symbol: "arrow.uturn.backward", title: Text("Undo", tableName: "Shared"),
                                enabled: flow.canUndo, busy: flow.isUndoing, palette: palette) {
                            Task { await flow.undo() }
                        }
                        .accessibilityIdentifier("quickSortUndo")
                        if flow.card != nil {
                            BarItem(symbol: "arrow.forward", title: Text(verbatim: QuickSortWording.skip()),
                                    enabled: flow.canSkip, palette: palette) { flow.skip() }
                                .accessibilityIdentifier("quickSortSkip")
                        }
                    }
                }
            }
            .navigationTitle(Text("Not sorted"))
            .navigationSubtitle(Text(verbatim: flow.progress))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // At the end the summary's own Done is the way out; one Done is enough.
                if flow.card != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }.accessibilityIdentifier("quickSortDone")
                    }
                }
            }
        }
        .environment(\.font, nil)
        // A light tap as a card is sorted (none for an undo).
        .sensoryFeedback(.impact(weight: .light), trigger: flow.sortedPayments) { old, new in new > old }
        .tourCard()
        .tint(palette.ink)
        .interactiveDismissDisabled(flow.isUndoing || flow.card?.isSaving == true
                                    || flow.card?.newCategory.isMaking == true)
    }

    /// The next card slides in from the right (from the left when Undo brings one back) while the one before fades; with
    /// Reduce Motion both fade.
    private var cardTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(insertion: .move(edge: flow.cameBack ? .leading : .trailing).combined(with: .opacity),
                           removal: .opacity)
    }
}

/// How far through the cards: the list's thin bar (`ValueRow`'s), in ink.
private struct QuickSortProgress: View {
    let fraction: Double
    let palette: Palette

    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(palette.grid).overlay(alignment: .leading) {
                Capsule().fill(palette.secondary).frame(width: geometry.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 3)
        .animation(.easeOut(duration: 0.3), value: fraction)
        .accessibilityHidden(true)
    }
}

/// One card and its tiles, scrolling as one when the tiles are many.
private struct QuickSortCardPage: View {
    let card: QuickSortCard
    let flow: QuickSortFlow
    let palette: Palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                QuickSortCardView(card: card, palette: palette)
                VStack(alignment: .leading, spacing: 10) {
                    Text(verbatim: QuickSortWording.tapLine(card.ids.count))
                        .font(AppFont.text(13)).foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    CategoryGrid(window: card, palette: palette, working: card.isSaving,
                                 pick: { name in Task { await card.sort(name) } },
                                 pickFromOtherSide: { name in Task { await card.sortFromOtherSide(name) } })
                }
                // A name that made no category (brief 60), a sort that failed, or an undo the data no longer allows.
                ForEach([card.newCategory.problem, card.saveError, flow.problem].compactMap { $0 }, id: \.self) { line in
                    Text(verbatim: line).font(AppFont.text(13)).foregroundStyle(palette.expenseText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("quickSortProblem")
                }
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
            .foregroundStyle(palette.ink)
        }
        .scrollBounceBehavior(.basedOnSize)
        .newCategoryAlert(card.newCategory, tint: palette.ink) { await card.createAndSort() }
    }
}

/// The card: the direction in the list headings' small capitals, the name in the payment page's title style, the money
/// signed in its side's colour as the payment page shows it, how many and over which months, then up to three of the
/// payments' texts in quiet type. VoiceOver reads it as one.
private struct QuickSortCardView: View {
    let card: QuickSortCard
    let palette: Palette

    var body: some View {
        let group = card.group
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: QuickSortWording.side(group.side).uppercased())
                .font(AppFont.text(11, weight: .semibold)).tracking(1.3).foregroundStyle(palette.muted)
            Text(verbatim: card.title).font(AppFont.text(22, weight: .bold)).foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Text(verbatim: Money.transaction(group.signedTotal)).font(AppFont.number(20, weight: .bold))
                .foregroundStyle(group.side == .income ? palette.balance : palette.expenseText)
                .padding(.top, 4)
            Text(verbatim: QuickSortWording.line(group)).font(AppFont.text(13.5)).foregroundStyle(palette.secondary)
                .padding(.top, 2)
            if !group.examples.isEmpty {
                Rectangle().fill(palette.line).frame(height: 1).padding(.vertical, 12)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(group.examples, id: \.self) { line in
                        Text(verbatim: line).font(AppFont.text(12.5)).foregroundStyle(palette.muted).lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(palette.card, in: shape)
        .overlay(shape.stroke(palette.line))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: QuickSortWording.spoken(group, title: card.title)))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("quickSortCard")
    }
}

/// The end: what was sorted, from how many names, how many were skipped (or that nothing is left), and Done.
private struct QuickSortEnd: View {
    let flow: QuickSortFlow
    let palette: Palette
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: flow.sortedPayments > 0 ? "checkmark" : "tray")
                .font(.system(size: 26, weight: .medium)).foregroundStyle(palette.secondary)
                .frame(width: 64, height: 64)
                .overlay(Circle().stroke(palette.line))
                .accessibilityHidden(true)
            Text(verbatim: flow.summaryTitle).font(AppFont.text(22, weight: .bold)).foregroundStyle(palette.ink)
                .multilineTextAlignment(.center).padding(.top, 18)
                .accessibilityAddTraits(.isHeader)
            let line = flow.summaryLine
            if !line.isEmpty {
                Text(verbatim: line).font(AppFont.text(14)).foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }
            Button("Done", action: done)
                .buttonStyle(FormButtonStyle(accent: nil))
                .frame(maxWidth: 260)
                .padding(.top, 26)
                .accessibilityIdentifier("quickSortEndDone")
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
    }
}

/// The card at the top of Not sorted's month list (Current and Overview): the way through what is Not sorted, name by
/// name, over all months. A month list's row on the card colour with the line around it, so it reads as part of the
/// list and as a way somewhere; the stack in the day's tile's place.
struct QuickSortListCard: View {
    let tally: QuickSortTally
    let palette: Palette
    let open: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button(action: open) {
            HStack(spacing: 12) {
                DayTile(palette: palette) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 17, weight: .medium))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: QuickSortWording.cardTitle()).font(AppFont.text(14.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Text(verbatim: QuickSortWording.cardLine(tally)).font(AppFont.text(12.5))
                        .foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).foregroundStyle(palette.muted)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(palette.card, in: shape)
            .overlay(shape.stroke(palette.line))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .tourAnchor(.quickSortCard)
        .accessibilityIdentifier("quickSortListCard")
    }
}

/// The offer's state and answers, from the owner of the imports (ContentView).
struct QuickSortOfferChoice {
    let tally: QuickSortTally
    let goThrough: () -> Void
    let later: () -> Void
}

/// "34 payments not sorted" after an import, in the result's card and place (brief 46's offer card): from how many
/// names, what one tap does, Go through and Later.
struct QuickSortOfferCard: View {
    let offer: QuickSortOfferChoice
    let palette: Palette

    var body: some View {
        OfferCard(symbol: "square.stack.3d.up", title: QuickSortWording.offerTitle(offer.tally),
                  line: QuickSortWording.offerLine(offer.tally), main: Text(verbatim: QuickSortWording.goThrough()),
                  quiet: Text(verbatim: QuickSortWording.later()), palette: palette, act: offer.goThrough,
                  decline: offer.later)
            .accessibilityIdentifier("quickSortOffer")
    }
}
