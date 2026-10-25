import Foundation
import Synchronization
import SwiftUI
import UIKit

/// Every app's root, inside its `WindowGroup`: `LanguageRoot { ContentView(…) }`. It shows the app in the language it
/// shows now and, when Settings → Language switches it, restarts the app inside itself: the choice is saved where iOS
/// keeps the app's language, every sheet and alert is closed, then the whole view tree is built again in the new
/// language, as at a launch. The main screen comes back, the stores load again (the servers answer in the new
/// language), the session restores the login, and push registers the device with the new language
/// (`PushCenter.start`). The app never quits itself (Apple asks apps not to).
struct LanguageRoot<Content: View>: View {
    private let setting: LanguageSetting
    private let widget: WidgetLanguage?
    private let content: () -> Content
    @State private var language = AppLanguage.current
    @State private var window = WindowReference()

    /// - Parameter widget: where the app's widget reads the app's choice; nil for apps without a widget.
    init(setting: LanguageSetting = .standard, widget: WidgetLanguage? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.setting = setting
        self.widget = widget
        self.content = content
    }

    var body: some View {
        content()
            .id(language)                                       // a new language: every view and its state anew
            .environment(\.locale, language.locale)            // SwiftUI's own lookups (Text, Button, …) and formats
            .environment(\.switchLanguage, SwitchLanguageAction(run: switchLanguage))
            .background { WindowReader(reference: window) }
            .task { widget?.publish(setting.choice) }        // a choice made in iOS Settings, or in an older version
            #if DEBUG
            .task { await switchFromLaunchArgument() }
            #endif
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

/// The window the root is shown in, to close what is presented over it.
@MainActor
private final class WindowReference {
    weak var window: UIWindow?

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

private struct WindowReader: UIViewRepresentable {
    let reference: WindowReference

    func makeUIView(context: Context) -> ReaderView { ReaderView(reference: reference) }
    func updateUIView(_ view: ReaderView, context: Context) {}

    final class ReaderView: UIView {
        let reference: WindowReference
        init(reference: WindowReference) {
            self.reference = reference
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { nil }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { reference.window = window }
        }
    }
}

/// Settings → Language's Restart: saves the choice and restarts the app in its language (`LanguageRoot`). Outside a
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

    /// Drops the arguments that open a screen (`LanguageRoot` calls it as it restarts the app).
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
        "-supportPhase", "-confirmLanguage", "-switchLanguage", "-openAccount", "-accountEmail", "-accountPhase",
    ]
    private static let opens: Set<String> = [
        "-scrollToEnd", "-scrollBottom", "-sampleIntro", "-sampleImportResult", "-sampleImportFailed", "-openLanguage",
        "-scrollToAccount", "-sampleAccountDeleted",
    ]
}
