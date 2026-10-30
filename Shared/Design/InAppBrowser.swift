import SafariServices
import SwiftUI
import UIKit

// Web pages inside the app (brief 41): Settings → About's Privacy and Imprint and the login screens' "Privacy · Imprint"
// open in Apple's in-app browser (`SFSafariViewController`, with its own close button) instead of leaving for Safari.
//
// Why not SwiftUI's own `openURL(_:prefersInApp:)` (iOS 26): it presents the browser from the window's root, which
// iOS refuses while a sheet is open ("Attempt to present <SFSafariViewController> … which is already presenting", iOS
// 27.0, 2026-10-30), and Settings is a sheet. Here the browser is presented from the screen the link is on: a plain view
// controller placed in that screen (`inAppBrowser(_:)`), so UIKit presents from that screen's own sheet or window.

/// Opens web pages in Apple's in-app browser over the screen marked with `inAppBrowser(_:)`.
@MainActor
final class InAppBrowser {
    /// The marked screen's place in UIKit's view controllers.
    fileprivate weak var host: UIViewController?

    /// Shows `url` inside the app. False when it cannot: not a web address, or the marked screen is not on screen (the
    /// caller then lets iOS open it).
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard Self.opensInside(url), let host, host.viewIfLoaded?.window != nil else { return false }
        host.present(SFSafariViewController(url: url), animated: true)
        return true
    }

    /// For `\.openURL` (a `Link`'s tap): web pages inside the app, anything else as iOS would.
    var openURLAction: OpenURLAction {
        OpenURLAction { [weak self] url in self?.open(url) == true ? .handled : .systemAction }
    }

    /// Only web pages: the in-app browser shows nothing else.
    nonisolated static func opensInside(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "")
    }
}

extension View {
    /// The screen `browser` presents its pages over: this view's own sheet or window.
    func inAppBrowser(_ browser: InAppBrowser) -> some View {
        background {
            InAppBrowserHost(browser: browser).frame(width: 0, height: 0).accessibilityHidden(true)
        }
    }
}

private struct InAppBrowserHost: UIViewControllerRepresentable {
    let browser: InAppBrowser

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isUserInteractionEnabled = false
        browser.host = controller
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) { browser.host = controller }
}
