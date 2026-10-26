import SwiftUI

/// Aresium's login, in its own layout and theme, from the shared login's pieces (Shared/Design/ProvinceLogin.swift):
/// "One Ares account for all Ares apps", Create account and Forgot password? (sheets), the no-access panel for an
/// account without Aresium.
struct LoginScreen: View {
    let session: EmpireSession
    let palette: Palette
    var waitingFiles = 0
    @State private var email = ""
    @State private var password = ""
    @State private var sheet: LoginSheet?
    @FocusState private var focused: Field?
    private enum Field { case email, password }

    init(session: EmpireSession, palette: Palette, waitingFiles: Int = 0) {
        self.session = session
        self.palette = palette
        self.waitingFiles = waitingFiles
        #if DEBUG
        _sheet = State(initialValue: LoginSheet.launched())
        #endif
    }

    var body: some View {
        LoginScroll(footerColor: palette.muted) {
            VStack(alignment: .leading, spacing: 22) {
                Image("Hermes").resizable().scaledToFit().frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "Aresium").font(AppFont.text(34, weight: .bold))
                    (session.isDenied ? Text("This account has no access to \(session.app.name).", tableName: "Shared")
                                      : Text("One Ares account for all Ares apps", tableName: "Shared"))
                        .font(AppFont.text(15)).foregroundStyle(palette.secondary)
                }
                if session.isDenied {
                    NoAccessPanel(session: session, style: style, alignment: .leading)
                } else {
                    form
                }
            }.padding(.horizontal, 28).padding(.top, 80)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeOut(duration: 0.2), value: session.isDenied)
        }
        .loginSheets($sheet, session: session, accent: nil, email: $email)
    }

    @ViewBuilder private var form: some View {
        if waitingFiles > 0 {
            Text("\(waitingFiles) files waiting, imported after login")
                .font(AppFont.text(14)).foregroundStyle(palette.secondary)
        }
        VStack(alignment: .leading, spacing: 14) {
            TextField("Email", text: $email).textContentType(.username).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($focused, equals: .email).submitLabel(.next).onSubmit { focused = .password }
            Divider().overlay(palette.line)
            SecureField("Password", text: $password).textContentType(.password)
                .focused($focused, equals: .password).submitLabel(.go).onSubmit { login() }
        }.font(AppFont.text(16)).padding(18).background(palette.card2, in: RoundedRectangle(cornerRadius: 14))
        if let error = session.error {
            Text(error).font(AppFont.text(14)).foregroundStyle(palette.expenseText).accessibilityLabel(error)
        } else if let notice = session.notice {
            Text(notice).font(AppFont.text(14)).foregroundStyle(palette.secondary)
        }
        VStack(alignment: .leading, spacing: 12) {
            Button(action: login) {
                HStack {
                    Spacer()
                    if session.isBusy { ProgressView().tint(palette.background) }
                    Text(session.loginUnavailable ? "Retry" : "Log in").font(AppFont.text(16, weight: .bold))
                    Spacer()
                }.padding(16).foregroundStyle(palette.background).background(palette.ink, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).disabled(session.isBusy || email.isEmpty || password.isEmpty)
            if session.needsRestoreRetry {
                Button("Retry") { Task { await session.restore() } }
                    .font(AppFont.text(14)).tint(palette.secondary).disabled(session.isBusy)
            }
            LoginLinks(style: style, createAccount: { sheet = .createAccount },
                       forgotPassword: { sheet = .forgotPassword })
        }
    }

    /// The shared pieces in Aresium's theme (dark, light or red).
    private var style: LoginStyle {
        LoginStyle(quiet: palette.secondary, button: palette.ink, buttonText: palette.background,
                   secondaryText: palette.ink, outline: palette.ink.opacity(0.18), box: palette.card2,
                   boxText: palette.secondary, buttonFont: AppFont.text(16, weight: .semibold))
    }

    private func login() {
        guard !email.isEmpty, !password.isEmpty, !session.isBusy else { return }
        focused = nil
        let submittedPassword = password
        password = ""
        Task { await session.login(email: email, password: submittedPassword) }
    }
}
