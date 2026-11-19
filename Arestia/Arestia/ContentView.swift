import SwiftUI

/// Arestia: the flat (Patrik's own service flatd on the home network) on the iPhone. No Ares account (Patrik,
/// 2026-11-19: "no account needed, just me"): without flatd's key the app shows the connect screen, with it two tabs,
/// Home and the 3D flat, and Settings behind the gear. Links: `arestia://home`, `arestia://flat` (never one with the
/// key: flatd's QR code is scanned inside the app).
///
/// DEBUG launch arguments: `-flatd <url> -flatdToken <key>` (connect to a fake flatd without the screen, e.g.
/// `scripts/fake-flatd.py`; never the real one), `-flatdService <name>` (with them: as found over Bonjour),
/// `-forgetFlatd` (start without a key), `-tab home|flat`, `-openSheet settings|connect`, `-scrollToEnd`,
/// `-scrollTo blinds|automations`, plus the shared ones (`-appearance`, `-openLanguage`, …).
struct ContentView: View {
    @State private var store: FlatStore
    @State private var navigation: ArestiaNavigation
    /// Settings needs a session for its contact form; Arestia never signs in (`EmpireAppIdentity.arestia`).
    @State private var session = EmpireSession(app: .arestia, restoreOnLaunch: false)
    private let follows: Bool
    @Environment(\.scenePhase) private var scenePhase

    init(arguments: [String] = LaunchArguments.current) {
        let connection = FlatdConnection.live
        #if DEBUG
        // The tests use the app as their host: it must not reach for flatd then.
        let testing = NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        DebugConnection.apply(arguments: arguments, to: connection)
        follows = !testing
        #else
        follows = true
        #endif
        _store = State(initialValue: FlatStore(connection: connection))
        _navigation = State(initialValue: ArestiaNavigation.launched(arguments: arguments))
    }

    var body: some View {
        Group {
            if store.link == .notSetUp {
                ConnectScreen(store: store)
            } else {
                tabs
            }
        }
        .task { if follows { store.start() } }
        // A language switch builds the app anew with a new store: this one stops following (Codex's review, 2026-11-19).
        .onDisappear { store.stop() }
        .onChange(of: scenePhase) { _, phase in
            guard follows else { return }
            switch phase {
            case .active: store.start()
            case .background: store.stop()
            default: break
            }
        }
        .onOpenURL { url in navigation.open(url) }
        .sheet(item: $navigation.sheet) { sheet in
            switch sheet {
            case .settings:
                SettingsScreen(app: SettingsApp(name: "Arestia", accent: .arestia), session: session, logOut: {}) {
                    ConnectionSection(store: store)
                    FlatViewSection()
                }
            case let .connect(code):
                ConnectScreen(store: store, code: code, closable: true) { navigation.tab = .home }
            }
        }
    }

    private var tabs: some View {
        TabView(selection: $navigation.tab) {
            Tab(value: ArestiaNavigation.Tab.home) {
                HomeScreen(store: store, openSettings: { navigation.sheet = .settings },
                           reconnect: { navigation.sheet = .connect(nil) })
                    .tint(Ink.primary)
            } label: {
                Label { Text("Home") } icon: { Image(systemName: "house") }
            }
            Tab(value: ArestiaNavigation.Tab.flat) {
                FlatScreen(store: store, isShown: navigation.tab == .flat)
            } label: {
                Label { Text("Flat") } icon: { Image(systemName: "cube") }
            }
        }
        .tint(AppAccent.arestia.color)
    }
}

/// Where the app is: the tab, and the sheet over it.
@MainActor @Observable
final class ArestiaNavigation {
    enum Tab: Hashable { case home, flat }

    enum Sheet: Identifiable, Equatable {
        case settings
        case connect(PairingCode?)

        var id: String {
            switch self {
            case .settings: "settings"
            case .connect: "connect"
            }
        }
    }

    var tab: Tab = .home
    var sheet: Sheet?

    /// `arestia://home`, `arestia://flat`.
    func open(_ url: URL) {
        guard url.scheme == "arestia" else { return }
        switch url.host() {
        case "flat":
            sheet = nil
            tab = .flat
        default:
            sheet = nil
            tab = .home
        }
    }

    static func launched(arguments: [String]) -> ArestiaNavigation {
        let navigation = ArestiaNavigation()
        #if DEBUG
        if LaunchArguments.value("-tab") == "flat" { navigation.tab = .flat }
        switch LaunchArguments.value("-openSheet") {
        case "settings": navigation.sheet = .settings
        case "connect": navigation.sheet = .connect(nil)
        default: break
        }
        #endif
        return navigation
    }
}

#if DEBUG
/// Screenshots and the simulator: point the app at a fake flatd from the launch arguments, never at the real one.
enum DebugConnection {
    static func apply(arguments: [String], to connection: FlatdConnection) {
        if arguments.contains("-forgetFlatd") { try? connection.forget() }
        guard let index = arguments.firstIndex(of: "-flatd"), arguments.indices.contains(index + 1),
              let url = PairingCode.serviceURL(arguments[index + 1]) else { return }
        let service = arguments.firstIndex(of: "-flatdService").flatMap {
            arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
        }
        guard let tokenIndex = arguments.firstIndex(of: "-flatdToken"), arguments.indices.contains(tokenIndex + 1) else {
            return
        }
        try? connection.save(FlatdPairing(link: FlatdLink(baseURL: url, serviceName: service),
                                          token: arguments[tokenIndex + 1]))
    }
}
#endif
