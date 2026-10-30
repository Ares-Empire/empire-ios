import SwiftUI
import UIKit

/// The app a Settings screen belongs to.
struct SettingsApp {
    let name: String                    // "Arestoteles": also names the app in the iOS Settings path
    var accent: AppAccent? = nil        // the wall's light and the one highlight; nil = ink only (Aresium, Empire)
    var sendsNotifications = false      // a Notifications row, opening the app's notification page in iOS Settings
    /// The app's `DELETE …/me` when its server keeps data per account (today only Arestemis): leaving the app deletes it
    /// there first. nil: the server keeps nothing per account (Aresium, Aresus, Arestoteles hold only Patrik's data).
    var serverData: URL? = nil
    /// In an app that works without an account (`EmpireAppIdentity.accountOptional`, Aresium): the line under the
    /// signed-out "Ares account" row, what an account is for in this app.
    var signInNote: String? = nil
    /// Licences besides the fonts', on the Fonts & licences page (Aresium: its shop list's).
    var licences: [BundledLicence] = []
}

/// Every app's Settings (the gear in its header), one sheet in the family look: the app's own section (optional, the
/// `appSection` slot, e.g. Arestemis's application texts), then General (Language, Appearance; Notifications in apps
/// that send them), Help (the app's own help rows, optional, the `help` slot, e.g. Aresium's bank guide and tour; then
/// Contact & support), About (Privacy, Imprint, Fonts & licences, Version) and Account (email, Change password, Log out;
/// then Leave <app> and Delete Ares account, `AccountScreens.swift`).
/// An app that works without an account (Aresium) shows, while no Ares app on the iPhone is logged in, a quiet "Ares
/// account" section in place of Account: Sign in (`SignInSheet`) and the app's line on what an account is for.
/// Log out does what the app's log-out did before (in sample mode it leaves the sample); so does the end of leaving or
/// deleting in sample mode, where nothing is sent.
struct SettingsScreen<AppSection: View, AppHelp: View>: View {
    let app: SettingsApp
    let session: EmpireSession          // the account's email; the login the support form sends with (brief E5)
    var sample = false                  // sample mode: a made-up email, nothing is sent
    let logOut: () -> Void
    let appSection: AppSection
    /// The app's own rows at the top of Help (rows with `SettingsDivider` between them), above Contact & support.
    let appHelp: AppHelp

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    #if DEBUG
    /// Screenshots: `-openSupport` opens Contact & support at once.
    @State private var showsSupport = LaunchArguments.current.contains("-openSupport")
    #else
    @State private var showsSupport = false
    #endif
    #if DEBUG
    /// Screenshots: `-openLanguage` opens Settings → Language at once.
    @State private var showsLanguage = LaunchArguments.current.contains("-openLanguage")
    #else
    @State private var showsLanguage = false
    #endif
    #if DEBUG
    /// Screenshots: `-openAppearance` opens Settings → Appearance at once.
    @State private var showsAppearance = LaunchArguments.current.contains("-openAppearance")
    #else
    @State private var showsAppearance = false
    #endif
    #if DEBUG
    /// Screenshots: `-openFonts` opens Settings → About → Fonts & licences at once.
    @State private var showsFonts = LaunchArguments.current.contains("-openFonts")
    #else
    @State private var showsFonts = false
    #endif
    @AppStorage(Appearance.key) private var appearance = Appearance.iPhone.rawValue
    @State private var path: [AccountPage] = []
    /// Log out asks first (brief 41).
    @State private var logOutQuestion = LogOutQuestion()
    /// Privacy and Imprint inside the app (brief 41).
    @State private var browser = InAppBrowser()
    #if DEBUG
    /// Screenshots: `-openSignIn` opens the sign-in sheet at once (an app that works without an account, signed out).
    @State private var showsSignIn = LaunchArguments.current.contains("-openSignIn")
    #else
    @State private var showsSignIn = false
    #endif

