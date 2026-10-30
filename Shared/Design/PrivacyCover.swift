import os
import Synchronization
import SwiftUI
import UIKit

/// What an Empire app shows instead of its screens while it is not the active app: in the app switcher, under Control
/// Center or Notification Center, behind a system alert it did not ask for (council 2026-10-23 and 2026-10-25: balances,
/// notes and the account's email must not appear in the app switcher). Not behind a prompt the app asked for itself
/// (`SystemPrompt`, brief 47). The look is the app's launch wall with the band that ends its
/// main screen (the app's name), so the switcher shows the app's own face rather than a blank card.
struct PrivacyCover {
    let word: String
    var fill: AnyShapeStyle? = nil

    /// The app's name from its Info.plist, in the usual band (`WordmarkBand`'s default fill).
    static var app: PrivacyCover {
        PrivacyCover(word: Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "")
    }
}

/// The cover itself: the app's `LaunchBackground` colour (every app has one, light and dark) and its band.
struct PrivacyCoverView: View {
    let cover: PrivacyCover

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color("LaunchBackground")
                if let fill = cover.fill {
                    WordmarkBand(word: cover.word, width: proxy.size.width, fill: fill)
                } else {
                    WordmarkBand(word: cover.word, width: proxy.size.width)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A system prompt the app asked for itself is up: iOS's notification permission, Face ID. iOS makes the app inactive
/// while one shows, or as it goes, which is no reason to cover it: the person is answering the app's own question, over
/// the app (brief 47, Patrik's phone: "Aresium" flashed for a moment when turning on Messages or the lock's Face ID).
/// Every place that asks iOS calls `begin()` before and `end()` after (a count: two can overlap). Measured on the iOS
/// 27.0 simulator (brief 47): Face ID keeps the app inactive while it checks; the notification permission does not, but
/// iOS makes the app inactive once more for a moment about 0.42 s after the answer has reached it, so a prompt counts as
/// up until `afterAnswer` after it ended. Thread-safe, so a worker can ask.
nonisolated enum SystemPrompt {
    private struct State {
        var open = 0
        var ended: ContinuousClock.Instant?
    }

    /// How long a prompt still counts as up after its answer came (about 3.5 times the 0.42 s measured).
    static let afterAnswer: Duration = .milliseconds(1500)
    private static let state = Mutex(State())
    private static let log = Logger(subsystem: "de.ares-empire.shared", category: "cover")

    static var isUp: Bool { isUp(at: .now) }

    static func isUp(at now: ContinuousClock.Instant) -> Bool {
        state.withLock { state in
            state.open > 0 || state.ended.map { now - $0 < afterAnswer } == true
        }
    }

    static func begin() {
        state.withLock { $0.open += 1 }
        log.debug("prompt begins")
    }

    static func end(at now: ContinuousClock.Instant = .now) {
        state.withLock { state in
            state.open = max(0, state.open - 1)
            state.ended = now
        }
        log.debug("prompt ended")
    }
}

/// When the cover shows (pure, so tests pin it): as the app goes to the background, always; as it stops being active
/// (the app switcher, Control Center, Notification Center, an alert iOS shows by itself), unless a prompt the app asked
/// for is up. While such a prompt is up the app switcher finds the app already inactive and sends nothing new, so it
/// shows the app as it is behind the prompt; going on to another app or the home screen covers it.
nonisolated enum PrivacyCoverRule {
    enum Moment { case willDeactivate, didEnterBackground }

    static func shows(at moment: Moment, promptUp: Bool) -> Bool {
        switch moment {
        case .didEnterBackground: true
        case .willDeactivate: !promptUp
        }
    }
}

/// Puts the cover in a window of its own above everything the app shows (sheets and alerts included), on the app's
/// scene. Shown at once when the scene stops being active (`willDeactivate`, before iOS takes the app switcher's
/// picture) and when it goes to the background (`PrivacyCoverRule`: not behind the app's own prompts); faded out when the
/// scene is active again. Never takes touches.
/// `AppRoot` attaches it to the app's window (`WindowReference`). DEBUG: `-privacyCover` keeps it shown, for screenshots.
final class PrivacyCoverWindow {
    private let cover: PrivacyCover
    private weak var appWindow: UIWindow?
    private var coverWindow: UIWindow?
    private var observers: [NSObjectProtocol] = []
    private var pinned = false
    private static let log = Logger(subsystem: "de.ares-empire.shared", category: "cover")

    init(cover: PrivacyCover) {
        self.cover = cover
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Called whenever the app's window is known; a window it already covers changes nothing.
    func attach(to window: UIWindow?) {
        guard let window, window !== appWindow, let scene = window.windowScene else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        coverWindow?.isHidden = true
        appWindow = window

        let coverWindow = UIWindow(windowScene: scene)
        coverWindow.windowLevel = .alert + 1
        coverWindow.isUserInteractionEnabled = false
        let host = UIHostingController(rootView: PrivacyCoverView(cover: cover))
        host.view.backgroundColor = UIColor(named: "LaunchBackground")
        coverWindow.rootViewController = host
        coverWindow.isHidden = true
        self.coverWindow = coverWindow

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIScene.willDeactivateNotification, object: scene, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.show(at: .willDeactivate) }
            },
            center.addObserver(forName: UIScene.didEnterBackgroundNotification, object: scene, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.show(at: .didEnterBackground) }
            },
            center.addObserver(forName: UIScene.didActivateNotification, object: scene, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            },
        ]
        #if DEBUG
        if LaunchArguments.current.contains("-privacyCover") {
            pinned = true
            show()
        }
        #endif
    }

    private func show(at moment: PrivacyCoverRule.Moment) {
        guard PrivacyCoverRule.shows(at: moment, promptUp: SystemPrompt.isUp) else {
            Self.log.debug("cover held back: the app's own prompt is up")
            return
        }
        show()
    }

    private func show() {
        guard let coverWindow else { return }
        // The cover takes the look the app shows now (its choice, or a mode that holds one, like Aresium's red).
        coverWindow.overrideUserInterfaceStyle = appWindow?.overrideUserInterfaceStyle ?? .unspecified
        coverWindow.layer.removeAllAnimations()
        coverWindow.alpha = 1
        coverWindow.isHidden = false
        Self.log.debug("cover shown")
    }

    private func hide() {
        guard let coverWindow, !coverWindow.isHidden, !pinned else { return }
        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            coverWindow.alpha = 0
        } completion: { finished in
            if finished { coverWindow.isHidden = true }
        }
        Self.log.debug("cover hidden")
    }
}
