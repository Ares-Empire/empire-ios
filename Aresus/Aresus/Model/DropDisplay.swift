import Foundation

// How drops read on screen (brief 91): the rows on the Aresync tab, the folder paths, the name rules in plain words.
// Kept out of the views so each state's line is tested; what a state means is aresus/docs/API.md → Drops.

/// The kind of file a row's small symbol shows, from the name's extension.
nonisolated enum DropFileKind: Equatable, Sendable {
    case photo, video, pdf, other

    init(name: String) {
        switch (name as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "heic", "heif", "png", "gif", "webp", "tif", "tiff", "dng", "bmp", "avif": self = .photo
        case "mov", "mp4", "m4v", "hevc": self = .video
        case "pdf": self = .pdf
        default: self = .other
        }
    }

    var symbol: String {
        switch self {
        case .photo: "photo"
        case .video: "film"
        case .pdf: "doc.text"
        case .other: "doc"
        }
    }
}

/// One row of "Sent to the MacBook": the name, one quiet line for its state, an optional note, and what can be done.
nonisolated struct DropRow: Identifiable, Equatable, Sendable {
    enum Tone: Equatable, Sendable { case normal, muted, warning }

    let id: String
    let name: String
    let kind: DropFileKind
    let line: String
    let tone: Tone
    /// A landed drop's note (why it went to the fallback folder, a missing inventory row), in muted text.
    let note: String?
    let canRetry: Bool
    let canRemove: Bool
    /// Cancelled: the whole row quieter, as an inactive machine.
    var isQuiet: Bool { tone == .muted }

    /// - Parameter local: the phone's own copy hidden behind a server row (its upload is still the phone's), from
    ///   `DropRow.hidden(for:in:)`.
    init(_ item: DropsItem, local: DropOutboxItem? = nil, now: Date = .now, calendar: Calendar = .current,
         language: AppLanguage = .current) {
        id = item.id
        switch item {
        case .phone(let phone):
            name = phone.drop.name
            (line, tone, canRetry, canRemove) = Self.phone(phone, language: language)
            note = nil
        case .server(let drop):
            name = drop.name
            if let local {
                (line, tone, canRetry, canRemove) = Self.phone(local, language: language)
                note = nil
            } else {
                (line, tone, note) = Self.server(drop, now: now, calendar: calendar, language: language)
                canRetry = false
                canRemove = [.uploading, .waiting, .failed].contains(drop.state)
            }
        }
        kind = DropFileKind(name: name)
    }

    /// The outbox's copy a server row stands for, while it is still uploading from this iPhone.
    static func hidden(for item: DropsItem, in outbox: [DropOutboxItem]) -> DropOutboxItem? {
        guard case .server(let drop) = item else { return nil }
        return outbox.first { $0.serverID == drop.id }
    }

    private static func phone(_ item: DropOutboxItem, language: AppLanguage)
        -> (String, Tone, retry: Bool, remove: Bool) {
        if item.cancellationRequested { return (language.string("Removing …"), .muted, false, false) }
        switch item.state {
        case .onPhone: return (language.string("On the phone · waits for a connection"), .normal, false, true)
        case .uploading: return (language.string("Uploading …"), .normal, false, true)
        case .failed:
            let error = item.lastError ?? language.string("The file could not be read.")
            return (language.string("Not sent: \(error)"), .warning, true, true)
        }
    }

    private static func server(_ drop: Drop, now: Date, calendar: Calendar, language: AppLanguage)
        -> (String, Tone, note: String?) {
        switch drop.state {
        case .uploading: return (language.string("Uploading …"), .normal, nil)
        case .waiting: return (language.string("Waiting for the MacBook"), .normal, nil)
        case .failed:
            // The server's note is the whole reason in one sentence ("The MacBook could not write the file."), so it is
            // the line by itself; a prefix would say the same twice.
            let note = drop.note?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (note.flatMap { $0.isEmpty ? nil : $0 } ?? language.string("The MacBook could not save it."), .warning, nil)
        case .landed:
            let folder = drop.landed.flatMap { DropPathText.lastFolder(ofLanded: $0, language: language) }
            let place = folder.map { language.string("In \($0)") } ?? language.string("On the MacBook")
            return (place + " · " + DropPathText.when(drop.updated, now: now, calendar: calendar, language: language),
                    .normal, drop.note)
        case .cancelled: return (language.string("Cancelled"), .muted, nil)
        }
    }
}

