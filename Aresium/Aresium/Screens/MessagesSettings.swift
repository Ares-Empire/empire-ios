import SwiftUI
import UIKit

// Settings → Messages (brief 46, phone mode only): Aresium's own local messages, the import reminder and the month
// review. A section with one row (its state on the right) opening a page of switches, Apple's menu for how often and
// Apple's time picker. Built from the Settings pieces (`SettingsSection`, `SettingsRow`, `FormNote`, `FormProblem`,
// glass cards), the Lock section's switches and the column check's `MenuChip`; ink only. The logic is brief 45's
// `AresiumMessages`; the words are `MessageWording`, the time `MessageTime`.

struct MessagesSettingsSection: View {
    let messages: AresiumMessages
    let lock: AppLock
    #if DEBUG
    /// Screenshots: `-openMessages` opens Settings → Messages at once.
    @State private var showsPage = LaunchArguments.current.contains("-openMessages")
    #else
    @State private var showsPage = false
    #endif

    var body: some View {
        SettingsSection(String(localized: "Messages")) {
            Button { showsPage = true } label: {
                SettingsRow(title: String(localized: "Reminder and review"),
                            value: MessageWording.state(messages.preferences, authorization: messages.authorization))
            }
            .buttonStyle(SettingsRowStyle())
            .navigationDestination(isPresented: $showsPage) { MessagesSettingsScreen(messages: messages, lock: lock) }
        }
    }
}

/// The page: Messages on or off; while on, the import reminder (with how often) and the month review, each with its
/// line, and the time for both; what iOS says when it has Aresium's notifications off; a failure; the quiet note.
struct MessagesSettingsScreen: View {
    let messages: AresiumMessages
    let lock: AppLock
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var preferences: MessagePreferences { messages.preferences }
    private var denied: Bool { preferences.enabled && messages.authorization == .denied }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    SwitchRow(title: Text("Messages"), isOn: binding(\.enabled))
                    if denied { deniedRows }
                }
                .glassCard()
                .padding(.top, 22)
                if preferences.enabled {
                    which.padding(.top, 16).transition(.opacity)
                    time.padding(.top, 16).transition(.opacity)
                } else {
                    FormNote(text: String(localized: "Aresium can remind you to import new statements and sum up each month."))
                        .padding(.top, 10)
                        .transition(.opacity)
                }
                if let error = messages.error { FormProblem(text: error).padding(.top, 12) }
                FormNote(text: MessageWording.note(lockOn: lock.isOn)).padding(.top, 14)
            }
            .padding(.horizontal, 18).padding(.bottom, 34)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: preferences.enabled)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: preferences.importReminder)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: denied)
        }
        .scrollIndicators(.hidden)
        .background { SettingsWall(accent: nil) }
        .navigationTitle(Text("Messages"))
        .navigationBarTitleDisplayMode(.inline)
        // iOS's answer may have changed in its Settings meanwhile (coming back to the app asks again too).
        .task { messages.refresh() }
    }

    /// iOS has Aresium's notifications off: what that means here, and the way to Aresium's page in iOS Settings. The
    /// switches keep what was chosen.
    @ViewBuilder private var deniedRows: some View {
        SettingsDivider()
        Text("iOS has notifications off for Aresium, so no messages come.")
            .font(AppFont.text(13)).foregroundStyle(FormProblem.ink).lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 12)
        SettingsDivider()
        Button {
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
        } label: {
            SettingsRow(title: String(localized: "Allow in iOS Settings"), trailing: .external)
        }
        .buttonStyle(SettingsRowStyle())
    }

    /// The two messages, each with its line; how often only while the reminder is on.
    private var which: some View {
        VStack(spacing: 0) {
            SwitchRow(title: Text("Import reminder"),
                      line: Text("A reminder to import new statements, counted from your last import."),
                      isOn: binding(\.importReminder))
            if preferences.importReminder {
                SettingsDivider()
                howOften
            }
            SettingsDivider()
            SwitchRow(title: Text("Month review"), line: Text("On the 3rd: last month's spending and income."),
                      isOn: binding(\.monthReview))
        }
        .glassCard()
    }

    /// Every week, every 2 weeks or every month: Apple's menu, opened from the column check's chip.
    private var howOften: some View {
        HStack(spacing: 12) {
            Text("How often").font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            Menu {
                Picker(selection: binding(\.interval)) {
                    ForEach(MessageInterval.allCases, id: \.self) { interval in
                        Text(verbatim: MessageWording.interval(interval)).tag(interval)
                    }
                } label: { EmptyView() }
            } label: {
                MenuChip(text: MessageWording.interval(preferences.interval))
            }
            .accessibilityLabel(Text("How often"))
            .accessibilityValue(Text(verbatim: MessageWording.interval(preferences.interval)))
        }
        .padding(.horizontal, 16).frame(minHeight: 52)
    }

    /// The time both messages come at: Apple's time picker, hours and minutes, in the app's language.
    private var time: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Time").font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                if preferences.importReminder && preferences.monthReview {
                    Text("For both messages").font(AppFont.text(12)).foregroundStyle(Ink.muted)
                }
            }
            .accessibilityHidden(true)
            Spacer(minLength: 8)
            DatePicker(String(localized: "Time"),
                       selection: Binding(get: { MessageTime.date(of: preferences) },
                                          set: { messages.setPreferences(MessageTime.setting($0, in: preferences)) }),
                       displayedComponents: .hourAndMinute)
                .labelsHidden()
                .environment(\.locale, AppLanguage.current.locale)
        }
        .padding(.horizontal, 16).frame(minHeight: 58)
        .glassCard()
    }

    /// A switch or a menu changes one choice: brief 45 saves it and plans the messages again off the main thread.
    private func binding<Value>(_ field: WritableKeyPath<MessagePreferences, Value>) -> Binding<Value> {
        Binding(get: { messages.preferences[keyPath: field] }, set: { value in
            var changed = messages.preferences
            changed[keyPath: field] = value
            messages.setPreferences(changed)
        })
    }
}

/// A switch in the Lock section's look: the title, an optional quiet line under it; its on colour is Settings' own
/// (`EmpireSwitchStyle`, brief 47).
private struct SwitchRow: View {
    let title: Text
    var line: Text? = nil
    let isOn: Binding<Bool>

    var body: some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                title.font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                if let line {
                    line.font(AppFont.text(12)).foregroundStyle(Ink.muted).lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, line == nil ? 0 : 9)
        .frame(minHeight: line == nil ? 50 : 58)
    }
}
