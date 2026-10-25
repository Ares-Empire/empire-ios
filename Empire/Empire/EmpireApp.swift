import SwiftUI

@main
struct EmpireApp: App {
    init() { AppFont.register() }

    var body: some Scene {
        WindowGroup { LanguageRoot { ContentView() } }
    }
}
