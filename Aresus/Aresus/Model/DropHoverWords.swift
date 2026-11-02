import Foundation

/// What the Aresync tab says while files hover over it (brief 100, `DropHoverScreen`): what letting go does, and what is
/// held: the file's name when it names itself, else how many.
nonisolated enum DropHoverWords {
    static func title(language: AppLanguage = .current) -> String {
        language.string(LocalizedStringResource("Let go to send to the MacBook"))
    }

    static func line(_ hover: ProviderFiles.Hover, language: AppLanguage = .current) -> String {
        if let name = hover.name { return name }
        return language.string(LocalizedStringResource("\(hover.count) files"))
    }
}
