import SwiftUI

/// Arestemis's Settings: the shared screen (Shared/Design/SettingsScreen) with the app's own sections on top: the hunts'
/// notifications, then, under "Flat applications" (applications are only written for flats), the application (brief 61): a switch
/// between automatic texts and the own text, the row that follows it (the own text, or the notes for automatic texts)
/// and About you, each opening a page with its text field.
/// Every change edits one draft, saved when the sheet closes (Done or swiping it away), also from a page.
struct SettingsSheet: View {
    let store: ArestemisStore
    let logOut: () -> Void
    @State private var draft: Settings?
    /// The text page pushed over Settings.
    @State private var page: ApplicationPage?

    /// Starts with the settings the store already has (loaded with the home screen), so the sheet opens with its
    /// sections instead of "Loading settings…" swapped for them mid-animation.
    init(store: ArestemisStore, logOut: @escaping () -> Void) {
        self.store = store
        self.logOut = logOut
        _draft = State(initialValue: store.settings)
    }

    var body: some View {
        SettingsScreen(app: SettingsApp(name: "Arestemis", accent: Look.accent, sendsNotifications: true,
                                       serverData: ArestemisAPI.accountDataURL, licences: [.townLocations()]),
                       session: store.session, sample: store.isSample, logOut: logOut) {
            if let draft = Binding($draft) {
                notifications(draft)
                application(draft)
            } else if let error = store.settingsError {
                CalmMessage(text: error, action: (String(localized: "Try again"), { Task { await load() } }))
                    .padding(.top, 26)
            } else {
                CalmMessage(text: String(localized: "Loading settings…"), loading: true).padding(.top, 26)
            }
        }
        .task { await load() }
        .onDisappear {
            if let draft { Task { await store.saveSettings(draft) } }
        }
    }

    private func load() async {
        if store.settings == nil { await store.loadSettings() }
        if draft == nil { draft = store.settings }
        #if DEBUG
        // Screenshots: `-openSettingsPage ownText|notes|aboutMe` pushes that page once the texts are there.
        if store.isSample, draft != nil, page == nil,
           let launched = LaunchArguments.value("-openSettingsPage").flatMap(ApplicationPage.init(rawValue:)) {
            page = launched
        }
        #endif
    }

    // MARK: notifications

    private func notifications(_ settings: Binding<Settings>) -> some View {
        VStack(alignment: .leading, spacing: Look.headingGap) {
            SectionHeading(text: String(localized: "Notifications")).padding(.leading, 4)
            FormCard {
                Toggle(isOn: settings.notify.push) { rowLabel(String(localized: "Push")) }
                    .tint(Look.accent.color).frame(minHeight: 50)
                Hairline()
                Toggle(isOn: settings.notify.timeSensitive) {
                    VStack(alignment: .leading, spacing: 2) {
                        rowLabel(String(localized: "Time-sensitive"))
                        Text("Shows even in Focus").font(AppFont.text(12)).foregroundStyle(Ink.muted)
                    }
                }
                .tint(Look.accent.color).frame(minHeight: 58)
                .disabled(!settings.wrappedValue.notify.push)
            }
        }
        .padding(.top, 26)
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text).font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
    }

    // MARK: application

    /// One card of rows like General's, under "Flat applications": the switch, the text it leads to, About you.
    private func application(_ settings: Binding<Settings>) -> some View {
        let written = ApplicationPage.written(for: settings.wrappedValue.applicationMode)
        return SettingsSection(String(localized: "Flat applications")) {
            Toggle(isOn: Binding(get: { settings.wrappedValue.applicationMode == .ai },
                                 set: { settings.wrappedValue.applicationMode = $0 ? .ai : .own })) {
                VStack(alignment: .leading, spacing: 2) {
                    rowLabel(String(localized: "Write automatically"))
                    Text("One text per listing").font(AppFont.text(12)).foregroundStyle(Ink.muted)
                }
            }
            .padding(.horizontal, 16).frame(minHeight: 58)
            SettingsDivider()
            textRow(written, settings.wrappedValue)
            SettingsDivider()
            textRow(.aboutMe, settings.wrappedValue)
        }
        .navigationDestination(item: $page) { page in
            ApplicationTextPage(page: page, text: text(page))
        }
    }

    /// A row that opens its page; under the title the start of what is written, else that nothing is.
    private func textRow(_ page: ApplicationPage, _ settings: Settings) -> some View {
        Button { self.page = page } label: {
            SettingsRow(title: page.title(), subtitle: page.summary(of: settings))
                .lineLimit(1)                                   // the preview stays on one line
        }
        .buttonStyle(SettingsRowStyle())
    }

    /// The draft's text for a page.
    private func text(_ page: ApplicationPage) -> Binding<String> {
        Binding(get: { draft?[keyPath: page.field] ?? "" }, set: { draft?[keyPath: page.field] = $0 })
    }
}

/// Settings → Application → Your text, Notes or About you: one text field in a glass card and what it is for, like the
/// Language page; the keyboard's Done closes the keyboard. The text is the Settings draft's.
private struct ApplicationTextPage: View {
    let page: ApplicationPage
    @Binding var text: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TextArea(placeholder: page.placeholder(), text: $text, minHeight: page == .ownText ? 260 : 160,
                         inWell: false)
                    .glassCard()
                Caption(text: page.caption()).padding(.horizontal, 4).padding(.top, 14)
            }
            .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background { SettingsWall(accent: Look.accent) }
        .navigationTitle(Text(verbatim: page.title()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { endTyping() }
            }
        }
    }
}
