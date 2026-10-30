import SwiftUI
import UIKit

// A swipe left on a row of a payment list (brief 44, Patrik: "like Mail", left only, no setting): the row slides and
// shows one action at its end; a tap on it does it, a full swipe past the threshold does it at once, with a tap of the
// haptics as the threshold is crossed. The lists are a `LazyVStack` in a `ScrollView`, not a `List`, so this is the
// app's own gesture: a UIKit pan (`RowSwipeRecognizer`) that begins only for a clearly sideways drag, so vertical
// scrolling never catches on it, and only to the left (a swipe right is the back swipe, `BackSwipe.swift`, also when it
// starts on a row; on an open row it closes the row, and the back swipe waits for that). One row is open at a time (the list holds which); it closes on
// scroll, on a tap anywhere on the list and when its action runs. VoiceOver: the same action by name. Reduce Motion:
// the row does not slide; the action fades in over the row's end.

/// The one action a row's swipe shows: an icon over a short word (Mail's), and its whole name for VoiceOver.
struct RowSwipeAction {
    let label: String
    let systemImage: String
    let accessibilityName: String
    let perform: () -> Void
}

/// The swipe's numbers and decisions (pure, so tests pin them).
nonisolated enum RowSwipeRule {
    /// How far an open row stands to the left: the action's width.
    static let actionWidth: CGFloat = 84
    /// Space between the row's content and the action.
    static let gap: CGFloat = 6
    /// A fling this fast (points a second) opens or closes the row whatever its distance.
    static let flingSpeed: CGFloat = 450

    /// Whether a drag that moved `dx`, `dy` (its first few points, `RowSwipeRecognizer.decision`) starts the swipe:
    /// clearly sideways (at most about 27° from level: the sideways part at least twice the vertical), and to the left,
    /// or to the right on an open row (closing it). Anything else is left to the list's scrolling and the back swipe.
    static func begins(dx: CGFloat, dy: CGFloat, isOpen: Bool) -> Bool {
        guard dx != 0, abs(dx) >= 2 * abs(dy) else { return false }
        return dx < 0 || isOpen
    }

    /// The distance of a full swipe, which does the action on release: past half the row and at least two actions.
    static func fullSwipe(width: CGFloat) -> CGFloat { max(actionWidth * 2, width * 0.55) }

    /// Where the row's content stands while dragged: from where it was (open or closed), never right of its place and
    /// never further left than its width.
    static func offset(translation: CGFloat, wasOpen: Bool, width: CGFloat) -> CGFloat {
        let start = wasOpen ? -actionWidth : 0
        return min(0, max(-max(width, actionWidth), start + translation))
    }

    /// Past the full swipe: letting go does the action (the haptic marks the moment it becomes so).
    static func isArmed(offset: CGFloat, width: CGFloat) -> Bool { -offset >= fullSwipe(width: width) }

    enum End: Equatable { case closed, open, perform }

    /// What letting go does.
    static func end(offset: CGFloat, velocity: CGFloat, width: CGFloat) -> End {
        if isArmed(offset: offset, width: width) { return .perform }
        if velocity >= flingSpeed { return .closed }
        if velocity <= -flingSpeed { return .open }
        return -offset > actionWidth / 2 ? .open : .closed
    }
}

extension View {
    /// The swipe left on this row of a list, showing `action` (nil: no swipe, as on a covered row or in the tour while it
    /// holds the screen). `open` is the list's open row (one at a time); `id` this row's. `shownAt` (screenshots only)
    /// shows the row so far left, as halfway through a swipe.
    func rowSwipe(_ action: RowSwipeAction?, id: String, open: Binding<String?>, shownAt: CGFloat? = nil) -> some View {
        modifier(RowSwipe(action: action, id: id, open: open, shownAt: shownAt))
    }

    /// A list whose rows swipe: scrolling closes the open row.
    func closesRowSwipe(_ open: Binding<String?>) -> some View {
        onScrollPhaseChange { _, phase in
            guard phase == .interacting, open.wrappedValue != nil else { return }
            withAnimation(RowSwipe.settle) { open.wrappedValue = nil }
        }
    }
}

private struct RowSwipe: ViewModifier {
    let action: RowSwipeAction?
    let id: String
    @Binding var open: String?
    let shownAt: CGFloat?
    /// The drag's sideways distance while it runs.
    @State private var drag: CGFloat?
    @State private var width: CGFloat = 0
    @State private var armed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let settle = Animation.snappy(duration: 0.3)

    private var isOpen: Bool { open == id }

    /// The content's place: following the finger, or where it rests. Reduce Motion: it never moves.
    private var offset: CGFloat {
        guard !reduceMotion else { return 0 }
        if let drag { return RowSwipeRule.offset(translation: drag, wasOpen: isOpen, width: width) }
        return isOpen ? -RowSwipeRule.actionWidth : 0
    }

    /// How wide the action is drawn: the room the content left; under Reduce Motion always its own width (it only fades).
    private var revealed: CGFloat {
        reduceMotion ? RowSwipeRule.actionWidth - RowSwipeRule.gap : max(0, -offset - RowSwipeRule.gap)
    }

    /// The action shows: room enough beside the content, or under Reduce Motion while the row is open.
    private var actionShown: Bool { reduceMotion ? isOpen : revealed > 2 }

