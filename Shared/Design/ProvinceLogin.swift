import SwiftUI

/// Logging in to a province app: the shared login (`AresLogin`) with the province's bust and name on the province wall.
struct ProvinceLogin: View {
    let session: EmpireSession
    let name: String            // "Arestemis"
    let bust: Image
    let accent: AppAccent

    var body: some View {
        AresLogin(session: session, accent: accent) {
            bust.resizable().scaledToFit().frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.6), radius: 17, y: 16)
                .padding(.bottom, 16).accessibilityHidden(true)
            Text(verbatim: name.uppercased()).font(AppFont.text(17, weight: .bold)).tracking(3.7).padding(.leading, 3.7)
                .foregroundStyle(Ink.primary).accessibilityAddTraits(.isHeader)
        } wall: {
            ProvinceWall(accent: accent)
        }
    }
}

/// The login of every Ares app but Aresium (which keeps its own layout, built from the same pieces): the app's mark and
/// name, "One Ares account for all Ares apps", the fields and Log in, then Create account and Forgot password? (sheets,
/// `AccountSheets.swift`). An account without this app sees the no-access panel in place of the fields. One account
/// for all apps, so this shows only while no Ares app on the iPhone is logged in, or when this one may not be used with
/// that login. The Empire app's register (crest, gold wordmark) came first; the provinces put their bust in its place.
struct AresLogin<Mark: View, Wall: View>: View {
    let session: EmpireSession
    var accent: AppAccent? = nil
    @ViewBuilder var mark: Mark
    @ViewBuilder var wall: Wall
    @State private var email = ""
    @State private var password = ""
    @State private var sheet: LoginSheet?
    @FocusState private var focused: Field?
    private enum Field { case email, password }

    init(session: EmpireSession, accent: AppAccent? = nil, @ViewBuilder mark: () -> Mark, @ViewBuilder wall: () -> Wall) {
        self.session = session
        self.accent = accent
        self.mark = mark()
        self.wall = wall()
        #if DEBUG
        _sheet = State(initialValue: LoginSheet.launched())
        #endif
    }

    var body: some View {
        LoginScroll { form }
            .background { wall }
            .preferredColorScheme(.dark)
            .loginSheets($sheet, session: session, accent: accent, email: $email)
    }

    private var form: some View {
        VStack(spacing: 0) {
            mark
            (session.isDenied ? Text("This account has no access to \(session.app.name).", tableName: "Shared")
                              : Text("One Ares account for all Ares apps", tableName: "Shared"))
                .font(AppFont.number(12, weight: .regular)).foregroundStyle(LoginStyle.dark.quiet)
                .multilineTextAlignment(.center).padding(.top, 8).padding(.bottom, 28)

            if session.isDenied {
                NoAccessPanel(session: session)
            } else {
                loginForm
            }
        }
        .padding(.horizontal, 30).padding(.top, 96)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.2), value: session.isDenied)
    }

    private var loginForm: some View {
        VStack(spacing: 0) {
            VStack(spacing: 11) {
                field { TextField("", text: $email, prompt: prompt(Text("Email", tableName: "Shared"))) }
                    .textContentType(.username).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focused, equals: .email).submitLabel(.next).onSubmit { focused = .password }
                field { SecureField("", text: $password, prompt: prompt(Text("Password", tableName: "Shared"))) }
                    .textContentType(.password)
                    .focused($focused, equals: .password).submitLabel(.go).onSubmit(login)
            }

            if let error = session.error {
                LoginBox(text: error, problem: true).padding(.top, 14)
            } else if let notice = session.notice {
                LoginBox(text: notice, problem: false).padding(.top, 14)
            }

            Button(action: login) {
                BusyLabel(text: session.loginUnavailable ? Text("Try again", tableName: "Shared")
                                                         : Text("Log in", tableName: "Shared"),
                          busy: session.isBusy, tint: LoginStyle.dark.buttonText)
                    .font(AppFont.text(14, weight: .semibold)).foregroundStyle(LoginStyle.dark.buttonText)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(LoginStyle.dark.button, in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(session.isBusy || email.isEmpty || password.isEmpty)
            .opacity(email.isEmpty || password.isEmpty ? 0.75 : 1)
            .padding(.top, 18)

            if session.needsRestoreRetry {
                Button { Task { await session.restore() } } label: { Text("Retry", tableName: "Shared") }
                    .font(AppFont.text(13)).foregroundStyle(LoginStyle.dark.secondaryText).disabled(session.isBusy)
                    .padding(.top, 14)
            }

            LoginLinks(createAccount: { sheet = .createAccount }, forgotPassword: { sheet = .forgotPassword })
                .padding(.top, 12)
        }
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(AppFont.number(15, weight: .regular)).foregroundStyle(Ink.primary)
            .padding(.horizontal, 16).frame(height: 50)
            .background(.white.opacity(0.04), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.12)))
    }

    private func prompt(_ text: Text) -> Text {
        text.foregroundStyle(Color(hex: 0x6F726F))
    }

    private func login() {
        guard !email.isEmpty, !password.isEmpty, !session.isBusy else { return }
        focused = nil
        let submitted = password
        password = ""
        Task { await session.login(email: email, password: submitted) }
    }
}

