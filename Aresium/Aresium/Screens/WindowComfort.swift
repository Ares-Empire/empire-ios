import SwiftUI

// The small pieces Aresium's windows share (brief 40: the receipt window, Add cash, the file check, a receipt's page):
// Cancel that asks before throwing away what was typed, Done above the number pad, the busy sign in the button that was
// tapped, and a row of equal buttons. Apple's own controls only (the confirmation dialog, the keyboard's toolbar, the
// spinner); the looks are the existing ones.

// MARK: - Cancel that asks first

/// Cancel in a window's top-left corner. With nothing typed or changed it closes at once; otherwise it asks first, as
/// Contact & support's X does: `question` ("Discard this entry?"), Discard (destructive) and Keep editing.
struct DiscardingCancel: View {
    /// Something the person typed or changed (or a reading that cannot be had again) would be lost.
    let asks: Bool
    let question: Text
    let close: () -> Void
    @State private var confirms = false

    var body: some View {
        Button("Cancel") {
            if asks { confirms = true } else { close() }
        }
        .confirmationDialog(question, isPresented: $confirms, titleVisibility: .visible) {
            Button(role: .destructive, action: close) { Text("Discard", tableName: "Shared") }
            Button(role: .cancel) {} label: { Text("Keep editing") }
        }
        #if DEBUG
        .task(id: asks) {
            // Screenshots: `-askDiscard` taps Cancel once the window shows something to discard.
            guard asks, LaunchArguments.current.contains("-askDiscard") else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { confirms = true }
        }
        #endif
    }
}

// MARK: - Done above the number pad

extension View {
    /// Done above the keyboard while `shown` (a number pad, which has no Return key): it closes the keyboard. Apple's
    /// keyboard toolbar. `top` follows where Done's word is on the screen (nil while it is not shown), for
    /// `clearOfKeyboardDone`.
    func numberPadDone(_ shown: Bool, top: Binding<CGFloat?>, close: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if shown {
                    Spacer()
                    Button(action: close) {
                        Text("Done", tableName: "Shared").fontWeight(.semibold)
                            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top.wrappedValue = $0 }
                            .onDisappear { top.wrappedValue = nil }
                    }
                }
            }
        }
    }

    /// A window's bottom bar (Save) while Done floats above the number pad: iOS 26 draws the keyboard's toolbar as a
    /// floating capsule outside the keyboard's safe area, so it covered Save's corner. The bar rises just enough to
    /// keep its button clear of Done (not at all when iOS already left room).
    func clearOfKeyboardDone(_ doneTop: CGFloat?) -> some View {
        modifier(ClearOfKeyboardDone(doneTop: doneTop))
    }
}

private struct ClearOfKeyboardDone: ViewModifier {
    let doneTop: CGFloat?
    /// The bar's bottom edge on the screen as it would be without the lift.
    @State private var bottom: CGFloat?
    /// From Done's word up to the bar's bottom edge: the word sits about 13 pt inside its capsule, the button keeps
    /// 8 pt of air above the capsule, and the bar's own 10 pt bottom padding counts as part of that.
    private static let gap: CGFloat = 11

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { bottom = $0 + lift }
            .padding(.bottom, lift)
    }

    private var lift: CGFloat {
        guard let doneTop, let bottom else { return 0 }
        return max(0, bottom - (doneTop - Self.gap))
    }
}

// MARK: - The busy sign

extension View {
    /// One of a few buttons while one of them works: the tapped one (`tapped`) keeps its look and shows the spinner in
    /// its label (`BusyLabel`, or a payment row's own), the others are greyed; none takes a tap until the work ends.
    func whileWorking(_ working: Bool, tapped: Bool) -> some View {
        disabled(working && !tapped).allowsHitTesting(!working)
    }
}

#if DEBUG
extension DebugLaunch {
    /// Screenshots: `-holdWork` keeps a tapped button's work waiting for a minute before it runs, so its spinner can be
    /// looked at.
    static func holdWork() async {
        guard LaunchArguments.current.contains("-holdWork") else { return }
        try? await Task.sleep(for: .seconds(60))
    }
}
#endif

// MARK: - Equal buttons side by side

/// Buttons side by side, each as wide as the widest needs (Apple's equal-width row from "Compose custom layouts with
/// SwiftUI"). Its ideal width is honest, so in a `ViewThatFits` the row is taken only when every label fits at its own
/// size; otherwise the next choice (one over the other).
struct EqualWidthRow: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let ideal = (sizes.map(\.width).max() ?? 0) * CGFloat(subviews.count) + gaps(subviews.count)
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? ideal
        return CGSize(width: width, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let width = max(0, (bounds.width - gaps(subviews.count)) / CGFloat(subviews.count))
        var x = bounds.minX
        for subview in subviews {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }

    private func gaps(_ count: Int) -> CGFloat { spacing * CGFloat(max(0, count - 1)) }
}
