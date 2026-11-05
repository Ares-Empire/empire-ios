import Foundation
import UIKit
import UserNotifications

/// The app delegate an Empire app adopts for push: `@UIApplicationDelegateAdaptor(PushAppDelegate.self) var delegate`
/// in its `App`, then `delegate.push.start(app:session:categories:)` once the session exists, and it routes
/// `delegate.push.openedURL`.
///
/// The delegate owns the app's `PushCenter` (no singleton): UIKit creates the delegate before the first scene, and the
/// app reaches the center through the adaptor. It forwards what only the application object gets: the device token,
/// the registration failure, taps on notifications, and becoming active (each foreground refreshes the registration).
/// It uses only the `application` UIKit hands it, never `UIApplication.shared`, because Shared is also compiled into
/// widget extensions.
class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let push = PushCenter()
    private var activeObserver: NSObjectProtocol?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Must be set before launching ends, or a tap that launched the app is lost.
        UNUserNotificationCenter.current().delegate = self
        push.registerForRemote = { [weak application] in application?.registerForRemoteNotifications() }
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: application, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.push.refresh() }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        push.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        push.didFailToRegister(error)
    }

    /// Banners also while the app is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler:
                                                @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    /// A tap on a notification or one of its actions (`NotificationTap` says why not the `async` form).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let url = PushCenter.url(from: response.notification.request.content.userInfo)
        NotificationTap.answer(completionHandler) { [push] in push.open(action: action, url: url) }
    }
}

/// How every app's notification delegate answers a tap: UIKit's completion handler must be called on the main thread,
/// or UIKit aborts the app. The `async` form of `userNotificationCenter(_:didReceive:)` finished on a background thread
/// and so crashed every tap (Arestemis builds up to 20, Patrik's crash reports of 2026-11-05); its compiler-made bridge
/// calls the handler wherever the method ends. So the completion-handler form, with both steps on the main actor.
nonisolated enum NotificationTap {
    static func answer(_ completionHandler: @escaping () -> Void, open: @escaping @MainActor () -> Void) {
        let done = MainThreadCompletion(call: completionHandler)
        Task { @MainActor in
            open()
            done.call()
        }
    }

    /// UIKit's handler is not marked Sendable; it is called once, on the main actor, as UIKit requires.
    private struct MainThreadCompletion: @unchecked Sendable {
        let call: () -> Void
    }
}
