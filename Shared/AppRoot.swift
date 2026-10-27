import Foundation
import Synchronization
import SwiftUI
import UIKit

/// Every app checks the marker synchronously before starting its existing foreground work.
private struct EmpireForeground: ViewModifier {
    let session: EmpireSession
    let action: @MainActor () async -> Void
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            session.followMarker()
            Task { await action() }
        }
    }
}

extension View {
    func onEmpireForeground(session: EmpireSession, perform action: @escaping @MainActor () async -> Void) -> some View {
        modifier(EmpireForeground(session: session, action: action))
    }
}

/// Every app's root, inside its `WindowGroup`: `AppRoot { ContentView(…) }`. It applies the app's two settings that
/// reach every screen:
/// - **Appearance** (Settings → Appearance): like the iPhone, light or dark, for the whole window and its sheets; the
///   shared colours follow (`Ink`, `AppAccent`). It switches at once, open sheets with it. A screen can hold the
///   window in one look for a while with `holdsColorScheme(_:)` (Aresium's red mode is dark). `\.appearanceScheme`
///   tells screens the look the app shows outside such a mode (the choice, or the iPhone's own look).
///   The look is set on the window itself (UIKit's `overrideUserInterfaceStyle`), which every sheet and alert follows.
///   Not SwiftUI's `preferredColorScheme`: it fixes a sheet's look when the sheet opens and keeps it, so a sheet open
///   while the look changes (Settings → Appearance itself) stayed in the old one (seen 2026-10-25). Screens never
///   call `preferredColorScheme`.
/// - **Language**: it shows the app in the language it shows now and, when Settings → Language switches it, restarts
///   the app inside itself: the choice is saved where iOS keeps the app's language, every sheet and alert is closed,
///   then the whole view tree is built again in the new language, as at a launch. The main screen comes back, the
///   stores load again (the servers answer in the new language), the session restores the login, and push registers
///   the device with the new language (`PushCenter.start`). The app never quits itself (Apple asks apps not to).
struct AppRoot<Content: View>: View {
    private let setting: LanguageSetting
    private let widget: WidgetLanguage?
    private let content: () -> Content
    @State private var language = AppLanguage.current
    @State private var window: WindowReference
    @AppStorage(Appearance.key) private var appearance = Appearance.iPhone.rawValue
    @State private var held: ColorScheme?
    /// The iPhone's own look; nil until the window is shown.
    @State private var iPhoneScheme: ColorScheme?
    @Environment(\.colorScheme) private var windowScheme
    @Environment(\.scenePhase) private var scenePhase

    /// - Parameters:
    ///   - widget: where the app's widget reads the app's choice; nil for apps without a widget.
    ///   - cover: what the app switcher shows instead of the app's screens (`PrivacyCover`); by default the app's name.
    init(setting: LanguageSetting = .standard, widget: WidgetLanguage? = nil, cover: PrivacyCover = .app,
         @ViewBuilder content: @escaping () -> Content) {
        self.setting = setting
        self.widget = widget
        self.content = content
        _window = State(initialValue: WindowReference(cover: cover))
    }

    var body: some View {
        let chosen = Appearance(saved: appearance).colorScheme
        content()
            .id(language)                                       // a new language: every view and its state anew
            .environment(\.locale, language.locale)            // SwiftUI's own lookups (Text, Button, …) and formats
            .environment(\.switchLanguage, SwitchLanguageAction(run: switchLanguage))
            .environment(\.appearanceScheme, chosen ?? iPhoneScheme ?? windowScheme)
            .onPreferenceChange(HeldColorScheme.self) { scheme in
                Task { @MainActor in held = scheme }
            }
            .onChange(of: held ?? chosen, initial: true) { _, scheme in window.show(scheme) }
            .background { WindowReader(reference: window, sceneChanged: readIPhoneScheme) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { readIPhoneScheme() }
            }
            .task { widget?.publish(setting.choice) }        // a choice made in iOS Settings, or in an older version
            #if DEBUG
            .task { await switchFromLaunchArgument() }
            #endif
    }

