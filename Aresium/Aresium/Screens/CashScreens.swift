import SwiftUI

// Cash (brief 33 part B): the Add cash window (the check window's look: `Ink`, the Settings cards, field boxes, Apple's
// segmented control and date picker, the column check's menu chip), Paid from (a Settings-style list with a checkmark),
// and the Cash page with its row on the dashboard (the dashboard's own rows, palette and wall; ink only, no accent). The
// logic is `Model/Cash.swift` and `Model/PhoneCash.swift`.

// MARK: - Add cash

/// Add cash (and Edit on an entry's page): Spent / Received, the amount, the day, what, the category and, for Spent,
/// Paid from; Save at the bottom.
struct CashEntryView: View {
    @Bindable var model: CashEntryModel
    let save: () async -> Void
    @FocusState private var typing: Box?
    private enum Box: Hashable { case amount, what }
    #if DEBUG
    /// Screenshots: `-openPaidFrom` opens Paid from at once.
    @State private var choosingSource = LaunchArguments.current.contains("-openPaidFrom")
    #else
    @State private var choosingSource = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Picker(String(localized: "Spent or received"), selection: $model.direction) {
                        Text("Spent").tag(ReceiptDirection.out)
                        Text("Received").tag(ReceiptDirection.in)
                    }
                    .pickerStyle(.segmented).padding(.top, 16)
                    Text(model.direction == .out ? "Cash you paid with, when there is no receipt to scan."
                                                 : "Cash you got that never came from your bank: a gift, money from selling something.")
                        .font(AppFont.text(13.5)).foregroundStyle(Ink.secondary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4).padding(.top, 12)
                    VStack(spacing: 0) {
                        FieldRow(label: String(localized: "Amount")) {
                            HStack(spacing: 8) {
                                TextField("", text: $model.amountText,
                                          prompt: Text(verbatim: ReceiptAmount.field(0)).foregroundStyle(Ink.muted))
                                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).font(AppFont.number(15))
                                    .accessibilityLabel(Text("Amount"))
                                    .focused($typing, equals: .amount)
                                    .fieldBox { typing = .amount }
                                    .frame(maxWidth: 150)
                                Text(verbatim: ReceiptAmount.euro).font(AppFont.number(13, weight: .medium))
                                    .foregroundStyle(Ink.muted)
                            }
                        }
                        SettingsDivider()
                        FieldRow(label: String(localized: "Date")) {
                            DatePicker(String(localized: "Date"), selection: $model.date, in: ...Date.now,
                                       displayedComponents: .date)
                                .labelsHidden().environment(\.locale, AppLanguage.current.locale)
                        }
                        SettingsDivider()
                        FieldRow(label: String(localized: "What")) {
                            TextField("", text: $model.what, prompt: Text(model.direction == .out ? "Where or what for"
                                                                                                   : "From whom or what for")
                                        .foregroundStyle(Ink.muted))
                                .textInputAutocapitalization(.sentences)
                                .accessibilityLabel(Text("What"))
                                .focused($typing, equals: .what)
                                .fieldBox { typing = .what }
                        }
                    }
                    .glassCard().padding(.top, 20)
                    VStack(spacing: 0) {
                        FieldRow(label: String(localized: "Category")) {
                            Menu {
                                Picker(selection: $model.category) {
                                    ForEach(model.choices) { choice in Text(verbatim: choice.name).tag(choice.id) }
                                } label: { EmptyView() }
                            } label: {
                                MenuChip(text: model.choices.first { $0.id == model.category }?.name ?? "")
                            }
                            .accessibilityLabel(Text("Category"))
                        }
                    }
                    .glassCard().padding(.top, 20)
                    if model.direction == .out {
                        VStack(spacing: 0) {
                            Button { choosingSource = true } label: {
                                SettingsRow(title: String(localized: "Paid from"), value: model.paidFromName)
                            }
                            .buttonStyle(SettingsRowStyle())
                        }
                        .glassCard().padding(.top, 20)
                        FormNote(text: String(localized: "Automatic takes it from the latest withdrawal or cash received up to this day."))
                            .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            bottom.overlay(alignment: .top) { Rectangle().fill(Ink.line).frame(height: 1) }
        }
        .task(id: model.day) { await model.loadSources() }
        .navigationDestination(isPresented: $choosingSource) {
            PaidFromList(sources: { model.sources }, day: model.day, selected: model.paidFrom) { model.paidFrom = $0 }
        }
    }

    private var bottom: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let problem = model.problem { FormProblem(text: problem) }
            else if let missing = model.missing {
                Label { Text(verbatim: missing) } icon: { Image(systemName: "exclamationmark.circle") }
                    .font(AppFont.text(13)).foregroundStyle(Ink.secondary).padding(.horizontal, 4)
            }
            Button {
                Task { await save() }
            } label: {
                BusyLabel(text: Text("Save"), busy: model.isSaving)
            }
            .buttonStyle(FormButtonStyle(accent: nil, busy: model.isSaving))
            .disabled(!model.canSave && !model.isSaving)
            .allowsHitTesting(!model.isSaving)
        }
        .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 10)
    }
}

