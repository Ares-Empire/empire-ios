import Testing
@testable import Aresium

struct ThemeStateTests {
    @Test(arguments: [AppTheme.dark, .light])
    func bandReturnsToPreviousTheme(start: AppTheme) {
        var state = ThemeState(rememberedValue: start.rawValue)
        state.send(.band, reduceMotion: false)
        #expect(state.theme == start)
        #expect(state.transition?.source == start)
        #expect(state.transition?.target == .red)
        #expect(state.previousTheme == start)
        state.advance(to: 0.559)
        #expect(state.theme == start)
        state.advance(to: 0.56)
        #expect(state.theme == .red)
        #expect(state.isAnimating)
        state.advance(to: 1)
        #expect(!state.isAnimating)
        state.send(.band, reduceMotion: false)
        #expect(state.transition?.target == start)
        #expect(state.transition?.entering == false)
        state.advance(to: 1)
        #expect(state.theme == start)
    }

    @Test(arguments: [AppTheme.dark, .light])
    func headerXExitsRed(start: AppTheme) {
        var state = ThemeState(rememberedValue: start.rawValue)
        state.send(.band, reduceMotion: true)
        state.send(.header, reduceMotion: false)
        #expect(state.theme == .red)
        #expect(state.transition?.target == start)
        state.advance(to: 1)
        #expect(state.theme == start)
    }

    @Test func headerTogglesDarkAndLightInstantly() {
        var state = ThemeState()
        state.send(.header, reduceMotion: false)
        #expect(state.theme == .light)
        #expect(!state.isAnimating)
        state.send(.header, reduceMotion: false)
        #expect(state.theme == .dark)
        #expect(!state.isAnimating)
    }

    @Test(arguments: AppTheme.allCases)
    func restoresRememberedTheme(theme: AppTheme) {
        let state = ThemeState(rememberedValue: theme.rawValue)
        #expect(state.theme == theme)
        #expect(!state.isAnimating)
    }

    @Test func restoresRedAndItsPreviousThemeAcrossLaunches() {
        var original = ThemeState(rememberedValue: "light")
        original.send(.band, reduceMotion: true)
        var restored = ThemeState(rememberedValue: original.theme.rawValue,
                                  previousValue: original.previousTheme.rawValue)
        restored.send(.header, reduceMotion: true)
        #expect(restored.theme == .light)
    }

    @Test func invalidPreferencesFallBackToDark() {
        #expect(ThemeState(rememberedValue: "invalid").theme == .dark)
        for previous in [nil, "invalid", "red"] {
            var state = ThemeState(rememberedValue: "red", previousValue: previous)
            state.send(.header, reduceMotion: true)
            #expect(state.theme == .dark)
        }
    }

    @Test(arguments: [AppTheme.dark, .light])
    func reduceMotionSkipsOverlayInBothDirections(start: AppTheme) {
        var state = ThemeState(rememberedValue: start.rawValue)
        state.send(.band, reduceMotion: true)
        #expect(state.theme == .red)
        #expect(state.transition == nil)
        state.send(.band, reduceMotion: true)
        #expect(state.theme == start)
        #expect(state.transition == nil)
    }

    @Test(arguments: [0.0, 0.56, 0.99])
    func tapsDuringAnimationAreIgnored(progress: Double) {
        var state = ThemeState(rememberedValue: "light")
        state.send(.band, reduceMotion: false)
        state.advance(to: progress)
        let transition = state.transition
        let theme = state.theme
        state.send(.band, reduceMotion: false)
        state.send(.header, reduceMotion: true)
        #expect(state.transition == transition)
        #expect(state.theme == theme)
        #expect(state.previousTheme == .light)
        state.advance(to: 1)
        state.send(.header, reduceMotion: false)
        #expect(state.transition?.target == .light)
        // Exiting must be guarded as well, both before and after its real theme swap.
        let exit = state.transition
        state.send(.band, reduceMotion: true)
        state.advance(to: 0.56)
        state.send(.header, reduceMotion: false)
        #expect(state.transition == exit)
        #expect(state.theme == .light)
    }

    @Test func enablingReduceMotionFinishesAnActiveTransition() {
        var state = ThemeState()
        state.send(.band, reduceMotion: false)
        state.finishImmediately()
        #expect(state.theme == .red)
        #expect(!state.isAnimating)
        state.advance(to: 0.56)
        #expect(state.theme == .red)
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