    /// The iPhone's look, read from the screen (the app's look is set on the window, below the scene and the screen),
    /// whenever the scene's look changes or the app comes to the front.
    private func readIPhoneScheme() {
        if let style = window.iPhoneStyle { iPhoneScheme = ColorScheme(style) }
    }

    private func switchLanguage(_ change: LanguageSwitch) {
        setting.choose(change.choice)
        widget?.publish(change.choice)
        guard change.language != language else { return }
        Task { await restart(in: change.language) }
    }

    private func restart(in new: AppLanguage) async {
        // SwiftUI keeps a sheet up when the view that presented it is replaced, so they are closed first (still in
        // the old language), then the app is built again.
        await window.closePresentedScreens()
        AppLanguage.show(new)
        LaunchArguments.restart()
        withAnimation(.easeInOut(duration: 0.35)) { language = new }
    }

    #if DEBUG
    /// Screenshots: `-switchLanguage en|de|iphone` does what the confirmation's Restart does, 2 s after launch.
    private func switchFromLaunchArgument() async {
        guard let value = LaunchArguments.value("-switchLanguage") else { return }
        let choice = AppLanguage(rawValue: value)
        try? await Task.sleep(for: .seconds(2))
        switchLanguage(LanguageSwitch(choice: choice, language: setting.language(for: choice)))
    }
    #endif
}

extension EnvironmentValues {
    /// The look the app shows outside a held mode: Settings → Appearance, or for "like the iPhone" the iPhone's own.
    /// Inside a mode that holds the window (Aresium's red), `colorScheme` is the held look and this the one to return to.
    @Entry var appearanceScheme: ColorScheme = .dark
}

/// A look a screen holds the whole window in, over the app's appearance (`holdsColorScheme(_:)`).
private struct HeldColorScheme: PreferenceKey {
    static let defaultValue: ColorScheme? = nil
    static func reduce(value: inout ColorScheme?, nextValue: () -> ColorScheme?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// Holds the window and its sheets in this look while the view is shown (nil: the app's appearance). For a
    /// special mode with its own colours, as Aresium's red one; `AppRoot` applies it.
    func holdsColorScheme(_ scheme: ColorScheme?) -> some View {
        preference(key: HeldColorScheme.self, value: scheme)
    }
}

/// The window the root is shown in, to close what is presented over it.
@MainActor
private final class WindowReference {
    weak var window: UIWindow? {
        didSet {
            window?.overrideUserInterfaceStyle = style
            cover.attach(to: window)
        }
    }
    /// The app switcher's cover, on the same scene (`PrivacyCover`).
    private let cover: PrivacyCoverWindow

    init(cover: PrivacyCover) {
        self.cover = PrivacyCoverWindow(cover: cover)
    }
    /// The look the window shows: the app's choice or a held one; unspecified follows the iPhone.
    private var style = UIUserInterfaceStyle.unspecified

    func show(_ scheme: ColorScheme?) {
        style = switch scheme {
        case .light: .light
        case .dark: .dark
        default: .unspecified
        }
        window?.overrideUserInterfaceStyle = style
    }

    /// The iPhone's own light or dark, whatever the app shows.
    var iPhoneStyle: UIUserInterfaceStyle? {
        window?.windowScene?.screen.traitCollection.userInterfaceStyle
    }

    /// Dismisses every sheet and alert over the window's root, waiting for one that is still on its way in or out
    /// (the confirmation closes as its Restart is tapped).
    func closePresentedScreens() async {
        guard let root = window?.rootViewController else { return }
        for _ in 0..<30 {                                   // at most about 3 s
            guard let presented = root.presentedViewController else { return }
            if presented.isBeingPresented || presented.isBeingDismissed {
                try? await Task.sleep(for: .milliseconds(100))
                continue
            }
            await withCheckedContinuation { done in root.dismiss(animated: true) { done.resume() } }
        }
    }
}

/// Finds the window the root is shown in, and says when it is shown and each time its scene's light or dark changes
/// (the iPhone switching while the app follows it, or the app's own choice).
private struct WindowReader: UIViewRepresentable {
    let reference: WindowReference
    let sceneChanged: () -> Void

