import SwiftUI
import UIKit
import os

// The system's back swipe on a NavigationStack whose screens hide the navigation bar and draw a header of their own
// (Aresium's dashboard, brief 38). UIKit's navigation controller refuses its interactive pop while its bar is hidden,
// so on such a stack only the header's own back arrow went back.
//
// A pushed screen marked `.backSwipe(_:)` gets the system's own swipe back: the edge swipe
// (`interactivePopGestureRecognizer`) and iOS 26's swipe from anywhere in the content
// (`interactiveContentPopGestureRecognizer`), with the system's animation and its interactive cancel.
//
// How: while a marked screen is on top, a stand-in takes the place of the two recognizers' own delegate. It decides
// whether the swipe begins (`BackSwipeRule`) and passes every other question to the system's delegate, except the
// system's private filter for incoming touches, which is where a hidden bar is refused (measured on iOS 27.0, 2026-10-30:
// with it passed on no touch reached the recognizers; without it the system's own public answers allow the swipe). While
// an unmarked screen is on top (the root, or a screen of another kind), the system's own delegate is back in place, so
// that screen behaves exactly as without this file. Nothing global: only a navigation controller that shows a marked
// screen is touched; sheets, the share sheet and every other stack are not. If a later iOS refuses the swipe somewhere
// else, the swipe stays off and the header's arrow still works.

extension View {
    /// Keeps the system's back swipe on this pushed screen while `enabled`, though its stack hides the navigation bar.
    /// Put it on the screen a `navigationDestination` shows (the root has nothing to go back to). The swipe pops the
    /// screen as `NavigationStack`'s own back button would: a bound path loses its last element. `false` turns the swipe
    /// off on this screen (its header shows no back arrow, or leaving must wait), whatever the bar.
    func backSwipe(_ enabled: Bool = true) -> some View {
        background { BackSwipeMark(enabled: enabled).frame(width: 0, height: 0).accessibilityHidden(true) }
    }
}

/// Whether a pop recognizer begins while the stand-in answers (pure, so tests pin it).
nonisolated enum BackSwipeRule {
    /// - Parameters:
    ///   - screens: the screens on the stack; 1 is the root alone, with nothing to go back to.
    ///   - transitioning: a push or pop is still under way.
    ///   - screenAllows: the top screen's mark (`.backSwipe(_:)`); nil when it has none.
    ///   - system: the system's own answer, asked only for a screen without the mark.
    static func begins(screens: Int, transitioning: Bool, screenAllows: Bool?, system: () -> Bool) -> Bool {
        guard screens > 1, !transitioning else { return false }
        return screenAllows ?? system()
    }

    /// Whether the stand-in passes a delegate question on to the system's delegate: every one but the system's private
    /// filters for incoming touches and events (selectors starting with "_" that ask whether to receive), which refuse
    /// every touch while the bar is hidden. The public `gestureRecognizer(_:shouldReceive:)` questions still go to the
    /// system, and so do its private rules about which gestures wait for which.
    static func passesOn(_ selector: String) -> Bool {
        !(selector.hasPrefix("_") && selector.contains("shouldReceive"))
    }
}

private struct BackSwipeMark: UIViewRepresentable {
    let enabled: Bool

    func makeUIView(context: Context) -> BackSwipeMarkView { BackSwipeMarkView() }
    func updateUIView(_ view: BackSwipeMarkView, context: Context) { view.enabled = enabled }
}

/// The mark in a screen's view: it finds the navigation controller showing the screen and tells that controller's
/// `BackSwipeStack` when it comes and goes; the stack asks it at the start of each swipe.
final class BackSwipeMarkView: UIView {
    var enabled = true
    /// The screen the mark is on: the view controller the navigation controller holds for it.
    private(set) weak var screen: UIViewController?
    private weak var stack: BackSwipeStack?

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // The screen shows (pushed, or back on top) or goes (popped, or covered by the next one).
        if window != nil, let (navigation, screen) = Self.screen(above: self) {
            self.screen = screen
            stack = BackSwipeStack.of(navigation)
        }
        stack?.marksChanged(self)
    }

    /// The first view controller up the responder chain that a navigation controller holds, and that controller.
    private static func screen(above view: UIView) -> (UINavigationController, UIViewController)? {
        var responder = view.next
        while let current = responder {
            if let controller = current as? UIViewController, let navigation = controller.parent as? UINavigationController {
                return (navigation, controller)
            }
            responder = current.next
        }
        return nil
    }
}

