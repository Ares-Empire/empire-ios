import SwiftUI

/// The login screen's two sheets. Every app's login opens them (`loginSheets`), since the first Ares app someone gets
/// may be any of them.
enum LoginSheet: String, Identifiable {
    case createAccount, forgotPassword
    var id: String { rawValue }

    #if DEBUG
    /// Screenshots: `-openSheet createAccount|forgotPassword` on the login screen.
    static func launched(_ arguments: [String] = LaunchArguments.current) -> LoginSheet? {
        AccountDebug.value("-openSheet", in: arguments).flatMap(LoginSheet.init(rawValue:))
    }
    #endif
}

extension View {
    /// Presents the login's sheets. `email` is the login's email field: the reset starts from it, and a new account
    /// fills it in.
    func loginSheets(_ sheet: Binding<LoginSheet?>, session: EmpireSession, accent: AppAccent?,
                     email: Binding<String>) -> some View {
        self.sheet(item: sheet) { which in
            switch which {
            case .createAccount:
                SignUpSheet(session: session, accent: accent) { email.wrappedValue = $0 }
            case .forgotPassword:
                PasswordResetSheet(session: session, accent: accent, email: email.wrappedValue)
            }
        }
    }
}

// MARK: - Create account

/// "Create account": email, password twice, an optional name (`SignUpForm`). Afterwards one calm screen: confirm the
/// email by the link just sent, then Patrik approves the account and an email says so; back to the login.
struct SignUpSheet: View {
    let accent: AppAccent?
    let created: (String) -> Void
    @State private var form: SignUpForm
    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss
    private enum Field { case email, password, again, name }

    /// - Parameter created: the new account's email, once the sheet closes after creating it.
    init(session: EmpireSession, accent: AppAccent? = nil, created: @escaping (String) -> Void = { _ in }) {
        self.accent = accent
        self.created = created
        let form = SignUpForm(session: session)
        #if DEBUG
        form.applyDebugArguments(LaunchArguments.current)
        #endif
        _form = State(initialValue: form)
    }

    var body: some View {
        AccountSheetFrame(title: Text("Create account", tableName: "Shared"), accent: accent,
                          showsClose: form.phase != .done, busy: form.phase == .sending) {
            if form.phase == .done { done } else { fields }
        } actions: {
            actions
        }
    }

    private var fields: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("One Ares account for all Ares apps. Once you have confirmed your email, Patrik approves it.",
                     tableName: "Shared")
                    .font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)

                VStack(spacing: 0) {
                    FormField(placeholder: String(localized: LocalizedStringResource("Email", table: "Shared",
                                                                                     locale: .appLanguage)), text: $form.email, kind: .email)
                        .focused($focus, equals: .email).submitLabel(.next).onSubmit { focus = .password }
                    SettingsDivider()
                    FormField(placeholder: String(localized: LocalizedStringResource("Password", table: "Shared",
                                                                                     locale: .appLanguage)), text: $form.password,
                              kind: .newPassword)
                        .focused($focus, equals: .password).submitLabel(.next).onSubmit { focus = .again }
                    SettingsDivider()
                    FormField(placeholder: String(localized: LocalizedStringResource("Password again", table: "Shared",
                                                                                     locale: .appLanguage)),
                              text: $form.passwordAgain, kind: .newPassword)
                        .focused($focus, equals: .again).submitLabel(.next).onSubmit { focus = .name }
                }
                .glassCard(accent: accent).padding(.top, 20)
                FormNote(text: String(localized: LocalizedStringResource("At least 8 characters.", table: "Shared",
                                                                         locale: .appLanguage))).padding(.top, 10)

                FormField(placeholder: String(localized: LocalizedStringResource("Name (optional)", table: "Shared",
                                                                                 locale: .appLanguage)), text: $form.name,
                          kind: .name)
                    .focused($focus, equals: .name).submitLabel(.done).onSubmit(send)
                    .glassCard(accent: accent).padding(.top, 24)
                FormNote(text: String(localized: LocalizedStringResource("Patrik sees it when he approves the account.",
                                                                         table: "Shared", locale: .appLanguage)))
                    .padding(.top, 10)
            }
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .disabled(form.phase == .sending || form.accountCreated)
        .opacity(form.accountCreated ? 0.55 : 1)
    }

    private var done: some View {
        CalmDone(symbol: "envelope",
                 title: Text("Confirm your email", tableName: "Shared"),
                 text: Text("A link is on its way to \(form.email). Open it to confirm your address. Then Patrik approves your account, and an email tells you once it's ready.",
                            tableName: "Shared"),
                 highlight: accent?.color ?? Ink.secondary)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let failure = form.failure {
                FormProblem(text: form.accountCreated
                    ? String(localized: LocalizedStringResource("Your account is created, but the confirmation email didn't go out. \(failure.message)",
                                                                table: "Shared", locale: .appLanguage))
                    : failure.message)
            }
            Button(action: primary) {
                switch form.phase {
                case .done: Text("Back to login", tableName: "Shared")
                case .sending: BusyLabel(text: Text("Creating…", tableName: "Shared"), busy: true)
                case .writing, .failed:
                    form.accountCreated ? Text("Send the email again", tableName: "Shared")
                                        : Text("Create account", tableName: "Shared")
                }
            }
            .buttonStyle(FormButtonStyle(accent: accent, busy: form.phase == .sending))
            .disabled(!(form.canSend || form.phase == .sending || form.phase == .done))
            .allowsHitTesting(form.phase != .sending)
        }
    }

    private func primary() {
        if form.phase == .done {
            created(form.email)
            dismiss()
        } else {
            send()
        }
    }

    private func send() {
        focus = nil
        Task { await form.send() }
    }
}

