import SwiftUI

/// Settings → Account's pages (pushed inside the Settings sheet): change the password, leave this app, delete the Ares
/// account. Their logic is in `Shared/Auth/AccountForms.swift`; they only show it.
enum AccountPage: String, Hashable {
    case changePassword, leave, delete

    #if DEBUG
    /// Screenshots: `-openSheet settings -openAccount changePassword|leave|delete` (with `-accountPhase …`).
    static func launched(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> AccountPage? {
        AccountDebug.value("-openAccount", in: arguments).flatMap(AccountPage.init(rawValue:))
    }
    #endif
}

// MARK: - Change password

/// The current password and the new one twice; afterwards the app logs in again by itself (`ChangePasswordForm`).
struct ChangePasswordScreen: View {
    let app: SettingsApp
    let closeSettings: () -> Void
    @State private var form: ChangePasswordForm
    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss
    private enum Field { case current, new, again }

    init(app: SettingsApp, session: EmpireSession, sample: Bool, closeSettings: @escaping () -> Void) {
        self.app = app
        self.closeSettings = closeSettings
        let form = ChangePasswordForm(session: session, sample: sample)
        #if DEBUG
        form.applyDebugArguments(ProcessInfo.processInfo.arguments)
        #endif
        _form = State(initialValue: form)
    }

    var body: some View {
        AccountPageFrame(title: Text("Change password", tableName: "Shared"), accent: app.accent,
                         holds: form.holdsThePage) {
            if form.phase == .done {
                CalmDone(title: Text("Password changed", tableName: "Shared"),
                         text: Text("\(app.name) is logged in with it. The other Ares apps on this iPhone follow when you open them.",
                                    tableName: "Shared"),
                         highlight: app.accent?.color ?? Ink.secondary)
            } else {
                fields
            }
        } actions: {
            actions
        }
        .onDisappear { form.close() }
    }

    private var fields: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    FormField(placeholder: String(localized: "Current password", table: "Shared"), text: $form.current,
                              kind: .password)
                        .focused($focus, equals: .current).submitLabel(.next).onSubmit { focus = .new }
                    SettingsDivider()
                    FormField(placeholder: String(localized: "New password", table: "Shared"), text: $form.newPassword,
                              kind: .newPassword)
                        .focused($focus, equals: .new).submitLabel(.next).onSubmit { focus = .again }
                    SettingsDivider()
                    FormField(placeholder: String(localized: "New password again", table: "Shared"),
                              text: $form.newAgain, kind: .newPassword)
                        .focused($focus, equals: .again).submitLabel(.done).onSubmit(change)
                }
                .glassCard(accent: app.accent)
                FormNote(text: String(localized: "At least 8 characters. Afterwards \(app.name) logs in again by itself; the other Ares apps on this iPhone follow.",
                                      table: "Shared"))
                    .padding(.top, 10)
            }
            .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .disabled(form.holdsThePage)
    }

    @ViewBuilder private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case .loginFailed(let failure) = form.phase {
                FormProblem(text: String(localized: "Your password is changed, but logging in with it didn't work. \(failure.message)",
                                         table: "Shared"))
                Button { Task { await form.retryLogin() } } label: { Text("Try again", tableName: "Shared") }
                    .buttonStyle(FormButtonStyle(accent: app.accent))
                Button {
                    form.close()            // logs out: the old login is refused by now
                    closeSettings()
                } label: {
                    Text("Log out and log in again", tableName: "Shared").font(AppFont.text(14, weight: .medium))
                        .foregroundStyle(Ink.secondary).frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.plain)
            } else {
                if let failure = form.failure { FormProblem(text: failure.message) }
                Button {
                    if form.phase == .done { dismiss() } else { change() }
                } label: {
                    switch form.phase {
                    case .done: Text("Done", tableName: "Shared")
                    case .changing: BusyLabel(text: Text("Changing…", tableName: "Shared"), busy: true)
                    default: Text("Change password", tableName: "Shared")
                    }
                }
                .buttonStyle(FormButtonStyle(accent: app.accent, busy: form.phase == .changing))
                .disabled(!(form.canChange || form.phase == .changing || form.phase == .done))
                .allowsHitTesting(form.phase != .changing)
            }
        }
    }

    private func change() {
        focus = nil
        Task { await form.change() }
    }
}

// MARK: - Leave this app

/// What leaving takes (this app's access, its data on its server where it keeps any, its data on this iPhone) and what
/// stays (the account, the other apps), a confirmation, then `LeaveAppFlow`. Afterwards the Settings sheet closes and the
/// app shows its no-access screen.
struct LeaveAppScreen: View {
    let app: SettingsApp
    let closeSettings: () -> Void
    @State private var flow: LeaveAppFlow
    @State private var confirms = false

    init(app: SettingsApp, session: EmpireSession, sample: Bool, closeSettings: @escaping () -> Void) {
        self.app = app
        self.closeSettings = closeSettings
        let flow = LeaveAppFlow(session: session, serverData: app.serverData, sample: sample)
        #if DEBUG
        flow.applyDebugArguments(ProcessInfo.processInfo.arguments)
        #endif
        _flow = State(initialValue: flow)
    }

