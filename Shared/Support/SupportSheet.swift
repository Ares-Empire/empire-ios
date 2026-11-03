import SwiftUI

/// "Contact & support" (every app's Settings → Help): pick what it is about, write it, send it. The account server mails
/// it to Patrik (ares-empire/docs/ACCOUNTS.md → Contact & support); the answer comes by email to the account's address.
/// Without a login (Aresium only, always: `EmpireAppIdentity.supportWithoutLogin`) the form also asks for the email to
/// answer to and, optionally, a name.
/// Present it as a sheet: `SupportSheet(session: session, accent: app.accent, sample: sample)`; it sets its own detent
/// and background, and asks before closing over unsent text. A place that opens it for one purpose passes the kind and
/// the start of the text (Arestemis's "Suggest a shop": an idea, "Suggest a shop: "); the text box then has the
/// keyboard, and closing over nothing but that start asks nothing.
struct SupportSheet: View {
    let accent: AppAccent?
    @State private var form: SupportForm
    @State private var confirmsDiscard = false
    @FocusState private var writing: Bool
    @FocusState private var replyField: ReplyField?
    private enum ReplyField { case email, name }
    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - accent: the app's accent (the wall's light, the Send button); nil keeps to ink (Empire, Aresium).
    ///   - sample: sample mode: pretends to send, never calls the server.
    ///   - kind: what the message is about when it opens.
    ///   - text: the message's start, for the person to go on from; "" for an empty box.
    init(session: EmpireSession, accent: AppAccent? = nil, sample: Bool = false, kind: SupportKind = .problem,
         text: String = "") {
        self.accent = accent
        let form = SupportForm(session: session, sample: sample, kind: kind, text: text)
        #if DEBUG
        form.applyDebugArguments(LaunchArguments.current)
        #endif
        _form = State(initialValue: form)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if form.phase == .sent { sent } else { compose }
                actions
            }
            .background { wall }
            .navigationTitle(Text("Contact & support", tableName: "Shared"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if form.phase != .sent {
                    // An X where the Settings sheet below has its Done, so closing stays in one place.
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .close, action: close)
                            .disabled(form.phase == .sending)
                            .confirmationDialog(Text("Discard this message?", tableName: "Shared"),
                                                isPresented: $confirmsDiscard, titleVisibility: .visible) {
                                Button(role: .destructive) { dismiss() } label: { Text("Discard", tableName: "Shared") }
                                Button(role: .cancel) {} label: { Text("Keep writing", tableName: "Shared") }
                            }
                    }
                }
            }
        }
        .tint(Ink.primary)
        .animation(.easeOut(duration: 0.2), value: form.phase)
        .sensoryFeedback(.success, trigger: form.phase) { _, phase in phase == .sent }
        .presentationDetents([.large])
        .presentationBackground(Ink.background)
        .interactiveDismissDisabled(form.hasUnsentText || form.phase == .sending)
        .onAppear {
            // Opened with its text started: the person goes on typing right there.
            if form.startsWithText { writing = true }
        }
    }

    // MARK: writing

    private var compose: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(text: String(localized: LocalizedStringResource("Topic", table: "Shared",
                                                                               locale: .appLanguage)))
                    .padding(.leading, 4)
                kindMenu.padding(.top, 10)

                SectionHeading(text: String(localized: LocalizedStringResource("Message", table: "Shared",
                                                                               locale: .appLanguage)))
                    .padding(.leading, 4).padding(.top, 26)
                messageBox.padding(.top, 10)
                if form.length > form.maxLength - 500 { counter.padding(.top, 8) }

                if form.sendsWithoutLogin {
                    SectionHeading(text: String(localized: LocalizedStringResource("Answer to", table: "Shared",
                                                                                   locale: .appLanguage)))
                        .padding(.leading, 4).padding(.top, 26)
                    replyBox.padding(.top, 10)
                    Text("Your app version, iOS version and language are sent with it. The answer comes by email, to this address.",
                         tableName: "Shared")
                        .font(AppFont.text(12)).foregroundStyle(Ink.muted).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4).padding(.top, 14)
                } else {
                    Text("Your app version, iOS version and language are sent with it. The answer comes by email, to your account's address.",
                         tableName: "Shared")
                        .font(AppFont.text(12)).foregroundStyle(Ink.muted).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4).padding(.top, 14)
                }
            }
            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .disabled(form.phase == .sending)
    }

    /// The kind as one glass row; tapping it opens the system menu with the four kinds.
    private var kindMenu: some View {
        Menu {
            Picker(selection: $form.kind) {
                ForEach(SupportKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.symbol).tag(kind)
                }
            } label: {
                Text("Topic", tableName: "Shared")
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: form.kind.symbol).font(.system(size: 15, weight: .medium))
                    .foregroundStyle(highlight).frame(width: 22).accessibilityHidden(true)
                Text(form.kind.title).font(AppFont.text(15, weight: .semibold)).foregroundStyle(Ink.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ink.muted).accessibilityHidden(true)
            }
            .padding(.horizontal, 16).frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(accent: accent)
        .opacity(form.phase == .sending ? 0.55 : 1)
        .accessibilityLabel(Text("Topic", tableName: "Shared"))
        .accessibilityValue(form.kind.title)
    }

    private var messageBox: some View {
        TextField("", text: $form.text, prompt: Text(form.kind.placeholder).foregroundStyle(Ink.muted), axis: .vertical)
            .font(AppFont.text(15)).foregroundStyle(Ink.primary).lineSpacing(4)
            .lineLimit(8...)
            .focused($writing)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .glassCard(accent: accent)
            .overlay {
                RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous)
                    .strokeBorder(highlight.opacity(writing ? 0.45 : 0), lineWidth: 1)
            }
            .animation(.easeOut(duration: 0.15), value: writing)
            .contentShape(Rectangle())
            .onTapGesture { writing = true }
            .opacity(form.phase == .sending ? 0.55 : 1)
            .accessibilityLabel(Text("Message", tableName: "Shared"))
    }

    /// Without a login: the email to answer to and an optional name, as the account forms' fields.
    private var replyBox: some View {
        VStack(spacing: 0) {
            FormField(placeholder: String(localized: LocalizedStringResource("Email", table: "Shared",
                                                                             locale: .appLanguage)),
                      text: $form.email, kind: .email)
                .textContentType(.emailAddress)
                .focused($replyField, equals: .email).submitLabel(.next).onSubmit { replyField = .name }
            SettingsDivider()
            FormField(placeholder: String(localized: LocalizedStringResource("Name (optional)", table: "Shared",
                                                                             locale: .appLanguage)),
                      text: $form.name, kind: .name)
                .focused($replyField, equals: .name).submitLabel(.done)
        }
        .glassCard(accent: accent)
        .opacity(form.phase == .sending ? 0.55 : 1)
    }

    /// Shown near the limit: "4,812 / 5,000", in the problem colour once over it.
    private var counter: some View {
        let locale = AppLanguage.current.locale
        let text = form.length.formatted(.number.locale(locale)) + " / "
            + form.maxLength.formatted(.number.locale(locale))
        return Text(verbatim: text)
            .font(AppFont.number(11, weight: .regular))
            .foregroundStyle(form.isTooLong ? StatusTone.issue.color(accent ?? .aresus) : Ink.muted)
            .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 4)
            .accessibilityLabel(Text("\(form.length) of \(form.maxLength) characters", tableName: "Shared"))
    }

    // MARK: sent

    private var sent: some View {
        CalmDone(title: Text("Thanks, it's arrived.", tableName: "Shared"),
                 text: Text("If it needs an answer, it comes by email.", tableName: "Shared"), highlight: highlight)
    }

    // MARK: the button

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let failure = form.failure { FormProblem(text: failure.message) }
            Button(action: primary) { primaryLabel }
                .buttonStyle(FormButtonStyle(accent: accent, busy: form.phase == .sending))
                .disabled(!(form.canSend || form.phase == .sending || form.phase == .sent))
                .allowsHitTesting(form.phase != .sending)
        }
        .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 10)
    }

    @ViewBuilder private var primaryLabel: some View {
        switch form.phase {
        case .writing: Text("Send", tableName: "Shared")
        case .sending: BusyLabel(text: Text("Sending…", tableName: "Shared"), busy: true)
        case .failed: Text("Send again", tableName: "Shared")
        case .sent: Text("Done", tableName: "Shared")
        }
    }

    private func primary() {
        if form.phase == .sent { dismiss(); return }
        writing = false
        replyField = nil
        Task { await form.send() }
    }

    private func close() {
        if form.hasUnsentText { confirmsDiscard = true } else { dismiss() }
    }

    // MARK: look

    /// The accent where the sheet has one small highlight (the kind's symbol, the focused box, the check).
    private var highlight: Color { accent?.color ?? Ink.secondary }

    @ViewBuilder private var wall: some View {
        if let accent { ProvinceWall(accent: accent) } else { Ink.background.ignoresSafeArea() }
    }
}

#if DEBUG
extension SupportForm {
    /// Screenshots: `-supportKind problem|idea|question|other`, `-supportText <text>`, `-supportEmail <text>` (the
    /// address to answer to, without a login), `-supportPhase sending|sent|offline|tooMany|loggedOut|other|invalidEmail`
    /// (the last five: a failed send).
    func applyDebugArguments(_ arguments: [String]) {
        func value(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        if let kind = value("-supportKind").flatMap(SupportKind.init(rawValue:)) { self.kind = kind }
        if let text = value("-supportText") { self.text = text }
        if let email = value("-supportEmail") { self.email = email }
        switch value("-supportPhase") {
        case "sending": debugPhase(.sending)
        case "sent": debugPhase(.sent)
        case "offline": debugPhase(.failed(.offline))
        case "tooMany": debugPhase(.failed(.tooMany))
        case "loggedOut": debugPhase(.failed(.loggedOut))
        case "other": debugPhase(.failed(.other))
        case "invalidEmail": debugPhase(.failed(.invalidEmail))
        default: break
        }
    }
}
#endif
