import SwiftUI

@main
struct AresusApp: App {
    /// Push notifications (Shared/Push): the delegate owns the app's PushCenter.
    @UIApplicationDelegateAdaptor(AresusAppDelegate.self) private var delegate

    init() { AppFont.register() }

    var body: some Scene {
        WindowGroup { AppRoot(widget: .aresus) { ContentView(push: delegate.push) } }
    }
}
