import SwiftUI

@main
struct ArestotelesApp: App {
    init() { AppFont.register() }

    var body: some Scene {
        WindowGroup { AppRoot { ContentView() } }
    }
}