/// Folder paths as the screens write them: "Documents › Studium › EIST".
nonisolated enum DropPathText {
    static let separator = " › "

    /// The root as Finder names it in the app's language ("Documents" / "Dokumente").
    static func root(_ root: DropRoot, language: AppLanguage = .current) -> String {
        switch root {
        case .documents: language.string("Documents")
        case .downloads: language.string("Downloads")
        }
    }

    /// A folder's last name, or the root's for the root itself.
    static func name(_ root: DropRoot, _ path: String, language: AppLanguage = .current) -> String {
        path.split(separator: "/").last.map(String.init) ?? Self.root(root, language: language)
    }

    /// The folder a target ends in: its new folder, else its folder's last name, else the root's.
    static func name(_ target: Target, language: AppLanguage = .current) -> String {
        if let new = target.newFolder, !new.isEmpty { return new }
        return name(target.root, target.folder, language: language)
    }

    /// "Documents › Studium › EIST", with an optional new folder at the end.
    static func path(_ root: DropRoot, _ folder: String, newFolder: String? = nil,
                     language: AppLanguage = .current) -> String {
        ([Self.root(root, language: language)] + folder.split(separator: "/").map(String.init)
            + [newFolder].compactMap { $0 }.filter { !$0.isEmpty })
            .joined(separator: separator)
    }

    static func path(_ target: Target, language: AppLanguage = .current) -> String {
        path(target.root, target.folder, newFolder: target.newFolder, language: language)
    }

    /// The folder a drop landed in, from the Mac's path relative to its home ("Documents/Receipts/x.pdf" → "Receipts";
    /// "Documents/x.pdf" → "Documents" in the app's language); nil for a file straight in the home folder.
    static func lastFolder(ofLanded landed: String, language: AppLanguage = .current) -> String? {
        let parts = landed.split(separator: "/").map(String.init).dropLast()
        guard let last = parts.last else { return nil }
        if parts.count == 1, let root = DropRoot.allCases.first(where: { $0.homeFolder == last }) {
            return Self.root(root, language: language)
        }
        return last
    }

    /// When a drop landed: "16:07" today, else as Aresus writes moments ("yesterday 23:57", "Mon 19 Oct 11:00").
    static func when(_ date: Date, now: Date, calendar: Calendar = .current, language: AppLanguage = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return AresusFormat.time(date, calendar: calendar, language: language) }
        return AresusFormat.relative(date, now: now, calendar: calendar, language: language)
    }
}

extension DropRoot {
    /// The folder's real name in the Mac's home ("Documents"), as `landed` paths carry it.
    nonisolated var homeFolder: String {
        switch self {
        case .documents: "Documents"
        case .downloads: "Downloads"
        }
    }
}

/// A name rule from `DropNames` in plain words, for the line under a field.
nonisolated enum DropRuleWording {
    static func text(_ rule: DropNames.Rule, language: AppLanguage = .current) -> String {
        switch rule {
        case .empty: language.string("Enter a name.")
        case .tooLong: language.string("This name is too long.")
        case .forbiddenCharacter: language.string("A name cannot contain a slash, a backslash or a colon.")
        case .dot: language.string("A name cannot be only dots.")
        case .leadingDot: language.string("A name cannot start with a dot.")
        case .trailingSpaceOrDot: language.string("A name cannot end with a dot.")
        case .tooManyParts: language.string("This folder lies too deep.")
        }
    }
}

/// A file name split for editing: the name is edited, the extension stays as it was ("Notes.final.pdf" →
/// "Notes.final" + "pdf"), so the file keeps its type on the Mac.
nonisolated struct DropNameParts: Equatable, Sendable {
    var stem: String
    let ext: String

    init(_ name: String) {
        let ext = (name as NSString).pathExtension
        // ".hidden" or "name." have no extension worth keeping apart.
        if ext.isEmpty || name.count == ext.count + 1 {
            stem = name
            self.ext = ""
        } else {
            stem = String(name.dropLast(ext.count + 1))
            self.ext = ext
        }
    }

    /// The name to send: the edited part without surrounding spaces, then the extension.
    var name: String {
        let trimmed = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        return ext.isEmpty ? trimmed : trimmed + "." + ext
    }

    /// The rule the name breaks, nil when it can be sent. An empty edited part is empty, even with an extension.
    var rule: DropNames.Rule? {
        stem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : DropNames.newName(name)
    }
}

/// The full list's days: drops in the store's order, grouped by the day they were sent ("Today", "Yesterday",
/// "Sat 31 Oct"); the phone's own items first, as the store keeps them.
nonisolated struct DropDay: Identifiable, Equatable, Sendable {
    let title: String
    let items: [DropsItem]
    var id: String { items.first?.id ?? title }

    static func group(_ items: [DropsItem], now: Date = .now, calendar: Calendar = .current,
                      language: AppLanguage = .current) -> [DropDay] {
        var days: [DropDay] = []
        for item in items {
            let title = AresusFormat.dayHeading(item.created, now: now, calendar: calendar, language: language)
            if let last = days.last, last.title == title {
                days[days.count - 1] = DropDay(title: title, items: last.items + [item])
            } else {
                days.append(DropDay(title: title, items: [item]))
            }
        }
        return days
    }
}

extension DropsItem {
    /// When it was sent: the phone's record, or the server's.
    nonisolated var created: Date {
        switch self {
        case .phone(let item): item.created
        case .server(let drop): drop.created
        }
    }
}
