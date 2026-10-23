import SwiftUI

@main
struct AresiumApp: App {
    init() { AppFont.register() }
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