/// One per navigation controller that has shown a marked screen, kept on that controller: it puts the stand-ins in
/// place while a marked screen is on top and answers their "should begin".
final class BackSwipeStack {
    private weak var navigation: UINavigationController?
    private let marks = NSHashTable<BackSwipeMarkView>.weakObjects()
    /// One stand-in per pop recognizer (a recognizer holds its delegate weakly).
    private var standIns: [BackSwipeDelegate] = []
    private var waitsForTransition = false
    private static var key: UInt8 = 0
    private static let log = Logger(subsystem: "de.ares-empire.shared", category: "backSwipe")

    private init(navigation: UINavigationController) {
        self.navigation = navigation
        standIns = [navigation.interactivePopGestureRecognizer, navigation.interactiveContentPopGestureRecognizer]
            .compactMap { $0 }
            .map { BackSwipeDelegate(recognizer: $0, stack: self) }
    }

    /// The navigation controller's stack, made on first use.
    static func of(_ navigation: UINavigationController) -> BackSwipeStack {
        if let stack = objc_getAssociatedObject(navigation, &key) as? BackSwipeStack { return stack }
        let stack = BackSwipeStack(navigation: navigation)
        objc_setAssociatedObject(navigation, &key, stack, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return stack
    }

    func marksChanged(_ mark: BackSwipeMarkView) {
        if mark.window == nil { marks.remove(mark) } else { marks.add(mark) }
        update()
    }

    /// The stand-ins while a marked screen is on top, the system's own delegates otherwise. Never during a push or pop
    /// (a swipe is one): once it has ended, finished or cancelled.
    private func update() {
        guard let navigation else { return }
        if let coordinator = navigation.transitionCoordinator {
            guard !waitsForTransition else { return }
            waitsForTransition = true
            let queued = coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                self?.waitsForTransition = false
                self?.update()
            }
            if !queued {
                DispatchQueue.main.async { [weak self] in
                    self?.waitsForTransition = false
                    self?.update()
                }
            }
            return
        }
        let marked = mark(on: navigation.topViewController) != nil
        for standIn in standIns { marked ? standIn.standIn() : standIn.stepAside() }
        Self.log.debug("\(marked ? "standing in" : "the system's own", privacy: .public) on \(navigation.viewControllers.count, privacy: .public) screens")
    }

    private func mark(on screen: UIViewController?) -> BackSwipeMarkView? {
        guard let screen else { return nil }
        return marks.allObjects.first { $0.screen === screen && $0.window != nil }
    }

    /// The answer for the screen on top: its mark's, or the system's when it has none.
    func begins(system: () -> Bool) -> Bool {
        guard let navigation else { return false }
        return BackSwipeRule.begins(screens: navigation.viewControllers.count,
                                    transitioning: navigation.transitionCoordinator != nil,
                                    screenAllows: mark(on: navigation.topViewController)?.enabled, system: system)
    }
}

/// Stands in for a pop recognizer's own delegate: answers "should begin" through the stack and passes the other
/// questions to the system's delegate (`BackSwipeRule.passesOn`).
final class BackSwipeDelegate: NSObject, UIGestureRecognizerDelegate {
    private weak var recognizer: UIGestureRecognizer?
    private weak var stack: BackSwipeStack?
    /// The recognizer's own delegate (the navigation controller keeps it).
    nonisolated(unsafe) private weak var system: (any UIGestureRecognizerDelegate)?

    init(recognizer: UIGestureRecognizer, stack: BackSwipeStack) {
        self.recognizer = recognizer
        self.stack = stack
    }

    /// Takes the recognizer's delegate's place (again, if UIKit has set its own since).
    func standIn() {
        guard let recognizer, recognizer.delegate !== self else { return }
        system = recognizer.delegate
        recognizer.delegate = self
    }

    /// Gives the place back to the system's delegate.
    func stepAside() {
        guard let recognizer, recognizer.delegate === self, let system else { return }
        recognizer.delegate = system
    }

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        let system = { [weak self] () -> Bool in
            guard let own = self?.system else { return false }
            return own.gestureRecognizerShouldBegin?(recognizer) ?? true
        }
        return stack?.begins(system: system) ?? false
    }

    nonisolated override func responds(to selector: Selector!) -> Bool {
        if super.responds(to: selector) { return true }
        guard BackSwipeRule.passesOn(NSStringFromSelector(selector)) else { return false }
        return system?.responds(to: selector) ?? false
    }

    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        if BackSwipeRule.passesOn(NSStringFromSelector(selector)), let system, system.responds(to: selector) {
            return system
        }
        return super.forwardingTarget(for: selector)
    }
}
