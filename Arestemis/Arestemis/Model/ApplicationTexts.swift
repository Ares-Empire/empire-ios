import Foundation

/// Settings → Application (brief 61, Patrik 2026-10-31): a switch between automatic texts and the own text, a row that
/// follows it (the own text, or the notes every automatic text includes) and About you, each opening a page with one
/// text field. The words and which text each page edits live here; `SettingsSheet` draws them.
enum ApplicationPage: String, CaseIterable, Identifiable, Hashable, Sendable {
    case ownText, notes, aboutMe              // the raw values are the screenshots' `-openSettingsPage` values
    var id: String { rawValue }

    /// The row under the switch: the own text while it is off, the notes while it is on.
    static func written(for mode: ApplicationMode) -> ApplicationPage {
        mode == .ai ? .notes : .ownText
    }

    /// The text the page edits.
    var field: WritableKeyPath<Settings, String> {
        switch self {
        case .ownText: \.ownText
        case .notes: \.applicationNotes
        case .aboutMe: \.aboutMe
        }
    }

    /// The row's and the page's title.
    func title(in language: AppLanguage = .current) -> String {
        switch self {
        case .ownText: language.string("Your text")
        case .notes: language.string("Notes")
        case .aboutMe: language.string("About you")
        }
    }

    /// The row's line under the title: the start of what is written, else that nothing is.
    func summary(of settings: Settings, language: AppLanguage = .current) -> String {
        if let preview = Self.preview(settings[keyPath: field]) { return preview }
        return self == .notes ? language.string("None") : language.string("Not written yet")
    }

    /// The field's grey text while it is empty.
    func placeholder(in language: AppLanguage = .current) -> String {
        switch self {
        case .ownText: language.string("Hallo, …")
        case .notes: language.string("e.g. I can come to a viewing any evening, my parents act as guarantors")
        case .aboutMe: language.string("Age, studies or job, non-smoker, …")
        }
    }

    /// The line under the field: what the text is for.
    func caption(in language: AppLanguage = .current) -> String {
        switch self {
        case .ownText:
            language.string("Your text as it is, with the greeting adapted when the contact's name is known.")
        case .notes:
            language.string("Every text written automatically includes these points. Only your notes and the facts about you are used, nothing is made up.")
        case .aboutMe:
            language.string("Only these facts are used, nothing is made up. Give your gender and age: many listings are only for women, men or an age range, and the check needs them.")
        }
    }

    /// A written text on one line ("Hallo, mein Name ist …"; the row cuts it to its width); nil when nothing is written.
    static func preview(_ text: String) -> String? {
        let words = text.split(whereSeparator: \.isWhitespace)
        return words.isEmpty ? nil : words.joined(separator: " ")
    }
}