/// Add cash in a sheet of its own (the import menu, the Cash page), with Cancel. It closes only with Cancel or Save, so
/// typed values are not lost by a swipe.
struct CashEntrySheet: View {
    let model: CashEntryModel
    /// After Save: the entry kept (the owner builds the dashboard again).
    let saved: (LedgerReceipt) async -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CashEntryView(model: model) {
                guard let entry = await model.save() else { return }
                dismiss()
                await saved(entry)
            }
            .background { Ink.background.ignoresSafeArea() }
            .navigationTitle(model.editing == nil ? Text("Add cash") : Text("Edit entry"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .tint(Ink.primary)
        .presentationBackground(Ink.background)
        .interactiveDismissDisabled(!model.amountText.isEmpty || !model.what.isEmpty)
        .task { await model.load() }
    }
}

extension View {
    /// Import → Add cash: the window while `entry` is set; `saved` after Save.
    func cashEntry(_ entry: Binding<CashEntryModel?>, saved: @escaping (LedgerReceipt) async -> Void) -> some View {
        modifier(CashEntryPresenter(entry: entry, saved: saved))
    }
}

private struct CashEntryPresenter: ViewModifier {
    @Binding var entry: CashEntryModel?
    let saved: (LedgerReceipt) async -> Void

    func body(content: Content) -> some View {
        content.sheet(item: $entry) { model in CashEntrySheet(model: model, saved: saved) }
    }
}

// MARK: - Paid from

/// Paid from: Automatic, or one withdrawal or cash received on or before the day, newest first, each with what it still
/// holds. A tap chooses and goes back.
struct PaidFromList: View {
    /// The choices, read as the list draws (so it follows its model as it loads); nil while they load.
    let sources: () -> [CashSource]?
    /// The payment's day: sources more than `CashPage.lookbackDays` before it wait behind "Show older".
    let day: String
    let selected: String?
    let choose: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsOlder = false

    var body: some View {
        let sources = sources()
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FormNote(text: String(localized: "Where this cash came from. Automatic takes it from the latest withdrawal or cash received up to this day."))
                    .padding(.top, 16)
                if let sources {
                    let groups = CashPage.split(sources, before: day, selected: selected)
                    SettingsSection(String(localized: "Paid from")) {
                        row(id: nil, title: CashWording.choice(nil), line: nil)
                        ForEach(groups.recent) { source in
                            SettingsDivider()
                            sourceRow(source)
                        }
                        if !groups.older.isEmpty {
                            if showsOlder {
                                ForEach(groups.older) { source in
                                    SettingsDivider()
                                    sourceRow(source)
                                }
                            } else {
                                SettingsDivider()
                                Button { showsOlder = true } label: {
                                    HStack {
                                        Text("Show older").font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.secondary)
                                        Spacer()
                                        Text(verbatim: "\(groups.older.count)").font(AppFont.number(13)).foregroundStyle(Ink.muted)
                                    }
                                    .frame(minHeight: 50).padding(.horizontal, 16).contentShape(Rectangle())
                                }
                                .buttonStyle(SettingsRowStyle())
                            }
                        }
                    }
                    if sources.isEmpty {
                        Text("No withdrawal or cash received on or before this day yet.")
                            .font(AppFont.text(13.5)).foregroundStyle(Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4).padding(.top, 14)
                    }
                } else {
                    ProgressView().tint(Ink.secondary).frame(maxWidth: .infinity).padding(30)
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background { Ink.background.ignoresSafeArea() }
        .navigationTitle(Text("Paid from")).navigationBarTitleDisplayMode(.inline)
    }

    private func sourceRow(_ source: CashSource) -> some View {
        row(id: source.id, title: CashWording.choice(source),
            line: [source.place, CashWording.left(source.left)].filter { !$0.isEmpty }.joined(separator: " · "))
    }

    private func row(id: String?, title: String, line: String?) -> some View {
        Button {
            choose(id)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                    if let line {
                        Text(verbatim: line).font(AppFont.text(12.5)).foregroundStyle(Ink.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                if id == selected {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Ink.primary)
                }
            }
            .frame(minHeight: line == nil ? 50 : 58).padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsRowStyle())
        .accessibilityAddTraits(id == selected ? .isSelected : [])
    }
}

// MARK: - the Cash page

/// What the Cash page opens: a withdrawal's payment page, a receipt's or entry's page, or Add cash.
private enum CashSheet: Identifiable {
    case payment(Transaction)
    case receipt(String)
    case add(ReceiptDirection)

