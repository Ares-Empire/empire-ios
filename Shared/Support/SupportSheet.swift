import SwiftUI

/// "Contact & support" (every app's Settings → Help): pick what it is about, write it, send it. The account server mails
/// it to Patrik (ares-empire/docs/ACCOUNTS.md → Contact & support); the answer comes by email to the account's address.
/// Present it as a sheet: `SupportSheet(session: session, accent: app.accent, sample: sample)`; it sets its own detent
/// and background, and asks before closing over unsent text.
struct SupportSheet: View {
    let accent: AppAccent?
    @State private var form: SupportForm
    @State private var confirmsDiscard = false
    @FocusState private var writing: Bool
    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - accent: the app's accent (the wall's light, the Send button); nil keeps to ink (Empire, Aresium).
    ///   - sample: sample mode: pretends to send, never calls the server.
    init(session: EmpireSession, accent: AppAccent? = nil, sample: Bool = false) {
        self.accent = accent
        let form = SupportForm(session: session, sample: sample)
        #if DEBUG
        form.applyDebugArguments(ProcessInfo.processInfo.arguments)
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
        .preferredColorScheme(.dark)
    }

    // MARK: writing

    private var compose: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(text: String(localized: "Topic", table: "Shared")).padding(.leading, 4)
                kindMenu.padding(.top, 10)

                SectionHeading(text: String(localized: "Message", table: "Shared")).padding(.leading, 4).padding(.top, 26)
                messageBox.padding(.top, 10)
                if form.length > SupportMessage.maxLength - 500 { counter.padding(.top, 8) }

                Text("Your app version, iOS version and language are sent with it. The answer comes by email, to your account's address.",
                     tableName: "Shared")
                    .font(AppFont.text(12)).foregroundStyle(Ink.muted).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4).padding(.top, 14)
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

    /// Shown near the limit: "4,812 / 5,000", in the problem colour once over it.
    private var counter: some View {
        let locale = AppLanguage.current.locale
        let text = form.length.formatted(.number.locale(locale)) + " / "
            + SupportMessage.maxLength.formatted(.number.locale(locale))
        return Text(verbatim: text)
            .font(AppFont.number(11, weight: .regular))
            .foregroundStyle(form.isTooLong ? StatusTone.issue.color(accent ?? .aresus) : Ink.muted)
            .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 4)
            .accessibilityLabel(Text("\(form.length) of \(SupportMessage.maxLength) characters", tableName: "Shared"))
    }

    // MARK: sent

    private var sent: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(highlight.opacity(0.10))
                Circle().strokeBorder(highlight.opacity(0.45), lineWidth: 1)
                Image(systemName: "checkmark").font(.system(size: 22, weight: .semibold)).foregroundStyle(highlight)
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)
            Text("Thanks, it's arrived.", tableName: "Shared")
                .font(AppFont.text(22, weight: .bold)).foregroundStyle(Ink.primary)
                .multilineTextAlignment(.center).padding(.top, 22)
            Text("If it needs an answer, it comes by email.", tableName: "Shared")
                .font(AppFont.text(14)).foregroundStyle(Ink.muted)
                .multilineTextAlignment(.center).padding(.top, 8)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .transition(.opacity)
    }

    // MARK: the button

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let failure = form.failure {
                Label { Text(failure.message) } icon: { Image(systemName: "exclamationmark.circle") }
                    .font(AppFont.text(13)).foregroundStyle(Self.problemInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }
            Button(action: primary) { primaryLabel }
                .buttonStyle(SupportButtonStyle(accent: accent, busy: form.phase == .sending))
                .disabled(!(form.canSend || form.phase == .sending || form.phase == .sent))
                .allowsHitTesting(form.phase != .sending)
        }
        .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 10)
    }

    @ViewBuilder private var primaryLabel: some View {
        switch form.phase {
        case .writing: Text("Send", tableName: "Shared")
        case .sending:
            HStack(spacing: 10) {
                ProgressView().tint(SupportButtonStyle.ink)
                Text("Sending…", tableName: "Shared")
            }
        case .failed: Text("Send again", tableName: "Shared")
        case .sent: Text("Done", tableName: "Shared")
        }
    }

    private func primary() {
        if form.phase == .sent { dismiss(); return }
        writing = false
        Task { await form.send() }
    }

    private func close() {
        if form.hasUnsentText { confirmsDiscard = true } else { dismiss() }
    }

    // MARK: look

    /// The accent where the sheet has one small highlight (the kind's symbol, the focused box, the check).
    private var highlight: Color { accent?.color ?? Ink.secondary }

    /// The shared login's soft problem colour (`ProvinceLogin`).
    private static let problemInk = Color(hex: 0xD9B4A6)

    @ViewBuilder private var wall: some View {
        if let accent { ProvinceWall(accent: accent) } else { Ink.background.ignoresSafeArea() }
    }
}

/// The form's one primary button: the app's accent with dark ink (ivory, like the login's button, when the app has no
/// accent); a quiet glass outline while there is nothing to send.
private struct SupportButtonStyle: ButtonStyle {
    let accent: AppAccent?
    var busy = false
    @Environment(\.isEnabled) private var isEnabled

    static let ink = Color(hex: 0x141617)
    private static let ivory = Color(hex: 0xEEEEE8)

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        configuration.label
            .font(AppFont.text(15, weight: .semibold))
            .lineLimit(1).minimumScaleFactor(0.85)
            .foregroundStyle(isEnabled ? Self.ink : Ink.muted)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                if isEnabled {
                    shape.fill(accent?.color ?? Self.ivory).opacity(busy ? 0.75 : 1)
                } else {
                    shape.fill(Color.white.opacity(0.06))
                }
            }
            .overlay { if !isEnabled { shape.strokeBorder(Color.white.opacity(0.12)) } }
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#if DEBUG
extension SupportForm {
    /// Screenshots: `-supportKind problem|idea|question|other`, `-supportText <text>`,
    /// `-supportPhase sending|sent|offline|tooMany|loggedOut|other` (the last four: a failed send).
    func applyDebugArguments(_ arguments: [String]) {
        func value(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        if let kind = value("-supportKind").flatMap(SupportKind.init(rawValue:)) { self.kind = kind }
        if let text = value("-supportText") { self.text = text }
        switch value("-supportPhase") {
        case "sending": debugPhase(.sending)
        case "sent": debugPhase(.sent)
        case "offline": debugPhase(.failed(.offline))
        case "tooMany": debugPhase(.failed(.tooMany))
        case "loggedOut": debugPhase(.failed(.loggedOut))
        case "other": debugPhase(.failed(.other))
        default: break
        }
    }
}
#endif
