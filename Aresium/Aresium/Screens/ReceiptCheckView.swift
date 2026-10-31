import SwiftUI

// A receipt's check window and its question (brief 31), in the file check window's look and wording style
// (FileCheckSheet: `Ink`, the Settings cards, the dashboard's payment rows, "Does this look right?" at the bottom with
// the main button). Apple's own controls for the values: text fields, the date picker, the segmented Card / Cash, menus
// for the currency and the category. Every value looks like something to tap (brief 33, Patrik 2026-10-28: the window
// asked "Does this look right?" but seemed to offer nothing to do when it was not): the text fields sit in the fields'
// box (`Ink.field`, a thin line), the menus are the column check's `MenuChip`, the date picker and the segmented control
// are Apple's own. The logic is `ReceiptCheckModel` and `PhoneBackend`'s receipt work.

/// "Does this look right?": what was read, the fields to check first, Save. Also the window that edits a saved receipt.
struct ReceiptCheckView: View {
    @Bindable var model: ReceiptCheckModel
    let palette: Palette
    let save: () async -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The text field being typed in: a tap anywhere on a field's box puts the cursor there. Shop's Return goes on to
    /// Total; the number pads (Total, Amount in euros) have Done above them (brief 40).
    @FocusState private var typing: TextBox?
    private enum TextBox: String, Hashable { case shop, total, euros }
    /// Where Done above the number pad is, so Save stays clear of it.
    @State private var doneTop: CGFloat?
    #if DEBUG
    /// Screenshots: `-openReceiptText` opens "As on the receipt".
    @State private var rowsOpen = LaunchArguments.current.contains("-openReceiptText")
    #else
    @State private var rowsOpen = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    intro
                    if model.editing != nil {
                        section(String(localized: "The receipt"), fields: ReceiptCheckModel.Field.allCases, notes: false)
                    } else if model.nothingRead {
                        section(String(localized: "The receipt"), fields: ReceiptCheckModel.Field.allCases, notes: false)
                    } else {
                        if !model.fieldsToCheck.isEmpty {
                            section(String(localized: "Please check"), fields: model.fieldsToCheck, notes: true)
                        }
                        if !model.fieldsRead.isEmpty {
                            section(String(localized: "Read from the receipt"), fields: model.fieldsRead, notes: true)
                        }
                    }
                    // Its own card, without a heading (its row says Category).
                    VStack(spacing: 0) { categoryRow }.glassCard().padding(.top, 22)
                    if !model.reading.rows.isEmpty {
                        ReceiptTextDisclosure(rows: model.reading.rows, isExpanded: $rowsOpen).padding(.top, 20)
                    }
                    if typeSize.isAccessibilitySize { question.padding(.horizontal, -18).padding(.top, 24) }
                }
                .padding(.horizontal, 18).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            if !typeSize.isAccessibilitySize {
                question.overlay(alignment: .top) { Rectangle().fill(Ink.line).frame(height: 1) }
                    .clearOfKeyboardDone(doneTop)
            }
        }
        .numberPadDone(typing == .total || typing == .euros, top: $doneTop) { typing = nil }
        #if DEBUG
        .task {
            // Screenshots: `-typeIn shop|total|euros` puts the cursor in that field once the window shows.
            // Several, comma-separated, move on every 2 s (as Return does).
            let fields = (LaunchArguments.value("-typeIn") ?? "").split(separator: ",").compactMap { TextBox(rawValue: String($0)) }
            for (index, field) in fields.enumerated() {
                try? await Task.sleep(for: .seconds(index == 0 ? 1 : 2))
                typing = field
            }
        }
        #endif
    }

    /// What the window shows, and the quiet line that says every value can be changed.
    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if model.editing != nil { Text("This is the receipt as you saved it.") }
                else if model.nothingRead { Text("Aresium couldn't read this receipt. Type what it says:") }
                else { Text("This is what Aresium read from the receipt:") }
            }
            .font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(3)
            if !model.nothingRead || model.editing != nil {
                Text("Something wrong? Tap it and change it.")
                    .font(AppFont.text(13)).foregroundStyle(Ink.muted).lineSpacing(2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4).padding(.top, 16)
    }

    // MARK: the fields

    private func section(_ title: String, fields: [ReceiptCheckModel.Field], notes: Bool) -> some View {
        SettingsSection(title) {
            ForEach(Array(fields.enumerated()), id: \.element) { index, field in
                if index > 0 { SettingsDivider() }
                VStack(alignment: .leading, spacing: 0) {
                    row(field)
                    if notes, let note = model.note(field) {
                        Label {
                            Text(verbatim: note)
                        } icon: {
                            Image(systemName: Self.symbol(model.mark(field)))
                        }
                        .font(AppFont.text(12.5)).foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16).padding(.bottom, 12).padding(.top, -4)
                    }
                    if field == .total { euroRow }
                }
            }
        }
        .padding(.top, 22)
    }

    private static func symbol(_ mark: ReceiptCheckModel.Mark) -> String {
        switch mark {
        case .missing: "exclamationmark.circle"
        case .corrected: "checkmark.circle"
        case .sure, .unsure: "questionmark.circle"
        }
    }

    @ViewBuilder private func row(_ field: ReceiptCheckModel.Field) -> some View {
        switch field {
        case .shop:
            FieldRow(label: String(localized: "Shop")) {
                TextField("", text: $model.shop, prompt: Text("Name on the receipt").foregroundStyle(Ink.muted))
                    .textInputAutocapitalization(.words).autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { typing = .total }
                    .accessibilityLabel(Text("Shop"))
                    .focused($typing, equals: .shop)
                    .fieldBox { typing = .shop }
            }
        case .date:
            FieldRow(label: String(localized: "Date")) {
                DatePicker(String(localized: "Date"), selection: $model.date, in: ...Date.now, displayedComponents: .date)
                    .labelsHidden().environment(\.locale, AppLanguage.current.locale)
            }
        case .total:
            FieldRow(label: String(localized: "Total")) {
                HStack(spacing: 8) {
                    TextField("", text: $model.totalText,
                              prompt: Text(verbatim: ReceiptAmount.field(0)).foregroundStyle(Ink.muted))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .font(AppFont.number(15))
                        .accessibilityLabel(Text("Total"))
                        .focused($typing, equals: .total)
                        .fieldBox { typing = .total }
                        .frame(maxWidth: 150)
                    currencyMenu
                }
            }
        case .method:
            FieldRow(label: String(localized: "Paid by")) {
                Picker(String(localized: "Paid by"), selection: $model.method) {
                    Text("Card").tag(ReceiptMethod?.some(.card))
                    Text("Cash").tag(ReceiptMethod?.some(.cash))
                }
                .pickerStyle(.segmented).frame(maxWidth: 190)
            }
        }
    }

    /// The total's currency, beside it: any receipt's can be changed (an undecided "kr" must be chosen).
    private var currencyMenu: some View {
        Menu {
            Picker(selection: $model.currency) {
                if model.currency == nil { Text("Choose").tag(String?.none) }
                ForEach(currencies, id: \.self) { code in Text(verbatim: code).tag(String?.some(code)) }
            } label: { EmptyView() }
        } label: {
            MenuChip(text: model.currency ?? String(localized: "Choose"), quiet: model.currency == nil, mono: true)
        }
        .accessibilityLabel(Text("Currency"))
        .accessibilityValue(Text(verbatim: model.currency ?? ""))
    }

    /// Under the total: what it cost in euros, for another currency paid in cash.
    @ViewBuilder private var euroRow: some View {
        if model.needsEuros {
            SettingsDivider()
            FieldRow(label: String(localized: "Amount in euros")) {
                HStack(spacing: 8) {
                    TextField("", text: $model.euroText,
                              prompt: Text(verbatim: ReceiptAmount.field(0)).foregroundStyle(Ink.muted))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).font(AppFont.number(15))
                        .accessibilityLabel(Text("Amount in euros"))
                        .focused($typing, equals: .euros)
                        .fieldBox { typing = .euros }
                        .frame(maxWidth: 150)
                    Text(verbatim: ReceiptAmount.euro).font(AppFont.number(13, weight: .medium)).foregroundStyle(Ink.muted)
                }
            }
        }
    }

    /// The read currency first if it is not on the list.
    private var currencies: [String] {
        let read = model.reading.currency.map { [$0.uppercased()] } ?? []
        return read.filter { !ReceiptCheckModel.currencies.contains($0) } + ReceiptCheckModel.currencies
    }

    private var categoryRow: some View {
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

    // MARK: the question

    private var question: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let problem = model.problem { FormProblem(text: problem) }
            else if let missing = model.missing {
                Label { Text(verbatim: missing) } icon: { Image(systemName: "exclamationmark.circle") }
                    .font(AppFont.text(13)).foregroundStyle(Ink.secondary).padding(.horizontal, 4)
            } else if let again = model.matchesAgainNote {
                Label { Text(verbatim: again) } icon: { Image(systemName: "arrow.triangle.2.circlepath") }
                    .font(AppFont.text(13)).foregroundStyle(Ink.secondary).padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Does this look right?").font(AppFont.text(17, weight: .semibold)).foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
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

extension View {
    /// A text field's box in a form row (the column check's chips and the bank name's field: the field fill and a thin
    /// line), so it reads as something to type in; `focus` puts the cursor in the field when the box around it is tapped.
    func fieldBox(focus: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return padding(.horizontal, 10).padding(.vertical, 6).frame(minHeight: 36)
            .background(Ink.field, in: shape)
            .overlay(shape.strokeBorder(Ink.line))
            .contentShape(shape)
            .onTapGesture(perform: focus)
    }
}

/// A form row: the label on the left in the Settings rows' ink, the control on the right.
struct FieldRow<Control: View>: View {
    let label: String
    @ViewBuilder let control: () -> Control
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                                                  : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Text(verbatim: label).font(AppFont.text(14.5, weight: .medium)).foregroundStyle(Ink.primary)
                .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
            control().frame(maxWidth: .infinity, alignment: typeSize.isAccessibilitySize ? .leading : .trailing)
        }
        .font(AppFont.text(14.5)).foregroundStyle(Ink.primary).tint(Ink.primary)
        .padding(.horizontal, 16).frame(minHeight: 50).padding(.vertical, 3)
    }
}

