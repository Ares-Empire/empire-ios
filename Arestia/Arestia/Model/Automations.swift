import Foundation

/// One row of the home screen's Automations card: what runs by itself or from outside the app, in a line. The modes and
/// scenes come from flatd's own lists with their devices' names; what they do is the contract's (flatd's API.md, v1.1).
struct AutomationRow: Equatable {
    let symbol: String
    let title: String
    let text: String

    static func rows(modes: [FlatMode], scenes: [FlatScene], devices: [Device],
                     language: AppLanguage = .current) -> [AutomationRow] {
        let named = { (ids: [String], kind: Device.Kind) -> String? in
            let names = ids.compactMap { id in devices.first { $0.id == id && $0.kind == kind }?.label }
            return names.isEmpty ? nil : names.formatted(.list(type: .and).locale(language.locale))
        }
        var rows: [AutomationRow] = []
        for mode in modes {
            let fans = named(mode.devices, .fan), blinds = named(mode.devices, .rollo)
            let text: String
            if mode.id == FlatMode.cookingID {
                switch (fans, blinds) {
                case let (fans?, blinds?):
                    text = language.string("\(fans) on, \(blinds) up. Done cooking: fans off, the blind to its favourite spot.")
                case let (fans?, nil):
                    text = language.string("\(fans) on. Done cooking: fans off.")
                default:
                    text = language.string("On until you end it.")
                }
            } else {
                text = language.string("On until you end it.")
            }
            rows.append(AutomationRow(symbol: FlatWords.symbol(mode: mode.id),
                                      title: FlatWords.modeTitle(mode, language: language), text: text))
        }
        for scene in scenes {
            let fans = named(scene.devices, .fan), blinds = named(scene.devices, .rollo)
            let text: String
            switch scene.id {
            case FlatScene.airOutID:
                text = switch (fans, blinds) {
                case let (fans?, blinds?): language.string("\(fans) on for 30 min, \(blinds) up.")
                case let (fans?, nil): language.string("\(fans) on for 30 min.")
                default: language.string("Runs once.")
                }
            case FlatScene.allDownID:
                text = blinds.map { language.string("\($0) down.") } ?? language.string("Runs once.")
            default:
                text = language.string("Runs once.")
            }
            rows.append(AutomationRow(symbol: FlatWords.symbol(mode: scene.id),
                                      title: FlatWords.sceneTitle(scene, language: language), text: text))
        }
        if devices.contains(where: { $0.kind == .fan }) {
            rows.append(AutomationRow(symbol: "timer", title: language.string("Fan timers"),
                                      text: language.string("The plug runs the timer: the fan goes off by itself, even when the Mac sleeps.")))
        }
        rows.append(AutomationRow(symbol: "wave.3.right", title: language.string("NFC tag"),
                                  text: language.string("Shortcuts → Automation → NFC: hold the iPhone to the tag, then choose Arestia's Start cooking.")))
        rows.append(AutomationRow(symbol: "switch.2", title: language.string("Control Center"),
                                  text: language.string("Cooking, Fans and a blind: open Control Center, hold, then + and Arestia.")))
        return rows
    }
}