    var id: String {
        switch self {
        case .payment(let transaction): "payment:" + transaction.id
        case .receipt(let id): "receipt:" + id
        case .add(let direction): "add:" + direction.rawValue
        }
    }
}

/// The Cash page for one month: what was withdrawn, received and spent, what is not accounted for, Add spending and
/// Add received cash, then every movement of the wallet, newest first. A view: it counts in no total.
struct CashScreen: View {
    let month: String
    let store: DashboardStore
    let palette: Palette
    let band: AresiumBand
    @State private var sheet: CashSheet?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var page: CashPage? { store.dashboard?.cash.map(CashPage.init) }

    var body: some View {
        VStack(spacing: 0) {
            DashboardStatus(store: store, palette: palette)
            WordmarkScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let movements = page?.movements(in: month) ?? []
                    if movements.isEmpty {
                        EmptyMessage(text: String(localized: "No cash this month."), palette: palette)
                        Text("Withdrawals from your bank, cash you received and what you paid with it show here.")
                            .font(AppFont.text(13.5)).foregroundStyle(palette.secondary).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.top, -14)
                        buttons.padding(.top, 22)
                    } else {
                        numbers(page?.month(month) ?? .none)
                        buttons.padding(.top, 18)
                        LazyVStack(spacing: 0) {
                            ForEach(movements) { movement in
                                Button { open(movement) } label: {
                                    CashMovementRow(movement: movement, page: page, palette: palette)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 14)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 6)
            } band: { _ in band }
            .refreshable { await store.reload() }.scrollBounceBehavior(.always)
        }
        .sheet(item: $sheet) { sheet in
            if let phone = store.phone {
                switch sheet {
                case .payment(let transaction):
                    TransactionDetailSheet(store: store.transactionDetailStore(for: transaction), palette: palette)
                case .receipt(let id):
                    ReceiptPageSheet(model: ReceiptPageModel(id: id, phone: phone) {
                        await store.reloadAfterTransactionChange()
                    }, palette: palette)
                case .add(let direction):
                    CashEntrySheet(model: CashEntryModel(direction: direction, phone: phone,
                                                         today: Self.day(in: month))) { _ in
                        await store.reloadAfterTransactionChange()
                    }
                }
            }
        }
        #if DEBUG
        .task {
            // Screenshots: `-addCash spent|received` opens Add cash from the page; `-cashOpen <text>` the movement whose
            // place contains the text.
            switch LaunchArguments.value("-addCash") {
            case "spent": sheet = .add(.out)
            case "received": sheet = .add(.in)
            default: break
            }
            if let text = LaunchArguments.value("-cashOpen") {
                for _ in 0..<40 where store.dashboard == nil { try? await Task.sleep(for: .milliseconds(100)) }
                if let movement = page?.movements(in: month).first(where: { $0.place.localizedCaseInsensitiveContains(text) }) {
                    open(movement)
                }
            }
        }
        #endif
    }

    /// The month's numbers: what is not accounted for first (in the withdrawals' category too), then withdrawn, received
    /// and spent.
    private func numbers(_ tally: CashMonth) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // The number beside its name; at the accessibility text sizes under it.
            let top = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                                   : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            top {
                Text(verbatim: CashWording.unaccounted()).font(AppFont.text(19, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
                Text(verbatim: Money.precise(tally.unaccounted)).font(AppFont.number(19, weight: .bold))
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
            Text("In your wallet still, or spent without a receipt.")
                .font(AppFont.text(12.5)).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                                                      : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
            layout {
                stat(CashWording.withdrawn(), tally.withdrawn)
                stat(CashWording.received(), tally.received)
                stat(CashWording.spent(), tally.spent)
            }
            .padding(.top, 16)
        }
        .padding(16)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.line))
        .accessibilityElement(children: .combine)
    }

