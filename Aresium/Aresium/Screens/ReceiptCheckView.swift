import SwiftUI

// A receipt's check window and its question (brief 31), in the file check window's look and wording style
// (FileCheckSheet: `Ink`, the Settings cards, the dashboard's payment rows, "Does this look right?" at the bottom with
// the main button). Apple's own controls for the values: a text field, the date picker, the segmented Card / Cash, the
// menu of categories. The logic is `ReceiptCheckModel` and `PhoneBackend`'s receipt work.

/// "Does this look right?": what was read, the fields to check first, Save.
struct ReceiptCheckView: View {
    @Bindable var model: ReceiptCheckModel
    let palette: Palette
    let save: () async -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
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
                    Text(model.nothingRead ? "Aresium couldn't read this receipt. Type what it says:"
                                           : "This is what Aresium read from the receipt:")
                        .font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4).padding(.top, 16)
                    if model.nothingRead {
                        section(String(localized: "The receipt"), fields: ReceiptCheckModel.Field.allCases, notes: false)
                    } else {
                        if !model.fieldsToCheck.isEmpty {
                            section(String(localized: "Please check"), fields: model.fieldsToCheck, notes: true)
                        }
                        if !model.fieldsRead.isEmpty {
                            section(String(localized: "Read from the receipt"), fields: model.fieldsRead, notes: false)
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
            }
        }
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
                            Image(systemName: model.mark(field) == .missing ? "exclamationmark.circle" : "questionmark.circle")
                        }
                        .font(AppFont.text(12.5)).foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16).padding(.bottom, 12).padding(.top, -4)
                    }
                    if field == .total { moneyRows }
                }
            }
        }
        .padding(.top, 22)
    }

    @ViewBuilder private func row(_ field: ReceiptCheckModel.Field) -> some View {
        switch field {
        case .shop:
            FieldRow(label: String(localized: "Shop")) {
                TextField(String(localized: "Name on the receipt"), text: $model.shop)
                    .textInputAutocapitalization(.words).autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
        case .date:
            FieldRow(label: String(localized: "Date")) {
                DatePicker(String(localized: "Date"), selection: $model.date, in: ...Date.now, displayedComponents: .date)
                    .labelsHidden().environment(\.locale, AppLanguage.current.locale)
            }
        case .total:
            FieldRow(label: String(localized: "Total")) {
                HStack(spacing: 6) {
                    TextField(ReceiptAmount.field(0), text: $model.totalText)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .font(AppFont.number(15))
                    Text(verbatim: model.currency ?? "").font(AppFont.text(13, weight: .semibold))
                        .foregroundStyle(Ink.muted)
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

    /// Under the total: the currency when it is not euros, and what it cost in euros when paid in cash.
    @ViewBuilder private var moneyRows: some View {
        if model.showsCurrency {
            SettingsDivider()
            FieldRow(label: String(localized: "Currency")) {
                Picker(String(localized: "Currency"), selection: $model.currency) {
                    if model.currency == nil { Text("Choose").tag(String?.none) }
                    ForEach(currencies, id: \.self) { code in Text(verbatim: code).tag(String?.some(code)) }
                }
                .pickerStyle(.menu)
            }
        }
        if model.needsEuros {
            SettingsDivider()
            FieldRow(label: String(localized: "Amount in euros")) {
                HStack(spacing: 6) {
                    TextField(ReceiptAmount.field(0), text: $model.euroText)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).font(AppFont.number(15))
                    Text(verbatim: ReceiptAmount.euro).font(AppFont.text(13, weight: .semibold)).foregroundStyle(Ink.muted)
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
            Picker(String(localized: "Category"), selection: $model.category) {
                ForEach(model.choices) { choice in Text(verbatim: choice.name).tag(choice.id) }
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: the question

    private var question: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let problem = model.problem { FormProblem(text: problem) }
            else if let missing = model.missing {
                Label { Text(verbatim: missing) } icon: { Image(systemName: "exclamationmark.circle") }
                    .font(AppFont.text(13)).foregroundStyle(Ink.secondary).padding(.horizontal, 4)
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
/// what differs, and "None of these" (it waits for the bank statement).
struct ReceiptQuestionView: View {
    let question: ReceiptQuestion
    let palette: Palette
    var problem: String?
    let answer: (String?) async -> Void
    @State private var answering = false

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
                        Button {
                            Task { await choose(option.payment.id) }
                        } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                FileCheckPaymentRow(payment: PreviewPayment(option.payment), palette: palette)
                                if let difference = ReceiptWording.difference(option.candidate, sameAmount: sameAmount) {
                                    Text(verbatim: difference).font(AppFont.text(12.5)).foregroundStyle(Ink.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.leading, 64).padding(.trailing, 14).padding(.bottom, 10).padding(.top, -4)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(answering)
                    }
                }
                .padding(.top, 22)
                if let problem { FormProblem(text: problem).padding(.top, 12) }
                Button {
                    Task { await choose(nil) }
                } label: {
                    Text("None of these")
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(answering)
                .padding(.top, 18)
                FormNote(text: String(localized: "Then the receipt waits for the bank statement and counts on its own until then."))
                    .padding(.top, 10)
            }
            .padding(.horizontal, 18).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    /// How many of the payments have the receipt's exact amount.
    private var sameAmount: Int { question.options.filter { $0.candidate?.why == .severalSame }.count }

    private func choose(_ paymentID: String?) async {
        guard !answering else { return }
        answering = true
        await answer(paymentID)
        answering = false
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
            DayTile(palette: palette) { Text(verbatim: ReceiptPageWording.dayNumber(receipt.date)) }
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
            .foregroundStyle(palette.expenseText).fixedSize()
    }
}

/// After a bank import: "Is this the same payment?" for a waiting card receipt, in a sheet of its own. Closing it
/// without an answer lets the receipt wait (asked again only after the next import).
struct ReceiptQuestionSheet: View {
    let question: ReceiptQuestion
    let phone: PhoneBackend
    let palette: Palette
    /// After an answer: the dashboard is built again.
    let changed: () async -> Void
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            ReceiptQuestionView(question: question, palette: palette, problem: problem) { paymentID in
                do {
                    try await phone.answer(question, with: paymentID)
                    await changed()
                } catch {
                    problem = error.localizedDescription
                }
            }
            .background { Ink.background.ignoresSafeArea() }
            .navigationTitle(Text("Receipt")).navigationBarTitleDisplayMode(.inline)
        }
        .tint(Ink.primary)
        .presentationBackground(Ink.background)
    }
}
