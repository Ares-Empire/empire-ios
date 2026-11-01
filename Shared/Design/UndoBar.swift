import SwiftUI

/// Something done with a single tap that can be taken back for a few seconds: "Listing dismissed · Undo" (Arestemis),
/// "Marked as discussed · Undo" (Arestoteles), "10 payments moved to Groceries · Undo" (Aresium). The action itself has
/// already happened when the offer appears; `undo` puts it back. A line without Undo says what could not be done (an
/// undo refused because the data changed since).
struct UndoOffer: Identifiable {
    let id = UUID()
    let message: String
    /// Nil: the line alone, no Undo.
    let undo: (@MainActor () async -> Void)?

    init(message: String, undo: @escaping @MainActor () async -> Void) {
        self.message = message
        self.undo = undo
    }

    /// A line alone, in the bar's place: what could not be done.
    init(message: String) {
        self.message = message
        undo = nil
    }

    /// How long the bar stays: longer while VoiceOver reads, so the Undo can still be reached after the message.
    static func shownFor(voiceOver: Bool) -> Duration { voiceOver ? .seconds(10) : .seconds(5) }
}

extension View {
    /// The undo bar at the bottom of this view, above the tab bar. A new offer replaces the one shown; the one replaced
    /// can no longer be undone (what it did stays done). Put it outside the screen's NavigationStack when the action
    /// can also come from a pushed page (that page's back then shows the bar on the list). `accent` nil: Undo in ink
    /// (the ink-only apps, Aresium).
    func undoBar(_ offer: Binding<UndoOffer?>, accent: AppAccent?) -> some View {
        modifier(UndoBarModifier(offer: offer, accent: accent))
    }
}

private struct UndoBarModifier: ViewModifier {
    @Binding var offer: UndoOffer?
    let accent: AppAccent?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let shown = offer {
                    UndoBar(message: shown.message, accent: accent, undo: shown.undo.map { undo in {
                        offer = nil
                        Task { await undo() }
                    } })
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

/// The bar itself: the message and Undo in the app's accent (or ink), on the raised glass card; a line alone without it.
private struct UndoBar: View {
    let message: String
    let accent: AppAccent?
    let undo: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(AppFont.text(14, weight: .medium)).foregroundStyle(Ink.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let undo {
                Button(action: undo) {
                    Text("Undo", tableName: "Shared")
                        .font(AppFont.text(14, weight: .semibold)).foregroundStyle(accent?.color ?? Ink.primary)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 16).padding(.trailing, undo == nil ? 16 : 8).padding(.vertical, undo == nil ? 8 : 0)
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