    var body: some View {
        AccountPageFrame(title: Text("Leave \(app.name)", tableName: "Shared"), accent: app.accent,
                         holds: flow.phase == .leaving) {
            ScrollView {
                AccountExplanation(
                    main: app.serverData == nil
                        ? String(localized: "Removes your access to \(app.name) and its data on this iPhone.", table: "Shared")
                        : String(localized: "Removes your access to \(app.name) and deletes your \(app.name) data, on its server and on this iPhone.",
                                 table: "Shared"),
                    rest: String(localized: "Your Ares account and the other apps stay. You can ask for access again later.",
                                 table: "Shared"),
                    accent: app.accent)
                    .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        } actions: {
            VStack(alignment: .leading, spacing: 12) {
                if let failure = flow.failure {
                    FormProblem(text: flow.serverDataDeleted
                        ? String(localized: "Your \(app.name) data on its server is deleted, but leaving didn't finish. \(failure.message)",
                                 table: "Shared")
                        : failure.message)
                }
                Button { confirms = true } label: {
                    BusyLabel(text: Text("Leave \(app.name)", tableName: "Shared"), busy: flow.phase == .leaving,
                              tint: FormButtonStyle.dangerInk)
                }
                .buttonStyle(FormButtonStyle(kind: .destructive, accent: app.accent, busy: flow.phase == .leaving))
                .allowsHitTesting(flow.phase != .leaving)
                .confirmationDialog(Text("Leave \(app.name)?", tableName: "Shared"), isPresented: $confirms,
                                    titleVisibility: .visible) {
                    Button(role: .destructive) { leave() } label: { Text("Leave \(app.name)", tableName: "Shared") }
                    Button(role: .cancel) {} label: { Text("Cancel", tableName: "Shared") }
                } message: {
                    Text("Your access and your data in \(app.name) go. Your Ares account stays.", tableName: "Shared")
                }
            }
        }
    }

    private func leave() {
        Task {
            await flow.leave()
            if flow.phase == .left { closeSettings() }
        }
    }
}

// MARK: - Delete the Ares account

/// What deleting takes (the account and its data in every Ares app), the password, a destructive confirmation, then
/// `DeleteAccountFlow`. Afterwards every Ares app on the iPhone is logged out.
struct DeleteAccountScreen: View {
    let app: SettingsApp
    let closeSettings: () -> Void
    @State private var flow: DeleteAccountFlow
    @State private var confirms = false
    @FocusState private var typing: Bool

    init(app: SettingsApp, session: EmpireSession, sample: Bool, closeSettings: @escaping () -> Void) {
        self.app = app
        self.closeSettings = closeSettings
        let flow = DeleteAccountFlow(session: session, sample: sample)
        #if DEBUG
        flow.applyDebugArguments(ProcessInfo.processInfo.arguments)
        #endif
        _flow = State(initialValue: flow)
    }

    var body: some View {
        AccountPageFrame(title: Text("Delete Ares account", tableName: "Shared"), accent: app.accent,
                         holds: flow.isWorking) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AccountExplanation(
                        main: String(localized: "Deletes your Ares account and its data in every Ares app, for good.",
                                     table: "Shared"),
                        rest: String(localized: "Every Ares app on this iPhone logs out. This can't be undone.",
                                     table: "Shared"),
                        accent: app.accent)
                    FormField(placeholder: String(localized: "Password", table: "Shared"), text: $flow.password,
                              kind: .password)
                        .focused($typing).submitLabel(.done).onSubmit(primary)
                        .glassCard(accent: app.accent).padding(.top, 24)
                        .disabled(flow.isWorking || flow.phase == .confirming)
                    FormNote(text: String(localized: "Your password, to be sure it's you.", table: "Shared"))
                        .padding(.top, 10)
                }
                .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        } actions: {
            VStack(alignment: .leading, spacing: 12) {
                if let failure = flow.failure { FormProblem(text: failure.message) }
                Button(action: primary) {
                    BusyLabel(text: flow.phase == .deleting ? Text("Deleting…", tableName: "Shared")
                                                            : Text("Delete Ares account", tableName: "Shared"),
                              busy: flow.isWorking, tint: FormButtonStyle.dangerInk)
                }
                .buttonStyle(FormButtonStyle(kind: .destructive, accent: app.accent, busy: flow.isWorking))
                .disabled(!(flow.canCheck || flow.isWorking || flow.phase == .confirming))
                .allowsHitTesting(!flow.isWorking)
                .confirmationDialog(Text("Delete your Ares account?", tableName: "Shared"), isPresented: $confirms,
                                    titleVisibility: .visible) {
                    Button(role: .destructive) { delete() } label: { Text("Delete account", tableName: "Shared") }
                    Button(role: .cancel) { flow.cancel() } label: { Text("Cancel", tableName: "Shared") }
                } message: {
                    Text("Your account and its data in every Ares app go for good.", tableName: "Shared")
                }
            }
        }
        .onChange(of: flow.phase) { _, phase in
            if phase == .confirming { confirms = true }        // the password is right: ask once more
        }
        .onAppear {
            if flow.phase == .confirming { confirms = true }
        }
    }

    /// Checks the password; once it is right, the confirmation opens (again, if it was closed without an answer).
    private func primary() {
        typing = false
        if flow.phase == .confirming { confirms = true } else { Task { await flow.check() } }
    }

    private func delete() {
        Task {
            await flow.delete()
            if flow.phase == .deleted { closeSettings() }
        }
    }
}

// MARK: - pieces

/// A page's frame inside the Settings sheet: the content, the actions at the bottom, the app's wall. While the page
/// `holds` (something is under way), neither going back nor closing the sheet is possible.
struct AccountPageFrame<Content: View, Actions: View>: View {
    let title: Text
    let accent: AppAccent?
    var holds = false
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            content
            actions.padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 10)
        }
        .background { SettingsWall(accent: accent) }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(holds)
        .interactiveDismissDisabled(holds)
    }
}

/// The page's explanation in a glass card: what happens, then (quieter) what stays.
struct AccountExplanation: View {
    let main: String
    let rest: String
    let accent: AppAccent?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(main).font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary).lineSpacing(3)
            Text(rest).font(AppFont.text(13.5)).foregroundStyle(Ink.secondary).lineSpacing(3)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassCard(accent: accent)
        .accessibilityElement(children: .combine)
    }
}
