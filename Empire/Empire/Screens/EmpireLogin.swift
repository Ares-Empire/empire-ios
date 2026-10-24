import SwiftUI

/// Logging in, in the phone hub's register (not the website's gold login card): the crest, the wordmark, one quiet
/// line, neutral fields and the ivory button. Signing up and resetting a password stay on the website.
struct EmpireLogin: View {
    let session: EmpireSession
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focused: Field?
    private enum Field { case email, password }

    var body: some View {
        LoginScroll {
            VStack(spacing: 0) {
                Image("Crest").resizable().scaledToFit().frame(width: 104, height: 130)
                    .shadow(color: .black.opacity(0.6), radius: 17, y: 16)
                    .padding(.bottom, 14).accessibilityHidden(true)
                Text("THE EMPIRE").font(AppFont.text(17, weight: .bold)).tracking(3.7).padding(.leading, 3.7).goldFill()
                    .accessibilityAddTraits(.isHeader)
                (session.isDenied ? Text("This app needs an Empire account with access.") : Text("Log in with your Empire account"))
                    .font(AppFont.number(12, weight: .regular)).foregroundStyle(Color(hex: 0x8F9390))
                    .multilineTextAlignment(.center).padding(.top, 8).padding(.bottom, 28)

                VStack(spacing: 11) {
                    field { TextField("", text: $email, prompt: prompt("Email")) }
                        .textContentType(.username).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focused, equals: .email).submitLabel(.next).onSubmit { focused = .password }
                    field { SecureField("", text: $password, prompt: prompt("Password")) }
                        .textContentType(.password)
                        .focused($focused, equals: .password).submitLabel(.go).onSubmit(login)
                }

                if let error = session.error {
                    Text(error).font(AppFont.text(12)).lineSpacing(5).foregroundStyle(Color(hex: 0xD9B4A6))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .background(Color(hex: 0x3A2222, opacity: 0.19), in: .rect(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: 0xCF8F78, opacity: 0.2)))
                        .padding(.top, 14)
                }

                Button(action: login) {
                    HStack(spacing: 10) {
                        if session.isBusy { ProgressView().tint(Color(hex: 0x141617)) }
                        session.loginUnavailable ? Text("Try again") : Text("Log in")
                    }
                    .font(AppFont.text(14, weight: .semibold)).foregroundStyle(Color(hex: 0x141617))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color(hex: 0xEEEEE8), in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(session.isBusy || email.isEmpty || password.isEmpty)
                .opacity(email.isEmpty || password.isEmpty ? 0.75 : 1)
                .padding(.top, 18)

                if session.needsRestoreRetry {
                    Button("Retry") { Task { await session.restore() } }
                        .font(AppFont.text(13)).foregroundStyle(Color(hex: 0xC0C4BF)).disabled(session.isBusy).padding(.top, 14)
                }

                HStack(spacing: 6) {
                    Link("Forgot password?", destination: URL(string: "https://www.ares-empire.de/forgot")!)
                    Text("·")
                    Link("Sign up", destination: URL(string: "https://www.ares-empire.de/signup")!)
                }
                .font(AppFont.text(12.5)).foregroundStyle(Color(hex: 0x8F9390)).tint(Color(hex: 0xC2C4BF))
                .padding(.top, 20)
            }
            .padding(.horizontal, 30).padding(.top, 96)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
        .background(EmpireStyle.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(AppFont.number(15, weight: .regular)).foregroundStyle(EmpireStyle.ink)
            .padding(.horizontal, 16).frame(height: 50)
            .background(.white.opacity(0.04), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.12)))
    }

    private func prompt(_ key: LocalizedStringKey) -> Text {
        Text(key).foregroundStyle(Color(hex: 0x6F726F))
    }

    private func login() {
        guard !email.isEmpty, !password.isEmpty, !session.isBusy else { return }
        focused = nil
        let submitted = password
        password = ""
        Task { await session.login(email: email, password: submitted) }
    }
}

/// While the hub loads, or when it could not: the crest and the wordmark, then the state (mobile.jsx `em-loading`).
struct EmpireLoading: View {
    var message: String? = nil
    var retry: (() -> Void)? = nil
    var logOut: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image("Crest").resizable().scaledToFit().frame(width: 70, height: 90).accessibilityHidden(true)
            Text("THE EMPIRE").font(AppFont.text(18, weight: .bold)).tracking(4).padding(.leading, 4).goldFill()
            if let message {
                Text(message).font(AppFont.text(13)).lineSpacing(7).foregroundStyle(Color(hex: 0xA0A79F))
                    .multilineTextAlignment(.center)
                VStack(spacing: 10) {
                    if let retry {
                        Button("Try again", action: retry).font(AppFont.text(12, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x141617)).frame(maxWidth: 260, minHeight: 46)
                            .background(Color(hex: 0xEEEEE8), in: .rect(cornerRadius: 11)).buttonStyle(.plain)
                    }
                    if let logOut {
                        Button("Log out", action: logOut).font(AppFont.text(12, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xC0C4BF)).frame(maxWidth: 260, minHeight: 46)
                            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.125))).buttonStyle(.plain)
                    }
                }
            } else {
                ProgressView().tint(Color(hex: 0xA0A79F)).accessibilityLabel("Loading")
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EmpireStyle.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