// MARK: - pieces every login uses (Aresium's too)

/// The login's colours and button type: the dark register of the Empire and province logins, or an app's own
/// (Aresium's palette).
struct LoginStyle {
    var quiet: Color            // the line under the name, small print
    var button: Color           // the main button's fill
    var buttonText: Color
    var secondaryText: Color    // an outlined button's words
    var outline: Color          // its edge
    var box: Color              // a calm note's fill
    var boxText: Color
    var buttonFont = AppFont.text(14, weight: .semibold)

    static let dark = LoginStyle(quiet: Color(hex: 0x8F9390), button: Color(hex: 0xEEEEE8),
                                 buttonText: Color(hex: 0x141617), secondaryText: Color(hex: 0xC0C4BF),
                                 outline: .white.opacity(0.125), box: .white.opacity(0.04), boxText: Color(hex: 0xC0C4BF))
}

/// Under the Log in button: "Create account" (an outlined button: the first Ares app someone opens may be this one)
/// and the quieter "Forgot password?".
struct LoginLinks: View {
    var style = LoginStyle.dark
    let createAccount: () -> Void
    let forgotPassword: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Button(action: createAccount) {
                Text("Create account", tableName: "Shared")
                    .font(style.buttonFont).foregroundStyle(style.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(style.outline))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: forgotPassword) {
                Text("Forgot password?", tableName: "Shared")
                    .font(AppFont.text(12.5)).foregroundStyle(style.quiet)
            }
            .buttonStyle(.plain)
        }
    }
}

/// A line in a box above the login button: a problem (the login's soft red) or a calm notice ("Your Ares account is
/// deleted.").
struct LoginBox: View {
    let text: String
    let problem: Bool
    var style = LoginStyle.dark
    var alignment: Alignment = .leading
    var symbol: String? = nil       // a small mark before the line ("checkmark" once access was asked for)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
            }
            Text(text).font(AppFont.text(12)).lineSpacing(5)
        }
        .foregroundStyle(problem ? Color(hex: 0xD9B4A6) : style.boxText)
        .frame(maxWidth: .infinity, alignment: alignment).padding(14)
        .background(problem ? Color(hex: 0x3A2222, opacity: 0.19) : style.box, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(problem ? Color(hex: 0xCF8F78, opacity: 0.2) : style.outline))
        .accessibilityElement(children: .combine)
    }
}

/// Logged in, but without this app: who is logged in, "Ask for access" (`AccessRequest`; afterwards "Asked. You get an
/// email once it's approved."), and Log out, which ends the login in every Ares app on the iPhone. When the app's
/// server refused an account that has the app (a 403), asking cannot help: its line and Log out only.
struct NoAccessPanel: View {
    let session: EmpireSession
    var style = LoginStyle.dark
    var alignment: HorizontalAlignment = .center
    @State private var request: AccessRequest

