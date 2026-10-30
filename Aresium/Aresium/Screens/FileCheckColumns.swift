import SwiftUI

// The column check (brief 23): the last resort when none of the engine's readings of an unknown file looked right. Plain
// questions ("Which column is the date?") instead of a meaning for every column; each answer is a menu of the file's
// columns by name and first value, the chosen column's first values under the question. Then how dates and amounts are
// written, the first payments read that way (as the window shows them), and Import; Back beside it returns to the last
// reading when there were readings. Logic: `ColumnCheckModel`.

struct ColumnCheckPage: View {
    @State var model: ColumnCheckModel
    let palette: Palette
    /// Back to the last reading (nil: the column check came at once, there is none).
    var back: (() -> Void)?
    /// After Import: the window closes.
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FileCheckFileRow(name: model.request.file.name, palette: palette)
                        .padding(.top, 16)
                    Text("Then show Aresium where things are in your file. The payments below follow your answers.")
                        .font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14).padding(.horizontal, 4)
                    SettingsSection(String(localized: "Where is what")) {
                        question(Text("Which column is the date?"), meaning: .date, optional: false)
                        SettingsDivider()
                        amountQuestion
                        if model.draft.amountInTwoColumns {
                            SettingsDivider()
                            question(Text("Which column is money out?"), meaning: .debit, optional: false)
                            SettingsDivider()
                            question(Text("Which column is money in?"), meaning: .credit, optional: false)
                        }
                        SettingsDivider()
                        question(Text("Which column is the name?"), meaning: .counterparty, optional: true)
                        SettingsDivider()
                        question(Text("Which column is the payment text?"), meaning: .text, optional: true)
                    }
                    SettingsSection(String(localized: "How it is written")) {
                        formatRow(Text("Dates"), example: LayoutDraft.example(of: model.draft.dateFormat)) {
                            Picker(selection: Binding(get: { model.draft.dateFormat }, set: { model.setDateFormat($0) })) {
                                ForEach(LayoutDraft.dateFormats, id: \.self) {
                                    Text(verbatim: LayoutDraft.example(of: $0)).tag($0)
                                }
                            } label: { EmptyView() }
                        }
                        SettingsDivider()
                        formatRow(Text("Amounts"), example: LayoutDraft.example(ofNumberFormat: model.draft.numberFormat)) {
                            Picker(selection: Binding(get: { model.draft.numberFormat }, set: { model.setNumberFormat($0) })) {
                                ForEach(LayoutDraft.numberFormats, id: \.self) {
                                    Text(verbatim: LayoutDraft.example(ofNumberFormat: $0)).tag($0)
                                }
                            } label: { EmptyView() }
                        }
                    }
                    SettingsSection(String(localized: "First payments")) {
                        if model.preview.isEmpty {
                            Text(model.draft.missing.isEmpty ? String(localized: "Nothing to show yet.")
                                                              : String(localized: "Answer the date and the amount first."))
                                .font(AppFont.text(13)).foregroundStyle(Ink.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(Array(model.preview.enumerated()), id: \.offset) { index, payment in
                            if index > 0 { TileRowDivider() }
                            FileCheckPaymentRow(payment: PreviewPayment(payment), palette: palette)
                        }
                    }
                    if let problem = model.previewProblem { FormProblem(text: problem).padding(.top, 12) }
                }
                .padding(.horizontal, 18).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            actions
        }
    }

    /// Import, with Back before it as No sits before Yes in the readings: side by side when they fit, else Import first.
    private var actions: some View {
        VStack(spacing: 10) {
            if let problem = model.saveProblem { FormProblem(text: problem) }
            if let back {
                ViewThatFits(in: .horizontal) {
                    EqualWidthRow {
                        backButton(back)
                        importButton
                    }
                    VStack(spacing: 10) {
                        importButton
                        backButton(back)
                    }
                }
            } else {
                importButton
            }
        }
        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 10)
        .overlay(alignment: .top) { Rectangle().fill(Ink.line).frame(height: 1) }
    }

    private var importButton: some View {
        Button { Task { if await model.confirm() { close() } } } label: {
            BusyLabel(text: Text("Import"), busy: model.isSaving)
        }
        .buttonStyle(FormButtonStyle(accent: nil, busy: model.isSaving))
        .disabled(model.draft.layout == nil)
        .allowsHitTesting(!model.isSaving)
    }

    private func backButton(_ back: @escaping () -> Void) -> some View {
        Button(action: back) { Text("Back") }
            .buttonStyle(QuietButtonStyle())
            .disabled(model.isSaving)
    }

    // MARK: questions

    /// One question: the menu of columns beside it when they fit (under it when not: long bank headers, the largest
    /// text sizes), and the chosen column's first values below, so the person sees what they picked.
    private func question(_ title: Text, meaning: ColumnMeaning, optional: Bool) -> some View {
        let chosen = model.chosen(meaning)
        let menu = Menu {
            Picker(selection: Binding(get: { chosen?.index }, set: { model.choose(meaning, column: $0) })) {
                ForEach(model.choices) { Text(verbatim: $0.label).tag(Optional($0.index)) }
                if optional { Text("None").tag(Int?.none) }
            } label: { EmptyView() }
        } label: {
            MenuChip(text: chosen?.name ?? (optional ? String(localized: "None") : String(localized: "Pick one")),
                     quiet: chosen == nil)
        }
        .accessibilityLabel(title)
        return questionRow(title, menu: menu, samples: chosen?.samples)
    }

    /// The amount: one column, or money out and money in from two (then asked one by one).
    private var amountQuestion: some View {
        let chosen = model.chosen(.amount)
        let two = model.draft.amountInTwoColumns
        let menu = Menu {
            Picker(selection: Binding<Int?>(get: { two ? -1 : chosen?.index }, set: { choice in
                if choice == -1 { model.useTwoAmountColumns() } else { model.choose(.amount, column: choice) }
            })) {
                ForEach(model.choices) { Text(verbatim: $0.label).tag(Optional($0.index)) }
                Text("Two columns: money out and money in").tag(Optional(-1))
            } label: { EmptyView() }
        } label: {
            MenuChip(text: two ? String(localized: "Two columns") : chosen?.name ?? String(localized: "Pick one"),
                     quiet: !two && chosen == nil)
        }
        .accessibilityLabel(Text("Which column is the amount?"))
        return questionRow(Text("Which column is the amount?"), menu: menu, samples: two ? nil : chosen?.samples)
    }

    /// The question's words are the menu's label for VoiceOver, so they are read once, with the answer.
    private func questionRow(_ title: Text, menu: some View, samples: String?) -> some View {
        let styled = title.font(AppFont.text(14.5, weight: .semibold)).foregroundStyle(Ink.primary)
            .accessibilityHidden(true)
        return VStack(alignment: .leading, spacing: 5) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    styled.lineLimit(1)
                    Spacer(minLength: 8)
                    menu
                }
                VStack(alignment: .leading, spacing: 8) {
                    styled.fixedSize(horizontal: false, vertical: true)
                    menu
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let samples, !samples.isEmpty {
                Text(verbatim: samples).font(AppFont.number(11.5, weight: .regular))
                    .foregroundStyle(Ink.muted).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    /// How dates or amounts are written: the examples as a menu, beside the title when they fit, under it when not.
    private func formatRow<Choices: View>(_ title: Text, example: String,
                                          @ViewBuilder choices: () -> Choices) -> some View {
        let styled = title.font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary).accessibilityHidden(true)
        let menu = Menu { choices() } label: { MenuChip(text: example, mono: true) }.accessibilityLabel(title)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                styled.lineLimit(1)
                Spacer(minLength: 8)
                menu
            }
            VStack(alignment: .leading, spacing: 8) {
                styled.fixedSize(horizontal: false, vertical: true)
                menu
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 11).frame(minHeight: 54)
    }
}

/// A menu's current choice: a quiet outlined chip (the website's `.md-edit`), muted while nothing is chosen. Its natural
/// width when there is room; narrower (on two lines at most) at the largest text sizes, never wider than the screen.
struct MenuChip: View {
    let text: String
    var quiet = false
    var mono = false

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: text)
                .font(mono ? AppFont.number(13, weight: .medium) : AppFont.text(13.5, weight: .semibold))
                .foregroundStyle(quiet ? Ink.muted : Ink.primary).lineLimit(2)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Ink.muted)
        }
        .padding(.horizontal, 11).padding(.vertical, 5).frame(minHeight: 32)
        .background(Ink.field, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Ink.line))
        .fixedSize(horizontal: false, vertical: true)
    }
}
