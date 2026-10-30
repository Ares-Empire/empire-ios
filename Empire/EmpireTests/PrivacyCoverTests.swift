import Testing
@testable import Empire

/// The app switcher cover's rule (brief 47, `Shared/Design/PrivacyCover.swift`): it covers the app for the app switcher,
/// Control Center and the background, but not behind a prompt the app asked for itself (the notification permission,
/// Face ID), which made "Aresium" flash on Patrik's phone.
@Suite(.serialized)
struct PrivacyCoverTests {
    @Test func theBackgroundIsAlwaysCovered() {
        #expect(PrivacyCoverRule.shows(at: .didEnterBackground, promptUp: false))
        #expect(PrivacyCoverRule.shows(at: .didEnterBackground, promptUp: true), "leaving the app with a prompt up")
    }

    @Test func notActiveIsCoveredExceptBehindTheAppsOwnPrompt() {
        #expect(PrivacyCoverRule.shows(at: .willDeactivate, promptUp: false), "app switcher, Control Center")
        #expect(!PrivacyCoverRule.shows(at: .willDeactivate, promptUp: true), "the app's own question")
    }

    @Test func promptsAreCountedSoTwoCanOverlap() {
        let start = ContinuousClock.now
        let later = start + SystemPrompt.afterAnswer + .milliseconds(10)
        #expect(!SystemPrompt.isUp(at: later + .seconds(10)))
        SystemPrompt.begin()
        SystemPrompt.begin()
        #expect(SystemPrompt.isUp(at: start))
        SystemPrompt.end(at: start)
        #expect(SystemPrompt.isUp(at: later), "one is still up")
        SystemPrompt.end(at: start)
        #expect(!SystemPrompt.isUp(at: later))
        SystemPrompt.end(at: start)                       // an extra end never leaves it negative
        SystemPrompt.begin()
        #expect(SystemPrompt.isUp(at: later))
        SystemPrompt.end(at: start)
        #expect(!SystemPrompt.isUp(at: later))
    }

    @Test func aPromptStillCountsAMomentAfterItsAnswer() {
        // The notification permission: iOS makes the app inactive about 0.42 s after the answer reached it.
        let answered = ContinuousClock.now
        SystemPrompt.begin()
        SystemPrompt.end(at: answered)
        #expect(SystemPrompt.isUp(at: answered + .milliseconds(420)))
        #expect(SystemPrompt.isUp(at: answered + .milliseconds(1400)))
        #expect(!SystemPrompt.isUp(at: answered + SystemPrompt.afterAnswer + .milliseconds(10)))
    }
}
