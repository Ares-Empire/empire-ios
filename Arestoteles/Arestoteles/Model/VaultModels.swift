import Foundation

/// The Arestoteles API, version 1 (Arestoteles/docs/API.md): Patrik's Weltbild vault as the server indexed it. The server
/// applies every rule of the vault; the app displays and sends edits. Field names on the wire are the contract's
/// (snake_case, in the CodingKeys). Texts marked `Text` in the contract are inline Markdown (`InlineMarkdown`).
///
/// Everything is `Codable`: the last vault is kept on disk (`VaultCache`) as the app encoded it. Values the contract lists
/// as a closed set but that only matter for display (note types, callout styles, block kinds) also read unknown values,
/// so one new kind of note on the server never makes the whole vault unreadable.

nonisolated struct Vault: Codable, Equatable, Sendable {
    let version: Int
    let commit: String                  // the vault's git commit the index was built from (short hash)
    let built: String                   // when the server built it (ISO 8601)
    let notes: [Note]                   // sorted by id
    let positions: [PositionGroup]      // "Across topics" first, then each topic in Positions.md's order
    let glossary: [Term]                // sorted by English
    let home: Home
}

nonisolated struct Home: Codable, Equatable, Sendable {
    let learnNext: [String]             // inline Markdown items

    enum CodingKeys: String, CodingKey { case learnNext = "learn_next" }
}

/// "topic", "mechanism", … An open set on purpose: an unknown type reads as itself.
nonisolated struct NoteType: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let topic = NoteType(rawValue: "topic")
    static let mechanism = NoteType(rawValue: "mechanism")
    static let event = NoteType(rawValue: "event")
    static let actor = NoteType(rawValue: "actor")
    static let question = NoteType(rawValue: "question")
    static let session = NoteType(rawValue: "session")
    static let inbox = NoteType(rawValue: "inbox")
    static let home = NoteType(rawValue: "home")
    static let positions = NoteType(rawValue: "positions")
    static let glossary = NoteType(rawValue: "glossary")

    /// The contract's types, in the order the search filter offers them.
    static let known: [NoteType] = [.topic, .mechanism, .event, .actor, .question, .session, .inbox, .home, .positions,
                                    .glossary]
}

nonisolated enum Confidence: String, Codable, CaseIterable, Sendable {
    case solid
    case myRead = "my-read"
    case shaky
}

