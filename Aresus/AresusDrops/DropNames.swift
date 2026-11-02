import Foundation

nonisolated enum DropSource: String, Codable, CaseIterable, Sendable { case file, photo, camera }

/// Validation returns a rule, leaving wording to the future screen. All limits count NFC UTF-8 bytes.
nonisolated enum DropNames {
    enum Rule: Error, Equatable { case empty, tooLong, forbiddenCharacter, dot, leadingDot, trailingSpaceOrDot, tooManyParts }

    static func normalized(_ name: String) -> String { name.precomposedStringWithCanonicalMapping }

    static func newName(_ name: String) -> Rule? { validate(name, existingFolder: false) }
    static func folderPart(_ name: String) -> Rule? { validate(name, existingFolder: true) }

    static func folderPath(_ path: String) -> Rule? {
        if path.isEmpty { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count <= 8 else { return .tooManyParts }
        return parts.lazy.compactMap { folderPart(String($0)) }.first
    }

    private static func validate(_ name: String, existingFolder: Bool) -> Rule? {
        let name = normalized(name)
        guard !name.isEmpty else { return .empty }
        guard name.utf8.count <= (existingFolder ? 255 : 200) else { return .tooLong }
        let forbidden = existingFolder ? "/" : "/\\:"
        if name.unicodeScalars.contains(where: { forbidden.unicodeScalars.contains($0) || CharacterSet.controlCharacters.contains($0) }) {
            return .forbiddenCharacter
        }
        if name == "." || name == ".." { return .dot }
        if name.hasPrefix(".") { return .leadingDot }
        if !existingFolder && (name.hasSuffix(" ") || name.hasSuffix(".")) { return .trailingSpaceOrDot }
        return nil
    }

    static func defaultName(suggested: String, source: DropSource, date: Date = .now,
                            timeZone: TimeZone = .current) -> String {
        guard source != .file else { return normalized(suggested) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let ext = (suggested as NSString).pathExtension
        return formatter.string(from: date) + (ext.isEmpty ? "" : "." + ext)
    }

    /// Whether a shared picture's name is one a camera or the system gave it ("IMG_1234", "IMG_E1234",
    /// "PXL_20261102_123456789", "DSC01234", "FullSizeRender", "image", a UUID), not one a person chose. Such a picture is
    /// named like a Photos pick (its capture time); any other name ("Lake.jpg" from Files) is kept. Takes the name with
    /// or without its extension.
    static func isCameraName(_ name: String) -> Bool {
        let stem = (name as NSString).deletingPathExtension.trimmingCharacters(in: .whitespaces)
        // No name, or only an extension (".jpg"): nothing a person chose.
        guard !stem.isEmpty, !stem.hasPrefix(".") else { return true }
        let patterns = [
            #"^(img|pxl|dsc[nf]?|mvimg|vid|mov|dcim)[_-]?e?[_-]?\d[\d_-]*$"#,
            #"^(image|photo|foto|bild|fullsizerender)( ?\(?\d+\)?)?$"#,
            #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#,
        ]
        return patterns.contains { stem.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    /// Also avoids collisions with names that already contain a numeric suffix.
    static func unique(_ names: [String]) -> [String] {
        var used = Set<String>()
        return names.map { original in
            let name = normalized(original)
            let ext = (name as NSString).pathExtension
            let stem = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
            var candidate = name
            var number = 2
            while used.contains(candidate) {
                candidate = stem + " (\(number))" + (ext.isEmpty ? "" : "." + ext)
                number += 1
            }
            used.insert(candidate)
            return candidate
        }
    }
}
