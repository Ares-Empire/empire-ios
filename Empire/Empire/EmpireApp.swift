import SwiftUI

@main
struct EmpireApp: App {
    /// Push notifications (Shared/Push): the delegate owns the app's PushCenter.
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var delegate

    init() { AppFont.register() }

    var body: some Scene {
        WindowGroup {
            // The app switcher shows the hub's own band, in gold.
            AppRoot(cover: PrivacyCover(word: "THE EMPIRE", fill: AnyShapeStyle(EmpireStyle.goldText))) {
                ContentView(push: delegate.push)
            }
        }
    }
}