nonisolated struct Note: Codable, Equatable, Identifiable, Sendable {
    let id: String                      // the file name without .md, unique in the vault
    let path: String                    // "Topics/Colonialism/Colonialism.md"
    let type: NoteType
    let title: String
    let summary: String?                // the "> [!summary]" box, inline Markdown
    let confidence: Confidence?
    let created: String?
    let updated: String?
    let tags: [String]
    let topic: String?                  // its topic overview (itself for an overview), nil outside Topics/
    let partOf: PartOf?
    let event: EventSpan?
    let ledTo: [String]
    let links: [String]
    let backlinks: [String]             // sorted by id
    let positions: [String]             // position ids written on this note, in order
    let callouts: [Callout]
    let blocks: [Block]
    /// Where each block sits in the body `GET /notes/{id}/source` returns (same order as `blocks`; nil: made up by the
    /// server, or a server from before the lookup additions). Editing one paragraph replaces exactly these lines.
    let blockLines: [LineRange?]
    let brief: Brief?                   // topic overviews only
    let inbox: InboxInfo?               // Inbox notes only: a note or a "discuss later" mark, and its status
    let version: String                 // git blob hash: edits of the text name it

    enum CodingKeys: String, CodingKey {
        case id, path, type, title, summary, confidence, created, updated, tags, topic, event, links, backlinks, positions
        case callouts, blocks, brief, inbox, version
        case partOf = "part_of", ledTo = "led_to", blockLines = "block_lines"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        type = try container.decode(NoteType.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        // Shown only: a value outside the three reads as "not set" instead of failing the vault.
        confidence = (try? container.decodeIfPresent(String.self, forKey: .confidence)).flatMap(Confidence.init(rawValue:))
        created = try container.decodeIfPresent(String.self, forKey: .created)
        updated = try container.decodeIfPresent(String.self, forKey: .updated)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        topic = try container.decodeIfPresent(String.self, forKey: .topic)
        partOf = try container.decodeIfPresent(PartOf.self, forKey: .partOf)
        event = try container.decodeIfPresent(EventSpan.self, forKey: .event)
        ledTo = try container.decodeIfPresent([String].self, forKey: .ledTo) ?? []
        links = try container.decodeIfPresent([String].self, forKey: .links) ?? []
        backlinks = try container.decodeIfPresent([String].self, forKey: .backlinks) ?? []
        positions = try container.decodeIfPresent([String].self, forKey: .positions) ?? []
        callouts = try container.decodeIfPresent([Callout].self, forKey: .callouts) ?? []
        blocks = try container.decodeIfPresent([Block].self, forKey: .blocks) ?? []
        // The server sends each block's `lines` inside the block; the app's own saved copy keeps them next to it.
        if let saved = try container.decodeIfPresent([LineRange?].self, forKey: .blockLines), saved.count == blocks.count {
            blockLines = saved
        } else {
            let probes = (try? container.decodeIfPresent([BlockLinesProbe].self, forKey: .blocks)) ?? []
            blockLines = probes.count == blocks.count ? probes.map(\.lines) : Array(repeating: nil, count: blocks.count)
        }
        brief = try container.decodeIfPresent(Brief.self, forKey: .brief)
        inbox = try container.decodeIfPresent(InboxInfo.self, forKey: .inbox)
        version = try container.decode(String.self, forKey: .version)
    }

    /// A topic overview: the note its topic is named after.
    var isTopicOverview: Bool { type == .topic && topic == id }
}

/// Lines `[start, end)` of a note's body (0-based, end exclusive), as the contract sends them: `[3, 5]`.
nonisolated struct LineRange: Codable, Equatable, Hashable, Sendable {
    let start: Int
    let end: Int

    init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        start = try container.decode(Int.self)
        end = try container.decode(Int.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(start)
        try container.encode(end)
    }
}

/// Reads only a block's `lines` (the rest is `Block`).
private nonisolated struct BlockLinesProbe: Decodable {
    let lines: LineRange?
}

/// An Inbox note's frontmatter: a quick note or a "discuss later" mark, what it is about, and whether Claude has
/// processed it yet.
nonisolated struct InboxInfo: Codable, Equatable, Sendable {
    let status: String                  // "new" until processed
    let kind: QuickNoteKind
    let about: String?                  // a note id
    let position: Int?                  // a position's number on that note

    var isOpen: Bool { status == "new" }
    /// The position id it is about ("Printing press#1"), when it names one.
    var positionID: String? { about.flatMap { note in position.map { "\(note)#\($0)" } } }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "new"
        kind = (try? container.decodeIfPresent(QuickNoteKind.self, forKey: .kind)) ?? .note
        about = try container.decodeIfPresent(String.self, forKey: .about)
        position = try container.decodeIfPresent(Int.self, forKey: .position)
    }
}

/// A quick note is a thought for the Inbox, or a mark that Patrik wants to discuss something later.
nonisolated enum QuickNoteKind: String, Codable, Equatable, Sendable {
    case note, discuss
}

nonisolated struct PartOf: Codable, Equatable, Sendable {
    let note: String
    let section: Int
}

/// An event's years (negative = BCE) and where it happened.
nonisolated struct EventSpan: Codable, Equatable, Sendable {
    let from: Int?
    let to: Int?
    let `where`: [String]
}

/// "claude", "shaky", "note" (every other callout type). An open set, like `NoteType`.
nonisolated struct CalloutStyle: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let claude = CalloutStyle(rawValue: "claude")
    static let shaky = CalloutStyle(rawValue: "shaky")
    static let note = CalloutStyle(rawValue: "note")
}

/// A `> [!claude]` or `> [!shaky]` callout of a note; `index` is what adopt/dismiss name.
nonisolated struct Callout: Codable, Equatable, Sendable {
    let index: Int
    let style: CalloutStyle
    let title: String?
    let text: String
}

nonisolated struct ListItem: Codable, Equatable, Sendable {
    let text: String
    let depth: Int                      // 0 = top level
    var lines: LineRange? = nil         // where the item sits in the body (one item can be edited on its own)
}

/// A piece of a note's body, for display (the frontmatter, the title and the summary box are left out).
nonisolated enum Block: Equatable, Sendable {
    case heading(level: Int, text: String, anchor: String)
    case paragraph(text: String)
    case list(ordered: Bool, items: [ListItem])
    case positions(ids: [String])                       // "## My position": position cards
    case callout(style: CalloutStyle, title: String?, text: String, index: Int)
    case quote(text: String)
    case embed(note: String, anchor: String?)           // ![[Note#Heading]]: that part of the other note
    case table(header: [String], rows: [[String]])
    case sectionLink(note: String)                      // "→ [[Section page]]" on its own line
    case rule
    case unknown(kind: String)                          // a kind this app does not know yet: not shown
}

