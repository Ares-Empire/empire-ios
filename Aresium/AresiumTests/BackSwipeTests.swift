import SwiftUI
import Testing
import UIKit
@testable import Aresium

/// The system's back swipe on a stack whose screens hide the navigation bar (brief 38, `Shared/Design/BackSwipe.swift`):
/// when it begins, that it is the navigation controller's own recognizers, that a pop shortens the bound path as the
/// header's arrow does, and that the tour turns it off while it holds the screen.
@MainActor @Suite(.serialized)
struct BackSwipeTests {
    // MARK: the rule

    @Test func aMarkedScreenBeginsOnlyWithAScreenToGoBackTo() {
        var asked = false
        let system = { asked = true; return false }
        #expect(BackSwipeRule.begins(screens: 2, transitioning: false, screenAllows: true, system: system))
        #expect(BackSwipeRule.begins(screens: 4, transitioning: false, screenAllows: true, system: system))
        #expect(!BackSwipeRule.begins(screens: 1, transitioning: false, screenAllows: true, system: system),
                "the root alone: nothing to go back to")
        #expect(!BackSwipeRule.begins(screens: 0, transitioning: false, screenAllows: true, system: system))
        #expect(!BackSwipeRule.begins(screens: 2, transitioning: true, screenAllows: true, system: system),
                "not while a push or pop is under way")
        #expect(!asked, "a marked screen decides without the system")
    }

    @Test func aScreenCanTurnItOff() {
        #expect(!BackSwipeRule.begins(screens: 2, transitioning: false, screenAllows: false, system: { true }),
                "off on this screen, even where the system would begin")
    }

    @Test func aScreenWithoutTheMarkGetsTheSystemsAnswer() {
        #expect(BackSwipeRule.begins(screens: 2, transitioning: false, screenAllows: nil, system: { true }))
        #expect(!BackSwipeRule.begins(screens: 2, transitioning: false, screenAllows: nil, system: { false }))
        #expect(!BackSwipeRule.begins(screens: 1, transitioning: false, screenAllows: nil, system: { true }),
                "never on the root alone, whatever the system says")
        #expect(!BackSwipeRule.begins(screens: 3, transitioning: true, screenAllows: nil, system: { true }))
    }

    @Test func theStandInPassesOnAllButTheSystemsPrivateReceiveFilters() {
        // The public questions go to the system's delegate.
        #expect(BackSwipeRule.passesOn("gestureRecognizer:shouldReceiveTouch:"))
        #expect(BackSwipeRule.passesOn("gestureRecognizer:shouldReceiveEvent:"))
        #expect(BackSwipeRule.passesOn("gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:"))
        #expect(BackSwipeRule.passesOn("gestureRecognizer:shouldRequireFailureOfGestureRecognizer:"))
        // Its private rules about which gesture waits for which too; only its private receive filter (where a hidden
        // bar is refused, iOS 27.0) is not asked.
        #expect(BackSwipeRule.passesOn("_gestureRecognizer:shouldRequireFailureOfGestureRecognizer:"))
        #expect(BackSwipeRule.passesOn("_gestureRecognizer:shouldBeRequiredToFailByGestureRecognizer:"))
        #expect(!BackSwipeRule.passesOn("_gestureRecognizer:shouldReceiveEvent:"))
    }

    // MARK: on a real navigation stack

    @Test func theNavigationControllersOwnRecognizersBeginOnAMarkedScreen() async throws {
        let probe = Probe()
        let shown = try await Shown(probe)
        defer { shown.close() }
        probe.path = [1]
        let navigation = try await shown.navigation(screens: 2)
        #expect(navigation.isNavigationBarHidden, "the screens hide the bar, as the dashboard's do")
        let recognizers = try Self.recognizers(of: navigation)
        for recognizer in recognizers {
            #expect(recognizer.delegate is BackSwipeDelegate, "the stand-in answers for \(type(of: recognizer))")
            #expect(Self.begins(recognizer), "begins on a pushed screen")
        }

        probe.enabled = false                                  // the screen turns it off (the tour holds the screen)
        await shown.markUpdated(enabled: false)
        for recognizer in recognizers { #expect(!Self.begins(recognizer), "off while the screen says so") }
        probe.enabled = true
        await shown.markUpdated(enabled: true)
        for recognizer in recognizers { #expect(Self.begins(recognizer)) }

        probe.path = [1, 100]                                  // an unmarked screen on top: the system's own delegate
        _ = try await shown.navigation(screens: 3)
        for recognizer in recognizers { #expect(!(recognizer.delegate is BackSwipeDelegate)) }
        probe.path = [1]                                       // the marked one on top again
        _ = try await shown.navigation(screens: 2)
        for recognizer in recognizers {
            #expect(recognizer.delegate is BackSwipeDelegate)
            #expect(Self.begins(recognizer))
        }

        probe.path = []                                        // the root alone: the system's own delegate again
        _ = try await shown.navigation(screens: 1)
        for recognizer in recognizers { #expect(!(recognizer.delegate is BackSwipeDelegate), "the root is untouched") }
    }

    @Test func aPopShortensThePathAsTheArrowDoes() async throws {
        let probe = Probe()
        let shown = try await Shown(probe)
        defer { shown.close() }
        probe.path = [1, 2]
        let navigation = try await shown.navigation(screens: 3)
        #expect(Self.begins(try Self.recognizers(of: navigation)[0]))
        // The swipe ends in the navigation controller's own pop, which SwiftUI writes back to the path.
        navigation.popViewController(animated: false)
        await waitForState { probe.path == [1] }
        #expect(probe.path == [1], "the last screen is gone, as with the header's arrow")
    }

    @Test func aStackWithoutTheMarkIsUntouched() async throws {
        let probe = Probe()
        let shown = try await Shown(probe)
        defer { shown.close() }
        probe.path = [100]
        let navigation = try await shown.navigation(screens: 2)
        for recognizer in try Self.recognizers(of: navigation) {
            #expect(!(recognizer.delegate is BackSwipeDelegate), "the system's own delegate stays")
        }
    }

    // MARK: the tour

    @Test func theTourTurnsItOffWhileItHoldsTheScreen() async throws {
        let parent = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "build/38-test-tours/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 12))!
        let tour = TourModel { try await TourWorld.make(in: parent, now: now, makeEngine: { try PhoneTest.engine() }) }
        await tour.start()
        defer { tour.end() }
        let world = try #require(tour.world)
        let groceries = try #require(world.firstCategory)
        #expect(!tour.holdsTheScreen, "the welcome points at nothing")

        tour.next()                                            // income: the whole page takes taps
        #expect(tour.step == .income)
        var place = tour.place
        place.path = [world.dashboard.route(category: groceries, side: .expenses, current: true)]
        tour.update(place)                                     // a category opened on the side
        #expect(!tour.holdsTheScreen, "the arrow takes taps, so the swipe is on")
        place = tour.place
        place.path.removeLast()                                // the swipe (or the arrow) back
        tour.update(place)
        #expect(tour.place.path.isEmpty && tour.step == .income, "back on the start screen, the step unchanged")

        while tour.step != .payment { tour.next() }            // a month's payments, one pointed at
        #expect(tour.place.path.last?.month != nil)
        #expect(tour.target != nil)
        #expect(tour.holdsTheScreen, "the veil keeps taps off the arrow, so the swipe is off")
        while tour.step != .categories { tour.next() }         // the gear pointed at, the list still there
        #expect(!tour.place.path.isEmpty)
        #expect(tour.holdsTheScreen)
        while tour.step != .done { tour.next() }
        #expect(!tour.holdsTheScreen)
    }

    // MARK: helpers

    private static func recognizers(of navigation: UINavigationController) throws -> [UIGestureRecognizer] {
        [try #require(navigation.interactivePopGestureRecognizer),
         try #require(navigation.interactiveContentPopGestureRecognizer)]
    }

    private static func begins(_ recognizer: UIGestureRecognizer) -> Bool {
        recognizer.delegate?.gestureRecognizerShouldBegin?(recognizer) ?? true
    }
}

@MainActor @Observable
private final class Probe {
    var path: [Int] = []
    var enabled = true
}

/// A stack like the dashboard's: every screen hides the bar; the pushed ones carry the mark, except those numbered 100
/// and above.
private struct ProbeStack: View {
    @Bindable var probe: Probe

    var body: some View {
        NavigationStack(path: $probe.path) {
            Text(verbatim: "Root").toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Int.self) { number in
                    if number < 100 {
                        Text(verbatim: "Screen \(number)").toolbar(.hidden, for: .navigationBar).backSwipe(probe.enabled)
                    } else {
                        Text(verbatim: "Screen \(number)").toolbar(.hidden, for: .navigationBar)
                    }
                }
        }
    }
}

/// The probe stack in a window of its own on the test host's scene.
@MainActor
private final class Shown {
    let window: UIWindow
    let probe: Probe

    init(_ probe: Probe) async throws {
        self.probe = probe
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: ProbeStack(probe: probe))
        window.isHidden = false
        await waitForViewState { Self.find(in: self.window.rootViewController) != nil }
    }

    /// The stack's navigation controller once it holds `screens` and no push or pop is under way.
    func navigation(screens: Int) async throws -> UINavigationController {
        await waitForViewState {
            guard let navigation = Self.find(in: self.window.rootViewController),
                  navigation.viewControllers.count == screens, navigation.transitionCoordinator == nil else { return false }
            let marked = self.probe.path.last.map { $0 < 100 } ?? false
            let delegates = [navigation.interactivePopGestureRecognizer, navigation.interactiveContentPopGestureRecognizer]
                .compactMap { $0 }.map { $0.delegate is BackSwipeDelegate }
            return !delegates.isEmpty && delegates.allSatisfy { $0 == marked }
        }
        return try #require(Self.find(in: window.rootViewController))
    }

    func markUpdated(enabled: Bool) async {
        await waitForViewState {
            guard let top = Self.find(in: self.window.rootViewController)?.topViewController else { return false }
            return Self.marks(in: top.view).contains { $0.screen === top && $0.enabled == enabled }
        }
    }

    private static func marks(in view: UIView) -> [BackSwipeMarkView] {
        (view as? BackSwipeMarkView).map { [$0] } ?? view.subviews.flatMap { marks(in: $0) }
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
    }

    private static func find(in controller: UIViewController?) -> UINavigationController? {
        guard let controller else { return nil }
        if let navigation = controller as? UINavigationController { return navigation }
        for child in controller.children { if let found = find(in: child) { return found } }
        return nil
    }
}
