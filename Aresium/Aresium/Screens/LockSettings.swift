import SwiftUI

// Settings → Lock (Aresium's own section, in both modes): Face ID as a switch, the own code as a page, and a line on
// what the lock does. Built from the Settings pieces (`SettingsSection`, `SettingsRow`, `FormNote`, the account pages'
// frame) and the lock screen's code pad; ink only. The logic is `AppLock` and `LockCodeChange`.

struct LockSettingsSection: View {
    let lock: AppLock
    /// The switch's value while Face ID is being asked (it follows the lock once the answer is in).
    @State private var pending: Bool?
    #if DEBUG
    /// Screenshots: `-openCode` opens Settings → Lock → Own code at once.
    @State private var showsCode = LaunchArguments.current.contains("-openCode")
    #else
    @State private var showsCode = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(String(localized: "Lock")) {
                Toggle(isOn: Binding(get: { pending ?? lock.faceID }, set: setFaceID)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lockWithBiometry).font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                        if let faceIDLine {
                            Text(faceIDLine).font(AppFont.text(12)).foregroundStyle(Ink.muted)
                        }
                    }
                }
                .disabled(lock.isAuthenticating || (!lock.faceID && !lock.canUseFaceID))
                .padding(.horizontal, 16).frame(minHeight: faceIDLine == nil ? 50 : 58)
                SettingsDivider()
                Button { showsCode = true } label: {
                    SettingsRow(title: String(localized: "Own code"),
                                value: lock.hasCode ? String(localized: "On") : String(localized: "Off"))
                }
                .buttonStyle(SettingsRowStyle())
                .navigationDestination(isPresented: $showsCode) { CodeSettingsScreen(lock: lock) }
            }
            FormNote(text: String(localized: "Aresium locks when it opens and after more than 10 seconds away. While the lock is on, the widgets show no numbers."))
                .padding(.top, 10)
        }
        .task { await lock.refreshAvailability() }
    }

    private func setFaceID(_ on: Bool) {
        pending = on
        Task {
            await lock.setFaceID(on)
            pending = nil
        }
    }

    private var lockWithBiometry: String {
        switch lock.biometry {
        case .touchID: String(localized: "Lock with Touch ID")
        case .opticID: String(localized: "Lock with Optic ID")
        case .faceID, .none: String(localized: "Lock with Face ID")
        }
    }

    /// What else opens Aresium with the switch on, or why it cannot be turned on.
    private var faceIDLine: String? {
        if !lock.faceID && !lock.canUseFaceID { return String(localized: "Needs a code on this iPhone") }
        return lock.hasCode ? String(localized: "Or your own code") : String(localized: "Or the iPhone's code")
    }
}

// MARK: - Own code

/// Settings → Lock → Own code: what it does and the warning (a forgotten code cannot be reset), then Set code, or
/// Change code and Remove code once there is one.
struct CodeSettingsScreen: View {
    let lock: AppLock
    @State private var goal: LockCodeChange.Goal?

    var body: some View {
        AccountPageFrame(title: Text("Own code"), accent: nil) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AccountExplanation(
                        main: String(localized: "A code of 6 digits, only for Aresium."),
                        rest: String(localized: "With it, Aresium opens with Face ID or this code, not with the iPhone's code."),
                        accent: nil)
                    warning.padding(.top, 14)
                    if lock.hasCode {
                        VStack(spacing: 0) {
                            Button { goal = .change } label: {
                                SettingsRow(title: String(localized: "Change code"))
                            }
                            .buttonStyle(SettingsRowStyle())
                            SettingsDivider()
                            Button { goal = .remove } label: {
                                SettingsRow(title: String(localized: "Remove code"), tint: FormButtonStyle.dangerInk)
                            }
                            .buttonStyle(SettingsRowStyle())
                        }
                        .glassCard()
                        .padding(.top, 26)
                    }
                }
                .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        } actions: {
            if !lock.hasCode {
                Button { goal = .set } label: { Text("Set code") }
                    .buttonStyle(FormButtonStyle(accent: nil))
            }
        }
        .navigationDestination(item: $goal) { goal in
            CodeEntryScreen(change: LockCodeChange(goal: goal, lock: lock))
        }
        #if DEBUG
        .task {
            // Screenshots: `-openCodeEntry set|change|remove` opens the code pad at once.
            if let value = LaunchArguments.value("-openCodeEntry") { goal = LockCodeChange.Goal(rawValue: value) }
        }
        #endif
    }

    /// The plain warning before anyone sets a code: in the login's soft problem box, as a note, not an alarm.
    private var warning: some View {
        LoginBox(text: String(localized: "A forgotten code can't be reset. Without it and without Face ID, the only way back is deleting Aresium's data on this iPhone, so export your data first."),
                 problem: true)
    }
}

/// The code pad for setting, changing or removing the code: what to type, the dots, a line, the keypad. It closes by
/// itself once the change is saved.
struct CodeEntryScreen: View {
    @State var change: LockCodeChange
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AccountPageFrame(title: title, accent: nil, holds: change.isWorking) {
            ScrollView {
                VStack(spacing: 0) {
                    prompt.font(AppFont.text(17, weight: .semibold)).foregroundStyle(Ink.primary)
                        .multilineTextAlignment(.center).padding(.top, 36)
                        .accessibilityAddTraits(.isHeader)
                    CodeDots(count: change.entry.digits.count, shake: reduceMotion ? 0 : change.shakes).padding(.top, 22)
                    line.font(AppFont.text(13)).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 40).padding(.top, 10).padding(.horizontal, 24)
                    CodeKeypad(disabled: change.isWorking, type: { digit in Task { await change.type(digit) } },
                               delete: { change.delete() })
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .padding(.top, 18)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        } actions: {
            EmptyView()
        }
        .sensoryFeedback(.error, trigger: change.shakes)
        .sensoryFeedback(.success, trigger: change.isDone) { _, done in done }
        .onChange(of: change.isDone) { _, done in if done { dismiss() } }
    }

    private var title: Text {
        switch change.goal {
        case .set: Text("Set code")
        case .change: Text("Change code")
        case .remove: Text("Remove code")
        }
    }

    private var prompt: Text {
        switch change.step {
        case .current: Text("Enter your current code")
        case .new: Text("Enter a new code")
        case .again: Text("Enter it again")
        }
    }

    @ViewBuilder private var line: some View {
        switch change.problem {
        case .wrongCurrent: Text("Wrong code").foregroundStyle(FormProblem.ink)
        case .differ: Text("The codes didn't match. Enter a new code again.").foregroundStyle(FormProblem.ink)
        case .waiting: Text("Too many wrong codes. Try again later.").foregroundStyle(Ink.secondary)
        case .notSaved(let message): Text(verbatim: message).foregroundStyle(FormProblem.ink)
        case nil:
            if change.isWorking { ProgressView().tint(Ink.secondary) } else { Color.clear.frame(height: 1) }
        }
    }
}
