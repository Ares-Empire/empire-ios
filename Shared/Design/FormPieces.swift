import SwiftUI

// The pieces every form sheet and Settings page is built from (the contact form, the account's sheets and pages), so
// they look and behave the same in every app.

/// A form's one main button: the app's accent with dark ink (ivory without an accent, like the login's button), a quiet
/// glass outline while it cannot be pressed. `destructive` (leaving an app, deleting the account) is the hub's soft red
/// (mobile.css `.em-danger`), never a loud one.
struct FormButtonStyle: ButtonStyle {
    enum Kind { case primary, destructive }

    var kind: Kind = .primary
    let accent: AppAccent?
    var busy = false
    @Environment(\.isEnabled) private var isEnabled

    static let ink = Color(hex: 0x141617)
    static let ivory = Color(hex: 0xEEEEE8)
    static let dangerInk = Color(hex: 0xE4AAAA)

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        configuration.label
            .font(AppFont.text(15, weight: .semibold))
            .lineLimit(1).minimumScaleFactor(0.85)
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                switch (kind, isEnabled) {
                case (.primary, true): shape.fill(accent?.color ?? Self.ivory).opacity(busy ? 0.75 : 1)
                case (.destructive, true): shape.fill(Color(hex: 0x5E2929, opacity: busy ? 0.22 : 0.30))
                case (_, false): shape.fill(Color.white.opacity(0.06))
                }
            }
            .overlay {
                switch (kind, isEnabled) {
                case (.destructive, true): shape.strokeBorder(Color(hex: 0xBC6D6D, opacity: 0.38))
                case (_, false): shape.strokeBorder(Color.white.opacity(0.12))
                default: EmptyView()
                }
            }
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    private var foreground: Color {
        guard isEnabled else { return Ink.muted }
        return kind == .destructive ? Self.dangerInk : Self.ink
    }
}

/// A button's label while it works: a small spinner before the words.
struct BusyLabel: View {
    let text: Text
    var busy: Bool
    var tint: Color = FormButtonStyle.ink

    var body: some View {
        HStack(spacing: 10) {
            if busy { ProgressView().tint(tint) }
            text
        }
    }
}

/// One input row of a form card: the placeholder names it; email, password and name rows get the keyboard, the
/// autofill and the capitalisation they need.
struct FormField: View {
    enum Kind { case email, password, newPassword, name }

    let placeholder: String
    @Binding var text: String
    var kind: Kind = .email

    var body: some View {
        Group {
            switch kind {
            case .password, .newPassword:
                SecureField("", text: $text, prompt: prompt)
                    .textContentType(kind == .password ? .password : .newPassword)
            case .email:
                TextField("", text: $text, prompt: prompt)
                    .textContentType(.username).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            case .name:
                TextField("", text: $text, prompt: prompt)
                    .textContentType(.name).textInputAutocapitalization(.words).autocorrectionDisabled()
            }
        }
        .font(AppFont.text(15)).foregroundStyle(Ink.primary)
        .padding(.horizontal, 16).frame(minHeight: 52)
        .accessibilityLabel(placeholder)
    }

    private var prompt: Text { Text(placeholder).foregroundStyle(Ink.muted) }
}

/// A short line under a form: what it does, what it needs.
struct FormNote: View {
    let text: String
    var body: some View {
        Text(text).font(AppFont.text(12.5)).foregroundStyle(Ink.muted).lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

/// Why something did not go through, in the login's soft problem colour.
struct FormProblem: View {
    let text: String
    static let ink = Color(hex: 0xD9B4A6)

    var body: some View {
        Label { Text(text) } icon: { Image(systemName: "exclamationmark.circle") }
            .font(AppFont.text(13)).foregroundStyle(Self.ink).lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .transition(.opacity)
    }
}

/// The calm screen after something went through: a mark in a thin circle, a title and one or two lines, centred.
struct CalmDone: View {
    var symbol = "checkmark"
    let title: Text
    let text: Text
    var highlight: Color = Ink.secondary

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(highlight.opacity(0.10))
                Circle().strokeBorder(highlight.opacity(0.45), lineWidth: 1)
                Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(highlight)
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)
            title
                .font(AppFont.text(22, weight: .bold)).foregroundStyle(Ink.primary)
                .multilineTextAlignment(.center).padding(.top, 22)
            text
                .font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(4)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .transition(.opacity)
    }
}
