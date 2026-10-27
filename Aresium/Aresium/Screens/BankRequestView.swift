import SwiftUI

// "My bank is missing" in the bank guide (brief 25): a glass card with one line on top and a quiet button, Tell us
// about your bank; it opens the bank's name (prefilled with what was searched for) and Send in place, then one line on
// how it went. Built from the guide's own pieces (glass card, the chips' and fields' `Ink.field`, `FormButtonStyle`,
// `FormProblem`, `FormNote`); ink only. Logic: `BankRequestForm`, `BankOutbox`.

/// The card: the line (the guide's no-match note, or "Your bank is missing?" at the end of Another bank) and, when the
/// app can send (not in the tour), the button and the form.
struct BankRequestCard: View {
    let lead: Text
    /// Where the name goes; nil in the tour, where nothing is sent.
    let outbox: BankOutbox?
    /// What the person searched for: the name's first value.
    var prefill = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            lead.font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let outbox { BankRequestBlock(outbox: outbox, prefill: prefill) }
        }
        .padding(16)
        .glassCard()
    }
}

/// Tell us about your bank, then the name and Send, then how it went.
private struct BankRequestBlock: View {
    let outbox: BankOutbox
    let prefill: String
    @State private var form: BankRequestForm?
    @FocusState private var typing: Bool

    var body: some View {
        Group {
            if let form {
                BankRequestFormView(form: form, typing: $typing)
            } else {
                Button(action: open) {
                    Text("Tell us about your bank").font(AppFont.text(14.5, weight: .semibold)).foregroundStyle(Ink.primary)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 44)
                        .background(Ink.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Ink.line))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: form == nil)
        // While the person has not changed the name, it follows the search.
        .onChange(of: prefill) { old, new in
            if let form, form.phase == .asking, form.bank == old { form.bank = new }
        }
        #if DEBUG
        .task {
            // Screenshots: `-bankRequest` opens the form, `-bankRequestPhase sending|sent|kept|refused|personal` shows a
            // state (`-bankRequestMessage <text>`: the server's refusal).
            guard LaunchArguments.current.contains("-bankRequest") || LaunchArguments.value("-bankRequestPhase") != nil
            else { return }
            let form = BankRequestForm(bank: prefill, outbox: outbox)
            switch LaunchArguments.value("-bankRequestPhase") {
            case "sending": form.debugPhase(.sending)
            case "sent": form.debugPhase(.sent)
            case "kept": form.debugPhase(.kept)
            case "refused": form.debugPhase(.refused(LaunchArguments.value("-bankRequestMessage")
                                                     ?? BankRequestForm.refusedLine()))
            case "personal": form.debugProblem(BankSubmission.personalLine())
            default: break
            }
            self.form = form
        }
        #endif
    }

    private func open() {
        form = BankRequestForm(bank: BankSubmission.cleanBank(prefill), outbox: outbox)
        // Nothing searched for (the end of Another bank): straight to typing, once the field is there. With a name
        // there, Send is the next tap.
        guard prefill.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            typing = true
        }
    }
}

/// The name and Send (the keyboard's Send too), the line on what goes out; then how it went.
private struct BankRequestFormView: View {
    @Bindable var form: BankRequestForm
    var typing: FocusState<Bool>.Binding

    var body: some View {
        Group {
            switch form.shown {
            case .asking, .sending:
                asking
            case .sent:
                outcome("checkmark.circle", Text("Thank you. We'll look at adding it."))
            case .kept:
                outcome("clock", Text("Not sent yet. Aresium sends it by itself as soon as it can."))
            case let .refused(message):
                FormProblem(text: message).padding(.horizontal, -4)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: form.shown)
    }

    private var asking: some View {
        let sending = form.shown == .sending
        return VStack(alignment: .leading, spacing: 0) {
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
            .disabled(sending)
            if let problem = form.problem {
                FormProblem(text: problem).padding(.horizontal, -4).padding(.top, 8)
            }
            Text("Only the name goes to us, with the app's version and language.")
                .font(AppFont.text(12.5)).foregroundStyle(Ink.muted).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }

    /// The bank's name, in the look of the format card's field.
    private var field: some View {
        TextField("", text: $form.bank, prompt: Text("Name of the bank").foregroundStyle(Ink.muted))
            .font(AppFont.text(15)).foregroundStyle(Ink.primary)
            .textContentType(.organizationName).textInputAutocapitalization(.words).autocorrectionDisabled()
            .submitLabel(.send).onSubmit(send)
            .focused(typing)
            .padding(.horizontal, 14).frame(minHeight: 50)
            .background(Ink.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Ink.line))
            .accessibilityLabel(Text("Name of the bank"))
    }

    private var sendButton: some View {
        Button(action: send) {
            BusyLabel(text: Text("Send"), busy: form.shown == .sending)
        }
        .buttonStyle(FormButtonStyle(accent: nil, busy: form.shown == .sending))
        .disabled(!form.canSend && form.shown != .sending)
        .allowsHitTesting(form.shown != .sending)
    }

    private func send() {
        guard form.canSend else { return }
        typing.wrappedValue = false
        Task { await form.send() }
    }

    private func outcome(_ symbol: String, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: symbol).foregroundStyle(Ink.secondary).accessibilityHidden(true)
            text.font(AppFont.text(14)).foregroundStyle(Ink.primary).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }
}