    func makeUIView(context: Context) -> ReaderView { ReaderView(reference: reference, sceneChanged: sceneChanged) }
    func updateUIView(_ view: ReaderView, context: Context) {}

    final class ReaderView: UIView {
        let reference: WindowReference
        let sceneChanged: () -> Void
        private weak var scene: UIWindowScene?
        private var registration: (any UITraitChangeRegistration)?

        init(reference: WindowReference, sceneChanged: @escaping () -> Void) {
            self.reference = reference
            self.sceneChanged = sceneChanged
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { nil }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window else { return }
            reference.window = window
            guard let windowScene = window.windowScene, windowScene !== scene else { return }
            if let registration, let scene { scene.unregisterForTraitChanges(registration) }
            scene = windowScene
            sceneChanged()
            registration = windowScene.registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
                [weak self] (_: UIWindowScene, _: UITraitCollection) in
                self?.sceneChanged()
            }
        }
    }
}

/// Settings → Language's Restart: saves the choice and restarts the app in its language (`AppRoot`). Outside a
/// root (previews) it only saves the choice.
struct SwitchLanguageAction {
    let run: (LanguageSwitch) -> Void
    func callAsFunction(_ change: LanguageSwitch) { run(change) }
}

extension EnvironmentValues {
    @Entry var switchLanguage = SwitchLanguageAction { change in LanguageSetting.standard.choose(change.choice) }
}

/// The launch arguments the app is built with (DEBUG screenshots read them here, not from `ProcessInfo`). After an
/// in-app restart, the ones that open or scroll to a screen are gone, so the app comes back on its main screen like
/// after a real restart, still with its sample data.
nonisolated enum LaunchArguments {
    static var current: [String] { arguments.withLock { $0 } }

    /// The value after `name` ("-tab aresync" → "aresync"); nil when the argument is missing.
    static func value(_ name: String) -> String? {
        let arguments = current
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// Drops the arguments that open a screen (`AppRoot` calls it as it restarts the app).
    static func restart() { arguments.withLock { $0 = afterRestart($0) } }

    /// The arguments without the ones that open or scroll to a screen (with their values).
    static func afterRestart(_ arguments: [String]) -> [String] {
        var kept: [String] = []
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            if opensWithValue.contains(argument) {
                index += 2
            } else {
                if !opens.contains(argument) { kept.append(argument) }
                index += 1
            }
        }
        return kept
    }

    private static let arguments = Mutex(ProcessInfo.processInfo.arguments)

    /// Screens, tabs, sheets, scroll positions and one-off notices of the apps' screenshot arguments (CLAUDE.md).
    private static let opensWithValue: Set<String> = [
        "-openSheet", "-openProvince", "-openRun", "-openMatch", "-openNote", "-openPosition", "-openBestMatch",
        "-tab", "-filter", "-library", "-search", "-tabSearch", "-scrollTo", "-sampleCategory", "-sampleMonth",
        "-sampleTransaction", "-sampleRecategorise", "-sampleIntroProgress", "-supportKind", "-supportText",
        "-supportPhase", "-supportEmail", "-confirmLanguage", "-switchLanguage", "-openAccount", "-accountEmail",
        "-accountPhase", "-openCodeEntry", "-openGuide", "-guidePlace", "-guideSearch", "-tour",
    ]
    private static let opens: Set<String> = [
        "-scrollToEnd", "-scrollBottom", "-sampleIntro", "-sampleImportResult", "-sampleImportFailed", "-openLanguage",
        "-openAppearance", "-openCode", "-openSupport", "-openSignIn",
        "-scrollToAccount", "-sampleAccountDeleted", "-tourSettings",
    ]
}
