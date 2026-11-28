import SwiftUI

/// Arestia: the flat (the owner's own service flatd on the home network) on the iPhone. No Ares account (owner, 2026-11-19)
/// ("no account needed, just me"): without flatd's key the app shows the connect screen, with it two tabs,
/// Home and the 3D flat, and Settings behind the gear. Links: `arestia://home`, `arestia://flat` (never one with the
/// key: flatd's QR code is scanned inside the app).
///
/// DEBUG launch arguments: `-flatdPairing <code>` (pair with a fake flatd without the screen: the JSON pairing code
/// `scripts/fake-flatd.py` prints; never the real one),
/// `-forgetFlatd` (start without a key), `-tab home|flat`, `-openSheet settings|connect`, `-connectCode <code>` (the
/// connect sheet with a code, as scanned; another flat's is refused), `-scrollToEnd`, `-scrollTo lights|blinds`,
/// `-renameDevice <id>` (a device's name open for editing on Home; `-renameText <text>` types into it), plus the shared
/// ones (`-appearance`, `-openLanguage`, …).
struct ContentView: View {
    /// The flat paired now and its store; Forget or a first pairing make a new store, and with it new screens.
    @State private var session: FlatSession
    @State private var navigation: ArestiaNavigation
    /// Settings needs a session for its contact form; Arestia never signs in (`EmpireAppIdentity.arestia`).
    @State private var account = EmpireSession(app: .arestia, restoreOnLaunch: false)
    private let follows: Bool

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
        _session = State(initialValue: FlatSession(connection: connection))
        _navigation = State(initialValue: ArestiaNavigation.launched(arguments: arguments))
    }

    var body: some View {
        Group {
            if let store = session.store {
                // A new store (Forget, a first pairing) gets new screens: nothing of the old one's stays on screen.
                FlatRoot(store: store, session: session, navigation: navigation, account: account, follows: follows)
                    .id(session.generation)
            } else {
                // The Keychain could not be read yet (the session reads it again by itself).
                ZStack {
                    ProvinceWall(accent: .arestia)
                    ProgressView().tint(Ink.secondary)
                }
            }
        }
        .onOpenURL { url in navigation.open(url) }
        .onChange(of: session.generation) { navigation.reset() }
        // A language switch builds the app anew with a session of its own: this one's store retires, so none of its
        // work goes on next to the new one's (Codex's review, round 6).
        .onDisappear { session.end() }
    }
}

/// The screens for one store: the connect screen while it has no pairing, else the two tabs; Settings and the connect
/// sheet over them. Made anew with every store (`ContentView`).
private struct FlatRoot: View {
    let store: FlatStore
    let session: FlatSession
    @Bindable var navigation: ArestiaNavigation
    let account: EmpireSession
    let follows: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.pairingID == nil {
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
        .sheet(item: $navigation.sheet) { sheet in
            switch sheet {
            case .settings:
                SettingsScreen(app: SettingsApp(name: "Arestia", accent: .arestia), session: account, logOut: {}) {
                    ConnectionSection(store: store, session: session)
                    FlatViewSection()
                    #if DEBUG && ARESTIA_GATE
                    GateTimingSection()
                    #endif
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

    /// Back to the start: a new store (Forget, a first pairing) begins at Home with nothing over it.
    func reset() {
        sheet = nil
        tab = .home
    }

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
        // A fake flatd's code handed to the connect sheet, as a scan would (another identity waits for Connect).
        if let text = LaunchArguments.value("-connectCode"), let code = PairingCode.parse(text) {
            navigation.sheet = .connect(code)
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
        if let index = arguments.firstIndex(of: "-flatdPairing"), arguments.indices.contains(index + 1),
           let code = PairingCode.parse(arguments[index + 1]), let url = code.baseURL {
            // The same fake flatd keeps its pairing identity across launches, so its controls keep their choices.
            let same = connection.pairing.flatMap { $0.pin == code.pin ? $0.id : nil }
            try? connection.save(FlatdPairing(baseURL: url, token: code.token, pin: code.pin, id: same ?? UUID()))
        }
        if arguments.contains("-deadFlatdHome"), let saved = connection.pairing {
            let dead = URL(string: "https://192.0.2.1:8788")!
            connection.move(saved, to: FlatdClient(saved, at: dead))
        }
    }
}
#endif
