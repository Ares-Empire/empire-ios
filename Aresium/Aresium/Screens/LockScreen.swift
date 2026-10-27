import SwiftUI
import UIKit

// The lock's screens (the logic is `AppLock`): the lock screen in a window of its own above everything, and the code
// pad that the lock screen and Settings → Lock → Own code share. Aresium's look: the app switcher cover's wall and band
// (`PrivacyCover`), keys in the header buttons' quiet look (card and line), digits in JetBrains Mono, ink only.

// MARK: - the code pad

/// Six dots for the digits typed so far: filled with ink for each, a thin ring for the rest. Shakes when `shake` grows.
struct CodeDots: View {
    let count: Int
    var shake = 0

    var body: some View {
        HStack(spacing: 18) {
            ForEach(0..<LockCode.length, id: \.self) { index in
                Circle()
                    .fill(index < count ? Ink.primary : .clear)
                    .overlay(Circle().strokeBorder(index < count ? Ink.primary : Ink.muted, lineWidth: 1.5))
                    .frame(width: 13, height: 13)
            }
        }
        .modifier(Shake(amount: CGFloat(shake)))
        .animation(.easeOut(duration: 0.4), value: shake)
        .accessibilityElement()
        .accessibilityLabel(Text("\(count) of \(LockCode.length) digits"))
    }

    /// A short side-to-side shake, as the iPhone's own code screen does on a wrong code.
    private struct Shake: GeometryEffect {
        var amount: CGFloat
        var animatableData: CGFloat {
            get { amount }
            set { amount = newValue }
        }
        func effectValue(size: CGSize) -> ProjectionTransform {
            ProjectionTransform(CGAffineTransform(translationX: 9 * sin(amount * .pi * 4), y: 0))
        }
    }
}

/// 1 to 9, then a key of the caller's (Face ID on the lock screen), 0 and delete. The keys keep their size at large
/// text sizes, as the iPhone's own keypad does; each says its digit to VoiceOver. `disabled` turns off the digits and
/// delete (a wait after wrong codes), never the caller's key.
struct CodeKeypad<Corner: View>: View {
    var disabled = false
    let type: (Character) -> Void
    let delete: () -> Void
    @ViewBuilder var corner: Corner

    private let rows: [[Character]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]

    var body: some View {
        Grid(horizontalSpacing: 14, verticalSpacing: 12) {
            ForEach(rows, id: \.self) { row in
                GridRow { ForEach(row, id: \.self) { digit in key(digit) } }
            }
            GridRow {
                corner.frame(width: Self.keyWidth, height: Self.keyHeight)
                key("0")
                Button(action: delete) {
                    Image(systemName: "delete.left").font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Ink.secondary)
                        .frame(width: Self.keyWidth, height: Self.keyHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Delete"))
                .disabled(disabled).opacity(disabled ? 0.45 : 1)
            }
        }
    }

    static var keyWidth: CGFloat { 92 }
    static var keyHeight: CGFloat { 58 }

    private func key(_ digit: Character) -> some View {
        Button { type(digit) } label: {
            Text(verbatim: String(digit))
                .font(.custom(AppFont.numberName, fixedSize: 24).weight(.semibold))
                .foregroundStyle(Ink.primary)
                .frame(width: Self.keyWidth, height: Self.keyHeight)
        }
        .buttonStyle(KeyStyle())
        .disabled(disabled).opacity(disabled ? 0.45 : 1)     // the corner key (Face ID) stays: a wait is for codes only
    }

    /// The header buttons' quiet look (card and line), with iOS's faint shade while pressed.
    private struct KeyStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            configuration.label
                .background(shape.fill(Ink.card))
                .background(shape.fill(configuration.isPressed ? Ink.press : .clear))
                .overlay(shape.strokeBorder(configuration.isPressed ? Ink.edge : Ink.line))
                .contentShape(shape)
        }
    }
}

extension CodeKeypad where Corner == Color {
    init(disabled: Bool = false, type: @escaping (Character) -> Void, delete: @escaping () -> Void) {
        self.init(disabled: disabled, type: type, delete: delete) { Color.clear }
    }
}

// MARK: - the lock screen

/// What shows while Aresium is locked: the app switcher cover's wall and band, then either the code (dots, keypad with
/// a Face ID key when Face ID is on, "Forgot the code?") or, with Face ID alone, one Face ID button. Calm: no slogans,
/// nothing of the data.
struct LockScreen: View {
    let lock: AppLock
    /// "Forgot the code?" also logs out (server mode: the lock must not open the server's data either).
    var forgotLogsOut = false
    /// Deletes Aresium's data on this iPhone and the lock (`ContentView`).
    let forgot: () async throws -> Void

