import Foundation

/// A device's own name (Patrik, 2026-11-20: "can we make the names of things changable so I can name rename things?").
/// The name lives in flatd (contract v1.3, "Renaming a device"), so the app, its Shortcuts and Control Center controls,
/// the 3D page, the desktop viewer and Claude all show one name. These are flatd's rules as the rename field applies
/// them while typing and before sending, so flatd refuses nothing the field let through. Pure, so the tests pin them.
enum DeviceNames {
    /// flatd's limit: characters (Unicode code points) after trimming, in NFC.
    static let maxLength = 40

    /// What saving a name does to a device's name.
    enum Change: Equatable {
        /// Its own name, as flatd keeps it.
        case own(String)
        /// flatd's config name again (the own name cleared).
        case original

        /// The body's `label`: nil asks flatd for its config name.
        var label: String? {
            if case let .own(name) = self { name } else { nil }
        }
    }

    /// What the field keeps of what was typed or pasted: no control characters, a line break as a space, and no more
    /// than flatd takes (whole characters dropped from the end, so an emoji is never cut in half).
    static func typed(_ text: String) -> String {
        var kept = ""
        for character in text {
            if character.isNewline {
                kept.append(" ")
            } else if !character.unicodeScalars.contains(where: isRefused) {
                kept.append(character)
            }
        }
        while cleaned(kept).unicodeScalars.count > maxLength { kept.removeLast() }
        return kept
    }

    /// The name as flatd keeps it: trimmed, in NFC.
    static func cleaned(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }

    /// What saving `text` changes: nil when nothing (the name it has, or an empty field on a device without an own
    /// name); `.original` for an empty field or flatd's config name; else the own name.
    static func change(_ text: String, for device: Device) -> Change? {
        let name = cleaned(typed(text))
        if name.isEmpty { return device.hasOwnName ? .original : nil }
        if name == device.label { return nil }
        if name == device.defaultLabel { return .original }
        return .own(name)
    }

    /// The name a change will show once flatd confirms it.
    static func shown(_ change: Change, for device: Device) -> String {
        switch change {
        case let .own(name): name
        case .original: device.defaultLabel ?? device.label
        }
    }

    /// Control characters, line and paragraph separators, lone surrogates: never in a name (flatd refuses them).
    private static func isRefused(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator, .surrogate: true
        default: false
        }
    }
}
