import SwiftUI

/// Logging in to a province app: the Empire app's approved login (EmpireLogin) with the province's bust and name instead
/// of the crest and the gold wordmark, on the province wall. Signing up and resetting a password stay on the website.
/// One login for all Empire apps, so this shows only when no other Empire app is logged in.
struct ProvinceLogin: View {
    let session: EmpireSession
    let name: String            // "Arestemis"
    let bust: Image
    let accent: AppAccent
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focused: Field?
    private enum Field { case email, password }

    var body: some View {
        LoginScroll { form }
            .background { ProvinceWall(accent: accent) }
            .preferredColorScheme(.dark)
    }

    private var form: some View {
        VStack(spacing: 0) {
            bust.resizable().scaledToFit().frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.6), radius: 17, y: 16)
                .padding(.bottom, 16).accessibilityHidden(true)
            Text(name.uppercased()).font(AppFont.text(17, weight: .bold)).tracking(3.7).padding(.leading, 3.7)
                .foregroundStyle(Ink.primary).accessibilityAddTraits(.isHeader)
            (session.isDenied ? Text("This account has no access to \(name).", tableName: "Shared")
                              : Text("Log in with your Empire account", tableName: "Shared"))
                .font(AppFont.number(12, weight: .regular)).foregroundStyle(Color(hex: 0x8F9390))
                .multilineTextAlignment(.center).padding(.top, 8).padding(.bottom, 28)

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
                Text(error).font(AppFont.text(12)).lineSpacing(5).foregroundStyle(Color(hex: 0xD9B4A6))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    .background(Color(hex: 0x3A2222, opacity: 0.19), in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: 0xCF8F78, opacity: 0.2)))
                    .padding(.top, 14)
            }

            Button(action: login) {
                HStack(spacing: 10) {
                    if session.isBusy { ProgressView().tint(Color(hex: 0x141617)) }
                    session.loginUnavailable ? Text("Try again", tableName: "Shared") : Text("Log in", tableName: "Shared")
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
                Button { Task { await session.restore() } } label: { Text("Retry", tableName: "Shared") }
                    .font(AppFont.text(13)).foregroundStyle(Color(hex: 0xC0C4BF)).disabled(session.isBusy).padding(.top, 14)
            }

            HStack(spacing: 6) {
                Link(destination: URL(string: "https://www.ares-empire.de/forgot")!) {
                    Text("Forgot password?", tableName: "Shared")
                }
                Text("·")
                Link(destination: URL(string: "https://www.ares-empire.de/signup")!) { Text("Sign up", tableName: "Shared") }
            }
            .font(AppFont.text(12.5)).foregroundStyle(Color(hex: 0x8F9390)).tint(Color(hex: 0xC2C4BF))
            .padding(.top, 20)
        }
        .padding(.horizontal, 30).padding(.top, 96)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
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