/// "As on the receipt": the read lines, folded, in the numbers' font (what is kept instead of a photo).
struct ReceiptTextDisclosure: View {
    let rows: [String]
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Text(verbatim: row).font(AppFont.number(12, weight: .regular)).foregroundStyle(Ink.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .textSelection(.enabled).padding(.top, 12)
        } label: {
            Text("As on the receipt").font(AppFont.text(13.5, weight: .semibold)).foregroundStyle(Ink.primary)
        }
        .tint(Ink.secondary)
        .padding(.horizontal, 4)
    }
}

// MARK: - the question

/// "Is this the same payment?": the receipt on top, the bank payments it may belong to as the dashboard's rows with
/// what differs, and "None of these" (it declines them and waits for the bank statement). Later, in the top-left
/// corner (brief 40), puts the question off as a swipe down does: the receipt waits and nothing is declined. While an
/// answer is kept, the tapped row or button shows the spinner and the others are greyed.
struct ReceiptQuestionView: View {
    let question: ReceiptQuestion
    let palette: Palette
    var problem: String?
    let answer: (String?) async -> Void
    /// Later: closes the question without an answer (what a swipe down does where the question is shown).
    let later: () -> Void
    /// The answer being kept: a payment's id, or `.some(nil)` for None of these.
    @State private var answering: String??

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Is this the same payment?").font(AppFont.text(20, weight: .bold)).foregroundStyle(Ink.primary)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4).padding(.top, 16)
                    .accessibilityAddTraits(.isHeader)
                Text("Your bank statement has payments that may be this receipt. Tap the one it belongs to, so it counts once.")
                    .font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4).padding(.top, 8)
                SettingsSection(String(localized: "Receipt")) {
                    ReceiptSummaryRow(receipt: question.receipt, palette: palette)
                }
                .padding(.top, 22)
                SettingsSection(String(localized: "Bank payments")) {
                    ForEach(Array(question.options.enumerated()), id: \.element.id) { index, option in
                        if index > 0 { TileRowDivider() }
                        let tapped = answering == .some(option.payment.id)
                        Button {
                            Task { await choose(option.payment.id) }
                        } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                FileCheckPaymentRow(payment: PreviewPayment(option.payment), palette: palette, busy: tapped)
                                if let difference = ReceiptWording.difference(option.candidate, sameAmount: sameAmount) {
                                    Text(verbatim: difference).font(AppFont.text(12.5)).foregroundStyle(Ink.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.leading, 64).padding(.trailing, 14).padding(.bottom, 10).padding(.top, -4)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .whileWorking(answering != nil, tapped: tapped)
                    }
                }
                .padding(.top, 22)
                if let problem { FormProblem(text: problem).padding(.top, 12) }
                Button {
                    Task { await choose(nil) }
                } label: {
                    BusyLabel(text: Text("None of these"), busy: answering == .some(nil), tint: Ink.primary)
                }
                .buttonStyle(QuietButtonStyle())
                .whileWorking(answering != nil, tapped: answering == .some(nil))
                .padding(.top, 18)
                FormNote(text: String(localized: "Then the receipt waits for the bank statement and counts on its own until then."))
                    .padding(.top, 10)
            }
            .padding(.horizontal, 18).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Later", action: later).disabled(answering != nil)
            }
        }
        #if DEBUG
        .task {
            // Screenshots: `-tapLater` taps Later on the first question shown (the next queued one then shows);
            // `-tapAnswer first|none` answers once the question shows (with `-holdWork` the spinner stays).
            if LaunchArguments.current.contains("-tapLater"), !Self.tappedLater {
                Self.tappedLater = true
                try? await Task.sleep(for: .seconds(2))
                later()
            }
            guard let tap = LaunchArguments.value("-tapAnswer") else { return }
            try? await Task.sleep(for: .seconds(1))
            await choose(tap == "none" ? nil : question.options.first?.payment.id)
        }
        #endif
    }

    #if DEBUG
    private static var tappedLater = false
    #endif

    /// How many of the payments have the receipt's exact amount.
    private var sameAmount: Int { question.options.filter { $0.candidate?.why == .severalSame }.count }

    private func choose(_ paymentID: String?) async {
        guard answering == nil else { return }
        answering = .some(paymentID)
        #if DEBUG
        await DebugLaunch.holdWork()
        #endif
        await answer(paymentID)
        answering = nil
    }
}

