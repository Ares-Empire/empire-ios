import SwiftUI

// Money paid back on screen (brief 203; words and logic in `Model/PaybackPage.swift`): the section on a payment's page
// and the window that makes or changes a link. Quiet and optional (Patrik, 2026-11-02): one action in the secondary ink
// below what the page had, like its other quiet rows; nothing elsewhere asks for it. The app's own pieces only: the page's
// cards (the "All from" card's look), the pen beside what a tap changes, the search field, the change window's bar.

/// The payment's page's section (after its rows and receipt, before the bank's own row): each link as a card that opens
/// the other payment, with the pen that changes its euros or removes it (also on the card's long press); one line on what
/// still counts; and, while the payment has euros free, the quiet action that makes a link. Nothing where the payment
/// cannot take part. The tour's paid back step rings all of it (`.payback`).
struct PaybackSection: View {
    let detail: TransactionDetail
    let links: PaybackLinks
    let palette: Palette
    /// The other payment's page, pushed on the page's own stack.
    let open: (String) -> Void

    var body: some View {
        let content = PaybackSectionContent(detail: detail, state: links.state)
        // While the state loads (off the main thread, brief 203: 69 ms on the sample, 417 ms at 5,000 payments) the
        // action's room is kept for a payment that will likely have it, so the bank's own row below does not jump.
        let waits = !links.isLoaded && content.action == nil && detail.currency == "EUR"
            && (Paybacks.cents(abs(detail.countedAmount)) ?? 0) > 0
        if !content.isEmpty || waits {
            VStack(alignment: .leading, spacing: 8) {
                if let heading = content.heading {
                    Text(verbatim: heading).font(AppFont.text(12, weight: .semibold)).foregroundStyle(palette.muted)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(content.links) { link in
                    linkRow(link, direction: content.direction)
                }
                if let summary = content.summary {
                    Text(verbatim: summary).font(AppFont.text(12.5)).foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("paybackSummary")
                }
                if let action = content.action {
                    Button { links.begin(detail: detail) } label: {
                        Label {
                            Text(verbatim: action).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "link").font(.system(size: 13, weight: .medium))
                        }
                        .font(AppFont.text(14, weight: .medium)).foregroundStyle(palette.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(links.isWorking)
                    .accessibilityIdentifier("paybackAction")
                } else if waits {
                    Color.clear.frame(height: 44).accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tourAnchor(content.isEmpty ? nil : .payback)
            .padding(.top, content.links.isEmpty ? 12 : 20)
        }
    }

    /// A link: the card opens the other payment; the pen beside it (as beside the name and the category) opens its
    /// euros with Remove link; the card's long press has both.
    private func linkRow(_ link: PaybackDetailLink, direction: PaybackDirection) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Button { open(link.payment) } label: {
                PaybackLinkCard(link: link, palette: palette)
                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: PaybackWording.spokenLink(link, direction: direction)))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("paybackLink")
            .contextMenu {
                Button("Change amount", systemImage: "pencil") { links.edit(link, detail: detail) }
                Button("Remove link", systemImage: "minus.circle", role: .destructive) {
                    Task { await links.remove(link, direction: direction) }
                }
            }
            PenButton(label: Text(verbatim: PaybackWording.changeLink()), palette: palette) {
                links.edit(link, detail: detail)
            }
            .accessibilityIdentifier("changePayback")
        }
    }
}

/// A link on a payment's page, in the "All from" card's look: the other payment's name, its day and own amount, the
/// linked euros and the chevron of a row that opens a page.
struct PaybackLinkCard: View {
    let link: PaybackDetailLink
    let palette: Palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: link.place).font(AppFont.text(14.5, weight: .semibold)).lineLimit(1)
                Text(verbatim: PaybackWording.linkLine(link)).font(AppFont.text(12.5)).foregroundStyle(palette.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: Money.precise(link.linkedAmount)).font(AppFont.number(14, weight: .semibold)).fixedSize()
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).foregroundStyle(palette.muted)
        }
        .foregroundStyle(palette.ink)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(palette.card, in: shape)
        .overlay(shape.stroke(palette.line))
        .contentShape(shape)
    }
}