    init(session: EmpireSession, style: LoginStyle = .dark, alignment: HorizontalAlignment = .center) {
        self.session = session
        self.style = style
        self.alignment = alignment
        let request = AccessRequest(session: session)
        #if DEBUG
        request.applyDebugArguments(LaunchArguments.current)
        #endif
        _request = State(initialValue: request)
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            if let email = session.email {
                Text("Logged in as \(email)", tableName: "Shared")
                    .font(AppFont.text(13)).foregroundStyle(style.secondaryText)
                    .lineLimit(1).truncationMode(.middle)
                    .padding(.bottom, 22)
            }
            if !session.canAskForAccess, let reason = session.error {
                LoginBox(text: reason, problem: false, style: style, alignment: textAlignment).padding(.bottom, 18)
            }

            if session.canAskForAccess {
                if request.isAsked {
                    LoginBox(text: String(localized: LocalizedStringResource("Asked. You get an email once it's approved.",
                                                                             table: "Shared", locale: .appLanguage)),
                             problem: false, style: style, alignment: textAlignment, symbol: "checkmark")
                        .transition(.opacity)
                } else {
                    Button { Task { await request.ask() } } label: {
                        BusyLabel(text: Text("Ask for access", tableName: "Shared"), busy: request.phase == .asking,
                                  tint: style.buttonText)
                            .font(style.buttonFont).foregroundStyle(style.buttonText)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(style.button, in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(request.phase == .asking)
                    if let failure = request.failure {
                        FormProblem(text: failure.message).padding(.top, 12)
                    }
                }
            }

            Button { session.logOut() } label: {
                Text("Log out", tableName: "Shared")
                    .font(style.buttonFont).foregroundStyle(style.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(style.outline))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(request.phase == .asking)
            .padding(.top, 12)
            Text("In all Ares apps on this iPhone", tableName: "Shared")
                .font(AppFont.text(11.5)).foregroundStyle(style.quiet)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .multilineTextAlignment(alignment == .leading ? .leading : .center)
        .animation(.easeOut(duration: 0.2), value: request.isAsked)
    }

    private var textAlignment: Alignment { alignment == .leading ? .leading : .center }
}

/// A login screen's scrolling content with the quiet legal footer ("Privacy · Imprint", in the app's language) at the
/// bottom of the screen, or below the content when that is taller. Used by every app's login.
struct LoginScroll<Content: View>: View {
    var footerColor = Color(hex: 0x6F726F)
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    content
                    Spacer(minLength: 32)
                    HStack(spacing: 6) {
                        Link(destination: LegalPage.privacy.url()) { Text("Privacy", tableName: "Shared") }
                        Text(verbatim: "·").accessibilityHidden(true)
                        Link(destination: LegalPage.imprint.url()) { Text("Imprint", tableName: "Shared") }
                    }
                    .font(AppFont.text(11.5)).foregroundStyle(footerColor).tint(footerColor)
                    .padding(.bottom, 14)
                }
                .frame(minHeight: geometry.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

/// While a province app restores its login or loads, or when loading failed: the bust and the name, then the state
/// (EmpireLoading in the province register).
struct ProvinceLoading: View {
    let name: String
    let bust: Image
    let accent: AppAccent
    var message: String? = nil
    var retry: (() -> Void)? = nil
    var logOut: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            bust.resizable().scaledToFit().frame(width: 84, height: 84).accessibilityHidden(true)
            Text(name.uppercased()).font(AppFont.text(17, weight: .bold)).tracking(3.7).padding(.leading, 3.7)
                .foregroundStyle(Ink.primary)
            if let message {
                Text(message).font(AppFont.text(13)).lineSpacing(7).foregroundStyle(Color(hex: 0xA0A79F))
                    .multilineTextAlignment(.center)
                VStack(spacing: 10) {
                    if let retry {
                        Button(action: retry) { Text("Try again", tableName: "Shared") }.font(AppFont.text(12, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x141617)).frame(maxWidth: 260, minHeight: 46)
                            .background(Color(hex: 0xEEEEE8), in: .rect(cornerRadius: 11)).buttonStyle(.plain)
                    }
                    if let logOut {
                        Button(action: logOut) { Text("Log out", tableName: "Shared") }.font(AppFont.text(12, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xC0C4BF)).frame(maxWidth: 260, minHeight: 46)
                            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.125))).buttonStyle(.plain)
                    }
                }
            } else {
                ProgressView().tint(Color(hex: 0xA0A79F)).accessibilityLabel(Text("Loading", tableName: "Shared"))
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { ProvinceWall(accent: accent) }
        .preferredColorScheme(.dark)
    }
}