    init(app: SettingsApp, session: EmpireSession, sample: Bool = false, logOut: @escaping () -> Void,
         @ViewBuilder appSection: () -> AppSection, @ViewBuilder help: () -> AppHelp) {
        self.app = app
        self.session = session
        self.sample = sample
        self.logOut = logOut
        self.appSection = appSection()
        self.appHelp = help()
        #if DEBUG
        _path = State(initialValue: AccountPage.launched().map { [$0] } ?? [])
        #endif
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        appSection
                        general
                        help
                        about
                        account.id(Self.accountID)
                    }
                    .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 34)
                }
                #if DEBUG
                .task(id: session.token == nil) {
                    // Screenshots: `-scrollToAccount` shows the Account section (again once a sample login arrived).
                    guard LaunchArguments.current.contains("-scrollToAccount") else { return }
                    try? await Task.sleep(for: .milliseconds(300))
                    proxy.scrollTo(Self.accountID, anchor: .bottom)
                }
                #endif
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background { SettingsWall(accent: app.accent) }
            .navigationTitle(Text("Settings", tableName: "Shared"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", tableName: "Shared") }
                }
            }
            .navigationDestination(for: AccountPage.self) { page in
                switch page {
                case .changePassword:
                    ChangePasswordScreen(app: app, session: session, sample: sample, closeSettings: accountEnded)
                case .leave: LeaveAppScreen(app: app, session: session, sample: sample, closeSettings: accountEnded)
                case .delete: DeleteAccountScreen(app: app, session: session, sample: sample, closeSettings: accountEnded)
                }
            }
        }
        .inAppBrowser(browser)
        .tint(Ink.primary)
        // Every switch inside, the app's own sections and pages too: on in a colour, never ink (brief 47).
        .toggleStyle(EmpireSwitchStyle(accent: app.accent))
        .presentationDetents([.large])
        .presentationBackground(Ink.background)
        .sheet(isPresented: $showsSupport) {
            SupportSheet(session: session, accent: app.accent, sample: sample)
        }
        .sheet(isPresented: $showsSignIn) {
            SignInSheet(session: session, accent: app.accent, note: app.signInNote)
        }
    }

    /// The app works without an account and no Ares app on the iPhone is logged in: Settings offers to sign in.
    private var signedOut: Bool { session.app.accountOptional && session.token == nil }

    private static var accountID: String { "settings-account" }

    // MARK: sections

    private var general: some View {
        SettingsSection(String(localized: LocalizedStringResource("General", table: "Shared", locale: .appLanguage))) {
            Button { showsLanguage = true } label: {
                SettingsRow(title: String(localized: LocalizedStringResource("Language", table: "Shared",
                                                                             locale: .appLanguage)),
                            value: AppLanguage.current.name)
            }
            .buttonStyle(SettingsRowStyle())
            .navigationDestination(isPresented: $showsLanguage) { LanguageScreen(app: app) }
            SettingsDivider()
            Button { showsAppearance = true } label: {
                SettingsRow(title: String(localized: LocalizedStringResource("Appearance", table: "Shared",
                                                                             locale: .appLanguage)),
                            value: Appearance(saved: appearance).name)
            }
            .buttonStyle(SettingsRowStyle())
            .navigationDestination(isPresented: $showsAppearance) { AppearanceScreen(app: app) }
            if app.sendsNotifications {
                SettingsDivider()
                Button { open(UIApplication.openNotificationSettingsURLString) } label: {
                    SettingsRow(title: String(localized: LocalizedStringResource("Notifications", table: "Shared",
                                                                                 locale: .appLanguage)),
                                subtitle: String(localized: LocalizedStringResource("In iOS Settings", table: "Shared",
                                                                                    locale: .appLanguage)),
                                trailing: .external)
                }
                .buttonStyle(SettingsRowStyle())
            }
        }
    }

    private var help: some View {
        SettingsSection(String(localized: LocalizedStringResource("Help", table: "Shared", locale: .appLanguage))) {
            if !(appHelp is EmptyView) {
                appHelp
                SettingsDivider()
            }
            Button { showsSupport = true } label: {
                SettingsRow(title: String(localized: LocalizedStringResource("Contact & support", table: "Shared",
                                                                             locale: .appLanguage)))
            }
            .buttonStyle(SettingsRowStyle())
        }
    }

    private var about: some View {
        SettingsSection(String(localized: LocalizedStringResource("About", table: "Shared", locale: .appLanguage))) {
            // Privacy and Imprint open inside the app, in Apple's in-app browser with its own close button (brief 41), not in Safari.
            Button { openLegal(.privacy) } label: {
                SettingsRow(title: String(localized: LocalizedStringResource("Privacy", table: "Shared",
                                                                             locale: .appLanguage)),
                            trailing: .external)
            }
            .buttonStyle(SettingsRowStyle())
            SettingsDivider()
            Button { openLegal(.imprint) } label: {
                SettingsRow(title: String(localized: LocalizedStringResource("Imprint", table: "Shared",
                                                                             locale: .appLanguage)),
                            trailing: .external)
            }
            .buttonStyle(SettingsRowStyle())
            SettingsDivider()
            Button { showsFonts = true } label: {
                SettingsRow(title: String(localized: LocalizedStringResource("Fonts & licences", table: "Shared",
                                                                             locale: .appLanguage)))
            }
            .buttonStyle(SettingsRowStyle())
            .navigationDestination(isPresented: $showsFonts) { FontsScreen(accent: app.accent, licences: app.licences) }
            SettingsDivider()
            HStack {
                Text("Version", tableName: "Shared").font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                Spacer(minLength: 12)
                Text(verbatim: AppVersion.text()).font(AppFont.number(13, weight: .regular)).foregroundStyle(Ink.secondary)
            }
            .frame(minHeight: 50).padding(.horizontal, 16)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var account: some View {
        if signedOut { signIn } else { signedIn }
    }

    /// Signed out, in an app that works without an account: a quiet row to sign in, and what an account is for here.
    private var signIn: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSection(String(localized: LocalizedStringResource("Ares account", table: "Shared",
                                                                      locale: .appLanguage))) {
                Button { showsSignIn = true } label: {
                    SettingsRow(title: String(localized: LocalizedStringResource("Sign in", table: "Shared",
                                                                                 locale: .appLanguage)),
                                tint: Ink.secondary)
                }
                .buttonStyle(SettingsRowStyle())
            }
            if let note = app.signInNote { FormNote(text: note) }
        }
    }

    private var signedIn: some View {
        VStack(spacing: 12) {
            SettingsSection(session.app.accountOptional
                            ? String(localized: LocalizedStringResource("Ares account", table: "Shared", locale: .appLanguage))
                            : String(localized: LocalizedStringResource("Account", table: "Shared", locale: .appLanguage))) {
                if let email = sample ? "sample@example.com" : session.email {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Signed in as", tableName: "Shared").font(AppFont.text(12)).foregroundStyle(Ink.muted)
                        Text(verbatim: email).font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading).padding(.horizontal, 16)
                    .accessibilityElement(children: .combine)
                    SettingsDivider()
                }
                NavigationLink(value: AccountPage.changePassword) {
                    SettingsRow(title: String(localized: LocalizedStringResource("Change password", table: "Shared",
                                                                                 locale: .appLanguage)))
                }
                .buttonStyle(SettingsRowStyle())
                SettingsDivider()
                Button { logOutQuestion.ask() } label: {
                    SettingsRow(title: String(localized: LocalizedStringResource("Log out", table: "Shared",
                                                                                 locale: .appLanguage)),
                                subtitle: String(localized: LocalizedStringResource("In all Ares apps on this iPhone",
                                                                                    table: "Shared",
                                                                                    locale: .appLanguage)),
                                trailing: .none)
                }
                .buttonStyle(SettingsRowStyle())
                // Asked first (brief 41): one login serves every Ares app on this iPhone.
                .confirmationDialog(Text(verbatim: LogOutQuestion.title()),
                                    isPresented: Binding(get: { logOutQuestion.isAsking },
                                                         set: { if !$0 { logOutQuestion.cancel() } }),
                                    titleVisibility: .visible) {
                    Button(role: .destructive) {
                        logOutQuestion.confirm {
                            dismiss()
                            logOut()
                        }
                    } label: { Text("Log out", tableName: "Shared") }
                    Button(role: .cancel) { logOutQuestion.cancel() } label: { Text("Cancel", tableName: "Shared") }
                } message: {
                    Text(verbatim: LogOutQuestion.message(app: app.name, keepsData: session.app.accountOptional))
                }
            }
            // Leaving and deleting apart from the everyday rows, in the hub's soft red. Leaving only while the account
            // has this app (an app that works without an account opens with any login).
            VStack(spacing: 0) {
                if sample || session.services.contains(session.app.service) {
                    NavigationLink(value: AccountPage.leave) {
                        SettingsRow(title: String(localized: LocalizedStringResource("Leave \(app.name)", table: "Shared",
                                                                                     locale: .appLanguage)), tint: FormButtonStyle.dangerInk)
                    }
                    .buttonStyle(SettingsRowStyle())
                    SettingsDivider()
                }
                NavigationLink(value: AccountPage.delete) {
                    SettingsRow(title: String(localized: LocalizedStringResource("Delete Ares account",
                                                                                 table: "Shared", locale: .appLanguage)),
                                tint: FormButtonStyle.dangerInk)
                }
                .buttonStyle(SettingsRowStyle())
            }
            .glassCard()
        }
    }

    /// The account left this app or was deleted: close Settings (the app shows its no-access screen or the login; an
    /// app that works without an account goes on as it is). In sample mode nothing was sent, so leave the sample for the
    /// login, as Log out does.
    private func accountEnded() {
        dismiss()
        if sample { logOut() }
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { openURL(url) }
    }

    /// A legal page inside the app; Safari only if the in-app browser cannot show it.
    private func openLegal(_ page: LegalPage) {
        if !browser.open(page.url()) { openURL(page.url()) }
    }
}

