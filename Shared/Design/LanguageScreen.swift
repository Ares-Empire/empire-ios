import SwiftUI

/// Settings → Language: like the iPhone, English or Deutsch, saved where iOS keeps an app's own language
/// (`LanguageSetting`). A row that brings another language asks first (`LanguageSwitch`: in the language it switches
/// to, Cancel in the current one), then the app restarts in it (`LanguageRoot`); below, where iOS keeps it too.
struct LanguageScreen: View {
    let app: SettingsApp
    private let setting: LanguageSetting
    private let shown = AppLanguage.current
    @State private var choice: AppLanguage?
    @State private var pending: LanguageSwitch?
    @Environment(\.switchLanguage) private var switchLanguage

    init(app: SettingsApp, setting: LanguageSetting = .standard) {
        self.app = app
        self.setting = setting
        _choice = State(initialValue: setting.choice)
        #if DEBUG
        // Screenshots: `-confirmLanguage en|de|iphone` shows the confirmation as if that row had been tapped.
        if let value = LaunchArguments.value("-confirmLanguage"),
           case .confirm(let change) = LanguageTap.tap(AppLanguage(rawValue: value), choice: setting.choice,
                                                      shown: shown, iPhone: { setting.iPhoneLanguage }) {
            _pending = State(initialValue: change)
        }
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    option(nil, title: String(localized: LocalizedStringResource("Like the iPhone", table: "Shared",
                                                                                 locale: .appLanguage)))
                    SettingsDivider()
                    option(.english, title: AppLanguage.english.name)
                    SettingsDivider()
                    option(.german, title: AppLanguage.german.name)
                }
                .glassCard()

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
        .alert(Text(verbatim: pending?.title ?? ""), isPresented: isAsking, presenting: pending) { change in
            Button(role: .cancel) { } label: { Text("Cancel", tableName: "Shared") }
            Button { switchLanguage(change) } label: { Text(verbatim: change.confirm) }
        } message: { change in
            Text(verbatim: change.message(app: app.name))
        }
    }

    private var isAsking: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    private func option(_ language: AppLanguage?, title: String) -> some View {
        let selected = choice == language
        return Button {
            switch LanguageTap.tap(language, choice: choice, shown: shown, iPhone: { setting.iPhoneLanguage }) {
            case .keep:
                break
            case .save(let change):
                switchLanguage(change)                  // saved (and told to the widget), the same language: no restart
                choice = setting.choice
            case .confirm(let change):
                pending = change
            }
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
