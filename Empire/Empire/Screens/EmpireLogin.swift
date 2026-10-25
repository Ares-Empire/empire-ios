import SwiftUI

/// Logging in, in the phone hub's register (not the website's gold login card): the crest and the wordmark over the
/// shared login (`AresLogin`: one quiet line, neutral fields, the ivory button, Create account, Forgot password?).
struct EmpireLogin: View {
    let session: EmpireSession

    var body: some View {
        AresLogin(session: session) {
            Image("Crest").resizable().scaledToFit().frame(width: 104, height: 130)
                .shadow(color: EmpireStyle.shadow(dark: 0.6), radius: 17, y: 16)
                .padding(.bottom, 14).accessibilityHidden(true)
            Text("THE EMPIRE").font(AppFont.text(17, weight: .bold)).tracking(3.7).padding(.leading, 3.7).goldFill()
                .accessibilityAddTraits(.isHeader)
        } wall: {
            EmpireStyle.background.ignoresSafeArea()
        }
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
                Text(message).font(AppFont.text(13)).lineSpacing(7).foregroundStyle(EmpireStyle.body(dark: 0xA0A79F))
                    .multilineTextAlignment(.center)
                VStack(spacing: 10) {
                    if let retry {
                        Button("Try again", action: retry).font(AppFont.text(12, weight: .semibold))
                            .foregroundStyle(LoginStyle.standard.buttonText).frame(maxWidth: 260, minHeight: 46)
                            .background(LoginStyle.standard.button, in: .rect(cornerRadius: 11)).buttonStyle(.plain)
                    }
                    if let logOut {
                        Button("Log out", action: logOut).font(AppFont.text(12, weight: .semibold))
                            .foregroundStyle(LoginStyle.standard.secondaryText).frame(maxWidth: 260, minHeight: 46)
                            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(LoginStyle.standard.outline))
                            .buttonStyle(.plain)
                    }
                }
            } else {
                ProgressView().tint(EmpireStyle.body(dark: 0xA0A79F)).accessibilityLabel("Loading")
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EmpireStyle.background.ignoresSafeArea())
    }
}