nonisolated extension Block: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, level, text, anchor, ordered, items, ids, style, title, index, note, header, rows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "heading":
            self = .heading(level: try container.decode(Int.self, forKey: .level),
                            text: try container.decode(String.self, forKey: .text),
                            anchor: try container.decode(String.self, forKey: .anchor))
        case "paragraph": self = .paragraph(text: try container.decode(String.self, forKey: .text))
        case "list":
            self = .list(ordered: try container.decode(Bool.self, forKey: .ordered),
                         items: try container.decode([ListItem].self, forKey: .items))
        case "positions": self = .positions(ids: try container.decode([String].self, forKey: .ids))
        case "callout":
            self = .callout(style: try container.decode(CalloutStyle.self, forKey: .style),
                            title: try container.decodeIfPresent(String.self, forKey: .title),
                            text: try container.decode(String.self, forKey: .text),
                            index: try container.decode(Int.self, forKey: .index))
        case "quote": self = .quote(text: try container.decode(String.self, forKey: .text))
        case "embed":
            self = .embed(note: try container.decode(String.self, forKey: .note),
                          anchor: try container.decodeIfPresent(String.self, forKey: .anchor))
        case "table":
            self = .table(header: try container.decode([String].self, forKey: .header),
                          rows: try container.decode([[String]].self, forKey: .rows))
        case "section_link": self = .sectionLink(note: try container.decode(String.self, forKey: .note))
        case "rule": self = .rule
        default: self = .unknown(kind: kind)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .heading(level, text, anchor):
            try container.encode("heading", forKey: .kind)
            try container.encode(level, forKey: .level)
            try container.encode(text, forKey: .text)
            try container.encode(anchor, forKey: .anchor)
        case let .paragraph(text):
            try container.encode("paragraph", forKey: .kind)
            try container.encode(text, forKey: .text)
        case let .list(ordered, items):
            try container.encode("list", forKey: .kind)
            try container.encode(ordered, forKey: .ordered)
            try container.encode(items, forKey: .items)
        case let .positions(ids):
            try container.encode("positions", forKey: .kind)
            try container.encode(ids, forKey: .ids)
        case let .callout(style, title, text, index):
            try container.encode("callout", forKey: .kind)
            try container.encode(style, forKey: .style)
            try container.encode(title, forKey: .title)
            try container.encode(text, forKey: .text)
            try container.encode(index, forKey: .index)
        case let .quote(text):
            try container.encode("quote", forKey: .kind)
            try container.encode(text, forKey: .text)
        case let .embed(note, anchor):
            try container.encode("embed", forKey: .kind)
            try container.encode(note, forKey: .note)
            try container.encode(anchor, forKey: .anchor)
        case let .table(header, rows):
            try container.encode("table", forKey: .kind)
            try container.encode(header, forKey: .header)
            try container.encode(rows, forKey: .rows)
        case let .sectionLink(note):
            try container.encode("section_link", forKey: .kind)
            try container.encode(note, forKey: .note)
        case .rule:
            try container.encode("rule", forKey: .kind)
        case let .unknown(kind):
            try container.encode(kind, forKey: .kind)
        }
    }
}

nonisolated struct Position: Codable, Equatable, Identifiable, Sendable {
    let id: String                      // "<note id>#<number>": "Colonialism#2", "Positions#3"
    let note: String                    // the note it is written on
    let number: Int
    let text: String                    // inline Markdown, without "(draft)" and the → links
    let draft: Bool                     // worded by Claude, not yet confirmed by Patrik
    let evidence: [String]              // note ids
    let history: [PositionChange]       // newest first
}

/// One entry of a note's "## How my view changed".
nonisolated struct PositionChange: Codable, Equatable, Sendable {
    let date: String                    // "2026-10-20"
    let text: String                    // what I thought
    let why: String?                    // what changed it
}

nonisolated struct PositionGroup: Codable, Equatable, Sendable {
    let title: String
    let note: String
    let positions: [Position]
}

/// A glossary entry: the English term, its German, and the note where it is explained.
nonisolated struct Term: Codable, Equatable, Hashable, Sendable {
    let english: String
    let german: String
    let note: String?
}

/// A topic before a discussion, built by the server from the vault's structure.
nonisolated struct Brief: Codable, Equatable, Sendable {
    let positions: [String]
    let sections: [Section]
    let counterpoints: [Counterpoint]
    let shaky: [Shaky]
    let terms: [Term]
    let questions: [String]

    struct Section: Codable, Equatable, Sendable {
        let title: String
        let summary: String
        let note: String?
    }

    struct Counterpoint: Codable, Equatable, Sendable {
        let note: String
        let title: String?
        let text: String
    }

    struct Shaky: Codable, Equatable, Sendable {
        let note: String
        let text: String
    }
}

