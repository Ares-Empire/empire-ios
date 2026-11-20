import AppIntents
import SwiftUI
import WidgetKit

/// Arestia's Control Center controls (iOS 18 `ControlWidget`; Patrik, 2026-11-19: "shortcuts good idea, especially
/// control center (widgets not needed yet)"): Cooking and Fans as toggles, and one Blind control per blind chosen when
/// it is added. Each reads its state from flatd when Control Center shows it and acts through the intents
/// (`ControlIntents.swift`), with the key from Arestia's Keychain group; the app need not run. They act on the flat
/// paired when they run (one flat per install): after Forget and a new pairing that is the new flat, and until Control
/// Center reads them again a toggle may still show the old state. Their words follow the app's language
/// (`WidgetLanguage.arestia`); the gallery's name and description are iOS's, in the iPhone's language.
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
    static var onNotAllFollowed: String { text(LocalizedStringResource("On · not all followed", table: "ArestiaShared")) }
    static var offNotAllFollowed: String {
        text(LocalizedStringResource("Off · not all followed", table: "ArestiaShared"))
    }
    static var chooseBlind: String { text(LocalizedStringResource("Choose a blind", table: "ArestiaShared")) }
    static var notInFlat: String { text(LocalizedStringResource("Not in your flat", table: "ArestiaShared")) }
    static var positionUnknown: String { text(LocalizedStringResource("Position unknown", table: "ArestiaShared")) }
}

// MARK: - Cooking

struct CookingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ArestiaControlKind.cooking, provider: CookingValue()) { state in
            ControlWidgetToggle(isOn: state.active, action: SetCookingIntent()) {
                Label(ControlWords.cooking, systemImage: "flame")
            } valueLabel: { isOn in
                // Devices that did not follow the last change outside the app: said while it still describes cooking.
                if state.notFollowed.isEmpty {
                    Text(verbatim: isOn ? ControlWords.on : ControlWords.off)
                } else {
                    Text(verbatim: isOn ? ControlWords.onNotAllFollowed : ControlWords.offNotAllFollowed)
                }
            }
            .tint(AppAccent.arestia.color)
        }
        .displayName(LocalizedStringResource("Cooking", table: "ArestiaShared"))
        .description(LocalizedStringResource("Start or end cooking: the fans and the blind together.",
                                             table: "ArestiaShared"))
    }
}

struct CookingValue: ControlValueProvider {
    var previewValue: CookingState { CookingState(active: false, notFollowed: []) }

    func currentValue() async throws -> CookingState {
        try await FlatActions.live.cookingState()
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
                Text(verbatim: value.note ?? (isOn ? ControlWords.up : ControlWords.down))
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
    /// In place of Up / Down when there is no blind to show: none chosen, or one the flat does not have (any more).
    let note: String?
}

struct RolloValueProvider: AppIntentControlValueProvider {
    /// The gallery's preview: the chosen blind's name as kept for the paired flat now, else the plain word Blind
    /// (never the name kept in the configuration, which may be a forgotten flat's); never a state.
    func previewValue(configuration: RolloControlConfiguration) -> RolloControlValue {
        let name = DeviceChoices.name(of: configuration.rollo?.id, kind: .rollo, from: FlatdConnection.live.known)
        return RolloControlValue(rollo: configuration.rollo, name: name ?? ControlWords.blind, isOpen: false, note: nil)
    }

    /// The blind as flatd has it now. A choice the flat does not know (a blind gone from flatd, or chosen before the
    /// flat was forgotten) shows "Not in your flat" under the plain word Blind, never its old name or a made-up state;
    /// a blind flatd has no position for shows "Position unknown", never Up.
    func currentValue(configuration: RolloControlConfiguration) async throws -> RolloControlValue {
        switch try await FlatActions.live.rolloControl(configuration.rollo?.id) {
        case .notChosen:
            RolloControlValue(rollo: nil, name: ControlWords.blind, isOpen: false, note: ControlWords.chooseBlind)
        case .gone:
            RolloControlValue(rollo: configuration.rollo, name: ControlWords.blind, isOpen: false,
                              note: ControlWords.notInFlat)
        case let .unknown(name):
            RolloControlValue(rollo: configuration.rollo, name: name, isOpen: false, note: ControlWords.positionUnknown)
        case let .blind(name, isOpen):
            RolloControlValue(rollo: configuration.rollo, name: name, isOpen: isOpen, note: nil)
        }
    }
}
