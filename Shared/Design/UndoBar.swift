import SwiftUI

/// Something done with a single tap that can be taken back for a few seconds: "Listing dismissed · Undo" (Arestemis),
/// "Marked as discussed · Undo" (Arestoteles). The action itself has already happened when the offer appears; `undo`
/// puts it back.
struct UndoOffer: Identifiable {
    let id = UUID()
    let message: String
    let undo: @MainActor () async -> Void

    /// How long the bar stays: longer while VoiceOver reads, so the Undo can still be reached after the message.
    static func shownFor(voiceOver: Bool) -> Duration { voiceOver ? .seconds(10) : .seconds(5) }
}

extension View {
    /// The undo bar at the bottom of this view, above the tab bar. A new offer replaces the one shown; the one replaced
    /// can no longer be undone (what it did stays done). Put it outside the screen's NavigationStack when the action
    /// can also come from a pushed page (that page's back then shows the bar on the list).
    func undoBar(_ offer: Binding<UndoOffer?>, accent: AppAccent) -> some View {
        modifier(UndoBarModifier(offer: offer, accent: accent))
    }
}

private struct UndoBarModifier: ViewModifier {
    @Binding var offer: UndoOffer?
    let accent: AppAccent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let shown = offer {
                    UndoBar(message: shown.message, accent: accent) {
                        offer = nil
                        Task { await shown.undo() }
                    }
                    .id(shown.id)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .task(id: shown.id) {
                        AccessibilityNotification.Announcement(shown.message).post()
                        try? await Task.sleep(for: UndoOffer.shownFor(voiceOver: voiceOver))
                        if offer?.id == shown.id { offer = nil }
                    }
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.3), value: offer?.id)
    }
}

/// The bar itself: the message and Undo in the app's accent, on the raised glass card.
private struct UndoBar: View {
    let message: String
    let accent: AppAccent
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(AppFont.text(14, weight: .medium)).foregroundStyle(Ink.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: undo) {
                Text("Undo", tableName: "Shared")
                    .font(AppFont.text(14, weight: .semibold)).foregroundStyle(accent.color)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16).padding(.trailing, 8)
        .frame(minHeight: 52)
        .glassCard(radius: 14, raised: true)
        .padding(.horizontal, 18).padding(.bottom, 10)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview {
    @Previewable @State var offer: UndoOffer? = UndoOffer(message: "Listing dismissed.") {}
    Color.clear
        .undoBar($offer, accent: .arestemis)
        .background(Ink.background)
}
#endif