    private func stat(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: label.uppercased()).font(AppFont.text(10.5, weight: .semibold)).tracking(1.1)
                .foregroundStyle(palette.muted).lineLimit(1).minimumScaleFactor(0.8)
            Text(verbatim: Money.precise(value)).font(AppFont.number(14.5)).foregroundStyle(palette.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Add spending and Add received cash, side by side (one above the other at the largest text sizes).
    private var buttons: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Button { sheet = .add(.out) } label: { Label("Add spending", systemImage: "minus") }
            Button { sheet = .add(.in) } label: { Label("Add received cash", systemImage: "plus") }
        }
        .buttonStyle(QuietButtonStyle())
        .disabled(store.phone == nil)
    }

    private func open(_ movement: CashMovement) {
        if movement.kind == .withdrawal {
            if let payment = store.dashboard?.transactions.first(where: { $0.id == movement.id }) { sheet = .payment(payment) }
        } else {
            sheet = .receipt(movement.id)
        }
    }

    /// A new entry from a month's page starts on that month's last day up to today.
    static func day(in month: String, today: Date = .now) -> Date {
        guard let first = ReceiptDay.date(month + "-01"),
              let next = ReceiptDay.calendar.date(byAdding: .month, value: 1, to: first),
              let last = ReceiptDay.calendar.date(byAdding: .day, value: -1, to: next) else { return today }
        return min(last, today)
    }
}

/// One movement of the wallet as the dashboard's payment rows: the day, where (or what), its kind and category, what a
/// source still holds or where a payment came from, and the amount from the wallet's side.
struct CashMovementRow: View {
    let movement: CashMovement
    let page: CashPage?
    let palette: Palette
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let large = typeSize.isAccessibilitySize
        HStack(alignment: large ? .top : .center, spacing: 12) {
            DayTile(palette: palette) { Text(verbatim: ReceiptPageWording.dayNumber(movement.date)) }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: CashWording.title(movement)).font(AppFont.text(14.5, weight: .semibold))
                    .lineLimit(large ? 3 : 1)
                Text(verbatim: line).font(AppFont.text(12.5)).foregroundStyle(palette.muted).lineLimit(large ? 4 : 1)
                if let second {
                    // "Aus dem erhaltenen Bargeld vom 3. Okt." needs a second line on a narrow iPhone.
                    Text(verbatim: second).font(AppFont.text(12.5)).foregroundStyle(palette.muted).lineLimit(large ? 4 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if large { amount.padding(.top, 2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !large { amount }
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).foregroundStyle(palette.muted)
        }
        .foregroundStyle(palette.ink)
        .padding(.horizontal, 12).padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Its kind and category: "Withdrawal · Cash withdrawals", "Entry · Eating out".
    private var line: String {
        [CashWording.kind(movement.kind), CategoryName.shown(movement.category)].joined(separator: " · ")
    }

    /// A source: what it still holds; a payment out: where it came from.
    private var second: String? {
        if movement.isSource { return movement.left.map { CashWording.left($0) } }
        return page.flatMap { CashWording.paidFrom(movement, in: $0) }
    }

    private var amount: some View {
        Text(Money.transaction(movement.amount)).font(AppFont.number(14))
            .foregroundStyle(movement.amount < 0 ? palette.expenseText : palette.income).fixedSize()
    }
}

/// The Cash page in Overview: the months with cash, newest first, each with what is not accounted for.
struct CashMonthsScreen: View {
    let store: DashboardStore
    let palette: Palette
    let band: AresiumBand
    let pick: (DashboardRoute) -> Void

    var body: some View {
        VStack(spacing: 0) {
            DashboardStatus(store: store, palette: palette)
            WordmarkScrollView {
                LazyVStack(spacing: 0) {
                    let page = store.dashboard?.cash.map(CashPage.init)
                    ForEach(page?.monthKeys ?? [], id: \.self) { key in
                        Button { pick(DashboardRoute(category: "", side: .expenses, month: key, cash: true)) } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(verbatim: store.monthTitle(key)).font(AppFont.text(14.5, weight: .semibold))
                                    Text(verbatim: CashRowWording.monthLine(page?.month(key) ?? .none))
                                        .font(AppFont.text(12.5)).foregroundStyle(palette.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(palette.muted)
                            }
                            .foregroundStyle(palette.ink).padding(.horizontal, 12).padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if page?.monthKeys.isEmpty ?? true {
                        EmptyMessage(text: String(localized: "No cash yet."), palette: palette)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 8)
            } band: { _ in band }
            .refreshable { await store.reload() }.scrollBounceBehavior(.always)
        }
    }
}

/// The dashboard's row to the Cash page: below the categories, only when there is any cash movement; it counts in no
/// total, so it shows no amount column, only what is not accounted for in its line.
struct CashRow: View {
    let store: DashboardStore
    let palette: Palette
    let current: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wallet.bifold").font(.system(size: 17, weight: .medium)).foregroundStyle(palette.secondary)
                .frame(width: 38, height: 38)
                .background(palette.card2, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.line))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Cash").font(AppFont.text(14.5, weight: .semibold))
                Text(verbatim: CashRowWording.line(unaccounted: store.cashUnaccounted(current: current)))
                    .font(AppFont.text(12.5)).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).foregroundStyle(palette.muted)
        }
        .foregroundStyle(palette.ink).padding(.horizontal, 12).padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
