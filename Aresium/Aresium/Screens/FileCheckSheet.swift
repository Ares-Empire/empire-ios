import SwiftUI

// An unknown bank's file (brief 23): "Does this look right?". Built from Aresium's own pieces: the file as a payment row
// starts (a day tile), the first payments as the dashboard's payment list draws them (`DayTile`, the place, a muted
// line, the amount in the money style and the expense/income ink), the Settings pieces (`SettingsSection`, glass card,
// `FormButtonStyle`). No column names here; those wait in the column check (FileCheckColumns.swift), the last resort.
// The flow is `FileCheckModel`.

/// The window for a file Aresium does not know: the engine's readings one after the other, then the column check.
/// Back (beside No, after a No) shows the reading before. Cancel at every step leaves the file out; it cannot be swiped
/// away by accident.
struct FileCheckSheet: View {
    @State var model: FileCheckModel
    let palette: Palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// At the accessibility text sizes the question follows the payments in the scroll, so the payments come first.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            Group {
                if model.step == .columns, let columns = model.columns {
                    ColumnCheckPage(model: columns, palette: palette,
                                    back: model.canGoBack ? { step { model.back() } } : nil) { dismiss() }
                        .transition(.opacity)
                } else {
                    readingPage
                }
            }
            .background { Ink.background.ignoresSafeArea() }
            .navigationTitle(Text("Check the file"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.cancel()
                        dismiss()
                    }
                    .disabled(model.isSaving || model.columns?.isSaving == true)
                }
            }
        }
        .tint(Ink.primary)
        .presentationBackground(Ink.background)
        .interactiveDismissDisabled()
        #if DEBUG
        .task {
            // Screenshots: `-sampleReading 2` shows the second reading, `-sampleReading columns` the column check.
            guard let wanted = LaunchArguments.value("-sampleReading") else { return }
            let target = Int(wanted)
            while model.step != .columns, model.number.map({ $0 != target }) ?? false { model.no() }
        }
        #endif
    }

    // MARK: a reading

    private var readingPage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FileCheckFileRow(name: model.request.file.name, palette: palette)
                        .padding(.top, 16)
                    Text("Aresium doesn't know this bank yet. This is how your payments would look:")
                        .font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14).padding(.horizontal, 4)
                    payments
                        .id(model.number)
                        .transition(.opacity)
                    if typeSize.isAccessibilitySize {
                        question.padding(.horizontal, -18).padding(.top, 24)
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            if !typeSize.isAccessibilitySize {
                question.overlay(alignment: .top) { Rectangle().fill(Ink.line).frame(height: 1) }
            }
        }
    }

    /// The reading's first payments, and under them what changed from the one before.
    private var payments: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(heading) {
                ForEach(Array(model.payments.enumerated()), id: \.offset) { index, payment in
                    if index > 0 { TileRowDivider() }
                    FileCheckPaymentRow(payment: PreviewPayment(payment), palette: palette)
                }
            }
            if let change = model.change {
                Label {
                    Text(verbatim: change)
                } icon: {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Ink.muted)
                }
                .font(AppFont.text(13)).foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12).padding(.horizontal, 4)
            }
        }
    }

    /// "Suggestion 2 of 3" while there are several readings; "First payments" with one.
    private var heading: String {
        let count = model.readings.count
        guard count > 1, let number = model.number else { return String(localized: "First payments") }
        return String(localized: "Suggestion \(number) of \(count)")
    }

    /// The question and its answers, kept at the bottom: No (with Back before it after a No) and Yes side by side when
    /// they fit, Yes keeping its half; else Yes over the others.
    private var question: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let problem = model.saveProblem { FormProblem(text: problem) }
            Text("Does this look right?").font(AppFont.text(17, weight: .semibold)).foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                EqualWidthRow {
                    backAndNo
                    yesButton
                }
                VStack(spacing: 10) {
                    yesButton
                    backAndNo
                }
                VStack(spacing: 10) {
                    yesButton
                    noButton
                    if model.canGoBack { backButton }
                }
            }
        }
        .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 10)
    }

    /// No, with Back before it once there is a reading to go back to (the two share No's place).
    @ViewBuilder private var backAndNo: some View {
        if model.canGoBack {
            HStack(spacing: 10) {
                backButton
                noButton
            }
        } else {
            noButton
        }
    }

    /// A step to another reading, faded as No's.
    private func step(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { change() }
    }

    private var yesButton: some View {
        Button {
            Task { if await model.yes() { dismiss() } }
        } label: {
            BusyLabel(text: Text("Yes, import"), busy: model.isSaving)
        }
        .buttonStyle(FormButtonStyle(accent: nil, busy: model.isSaving))
        .allowsHitTesting(!model.isSaving)
    }

    private var noButton: some View {
        Button {
            step { model.no() }
        } label: {
            Text("No")
        }
        .buttonStyle(QuietButtonStyle())
        .disabled(model.isSaving)
    }

    private var backButton: some View {
        Button {
            step { model.back() }
        } label: {
            Text("Back")
        }
        .buttonStyle(QuietButtonStyle())
        .disabled(model.isSaving)
    }
}

// MARK: - pieces (the column check uses them too)

/// The file, as a payment row starts: a document in a day tile and its name.
struct FileCheckFileRow: View {
    let name: String
    let palette: Palette

    var body: some View {
        HStack(spacing: 12) {
            DayTile(palette: palette) { Image(systemName: "doc.text").font(.system(size: 16, weight: .medium)) }
                .accessibilityHidden(true)
            Text(verbatim: name).font(AppFont.text(14.5, weight: .semibold)).foregroundStyle(Ink.primary)
                .lineLimit(2).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
    }
}

/// A payment as the dashboard's payment list draws it: the day in its tile, who (or the text), a muted line with the
/// whole date (so a day and month the wrong way round show at once) and the text, and the amount in the money style.
/// At the accessibility text sizes the words wrap and the amount goes under them, so the payment can still be read.
/// `busy`: the row was tapped and its work runs (the receipt question, Join with a payment): a small spinner stands in
/// the amount's place until it ends.
struct FileCheckPaymentRow: View {
    let payment: PreviewPayment
    let palette: Palette
    var busy = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let large = typeSize.isAccessibilitySize
        HStack(alignment: large ? .top : .center, spacing: 12) {
            DayTile(palette: palette) { Text(verbatim: payment.day.map { DayWording.alone($0) } ?? "–") }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: payment.title).font(AppFont.text(14.5, weight: .semibold)).foregroundStyle(Ink.primary)
                    .lineLimit(large ? 3 : 1)
                Text(verbatim: ([payment.date] + [payment.detail].compactMap { $0 }).joined(separator: " · "))
                    .font(AppFont.text(12.5)).foregroundStyle(Ink.muted).lineLimit(large ? 4 : 1)
                if large { amount.padding(.top, 2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !large { amount }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var amount: some View {
        Text(verbatim: Money.transaction(payment.amount)).font(AppFont.number(14))
            .foregroundStyle(payment.amount < 0 ? palette.expenseText : palette.income).fixedSize()
            .opacity(busy ? 0 : 1)
            .overlay(alignment: .trailing) {
                if busy { ProgressView().tint(Ink.secondary) }
            }
    }
}

/// The second answer beside a main button: the same size, the header buttons' quiet look (a field fill and a thin line).
struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        configuration.label
            .font(AppFont.text(15, weight: .semibold))
            .lineLimit(1).minimumScaleFactor(0.85)
            .foregroundStyle(isEnabled ? Ink.primary : Ink.muted)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Ink.field, in: shape)
            .overlay(shape.strokeBorder(Ink.line))
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