// MARK: - Forgot password

/// "Forgot password?": the email (from the login's field), then the same calm line whether or not an account has it.
struct PasswordResetSheet: View {
    let accent: AppAccent?
    @State private var form: PasswordResetForm
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(session: EmpireSession, accent: AppAccent? = nil, email: String = "") {
        self.accent = accent
        let form = PasswordResetForm(session: session, email: email)
        #if DEBUG
        form.applyDebugArguments(LaunchArguments.current)
        #endif
        _form = State(initialValue: form)
    }

    var body: some View {
        AccountSheetFrame(title: Text("Forgot password", tableName: "Shared"), accent: accent,
                          showsClose: form.phase != .sent, busy: form.phase == .sending) {
            if form.phase == .sent { sent } else { fields }
        } actions: {
            actions
        }
    }

    private var fields: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Your account's email. You get a link there to choose a new password.", tableName: "Shared")
                    .font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
                FormField(placeholder: String(localized: LocalizedStringResource("Email", table: "Shared",
                                                                                 locale: .appLanguage)), text: $form.email, kind: .email)
                    .focused($focused).submitLabel(.send).onSubmit(send)
                    .glassCard(accent: accent).padding(.top, 20)
            }
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .disabled(form.phase == .sending)
    }

    private var sent: some View {
        CalmDone(symbol: "envelope",
                 title: Text("Check your email", tableName: "Shared"),
                 text: Text("If there is an account for this address, an email is on its way.", tableName: "Shared"),
                 highlight: accent?.color ?? Ink.secondary)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let failure = form.failure { FormProblem(text: failure.message) }
            Button {
                if form.phase == .sent { dismiss() } else { send() }
            } label: {
                switch form.phase {
                case .sent: Text("Back to login", tableName: "Shared")
                case .sending: BusyLabel(text: Text("Sending…", tableName: "Shared"), busy: true)
                case .writing, .failed: Text("Send link", tableName: "Shared")
                }
            }
            .buttonStyle(FormButtonStyle(accent: accent, busy: form.phase == .sending))
            .disabled(!(form.canSend || form.phase == .sending || form.phase == .sent))
            .allowsHitTesting(form.phase != .sending)
        }
    }

    private func send() {
        focused = false
        Task { await form.send() }
    }
}

// MARK: - the frame

/// A form sheet's frame (the contact form's): a navigation bar with the title and a close button, the content, the
/// actions at the bottom, the app's wall; dark in every app.
struct AccountSheetFrame<Content: View, Actions: View>: View {
    let title: Text
    let accent: AppAccent?
    var showsClose = true
    var busy = false
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content
                actions.padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 10)
            }
            .background { SettingsWall(accent: accent) }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsClose {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .close) { dismiss() }.disabled(busy)
                    }
                }
            }
        }
        .tint(Ink.primary)
        .animation(.easeOut(duration: 0.2), value: showsClose)
        .presentationDetents([.large])
        .presentationBackground(Ink.background)
        .interactiveDismissDisabled(busy)
        .preferredColorScheme(.dark)
    }
}
