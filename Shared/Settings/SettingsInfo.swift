import Foundation

/// The Empire's legal pages, open without a login (the hub serves them), each in the app's language. Used by every app's
/// Settings → About and the login screens' footer.
nonisolated enum LegalPage: CaseIterable, Sendable {
    case privacy, imprint

    static let privacyGerman = URL(string: "https://www.ares-empire.de/datenschutz")!
    static let privacyEnglish = URL(string: "https://www.ares-empire.de/privacy")!
    static let imprintGerman = URL(string: "https://www.ares-empire.de/impressum")!
    static let imprintEnglish = URL(string: "https://www.ares-empire.de/imprint")!

    func url(in language: AppLanguage = .current) -> URL {
        switch (self, language) {
        case (.privacy, .german): Self.privacyGerman
        case (.privacy, .english): Self.privacyEnglish
        case (.imprint, .german): Self.imprintGerman
        case (.imprint, .english): Self.imprintEnglish
        }
    }
}

/// The app's version as Settings → About shows it: "1.0 (12)" (marketing version, build number).
nonisolated enum AppVersion {
    static func text(_ info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }
}

/// The two typefaces every app ships (Shared/Fonts) and their licence files; the SIL Open Font License asks for the
/// licence to travel with the fonts, so Settings → About shows it.
nonisolated enum BundledFont: String, CaseIterable, Identifiable, Sendable {
    case spaceGrotesk = "Space Grotesk"
    case jetBrainsMono = "JetBrains Mono"

    var id: String { rawValue }
    var licenceFile: String { self == .spaceGrotesk ? "OFL-SpaceGrotesk" : "OFL-JetBrainsMono" }
    static let licenceName = "SIL Open Font License 1.1"

    /// The licence text from the app's bundle; nil if the file is missing.
    func licence(in bundle: Bundle = .main) -> String? {
        bundle.url(forResource: licenceFile, withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}

/// A licence an app ships besides the fonts, under Settings → About → Fonts & licences: what the licensed work is, the
/// licence's short name, and its text file in the app's own bundle. Only the app that ships the work names it (Aresium:
/// the shop list's brand names from name-suggestion-index, `BundledLicence.shopList`).
nonisolated struct BundledLicence: Identifiable, Hashable, Sendable {
    let name: String            // the work, as its authors name it ("name-suggestion-index")
    let purpose: String         // what the app uses it for, in the app's language
    let licenceName: String     // "BSD-3-Clause"
    let file: String            // the text file's name in the bundle, without ".txt"
    var links: [SourceLink] = []
    var id: String { name }

    nonisolated struct SourceLink: Hashable, Sendable {
        let title: String
        let url: URL
    }

    /// The licence text from the app's bundle; nil if the file is missing.
    func text(in bundle: Bundle = .main) -> String? {
        bundle.url(forResource: file, withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}

/// A plain-text licence (hard-wrapped at about 70 characters) as paragraphs that wrap on the phone's width: lines are
/// joined within a paragraph, blank lines end one, rules made of dashes are dropped, and a short all-capital line that
/// starts a paragraph and ends without punctuation ("PREAMBLE", "PERMISSION & CONDITIONS") becomes a heading.
nonisolated struct LicenceParagraph: Equatable, Sendable {
    let text: String
    let isHeading: Bool

    static func paragraphs(_ text: String) -> [LicenceParagraph] {
        var result: [LicenceParagraph] = []
        var lines: [String] = []
        func flush() {
            if !lines.isEmpty { result.append(LicenceParagraph(text: lines.joined(separator: " "), isHeading: false)) }
            lines = []
        }
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.allSatisfy({ $0 == "-" }) {
                flush()
            } else if lines.isEmpty, isHeading(line) {
                flush()
                result.append(LicenceParagraph(text: line, isHeading: true))
            } else {
                lines.append(line)
            }
        }
        flush()
        return result
    }

    private static func isHeading(_ line: String) -> Bool {
        line == line.uppercased() && line.last?.isLetter == true && line.split(separator: " ").count <= 3
    }
}
