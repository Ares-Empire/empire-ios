import AppIntents
import SwiftUI

@main
struct ArestiaApp: App {
    init() { AppFont.register() }

    var body: some Scene {
        WindowGroup { AppRoot(widget: .arestia) { ContentView() } }
    }
}

/// Siri phrases and the Shortcuts app's ready-made actions. An NFC tag can run any of them through a personal
/// automation (Shortcuts → Automation → NFC), including "Toggle cooking".
struct ArestiaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartCookingIntent(),
                    phrases: ["Start cooking in \(.applicationName)", "\(.applicationName) cooking"],
                    shortTitle: LocalizedStringResource("Start cooking", table: "ArestiaShared"),
                    systemImageName: "flame")
        AppShortcut(intent: EndCookingIntent(),
                    phrases: ["End cooking in \(.applicationName)", "Done cooking in \(.applicationName)"],
                    shortTitle: LocalizedStringResource("End cooking", table: "ArestiaShared"),
                    systemImageName: "flame.fill")
        AppShortcut(intent: ToggleCookingIntent(),
                    phrases: ["Toggle cooking in \(.applicationName)"],
                    shortTitle: LocalizedStringResource("Toggle cooking", table: "ArestiaShared"),
                    systemImageName: "flame")
        AppShortcut(intent: FansOnIntent(),
                    phrases: ["Fans on in \(.applicationName)", "Turn on the fans in \(.applicationName)"],
                    shortTitle: LocalizedStringResource("Fans on", table: "ArestiaShared"),
                    systemImageName: "fan")
        AppShortcut(intent: FansOffIntent(),
                    phrases: ["Fans off in \(.applicationName)", "Turn off the fans in \(.applicationName)"],
                    shortTitle: LocalizedStringResource("Fans off", table: "ArestiaShared"),
                    systemImageName: "fan.slash")
        AppShortcut(intent: AirOutIntent(),
                    phrases: ["Air out with \(.applicationName)"],
                    shortTitle: LocalizedStringResource("Air out", table: "ArestiaShared"),
                    systemImageName: "wind")
        AppShortcut(intent: AllDownIntent(),
                    phrases: ["All blinds down with \(.applicationName)"],
                    shortTitle: LocalizedStringResource("All blinds down", table: "ArestiaShared"),
                    systemImageName: "blinds.horizontal.closed")
        AppShortcut(intent: MoveRolloIntent(),
                    phrases: ["Move a blind with \(.applicationName)"],
                    shortTitle: LocalizedStringResource("Move a blind", table: "ArestiaShared"),
                    systemImageName: "blinds.horizontal.open")
    }
}