// MARK: - the window

/// The window (a sheet over the payment's page, as the change window): the other payment, then the euros. A new link
/// starts at the choice: the payment and the question, the search field, the suggestions (or, while typing, what the
/// search finds); a tap pushes the euros. A link being changed starts at its euros, with Remove link.
struct PaybackSheet: View {
    @Bindable var window: PaybackWindow
    let store: DashboardStore
    let palette: Palette

    var body: some View {
        NavigationStack {
            if window.isEditing {
                PaybackAmountStep(window: window, store: store, palette: palette, isRoot: true)
            } else {
                PaybackChoice(window: window, store: store, palette: palette)
                    .navigationDestination(isPresented: $window.showsAmount) {
                        PaybackAmountStep(window: window, store: store, palette: palette, isRoot: false)
                    }
            }
        }
        // As the change window: the bar keeps the system's font; the content sets the app's.
        .environment(\.font, nil)
        .tint(palette.ink)
        .interactiveDismissDisabled(window.isWorking)
        .task { await window.load() }
    }
}

/// The choice: this payment, the question, the search, then the suggestions or the search's results.
private struct PaybackChoice: View {
    @Bindable var window: PaybackWindow
    let store: DashboardStore
    let palette: Palette
    @FocusState private var searching: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: window.payment.place).font(AppFont.text(20, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: window.payment.signedAmount).font(AppFont.number(17, weight: .bold))
                        .foregroundStyle(window.payment.amount < 0 ? palette.expenseText : palette.balance)
                }
                Text(verbatim: PaybackWording.question(direction: window.direction))
                    .font(AppFont.text(13.5)).foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                SearchField(text: $window.query, prompt: SearchPage.prompt(), palette: palette, focused: $searching)
                    .padding(.top, 14)
                list.padding(.top, 14)
            }
            .padding(20)
            .font(AppFont.text(14)).foregroundStyle(palette.ink)
        }
        .scrollDismissesKeyboard(.immediately)
        .background { Wall(palette: palette) }
        .navigationTitle(Text(verbatim: PaybackWording.windowTitle(direction: window.direction)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        // The search waits a moment after the last key (each search reads the store's payments).
        .task(id: window.query) {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await window.search()
        }
        #if DEBUG
        .task { await debugLaunch() }
        #endif
    }

    @ViewBuilder private var list: some View {
        let typed = window.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty {
            Text(verbatim: PaybackWording.suggestedHeading().uppercased()).font(AppFont.text(11, weight: .semibold))
                .tracking(1.3).foregroundStyle(palette.muted)
                .padding(.horizontal, 4).padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            if let suggestions = window.suggestions {
                if suggestions.isEmpty {
                    EmptyMessage(text: PaybackWording.noSuggestion(), palette: palette)
                } else {
                    rows(suggestions)
                }
            } else {
                ProgressView().tint(palette.secondary).frame(maxWidth: .infinity).padding(24)
            }
        } else if let results = window.results, window.resultsQuery == typed {
            if results.isEmpty {
                EmptyMessage(text: PaybackWording.noMatch(typed), palette: palette)
            } else {
                rows(results)
            }
        } else {
            ProgressView().tint(palette.secondary).frame(maxWidth: .infinity).padding(24)
        }
    }

    private func rows(_ suggestions: [PaybackSuggestion]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(suggestions) { suggestion in
                Button {
                    searching = false
                    window.choose(suggestion)
                } label: {
                    PaybackChoiceRow(suggestion: suggestion, store: store, palette: palette)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("paybackChoice")
            }
        }
        .padding(.horizontal, -8)
    }

    #if DEBUG
    /// Screenshots: `-paybackSearch <text>` types it; `-paybackPick <text>` taps the first suggestion (or result) whose
    /// name contains the text.
    private func debugLaunch() async {
        if let text = LaunchArguments.value("-paybackSearch") {
            try? await Task.sleep(for: .milliseconds(500))
            window.query = text
        }
        guard let text = LaunchArguments.value("-paybackPick") else { return }
        for _ in 0..<40 {
            let shown = window.query.isEmpty ? window.suggestions : window.results
            if let hit = shown?.first(where: { $0.transaction.place.localizedCaseInsensitiveContains(text) }) {
                try? await Task.sleep(for: .milliseconds(500))
                window.choose(hit)
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
    #endif
}

/// A suggestion or result: its category's tile, its name, its day and what fits ("29 Oct · half"), its own amount signed
/// as a payment row, and the chevron (the euros come next).
private struct PaybackChoiceRow: View {
    let suggestion: PaybackSuggestion
    let store: DashboardStore
    let palette: Palette

    var body: some View {
        let transaction = suggestion.transaction
        let category = store.categoryLook(named: transaction.categoryName)
        HStack(spacing: 12) {
            CategoryTile(icon: category?.icon ?? "Tag", color: category?.color ?? SearchPage.noCategoryColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: transaction.place).font(AppFont.text(14.5, weight: .semibold)).lineLimit(1)
                line.font(AppFont.text(12.5)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: Money.transaction(transaction.amount)).font(AppFont.number(14))
                .foregroundStyle(transaction.amount < 0 ? palette.expenseText : palette.income).fixedSize()
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).foregroundStyle(palette.muted)
                .accessibilityHidden(true)
        }
        .foregroundStyle(palette.ink)
        .padding(.horizontal, 12).padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// The day in the quiet ink, what fits a little stronger.
    private var line: Text {
        let day = Text(verbatim: PaybackWording.day(suggestion.transaction.date)).foregroundStyle(palette.muted)
        guard let fit = suggestion.fit else { return day }
        return day + Text(verbatim: " · ").foregroundStyle(palette.muted)
            + Text(verbatim: PaybackWording.fit(fit)).foregroundStyle(palette.secondary)
    }
}

/// The euros: the two payments (the one that came in over the expense it pays back), the question, the field with the
/// suggestion's euros (or the link's), the most it can take, then Link (Save while a link is changed) in the bar.
private struct PaybackAmountStep: View {
    @Bindable var window: PaybackWindow
    let store: DashboardStore
    let palette: Palette
    /// A link being changed opens here: Cancel in the bar, Remove link under the field.
    let isRoot: Bool
    @FocusState private var typing: Bool
    @State private var doneTop: CGFloat?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let pick = window.pick {
                    pair(pick)
                    Text(verbatim: PaybackWording.amountQuestion()).font(AppFont.text(14.5, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 24)
                    field.padding(.top, 10)
                    Text(verbatim: PaybackWording.maximum(pick.maximum)).font(AppFont.text(12.5))
                        .foregroundStyle(window.check == .tooMuch ? palette.expenseText : palette.muted)
                        .padding(.top, 8)
                        .accessibilityIdentifier("paybackMaximum")
                    if let problem = window.problem {
                        Text(verbatim: problem).font(AppFont.text(13)).foregroundStyle(palette.expenseText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                    }
                    if window.isEditing {
                        Button(role: .destructive) { Task { await window.remove() } } label: {
                            Text("Remove link").font(AppFont.text(14, weight: .semibold))
                                .foregroundStyle(palette.expenseText)
                        }
                        .buttonStyle(.bordered).tint(palette.expenseText)
                        .disabled(window.isWorking)
                        .padding(.top, 28)
                        .accessibilityIdentifier("removePayback")
                    }
                } else {
                    ProgressView().tint(palette.secondary).frame(maxWidth: .infinity).padding(30)
                }
            }
            .padding(20)
            .font(AppFont.text(14)).foregroundStyle(palette.ink)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { Wall(palette: palette) }
        .navigationTitle(Text("Amount")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isRoot {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                // Muted while it cannot link (nothing typed, too much, unchanged), as the change window's Save.
                Button { Task { await window.confirm() } } label: {
                    if window.isWorking {
                        ProgressView().tint(palette.ink)
                    } else {
                        (window.isEditing ? Text("Save") : Text("Link"))
                            .foregroundStyle(window.canConfirm ? palette.ink : palette.muted)
                    }
                }
                .disabled(!window.canConfirm)
                .accessibilityIdentifier("confirmPayback")
            }
        }
        .numberPadDone(typing, top: $doneTop) { typing = false }
        .task(id: window.pick?.other.id) {
            // The field ready once the step has come in (a field focused while it slides in loses the keyboard).
            guard window.pick != nil else { return }
            try? await Task.sleep(for: .milliseconds(450))
            #if DEBUG
            if let text = LaunchArguments.value("-paybackAmount") { window.debugType(text) }
            if LaunchArguments.current.contains("-paybackKeyboardDown") { return }
            #endif
            typing = true
        }
    }

    /// The payment that came in over the expense it pays back, as rows of a list in one card.
    private func pair(_ pick: PaybackPick) -> some View {
        let this = PaybackParty(detail: window.payment, store: store)
        let other = PaybackParty(transaction: pick.other, store: store)
        let (incoming, expense) = window.direction == .moneyIn ? (this, other) : (other, this)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(spacing: 0) {
            PaybackPartyRow(party: incoming, palette: palette)
            Rectangle().fill(palette.line).frame(height: 1).padding(.horizontal, 12).accessibilityHidden(true)
            PaybackPartyRow(party: expense, palette: palette)
        }
        .background(palette.card, in: shape)
        .overlay(shape.stroke(palette.line))
    }

    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return HStack(spacing: 8) {
            TextField(text: $window.amountText, prompt: Text(verbatim: ReceiptAmount.field(0)).foregroundStyle(palette.muted)) {
                Text("Amount")
            }
            .keyboardType(.decimalPad)
            .font(AppFont.number(20, weight: .semibold)).foregroundStyle(palette.ink)
            .focused($typing)
            .accessibilityIdentifier("paybackAmount")
            Text(verbatim: "€").font(AppFont.number(17, weight: .medium)).foregroundStyle(palette.muted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14).frame(minHeight: 48)
        .background(palette.card2, in: shape)
        .overlay(shape.strokeBorder(window.check == .tooMuch ? palette.expenseText : palette.line))
        .contentShape(shape)
        .onTapGesture { typing = true }
        .disabled(window.isWorking)
    }
}

/// One of the two payments of a link, as the amount step shows it.
private struct PaybackParty {
    let name: String
    let date: String
    let amount: Double
    let category: Category?
    let color: String

    init(detail: TransactionDetail, store: DashboardStore) {
        name = detail.place
        date = detail.bookingDate
        amount = detail.amount
        category = store.categoryLook(named: detail.category)
        color = detail.categoryColor
    }

    init(transaction: Transaction, store: DashboardStore) {
        name = transaction.place
        date = transaction.date
        amount = transaction.amount
        category = store.categoryLook(named: transaction.categoryName)
        color = category?.color ?? SearchPage.noCategoryColor
    }
}

private struct PaybackPartyRow: View {
    let party: PaybackParty
    let palette: Palette

    var body: some View {
        HStack(spacing: 12) {
            CategoryTile(icon: party.category?.icon ?? "Tag", color: party.category?.color ?? party.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: party.name).font(AppFont.text(14.5, weight: .semibold)).lineLimit(1)
                Text(verbatim: PaybackWording.day(party.date)).font(AppFont.text(12.5)).foregroundStyle(palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: Money.transaction(party.amount)).font(AppFont.number(14))
                .foregroundStyle(party.amount < 0 ? palette.expenseText : palette.income).fixedSize()
        }
        .foregroundStyle(palette.ink)
        .padding(.horizontal, 12).padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}