extension SettingsScreen where AppHelp == EmptyView {
    init(app: SettingsApp, session: EmpireSession, sample: Bool = false, logOut: @escaping () -> Void,
         @ViewBuilder appSection: () -> AppSection) {
        self.init(app: app, session: session, sample: sample, logOut: logOut, appSection: appSection) { EmptyView() }
    }
}

extension SettingsScreen where AppSection == EmptyView, AppHelp == EmptyView {
    init(app: SettingsApp, session: EmpireSession, sample: Bool = false, logOut: @escaping () -> Void) {
        self.init(app: app, session: session, sample: sample, logOut: logOut) { EmptyView() }
    }
}

// MARK: - pieces (public so an app's own section can look the same)

/// A section of the Settings screen: a tracked-caps heading over one glass card of rows.
struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: title).padding(.leading, 4)
            VStack(spacing: 0) { content }.glassCard()
        }
        .padding(.top, 26)
    }
}

/// One row: the title on the left, an optional quiet value, and where it leads (a page, or out of the app).
struct SettingsRow: View {
    enum Trailing { case push, external, none }

    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var trailing: Trailing = .push
    var tint: Color = Ink.primary       // the title's colour (the hub's soft red for leaving and deleting)

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.text(15, weight: .medium)).foregroundStyle(tint)
                if let subtitle { Text(subtitle).font(AppFont.text(12)).foregroundStyle(Ink.muted) }
            }
            Spacer(minLength: 12)
            if let value { Text(value).font(AppFont.text(15)).foregroundStyle(Ink.secondary).lineLimit(1) }
            switch trailing {
            case .push:
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.muted)
            case .external:
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.muted)
            case .none:
                EmptyView()
            }
        }
        .frame(minHeight: subtitle == nil ? 50 : 58).padding(.horizontal, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The thin line between rows inside a card.
struct SettingsDivider: View {
    var body: some View { Rectangle().fill(Ink.line).frame(height: 1).padding(.horizontal, 16) }
}

/// A row that answers a press with a faint shade, like the rows of iOS's own lists.
struct SettingsRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Ink.press : .clear)
    }
}