    func body(content: Content) -> some View {
        content
            // While a row is open, a tap anywhere on the list closes it (and opens nothing).
            .overlay {
                if open != nil {
                    Color.clear.contentShape(Rectangle()).onTapGesture { close() }.accessibilityHidden(true)
                }
            }
            .offset(x: offset)
            .overlay(alignment: .trailing) { if let action { actionView(action) } }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .gesture(RowSwipePan(enabled: action != nil, isOpen: isOpen, changed: changed, ended: ended))
            .accessibilityActions {
                if let action {
                    Button(action.accessibilityName) { perform(action) }
                }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: armed) { old, new in new && !old }
            #if DEBUG
            .task(id: shownAt) {
                if let shownAt, action != nil {
                    drag = -shownAt
                    armed = RowSwipeRule.isArmed(offset: offset, width: width)
                }
            }
            #endif
    }

    private func actionView(_ action: RowSwipeAction) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button { perform(action) } label: {
            VStack(spacing: 3) {
                Image(systemName: action.systemImage).font(.system(size: 17, weight: .semibold))
                Text(verbatim: action.label).font(AppFont.text(12, weight: .semibold)).lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: RowSwipeRule.actionWidth - RowSwipeRule.gap)
            // Past the full swipe the word moves to the row's edge (Mail's), so it travels with the finger.
            .frame(width: revealed, alignment: armed ? .leading : .trailing)
            .frame(maxHeight: .infinity)
            // Mail's quiet grey action in Aresium's inks: the second ink with the wall's colour on it (at least 5.5:1
            // in light and dark; red mode holds dark).
            .foregroundStyle(Ink.background)
            .background(Ink.secondary, in: shape)
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .opacity(actionShown ? 1 : 0)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : nil, value: isOpen)
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: armed)
        .allowsHitTesting(actionShown)
        .accessibilityHidden(true)            // the row's own action carries it for VoiceOver
    }

    private func changed(_ translation: CGFloat) {
        if drag == nil, let other = open, other != id {
            withAnimation(Self.settle) { open = nil }            // one row open at a time
        }
        drag = translation
        let now = RowSwipeRule.isArmed(offset: RowSwipeRule.offset(translation: translation, wasOpen: isOpen,
                                                                    width: width), width: width)
        if now != armed { armed = now }
    }

    private func ended(_ translation: CGFloat?, _ velocity: CGFloat) {
        guard let translation else {                             // cancelled
            withAnimation(Self.settle) { drag = nil }
            armed = false
            return
        }
        let result = RowSwipeRule.end(offset: RowSwipeRule.offset(translation: translation, wasOpen: isOpen, width: width),
                                      velocity: velocity, width: width)
        armed = false
        withAnimation(reduceMotion ? nil : Self.settle) {
            drag = nil
            switch result {
            case .open: open = id
            case .closed, .perform: if open == id { open = nil }
            }
        }
        if result == .perform, let action { action.perform() }
    }

    private func perform(_ action: RowSwipeAction) {
        withAnimation(reduceMotion ? nil : Self.settle) { if open == id { open = nil } }
        action.perform()
    }

    private func close() {
        withAnimation(reduceMotion ? nil : Self.settle) { open = nil }
    }
}

/// The swipe's pan (`RowSwipeRecognizer`): UIKit's own, so the list's scrolling defers to it as to any pan inside it,
/// and it decides by itself within the first points whether this drag is its swipe; anything else fails it at once,
/// leaving the touch to the scrolling and the back swipe.
private struct RowSwipePan: UIGestureRecognizerRepresentable {
    let enabled: Bool
    let isOpen: Bool
    let changed: (CGFloat) -> Void
    /// The translation (nil when cancelled) and the sideways velocity.
    let ended: (CGFloat?, CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> RowSwipeRecognizer {
        let recognizer = RowSwipeRecognizer()
        recognizer.maximumNumberOfTouches = 1
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: RowSwipeRecognizer, context: Context) {
        recognizer.isEnabled = enabled
        recognizer.isOpen = isOpen
    }

    func handleUIGestureRecognizerAction(_ recognizer: RowSwipeRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed: changed(translation)
        case .ended: ended(translation, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed: ended(nil, 0)
        default: break
        }
    }
}

/// A one-finger pan that is only a row's swipe: once the finger has moved `decision` points (before a pan would
/// begin), it fails unless `RowSwipeRule.begins` (clearly sideways, to the left, or to the right on an open row). The
/// rule lives in the recognizer itself rather than in a delegate, so it holds whatever SwiftUI does with a
/// representable's delegate. A pan, not a plain `UIGestureRecognizer`: a plain one, tried on iOS 27.0, got the touch's
/// start but none of its moves inside the list, and never began. On an open row the back swipe waits for it, so a
/// swipe right closes the row rather than going back; on a closed row it fails at once, and the back swipe from the
/// middle goes back as on a row without it (checked with real touches on the simulator, 6 of 6 as on main).
final class RowSwipeRecognizer: UIPanGestureRecognizer {
    static let decision: CGFloat = 6
    var isOpen = false
    private var start: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if start == nil { start = touches.first?.location(in: nil) }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible, let start, let point = touches.first?.location(in: nil) {
            let dx = point.x - start.x, dy = point.y - start.y
            if hypot(dx, dy) >= Self.decision, !RowSwipeRule.begins(dx: dx, dy: dy, isOpen: isOpen) {
                state = .failed
                return
            }
        }
        super.touchesMoved(touches, with: event)
    }

    override func reset() {
        super.reset()
        start = nil
    }

    override func shouldBeRequiredToFail(by other: UIGestureRecognizer) -> Bool {
        (isOpen && isBackSwipe(other)) || super.shouldBeRequiredToFail(by: other)
    }

    private func isBackSwipe(_ other: UIGestureRecognizer) -> Bool {
        var responder: UIResponder? = view
        while let current = responder {
            if let controller = current as? UIViewController, let navigation = controller.navigationController {
                return other === navigation.interactivePopGestureRecognizer
                    || other === navigation.interactiveContentPopGestureRecognizer
            }
            responder = current.next
        }
        return false
    }
}
