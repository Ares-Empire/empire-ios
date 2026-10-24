import Foundation

/// What a discussion is about: a note or one of the positions.
enum DiscussSubject: Hashable, Sendable {
    case note(String)
    case position(String)

    /// The note or position id (what a quick note's `about` names).
    var id: String {
        switch self {
        case let .note(id), let .position(id): id
        }
    }

    /// An Inbox note's `about` as a subject: a position when it names one.
    init?(inbox: InboxInfo) {
        if let position = inbox.positionID { self = .position(position) }
        else if let note = inbox.about { self = .note(note) }
        else { return nil }
    }
}

/// Discuss with Claude (ares-empire/docs/ARESTOTELES-APP.md): no AI in the app. The app writes a prompt for a Claude
/// Code session on the vault repo, copies it, and opens Claude, where Patrik pastes it. The prompt is a message to
/// Claude, not interface text, so it is English like the vault (only Patrik's own question is as he types it).
enum DiscussPrompt {
    /// Where Discuss sends Patrik. One constant, so the lead can change the target after trying it on the phone
    /// (the Claude app's own link, or the web page that hands over to it).
    static let target = URL(string: "https://claude.ai/code")!

    static let opening = "Weltbild vault, repo carlsenares/opinions: read CLAUDE.md first."

    /// The whole prompt; nil when the subject is not in the vault (any more).
    static func make(_ subject: DiscussSubject, question: String = "", index: VaultIndex) -> String? {
        let about: String
        switch subject {
        case let .note(id):
            guard let note = index.note(id) else { return nil }
            about = "Let's discuss the note \"\(note.title)\" (\(note.path))."
        case let .position(id):
            guard let position = index.position(id), let note = index.note(position.note) else { return nil }
            let draft = position.draft ? " (still a draft)" : ""
            about = "Let's discuss my position \(position.number) on \"\(note.title)\" (\(note.path))\(draft): "
                + "\"\(InlineMarkdown.plain(position.text))\""
        }
        var prompt = opening + " " + about
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if !question.isEmpty { prompt += "\n\n" + question }
        return prompt
    }
}
