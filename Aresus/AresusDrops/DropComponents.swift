import SwiftUI

// Shared by the app and the send extension; the status widget does not need these views.
enum AresusInk {
    /// Amber: something to look at that is not a failure (commits on GitHub not deployed yet). Deeper on the light
    /// wall, so it reads on a light card (5:1).
    static let warning = Color(light: Color(hex: 0x8F6210), dark: Color(hex: 0xE0B15A))
}

struct CalmMessage: View {
    let text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Text(text).font(AppFont.text(14)).lineSpacing(5).foregroundStyle(Ink.muted)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(AppFont.text(13, weight: .semibold)).foregroundStyle(Ink.primary)
                    .padding(.horizontal, 22).frame(minHeight: 42)
                    .background(Ink.card2, in: .capsule)
                    .overlay(Capsule().strokeBorder(Ink.edge))
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity)
    }
}

struct CalmLoading: View {
    var body: some View {
        ProgressView().tint(Ink.muted).controlSize(.regular)
            .frame(maxWidth: .infinity).accessibilityLabel(Text("Loading", tableName: "AresusDrops"))
    }
}

struct PressedRow: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Ink.press : .clear)
    }
}

struct PressedBox: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct RowDivider: View {
    var body: some View { Rectangle().fill(Ink.line).frame(height: 1).padding(.horizontal, 16) }
}
