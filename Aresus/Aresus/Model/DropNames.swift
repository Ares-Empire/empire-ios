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
