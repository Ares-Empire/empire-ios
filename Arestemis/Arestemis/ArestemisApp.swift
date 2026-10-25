import SwiftUI

@main
struct ArestemisApp: App {
    /// Push notifications (Shared/Push): the delegate owns the app's PushCenter.
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var delegate

    init() { AppFont.register() }

    var body: some Scene {
        WindowGroup { AppRoot { ContentView(push: delegate.push) } }
    }
}