/// `GET /notes/{id}/source`: a note's body as Markdown (without frontmatter), for the free editor.
nonisolated struct NoteSource: Codable, Equatable, Sendable {
    let id: String
    let version: String
    let markdown: String
}

/// `POST /edits` answered: the vault rebuilt after the edit.
nonisolated struct EditResult: Codable, Equatable, Sendable {
    let vault: Vault
    let changed: [String]               // note ids the edit touched (a quick note: the new Inbox note)
    let pushed: Bool                    // false: committed on the server, the push to GitHub waits
    let warnings: [String]              // the vault check's warnings after the edit
}

/// One edit, as `POST /edits` takes it.
nonisolated enum Edit: Equatable, Sendable {
    case confirmPosition(position: String)
    case rewordPosition(position: String, text: String)
    case changePosition(position: String, text: String, why: String)
    case dropPosition(position: String, why: String)
    case addPosition(note: String, text: String, evidence: [String])
    case setConfidence(note: String, confidence: Confidence)
    case adoptCallout(note: String, callout: Int, version: String)
    case dismissCallout(note: String, callout: Int, version: String)
    case editNote(note: String, version: String, markdown: String)
    case quickNote(text: String, about: String? = nil, kind: QuickNoteKind = .note)
    case setInboxStatus(note: String, status: String)

    /// The contract's `op`.
    var op: String {
        switch self {
        case .confirmPosition: "confirm_position"
        case .rewordPosition: "reword_position"
        case .changePosition: "change_position"
        case .dropPosition: "drop_position"
        case .addPosition: "add_position"
        case .setConfidence: "set_confidence"
        case .adoptCallout: "adopt_callout"
        case .dismissCallout: "dismiss_callout"
        case .editNote: "edit_note"
        case .quickNote: "quick_note"
        case .setInboxStatus: "set_inbox_status"
        }
    }

    /// The note the edit is about, when it names one (positions: the note they are written on).
    var note: String? {
        switch self {
        case let .confirmPosition(position), let .rewordPosition(position, _), let .changePosition(position, _, _),
             let .dropPosition(position, _):
            Position.note(ofID: position)
        case let .addPosition(note, _, _), let .setConfidence(note, _), let .adoptCallout(note, _, _),
             let .dismissCallout(note, _, _), let .editNote(note, _, _), let .setInboxStatus(note, _):
            note
        case .quickNote:
            nil
        }
    }
}

nonisolated extension Edit: Encodable {
    private enum CodingKeys: String, CodingKey {
        case op, position, text, why, note, evidence, confidence, callout, version, markdown, about, kind, status
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(op, forKey: .op)
        switch self {
        case let .confirmPosition(position):
            try container.encode(position, forKey: .position)
        case let .rewordPosition(position, text):
            try container.encode(position, forKey: .position)
            try container.encode(text, forKey: .text)
        case let .changePosition(position, text, why):
            try container.encode(position, forKey: .position)
            try container.encode(text, forKey: .text)
            try container.encode(why, forKey: .why)
        case let .dropPosition(position, why):
            try container.encode(position, forKey: .position)
            try container.encode(why, forKey: .why)
        case let .addPosition(note, text, evidence):
            try container.encode(note, forKey: .note)
            try container.encode(text, forKey: .text)
            try container.encode(evidence, forKey: .evidence)
        case let .setConfidence(note, confidence):
            try container.encode(note, forKey: .note)
            try container.encode(confidence, forKey: .confidence)
        case let .adoptCallout(note, callout, version), let .dismissCallout(note, callout, version):
            try container.encode(note, forKey: .note)
            try container.encode(callout, forKey: .callout)
            try container.encode(version, forKey: .version)
        case let .editNote(note, version, markdown):
            try container.encode(note, forKey: .note)
            try container.encode(version, forKey: .version)
            try container.encode(markdown, forKey: .markdown)
        case let .quickNote(text, about, kind):
            try container.encode(text, forKey: .text)
            // Only sent when set, so a plain quick note is exactly what the first version of the contract takes.
            try container.encodeIfPresent(about, forKey: .about)
            if kind != .note { try container.encode(kind, forKey: .kind) }
        case let .setInboxStatus(note, status):
            try container.encode(note, forKey: .note)
            try container.encode(status, forKey: .status)
        }
    }
}

nonisolated extension Position {
    /// The note part of a position id ("Printing press#2" → "Printing press"): everything before the last "#".
    static func note(ofID id: String) -> String {
        guard let hash = id.lastIndex(of: "#") else { return id }
        return String(id[..<hash])
    }
}
