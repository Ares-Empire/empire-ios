import SwiftUI

@main
struct AresusApp: App {
    init() { AppFont.register() }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
