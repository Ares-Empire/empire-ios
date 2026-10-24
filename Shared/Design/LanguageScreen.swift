import SwiftUI

/// Settings → Language: like the iPhone, English or Deutsch, saved where iOS keeps an app's own language
/// (`LanguageSetting`). The choice takes effect when the app next starts, so a line says so once it is changed;
/// below, where iOS keeps the same setting.
struct LanguageScreen: View {
    let app: SettingsApp
    private let setting: LanguageSetting
    private let current = AppLanguage.current
    @State private var choice: AppLanguage?
    @State private var changedHere = false

    init(app: SettingsApp, setting: LanguageSetting = .standard) {
        self.app = app
        self.setting = setting
        _choice = State(initialValue: setting.choice)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    option(nil, title: String(localized: "Like the iPhone", table: "Shared"))
                    SettingsDivider()
                    option(.english, title: AppLanguage.english.name)
                    SettingsDivider()
                    option(.german, title: AppLanguage.german.name)
                }
                .glassCard()

                if setting.announcesSwitch(current: current, changedHere: changedHere) {
                    Text("Takes effect after you close \(app.name) and open it again.", tableName: "Shared")
                        .font(AppFont.text(13)).foregroundStyle(Ink.secondary).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4).padding(.top, 14)
                        .transition(.opacity)
                }
                Text("iOS keeps the same setting in Settings → Apps → \(app.name) → Language, shown there when the iPhone has more than one language.",
                     tableName: "Shared")
                    .font(AppFont.text(12)).foregroundStyle(Ink.muted).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4).padding(.top, 14)
            }
            .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 34)
            .animation(.easeOut(duration: 0.2), value: choice)
        }
        .scrollIndicators(.hidden)
        .background { SettingsWall(accent: app.accent) }
        .navigationTitle(Text("Language", tableName: "Shared"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func option(_ language: AppLanguage?, title: String) -> some View {
        let selected = choice == language
        return Button {
            guard !selected else { return }
            setting.choose(language)
            choice = setting.choice
            changedHere = true
        } label: {
            HStack(spacing: 10) {
                Text(verbatim: title).font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                Spacer(minLength: 12)
                Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(app.accent?.color ?? Ink.primary)
                    .opacity(selected ? 1 : 0)
            }
            .frame(minHeight: 50).padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsRowStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
