import SwiftUI

struct LoginScreen: View {
    let session: EmpireSession
    let palette: Palette
    var waitingFiles = 0
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focused: Field?
    private enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image("Hermes").resizable().scaledToFit().frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "Aresium").font(AppFont.text(34, weight: .bold))
                    Text("Log in with your Empire account.").font(AppFont.text(15)).foregroundStyle(palette.secondary)
                }
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
                    Text(error).font(AppFont.text(14)).foregroundStyle(palette.expense).accessibilityLabel(error)
                }
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
            }.padding(.horizontal, 28).padding(.top, 80)
        }.scrollDismissesKeyboard(.interactively)
    }

    private func login() {
        guard !email.isEmpty, !password.isEmpty, !session.isBusy else { return }
        focused = nil
        let submittedPassword = password
        password = ""
        Task { await session.login(email: email, password: submittedPassword) }
    }
}
