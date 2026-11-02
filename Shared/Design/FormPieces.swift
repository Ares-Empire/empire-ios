import SwiftUI

// The pieces every form sheet and Settings page is built from (the contact form, the account's sheets and pages), so
// they look and behave the same in every app.

/// A form's one main button: the app's accent (ivory without an accent, like the login's button; near-black on the light
/// wall), a quiet glass outline while it cannot be pressed. `destructive` (leaving an app, deleting the account) is the
/// hub's soft red (mobile.css `.em-danger`), never a loud one.
struct FormButtonStyle: ButtonStyle {
    enum Kind { case primary, destructive }

    var kind: Kind = .primary
    let accent: AppAccent?
    var busy = false
    @Environment(\.isEnabled) private var isEnabled

    /// The words on the main button: dark on the bright dark-mode fills, white on the deeper light-mode ones.
    static let ink = AppAccent.onColor
    /// The main button without an accent: ivory on the dark wall, near-black on the light one.
    static let ivory = Color(light: Color(hex: 0x16181C), dark: Color(hex: 0xEEEEE8))
    /// The hub's soft red, for leaving an app and deleting the account (darker on the light wall).
    static let dangerInk = Color(light: Color(hex: 0xA33A3A), dark: Color(hex: 0xE4AAAA))
    /// The destructive button's faint fill and its edge (also a row's Delete when swiped, `RowSwipe.swift`).
    static let dangerFill = Color(light: Color(hex: 0xC24848, opacity: 0.10), dark: Color(hex: 0x5E2929, opacity: 0.30))
    static let dangerEdge = Color(light: Color(hex: 0xB84A4A, opacity: 0.35), dark: Color(hex: 0xBC6D6D, opacity: 0.38))
    /// A main button that cannot be pressed: a faint fill (with `Ink.edge` around it).
    static let offFill = Color(light: Color(hex: 0x0F1428, opacity: 0.05), dark: .white.opacity(0.06))

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
                case (.destructive, true): shape.fill(Self.dangerFill).opacity(busy ? 0.75 : 1)
                case (_, false): shape.fill(Self.offFill)
                }
            }
            .overlay {
                switch (kind, isEnabled) {
                case (.destructive, true): shape.strokeBorder(Self.dangerEdge)
                case (_, false): shape.strokeBorder(Ink.edge)
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

/// Every switch in an app's Settings (brief 47): Apple's own switch with an on colour that stands apart from its white
/// knob and from the grey off track, in light, dark and Aresium's red mode (which holds dark). Patrik's phone, build 4:
/// the ink tint drew "on" as a pale track under the white knob in dark mode, so on and off could not be told apart. The
/// colour is the app's accent where it has one, else the Empire's green for on and running (`StatusTone.activeColor`,
/// the hub's CONQUERED, and the colour iOS gives a switch that is on), a shared pair, not a new colour. `SettingsScreen`
/// sets it for everything inside it; a switch elsewhere takes it with `.toggleStyle(EmpireSwitchStyle(accent:))`.
struct EmpireSwitchStyle: ToggleStyle {
    var accent: AppAccent? = nil

    /// The track's colour while the switch is on.
    static func onColor(_ accent: AppAccent?) -> Color { accent?.color ?? StatusTone.activeColor }

    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration).toggleStyle(.switch).tint(Self.onColor(accent))
    }
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
    static let ink = Color(light: Color(hex: 0xA2503C), dark: Color(hex: 0xD9B4A6))

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
