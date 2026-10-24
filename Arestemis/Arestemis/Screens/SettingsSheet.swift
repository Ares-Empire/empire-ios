import SwiftUI

/// Application (own text or AI per listing, the own text, facts about you), notifications, the account. Changes are
/// saved when the sheet closes (Done or swiping it away).
struct SettingsSheet: View {
    let store: ArestemisStore
    let logOut: () -> Void
    @State private var draft: Settings?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let draft = Binding($draft) {
                        application(draft)
                        notifications(draft)
                    } else if let error = store.settingsError {
                        CalmMessage(text: error, action: (String(localized: "Try again"), { Task { await load() } }))
                    } else {
                        CalmMessage(text: String(localized: "Loading settings…"), loading: true)
                    }
                    account
                }
                .padding(.horizontal, Look.side).padding(.top, 4).padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .provinceWall()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { endTyping() }
                }
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
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Look.headingGap) {
            SectionHeading(text: title).padding(.leading, 4)
            content()
        }
        .padding(.top, 22)
    }

    // MARK: application

    private func application(_ settings: Binding<Settings>) -> some View {
        section(String(localized: "Application")) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Application text", selection: settings.applicationMode) {
                    Text("Your text").tag(ApplicationMode.own)
                    Text("AI per listing").tag(ApplicationMode.ai)
                }
                .pickerStyle(.segmented)
                Caption(text: settings.wrappedValue.applicationMode == .own
                        ? String(localized: "Your text as it is, with the greeting adapted when the contact's name is known.")
                        : String(localized: "The AI writes a German text for each listing, from your text and the facts about you."))
                    .padding(.horizontal, 4)
            }
            .padding(.bottom, 8)
            CapsLabel(text: String(localized: "Your text"), size: 10.5).padding(.leading, 4).padding(.top, 8)
            TextArea(placeholder: String(localized: "Hallo, …"), text: settings.ownText, minHeight: 150, font: AppFont.text(14), inWell: false)
                .glassCard()
            CapsLabel(text: String(localized: "About you"), size: 10.5).padding(.leading, 4).padding(.top, 14)
            TextArea(placeholder: String(localized: "Age, studies or job, non-smoker, …"), text: settings.aboutMe, minHeight: 96,
                     font: AppFont.text(14), inWell: false)
                .glassCard()
            Caption(text: String(localized: "Facts the AI may use; it never invents others. Give your gender and age: many listings are only for women, men or an age range, and the check needs them.")).padding(.leading, 4)
        }
    }

    // MARK: notifications

    private func notifications(_ settings: Binding<Settings>) -> some View {
        section(String(localized: "Notifications")) {
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
    }

    // MARK: account

    private var account: some View {
        section(String(localized: "Account")) {
            VStack(spacing: 0) {
                if let name = store.overview?.me.name {
                    HStack {
                        rowLabel(String(localized: "Signed in as"))
                        Spacer()
                        Text(name).font(AppFont.text(15)).foregroundStyle(Ink.secondary)
                    }
                    .frame(minHeight: 50)
                    .padding(.horizontal, 16)
                    .accessibilityElement(children: .combine)
                    Hairline()
                }
                Button {
                    dismiss()
                    logOut()
                } label: {
                    Text("Log out").font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                        .frame(maxWidth: .infinity, minHeight: 50).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .glassCard()
        }
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text).font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
    }
}
