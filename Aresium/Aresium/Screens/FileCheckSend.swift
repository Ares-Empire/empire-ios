import SwiftUI

// Sending an unknown bank's format (brief 23): one quiet card inside the import's result, two taps (type the bank's
// name, Send). Built from the result's own look (the toast's palette ink, its line between parts) and the form pieces
// (`FormButtonStyle`, the field look of the login's fields). "What is sent?" is a Settings-style page of exactly what
// goes out (`SharedFormat`). Logic: `BankFormatCard`, `BankFormatOutbox`.

/// The card: "Help Aresium learn your bank", the bank's name and Send, "What is sent?" and Not now; then one line with
/// how it went.
struct BankFormatCardView: View {
    @Bindable var card: BankFormatCard
    let palette: Palette
    /// Not now: the result closes, and this layout is never offered again.
    let notNow: () -> Void
    @State private var showsDetails = false
    @FocusState private var typing: Bool

    var body: some View {
        Group {
            switch card.shown {
            case .asking, .sending:
                form
            case .sent:
                outcome("checkmark.circle", tint: palette.income,
                        Text("Thank you. Aresium learns your bank with the next update."))
            case .kept:
                outcome("clock", tint: palette.secondary,
                        Text("Not sent yet. Aresium sends it by itself as soon as it can."))
            case let .refused(message):
                outcome("exclamationmark.circle", tint: palette.expenseText, Text(verbatim: message))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: card.shown)
        .sheet(isPresented: $showsDetails) { SharedFormatSheet(shared: card.shared) }
        #if DEBUG
        .task {
            // Screenshots: `-openFormatDetails` opens "What is sent?", `-formatFocus` the keyboard on the name.
            if LaunchArguments.current.contains("-openFormatDetails") { showsDetails = true }
            if LaunchArguments.current.contains("-formatFocus") { typing = true }
        }
        #endif
    }

    private var form: some View {
        let sending = card.shown == .sending
        return VStack(alignment: .leading, spacing: 0) {
            Text("Help Aresium learn your bank").font(AppFont.text(14.5, weight: .semibold))
                .foregroundStyle(palette.ink).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Only how its file is laid out goes to us, never a payment.").font(AppFont.text(12.5))
                .foregroundStyle(palette.secondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    field
                    sendButton.fixedSize(horizontal: true, vertical: false)
                }
                VStack(spacing: 8) {
                    field
                    sendButton
                }
            }
            .padding(.top, 12)
            .disabled(sending)
            if let problem = card.problem {
                FormProblem(text: problem).padding(.top, 8)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    detailsLink
                    Spacer(minLength: 0)
                    notNowButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    detailsLink
                    notNowButton
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
    }

    private var detailsLink: some View {
        Button("What is sent?") { typing = false; showsDetails = true }
            .font(AppFont.text(13, weight: .semibold)).foregroundStyle(palette.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var notNowButton: some View {
        Button("Not now", action: notNow).font(AppFont.text(13, weight: .bold)).foregroundStyle(palette.ink)
            .fixedSize(horizontal: false, vertical: true)
            .disabled(card.shown == .sending)
    }

    /// The bank's name, in the look of the login's fields: the keyboard's Send sends.
    private var field: some View {
        TextField("", text: $card.bank, prompt: Text("Name of the bank").foregroundStyle(Ink.muted))
            .font(AppFont.text(15)).foregroundStyle(palette.ink)
            .textContentType(.organizationName).textInputAutocapitalization(.words).autocorrectionDisabled()
            .submitLabel(.send).onSubmit(send)
            .focused($typing)
            .padding(.horizontal, 14).frame(minHeight: 50)
            .background(Ink.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.line))
            .accessibilityLabel(Text("Name of the bank"))
    }

    private var sendButton: some View {
        Button(action: send) {
            BusyLabel(text: Text("Send"), busy: card.shown == .sending)
        }
        .buttonStyle(FormButtonStyle(accent: nil, busy: card.shown == .sending))
        .disabled(!card.canSend && card.shown != .sending)
        .allowsHitTesting(card.shown != .sending)
    }

    private func send() {
        guard card.canSend else { return }
        typing = false
        Task { await card.send() }
    }

    private func outcome(_ symbol: String, tint: Color, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: symbol).foregroundStyle(tint).accessibilityHidden(true)
            text.font(AppFont.text(13)).foregroundStyle(palette.ink).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }
}

/// "What is sent?": the format exactly as Send sends it, in plain words: the bank's name, every column of the file with
/// what it holds, how dates and amounts are written (and any other setting), the app's version and language.
struct SharedFormatSheet: View {
    let shared: SharedFormat
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FormNote(text: String(localized: "Only how your bank's file is laid out: its column names, what each one holds and how dates and amounts are written. Never a payment, an amount, an IBAN or a name."))
                        .padding(.top, 16)
                    SettingsSection(String(localized: "Bank")) {
                        line(Text("Name"), value: shared.bank.isEmpty ? Text("Not typed yet") : Text(verbatim: shared.bank),
                             quiet: shared.bank.isEmpty)
                    }
                    SettingsSection(String(localized: "Columns")) {
                        ForEach(Array(shared.columns.enumerated()), id: \.offset) { index, column in
                            if index > 0 { SettingsDivider() }
                            line(Text(verbatim: column.name),
                                 value: column.meaning.map { Text(verbatim: $0) } ?? Text("Not used"),
                                 quiet: column.meaning == nil)
                        }
                    }
                    SettingsSection(String(localized: "How it is written (example)")) {
                        ForEach(Array(shared.lines.enumerated()), id: \.offset) { index, item in
                            if index > 0 { SettingsDivider() }
                            line(Text(verbatim: item.title), value: Text(verbatim: item.value), quiet: false)
                        }
                    }
                    SettingsSection(String(localized: "Sent with it")) {
                        line(Text("App version"), value: Text(verbatim: shared.appVersion), quiet: false)
                        SettingsDivider()
                        line(Text("Language"), value: Text(verbatim: shared.language), quiet: false)
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background { Ink.background.ignoresSafeArea() }
            .navigationTitle(Text("What is sent"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(Ink.primary)
        .presentationBackground(Ink.background)
    }

    /// A name and its value side by side, the value under the name when they do not fit.
    private func line(_ title: Text, value: Text, quiet: Bool) -> some View {
        let name = title.font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
        let shown = value.font(AppFont.text(14)).foregroundStyle(quiet ? Ink.muted : Ink.secondary)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                name.lineLimit(1)
                Spacer(minLength: 8)
                shown.lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 3) {
                name.fixedSize(horizontal: false, vertical: true)
                shown.fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 50)
        .accessibilityElement(children: .combine)
    }
}
