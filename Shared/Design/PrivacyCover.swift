import os
import SwiftUI
import UIKit

/// What an Empire app shows instead of its screens while it is not the active app: in the app switcher, under Control
/// Center or Notification Center, behind a system alert (council 2026-10-23 and 2026-10-25: balances, notes and the
/// account's email must not appear in the app switcher). The look is the app's launch wall with the band that ends its
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

/// Puts the cover in a window of its own above everything the app shows (sheets and alerts included), on the app's
/// scene. Shown at once when the scene stops being active (`willDeactivate`, before iOS takes the app switcher's
/// picture) and when it goes to the background; faded out when the scene is active again. Never takes touches.
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
                MainActor.assumeIsolated { self?.show() }
            },
            center.addObserver(forName: UIScene.didEnterBackgroundNotification, object: scene, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.show() }
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