/// The wall, with the app's accent as a faint light when it has one.
struct SettingsWall: View {
    let accent: AppAccent?
    var body: some View {
        if let accent { ProvinceWall(accent: accent) } else { Ink.background.ignoresSafeArea() }
    }
}

// MARK: - About pages

/// Settings → About → Fonts & licences: the two typefaces, each opening its licence, and the app's other licences
/// (`SettingsApp.licences`) in a card of their own; with none, the fonts' card alone, as before.
struct FontsScreen: View {
    let accent: AppAccent?
    var licences: [BundledLicence] = []
    #if DEBUG
    /// Screenshots: `-openLicence <name>` opens that licence at once (`-openFonts -openLicence name-suggestion-index`).
    @State private var shown: BundledLicence?
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if licences.isEmpty {
                    VStack(spacing: 0) { fonts }.glassCard().padding(.top, 22)
                } else {
                    SettingsSection(String(localized: LocalizedStringResource("Fonts", table: "Shared",
                                                                              locale: .appLanguage))) { fonts }
                    SettingsSection(String(localized: LocalizedStringResource("Data", table: "Shared",
                                                                              locale: .appLanguage))) {
                        ForEach(Array(licences.enumerated()), id: \.element.id) { index, licence in
                            if index > 0 { SettingsDivider() }
                            NavigationLink {
                                LicenceScreen(title: licence.name, text: licence.text(), accent: accent)
                            } label: {
                                row(Text(verbatim: licence.name).font(AppFont.text(15, weight: .medium)),
                                    detail: "\(licence.purpose) · \(licence.licenceName)")
                            }
                            .buttonStyle(SettingsRowStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .background { SettingsWall(accent: accent) }
        .navigationTitle(Text("Fonts & licences", tableName: "Shared"))
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG
        .navigationDestination(item: $shown) { licence in
            LicenceScreen(title: licence.name, text: licence.text(), accent: accent)
        }
        .task {
            let arguments = LaunchArguments.current
            if let index = arguments.firstIndex(of: "-openLicence"), arguments.indices.contains(index + 1) {
                shown = licences.first { $0.name == arguments[index + 1] }
            }
        }
        #endif
    }

    /// The typefaces' rows (the card is the caller's: alone, or a section's).
    @ViewBuilder private var fonts: some View {
        ForEach(Array(BundledFont.allCases.enumerated()), id: \.element) { index, font in
            if index > 0 { SettingsDivider() }
            NavigationLink {
                LicenceScreen(title: font.rawValue, text: font.licence(), accent: accent)
            } label: {
                row(Text(verbatim: font.rawValue)
                        .font(font == .jetBrainsMono ? AppFont.number(15, weight: .medium) : AppFont.text(15, weight: .medium)),
                    detail: BundledFont.licenceName)
            }
            .buttonStyle(SettingsRowStyle())
        }
    }

    private func row(_ title: Text, detail: String) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                title.foregroundStyle(Ink.primary)
                Text(verbatim: detail).font(AppFont.text(12)).foregroundStyle(Ink.muted)
            }
            Spacer(minLength: 12)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Ink.muted)
        }
        .frame(minHeight: 58).padding(.horizontal, 16).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// One licence file, as it ships with the app (English, like the licence itself): a typeface's or another licence's.
struct LicenceScreen: View {
    let title: String
    let text: String?
    let accent: AppAccent?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let paragraphs = text.map(LicenceParagraph.paragraphs) ?? []
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    if paragraph.isHeading {
                        SectionHeading(text: paragraph.text).padding(.top, 10)
                    } else {
                        Text(verbatim: paragraph.text)
                            .font(AppFont.text(index == 0 ? 14 : 13, weight: index == 0 ? .medium : .regular))
                            .foregroundStyle(index == 0 ? Ink.primary : Ink.secondary)
                            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .background { SettingsWall(accent: accent) }
        .navigationTitle(Text(verbatim: title))
        .navigationBarTitleDisplayMode(.inline)
    }
}
