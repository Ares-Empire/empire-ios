import SwiftUI

/// Settings → Appearance: like the iPhone, light or dark. The app (this page and Settings with it) switches at once,
/// without a restart.
struct AppearanceScreen: View {
    let app: SettingsApp
    @AppStorage(Appearance.key) private var saved = Appearance.iPhone.rawValue

    var body: some View {
        let choice = Appearance(saved: saved)
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(Appearance.allCases.enumerated()), id: \.element) { index, option in
                    if index > 0 { SettingsDivider() }
                    Button { saved = option.rawValue } label: {
                        HStack(spacing: 10) {
                            Text(verbatim: option.name).font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                            Spacer(minLength: 12)
                            Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(app.accent?.color ?? Ink.primary)
                                .opacity(choice == option ? 1 : 0)
                        }
                        .frame(minHeight: 50).padding(.horizontal, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SettingsRowStyle())
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(choice == option ? .isSelected : [])
                }
            }
            .glassCard()
            .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .background { SettingsWall(accent: app.accent) }
        .navigationTitle(Text("Appearance", tableName: "Shared"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
