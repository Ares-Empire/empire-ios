import SwiftUI

/// Settings → Ares account → Sign in, in an app that works without an account (`EmpireAppIdentity.accountOptional`,
/// Aresium): the login as a form sheet, without "Create account" (the app needs no account; one is only for what the
/// app's line says, Aresium's own server). Forgot password? stays. The login is the shared one (`EmpireSession.login`),
/// so it signs in every Ares app on the iPhone; the sheet closes once it went through.
struct SignInSheet: View {
    let session: EmpireSession
    let accent: AppAccent?
    /// What an account is for in this app (`SettingsApp.signInNote`).
    var note: String?
    @State private var email = ""
    @State private var password = ""
    /// The session's line is shown only after a try from this sheet (a renewal that failed earlier is not this sheet's).
    @State private var tried = false
    @State private var resetsPassword = false
    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss
    private enum Field { case email, password }

    var body: some View {
        AccountSheetFrame(title: Text("Ares account", tableName: "Shared"), accent: accent, busy: session.isBusy) {
            fields
        } actions: {
            actions
        }
        .onChange(of: session.token) { _, token in
            if token != nil { dismiss() }
        }
        .sheet(isPresented: $resetsPassword) {
            PasswordResetSheet(session: session, accent: accent, email: email)
        }
    }

    private var fields: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let note {
                    Text(note).font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
                }
                VStack(spacing: 0) {
                    FormField(placeholder: String(localized: LocalizedStringResource("Email", table: "Shared",
                                                                                     locale: .appLanguage)),
                              text: $email, kind: .email)
                        .focused($focus, equals: .email).submitLabel(.next).onSubmit { focus = .password }
                    SettingsDivider()
                    FormField(placeholder: String(localized: LocalizedStringResource("Password", table: "Shared",
                                                                                     locale: .appLanguage)),
                              text: $password, kind: .password)
                        .focused($focus, equals: .password).submitLabel(.go).onSubmit(logIn)
                }
                .glassCard(accent: accent).padding(.top, note == nil ? 0 : 20)
                // No "One Ares account for all Ares apps" under the fields: it went from the logins on 2026-10-31
                // (Patrik), and from this sheet with brief 215.
            }
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .disabled(session.isBusy)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if tried, let error = session.error { FormProblem(text: error) }
            Button(action: logIn) {
                BusyLabel(text: session.loginUnavailable ? Text("Try again", tableName: "Shared")
                                                         : Text("Log in", tableName: "Shared"),
                          busy: session.isBusy)
            }
            .buttonStyle(FormButtonStyle(accent: accent, busy: session.isBusy))
            .disabled(!(canLogIn || session.isBusy))
            .allowsHitTesting(!session.isBusy)
            Button { resetsPassword = true } label: {
                Text("Forgot password?", tableName: "Shared")
                    .font(AppFont.text(13)).foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(session.isBusy)
        }
    }

    private var canLogIn: Bool { !AccountInput.trimmedEmail(email).isEmpty && !password.isEmpty }

    private func logIn() {
        guard canLogIn, !session.isBusy else { return }
        focus = nil
        tried = true
        let typed = password
        password = ""
        Task { await session.login(email: AccountInput.trimmedEmail(email), password: typed) }
    }
}