/// A receipt as a payment row: the day in its tile, the shop, its date and Card or Cash, the amount in its currency.
struct ReceiptSummaryRow: View {
    let receipt: LedgerReceipt
    let palette: Palette
    var showsState = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let large = typeSize.isAccessibilitySize
        HStack(alignment: large ? .top : .center, spacing: 12) {
            DayTile(palette: palette) { Text(verbatim: DayWording.alone(date: receipt.date)) }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: ReceiptPageWording.title(receipt)).font(AppFont.text(14.5, weight: .semibold))
                    .foregroundStyle(Ink.primary).lineLimit(large ? 3 : 1)
                // Where it stands may take a second line ("Wartet auf den Kontoauszug").
                Text(verbatim: ReceiptPageWording.line(receipt, withState: showsState))
                    .font(AppFont.text(12.5)).foregroundStyle(Ink.muted).lineLimit(large ? 4 : showsState ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                if large { amount.padding(.top, 2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !large { amount }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var amount: some View {
        Text(verbatim: ReceiptPageWording.amount(receipt)).font(AppFont.number(14))
            .foregroundStyle(receipt.direction == .in ? palette.income : palette.expenseText).fixedSize()
    }
}

/// After a bank import: "Is this the same payment?" for a waiting card receipt, in a sheet of its own. Later or a swipe
/// down closes it without an answer: the receipt waits (asked again only after the next import), and the next queued
/// question, if any, opens after it (ContentView).
struct ReceiptQuestionSheet: View {
    let question: ReceiptQuestion
    let phone: PhoneBackend
    let palette: Palette
    /// After an answer: the dashboard is built again.
    let changed: () async -> Void
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ReceiptQuestionView(question: question, palette: palette, problem: problem, answer: { paymentID in
                do {
                    try await phone.answer(question, with: paymentID)
                    await changed()
                } catch {
                    problem = error.localizedDescription
                }
            }, later: { dismiss() })
            .background { Ink.background.ignoresSafeArea() }
            .navigationTitle(Text("Receipt")).navigationBarTitleDisplayMode(.inline)
        }
        .tint(Ink.primary)
        .presentationBackground(Ink.background)
    }
}