    @State private var entry = CodeEntry()
    @State private var shake = 0
    @State private var wrongLine = false
    @State private var confirmsForgot = false
    @State private var forgetting = false
    @State private var forgotProblem: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            if lock.hasCode {
                GeometryReader { proxy in codeLayout(width: proxy.size.width, height: proxy.size.height) }
            } else {
                // Measured over the whole screen, as the cover is, so the band sits exactly where the cover has it.
                GeometryReader { proxy in faceIDLayout(width: proxy.size.width, height: proxy.size.height) }.ignoresSafeArea()
            }
        }
        .sensoryFeedback(.error, trigger: shake)
        .confirmationDialog(Text("Forgot the code?"), isPresented: $confirmsForgot, titleVisibility: .visible) {
            Button("Delete Aresium data", role: .destructive) { forget() }
            Button("Cancel", role: .cancel) {}
        } message: {
            forgotLogsOut
                ? Text("A forgotten code can't be reset. Deleting Aresium's data on this iPhone removes the code with it and logs out of your Ares account; afterwards you can restore an export.")
                : Text("A forgotten code can't be reset. Deleting Aresium's data on this iPhone removes the code with it; afterwards you can restore an export.")
        }
    }

    // MARK: with a code

    private func codeLayout(width: CGFloat, height: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // The cover's band, in the middle of the room above the code.
                Spacer(minLength: 24)
                WordmarkBand(word: "Aresium", width: width)
                Spacer(minLength: 28)
                Text("Enter your code").font(AppFont.text(17, weight: .semibold)).foregroundStyle(Ink.primary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                CodeDots(count: entry.digits.count, shake: reduceMotion ? 0 : shake).padding(.top, 22)
                status.frame(minHeight: 40).padding(.top, 10).padding(.horizontal, 24)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    CodeKeypad(disabled: lock.remainingWait() > 0 || lock.isChecking || forgetting,
                               type: type, delete: { entry.delete() }) {
                        if lock.faceID {
                            Button { Task { await lock.unlockWithBiometrics() } } label: {
                                Image(systemName: biometrySymbol).font(.system(size: 24, weight: .regular))
                                    .foregroundStyle(Ink.secondary)
                                    .frame(width: CodeKeypad<Color>.keyWidth, height: CodeKeypad<Color>.keyHeight)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(unlockWithBiometry))
                        } else {
                            Color.clear
                        }
                    }
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
                .padding(.top, 24)
                Button { confirmsForgot = true } label: {
                    Text("Forgot the code?").font(AppFont.text(13)).foregroundStyle(Ink.secondary)
                        .frame(minHeight: 44).padding(.horizontal, 16).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(forgetting)
                .padding(.top, 14).padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity, minHeight: height)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }

    /// Under the dots: a wrong code, the wait after too many, or why "Forgot the code?" did not go through.
    @ViewBuilder private var status: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let wait = lock.remainingWait()
            Group {
                if let forgotProblem {
                    FormProblem(text: forgotProblem)
                } else if wait > 0 {
                    Text("Too many wrong codes. Try again in \(Self.clock(wait)).")
                        .foregroundStyle(Ink.secondary)
                } else if wrongLine {
                    Text("Wrong code").foregroundStyle(FormProblem.ink)
                } else if lock.isChecking || forgetting {
                    ProgressView().tint(Ink.secondary)
                }
            }
            .font(AppFont.text(13)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func type(_ digit: Character) {
        wrongLine = false
        entry.type(digit)
        guard entry.isComplete else { return }
        let typed = entry.digits
        Task {
            let result = await lock.enterCode(typed)
            entry.clear()
            if result != .right {
                wrongLine = result == .wrong
                shake += 1
            }
        }
    }

    private func forget() {
        forgetting = true
        forgotProblem = nil
        Task {
            do { try await forgot() } catch { forgotProblem = error.localizedDescription }
            forgetting = false
        }
    }

    /// "4:59": minutes and seconds of a wait, rounded up.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: with Face ID alone

    /// The cover as it is (the band in the middle of the wall), with one Face ID button 44 pt under it; the button grows
    /// downwards at large text sizes, so the band stays where the cover has it.
    private func faceIDLayout(width: CGFloat, height: CGFloat) -> some View {
        let band = WordmarkBand.height(of: "Aresium", width: width)
        return ZStack(alignment: .top) {
            WordmarkBand(word: "Aresium", width: width)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if lock.faceID {
                Button { Task { await lock.unlockWithBiometrics() } } label: {
                    Label { Text(unlockWithBiometry) } icon: { Image(systemName: biometrySymbol) }
                        .font(AppFont.text(15, weight: .semibold)).foregroundStyle(Ink.primary)
                        .padding(.horizontal, 22).padding(.vertical, 8).frame(minHeight: 48)
                        .background(Ink.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Ink.line))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(lock.isAuthenticating)
                .padding(.horizontal, 24)
                .padding(.top, (height + band) / 2 + 44)
            }
        }
        .frame(width: width, height: height)
    }

    // MARK: words and marks

    private var biometrySymbol: String {
        switch lock.biometry {
        case .touchID: "touchid"
        case .opticID: "opticid"
        case .faceID: "faceid"
        case .none: "lock.open"
        }
    }

    private var unlockWithBiometry: String {
        switch lock.biometry {
        case .touchID: String(localized: "Unlock with Touch ID")
        case .opticID: String(localized: "Unlock with Optic ID")
        case .faceID: String(localized: "Unlock with Face ID")
        case .none: String(localized: "Unlock")
        }
    }
}

// MARK: - the window

/// The lock screen's own window, above everything the app shows (sheets, alerts, and the app switcher cover: while
/// locked, the lock screen is all there is to see). It follows `AppLock`: shown when it locks (at launch, and coming
/// back after more than 10 seconds in the background, before the app is seen), faded out when it opens. It tells the
/// lock when the scene goes to the background, comes back, and is active (Face ID is offered once by itself).
/// One per launch (`AresiumApp`); `ContentView` attaches it to the app's window and hands it "Forgot the code?".
@MainActor
final class LockWindow {
    let lock: AppLock
    /// Deletes Aresium's data on this iPhone and the lock (`ContentView`).
    var forgot: () async throws -> Void = {}
    /// Whether "Forgot the code?" also logs out (server mode).
    var forgotLogsOut: () -> Bool = { false }
    private weak var appWindow: UIWindow?
    private var window: UIWindow?
    private var host: UIHostingController<AnyView>?
    private var observers: [NSObjectProtocol] = []

    init(lock: AppLock) {
        self.lock = lock
        lock.lockedChanged = { [weak self] locked in
            if locked { self?.show() } else { self?.hide() }
        }
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Called whenever the app's window is known; a window it already serves changes nothing.
    func attach(to appWindow: UIWindow?) {
        guard let appWindow, appWindow !== self.appWindow, let scene = appWindow.windowScene else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        window?.isHidden = true
        self.appWindow = appWindow

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 2              // the app switcher cover is .alert + 1
        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = UIColor(named: "LaunchBackground")
        window.rootViewController = host
        window.isHidden = true
        self.window = window
        self.host = host

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIScene.didEnterBackgroundNotification, object: scene, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lock.enteredBackground() }
            },
            center.addObserver(forName: UIScene.willEnterForegroundNotification, object: scene, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lock.willEnterForeground() }
            },
            center.addObserver(forName: UIScene.didActivateNotification, object: scene, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lock.becameActive() }
            },
        ]
        if lock.isLocked { show() }
        if scene.activationState == .foregroundActive { lock.becameActive() }
    }

    private func content() -> AnyView {
        AnyView(LockScreen(lock: lock, forgotLogsOut: forgotLogsOut()) { [weak self] in try await self?.forgot() }
            .environment(\.locale, AppLanguage.current.locale))
    }

    private func show() {
        guard let window, let host else { return }
        host.rootView = content()                       // in the language and the mode the app shows now
        window.overrideUserInterfaceStyle = appWindow?.overrideUserInterfaceStyle ?? .unspecified
        appWindow?.endEditing(true)                     // no keyboard over the lock, no typing into the hidden app
        window.layer.removeAllAnimations()
        window.alpha = 1
        window.isHidden = false
        window.makeKey()
    }

    private func hide() {
        guard let window, !window.isHidden else { return }
        appWindow?.makeKey()
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            window.alpha = 0
        } completion: { [weak self] finished in
            if finished, self?.lock.isLocked == false { window.isHidden = true }
        }
    }
}

/// Finds the app's window for the lock window (`LockWindow.attach`).
struct LockWindowReader: UIViewRepresentable {
    let lockWindow: LockWindow

    func makeUIView(context: Context) -> ReaderView { ReaderView(lockWindow: lockWindow) }
    func updateUIView(_ view: ReaderView, context: Context) {}

    final class ReaderView: UIView {
        let lockWindow: LockWindow
        init(lockWindow: LockWindow) {
            self.lockWindow = lockWindow
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { nil }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            lockWindow.attach(to: window)
        }
    }
}
