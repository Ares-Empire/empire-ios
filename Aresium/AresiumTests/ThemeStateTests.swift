import SwiftUI
import Testing
@testable import Aresium

struct ThemeStateTests {
    @Test(arguments: [AppTheme.dark, .light])
    func bandEntersAndLeavesRedOverTheAppearance(base: AppTheme) {
        var state = ThemeState()
        #expect(state.theme(over: base) == base)
        state.send(.band, reduceMotion: false)
        #expect(state.transition?.entering == true)
        state.advance(to: 0.559)
        #expect(state.theme(over: base) == base)
        state.advance(to: 0.56)
        #expect(state.theme(over: base) == .red)
        #expect(state.isAnimating)
        state.advance(to: 1)
        #expect(!state.isAnimating)
        state.send(.band, reduceMotion: false)
        #expect(state.transition?.entering == false)
        state.advance(to: 1)
        #expect(state.theme(over: base) == base)
    }

    @Test func headerXLeavesRed() {
        var state = ThemeState(red: true)
        state.send(.header, reduceMotion: false)
        #expect(state.red)
        #expect(state.transition?.entering == false)
        state.advance(to: 1)
        #expect(!state.red)
    }

    /// Outside red the header has no X (light and dark are Settings → Appearance, brief 42): `.header` changes nothing.
    @Test func headerOutsideRedLeavesTheStateAlone() {
        var state = ThemeState()
        state.send(.header, reduceMotion: false)
        #expect(!state.red)
        #expect(!state.isAnimating)
    }

    /// Red stays on across launches, over whichever look the appearance gives then.
    @Test func redIsRememberedAndShowsOverEitherLook() {
        let state = ThemeState(red: true)
        #expect(state.theme(over: .light) == .red)
        #expect(state.theme(over: .dark) == .red)
        #expect(!state.isAnimating)
        #expect(ThemeState().theme(over: .light) == .light)
    }

    @Test func reduceMotionSkipsOverlayInBothDirections() {
        var state = ThemeState()
        state.send(.band, reduceMotion: true)
        #expect(state.red)
        #expect(state.transition == nil)
        state.send(.band, reduceMotion: true)
        #expect(!state.red)
        #expect(state.transition == nil)
    }

    @Test(arguments: [0.0, 0.56, 0.99])
    func tapsDuringAnimationAreIgnored(progress: Double) {
        var state = ThemeState()
        state.send(.band, reduceMotion: false)
        state.advance(to: progress)
        let transition = state.transition
        let red = state.red
        state.send(.band, reduceMotion: false)
        state.send(.header, reduceMotion: true)
        #expect(state.transition == transition)
        #expect(state.red == red)
        state.advance(to: 1)
        state.send(.header, reduceMotion: false)
        #expect(state.transition?.entering == false)
        // Exiting must be guarded as well, both before and after its real swap.
        let exit = state.transition
        state.send(.band, reduceMotion: true)
        state.advance(to: 0.56)
        state.send(.header, reduceMotion: false)
        #expect(state.transition == exit)
        #expect(!state.red)
    }

    @Test func enablingReduceMotionFinishesAnActiveTransition() {
        var state = ThemeState()
        state.send(.band, reduceMotion: false)
        state.finishImmediately()
        #expect(state.red)
        #expect(!state.isAnimating)
        state.advance(to: 0.56)
        #expect(state.red)
    }

    @Test func timelineMatchesWebsiteAnchors() {
        #expect(IntroTimeline.duration == 1.5)
        #expect(abs(IntroTimeline.duration * IntroTimeline.swapAt - 0.84) < 0.000001)
        #expect(IntroTimeline.enter.map(\.offset) == [0, 0.26, 0.30, 0.345, 0.39, 0.435, 0.48, 1])
        #expect(IntroTimeline.exit.map(\.offset) == [0, 0.30, 0.345, 0.39, 0.435, 0.48, 0.54, 1])
        let hero = IntroTimeline.frame(at: 0.26, entering: true)
        #expect(hero.y == -30 && hero.scale == 1.18 && hero.opacity == 1)
        let jitter = IntroTimeline.frame(at: 0.345, entering: true)
        #expect(jitter.x == 7 && jitter.rotation == 0.5 && jitter.y == -30.6)
        let landed = IntroTimeline.frame(at: 1, entering: true)
        #expect(landed.y == 0 && landed.scale == 1 && landed.opacity == 1)
        let lifted = IntroTimeline.frame(at: 0.30, entering: false)
        #expect(lifted.y == -30 && lifted.scale == 1.18)
        let gone = IntroTimeline.frame(at: 1, entering: false)
        #expect(gone.y == 70 && gone.scale == 1.04 && gone.opacity == 0)
    }

    @Test func backgroundCoversThePageBeforeTheThemeSwap() {
        #expect(IntroTimeline.backgroundOpacity(at: 0) == 0)
        #expect(IntroTimeline.backgroundOpacity(at: 0.25) > 0.5)
        #expect(IntroTimeline.backgroundOpacity(at: 0.5) == 1)
        #expect(IntroTimeline.backgroundOpacity(at: IntroTimeline.swapAt) == 1)
        #expect(IntroTimeline.backgroundOpacity(at: 1) == 1)
    }

    @Test func landingUsesTheWebsiteBezierRatherThanLinearMotion() {
        let progress = 0.74 // halfway through the 0.48 ... 1 landing segment
        let eased = IntroTimeline.Easing.settle.value(at: 0.5)
        let pose = IntroTimeline.frame(at: progress, entering: true)
        #expect(eased > 0.5 && eased < 1)
        #expect(abs(pose.y - (-30 + 30 * eased)) < 0.00001)
    }
}
