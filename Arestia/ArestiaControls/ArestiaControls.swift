import AppIntents
import SwiftUI
import WidgetKit

/// Arestia's Control Center controls (iOS 18 `ControlWidget`; Patrik, 2026-11-19: "shortcuts good idea, especially
/// control center (widgets not needed yet)"): Cooking and Fans as toggles, and one Blind control per blind chosen when
/// it is added. Each reads its state from flatd when Control Center shows it and acts through the app's intents
/// (`ArestiaIntents.swift`), with the key from Arestia's Keychain group; the app need not run. Their words follow the
/// app's language (`WidgetLanguage.arestia`); the gallery's name and description are iOS's, in the iPhone's language.
@main
struct ArestiaControlsBundle: WidgetBundle {
    var body: some Widget {
        CookingControl()
        FansControl()
        RolloControl()
    }
}

/// The words the controls show, in the app's language (their own process follows the app's choice first).
nonisolated enum ControlWords {
    private static func text(_ resource: LocalizedStringResource) -> String {
        WidgetLanguage.arestia.follow()
        return AppLanguage.current.string(resource)
    }

    static var cooking: String { text(LocalizedStringResource("Cooking", table: "ArestiaShared")) }
    static var fans: String { text(LocalizedStringResource("Fans", table: "ArestiaShared")) }
    static var blind: String { text(LocalizedStringResource("Blind", table: "ArestiaShared")) }
    static var on: String { text(LocalizedStringResource("On", table: "ArestiaShared")) }
    static var off: String { text(LocalizedStringResource("Off", table: "ArestiaShared")) }
    static var up: String { text(LocalizedStringResource("Up", table: "ArestiaShared")) }
    static var down: String { text(LocalizedStringResource("Down", table: "ArestiaShared")) }
}

// MARK: - Cooking

struct CookingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ArestiaControlKind.cooking, provider: CookingValue()) { active in
            ControlWidgetToggle(isOn: active, action: SetCookingIntent()) {
                Label(ControlWords.cooking, systemImage: "flame")
            } valueLabel: { isOn in
                Text(verbatim: isOn ? ControlWords.on : ControlWords.off)
            }
            .tint(AppAccent.arestia.color)
        }
        .displayName(LocalizedStringResource("Cooking", table: "ArestiaShared"))
        .description(LocalizedStringResource("Start or end cooking: the fans and the blind together.",
                                             table: "ArestiaShared"))
    }
}

struct CookingValue: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        try await FlatActions.live.isCooking()
    }
}

// MARK: - Fans

struct FansControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ArestiaControlKind.fans, provider: FansValue()) { running in
            ControlWidgetToggle(isOn: running, action: SetFansIntent()) {
                Label(ControlWords.fans, systemImage: "fan")
            } valueLabel: { isOn in
                Text(verbatim: isOn ? ControlWords.on : ControlWords.off)
            }
            .tint(AppAccent.arestia.color)
        }
        .displayName(LocalizedStringResource("Fans", table: "ArestiaShared"))
        .description(LocalizedStringResource("Every fan on or off.", table: "ArestiaShared"))
    }
}

struct FansValue: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        try await FlatActions.live.fansRunning()
    }
}

// MARK: - Blind (one per blind, chosen when the control is added)

struct RolloControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: ArestiaControlKind.rollo, provider: RolloValueProvider()) { value in
            ControlWidgetToggle(isOn: value.isOpen, action: SetRolloOpenIntent(rollo: value.rollo)) {
                Label(value.name, systemImage: value.isOpen ? "blinds.horizontal.open" : "blinds.horizontal.closed")
            } valueLabel: { isOn in
                Text(verbatim: isOn ? ControlWords.up : ControlWords.down)
            }
            .tint(AppAccent.arestia.color)
        }
        .promptsForUserConfiguration()
        .displayName(LocalizedStringResource("Blind", table: "ArestiaShared"))
        .description(LocalizedStringResource("Sends a blind up or down.", table: "ArestiaShared"))
    }
}

struct RolloControlValue {
    let rollo: RolloEntity?
    let name: String
    let isOpen: Bool
}

struct RolloValueProvider: AppIntentControlValueProvider {
    func previewValue(configuration: RolloControlConfiguration) -> RolloControlValue {
        RolloControlValue(rollo: configuration.rollo, name: configuration.rollo?.name ?? ControlWords.blind,
                          isOpen: true)
    }

    func currentValue(configuration: RolloControlConfiguration) async throws -> RolloControlValue {
        guard let rollo = configuration.rollo else { return previewValue(configuration: configuration) }
        let device = try await FlatActions.live.rollo(rollo.id)
        return RolloControlValue(rollo: rollo, name: device?.label ?? rollo.name,
                                 isOpen: device.map { RolloOpenness.isOpen($0.state) } ?? true)
    }
}
