import Foundation

/// `GET /search` answered (the search contract of 2026-10-24, Arestoteles docs/API.md): passages of the vault that
/// answer a query, best first, found by their words and by their meaning. No text is written for the answer: every
/// result is a passage of the vault as it stands.
nonisolated struct SearchAnswer: Codable, Equatable, Sendable {
    let commit: String                  // the vault commit the results come from (may be older than the app's vault)
    let meaning: Bool                   // false while the server's meaning model is not ready: word matches only
    let results: [SearchHit]
}

/// One passage: a paragraph, a list item, a quote, a callout or a position, and where it stands.
nonisolated struct SearchHit: Codable, Equatable, Sendable {
    /// How the server found it. Only `meaning` has none of the query's words, so its row marks none.
    enum Match: String, Codable, Sendable {
        case words, meaning, both
    }

    let note: String                    // the note's id
    let block: Int                      // index in that note's `blocks`
    let item: Int?                      // for a list: the item's index
    let position: String?               // for a position: its id (`block` is then the positions block)
    let heading: String?                // the heading it stands under, plain text
    let text: String                    // the whole passage, inline Markdown
    let sentence: String                // the passage's sentence that answers best, plain text
    let match: Match

    enum CodingKeys: String, CodingKey { case note, block, item, position, heading, text, sentence, match }

    init(note: String, block: Int, item: Int? = nil, position: String? = nil, heading: String? = nil, text: String,
         sentence: String, match: Match) {
        self.note = note
        self.block = block
        self.item = item
        self.position = position
        self.heading = heading
        self.text = text
        self.sentence = sentence
        self.match = match
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        note = try container.decode(String.self, forKey: .note)
        block = try container.decode(Int.self, forKey: .block)
        item = try container.decodeIfPresent(Int.self, forKey: .item)
        position = try container.decodeIfPresent(String.self, forKey: .position)
        heading = try container.decodeIfPresent(String.self, forKey: .heading)
        text = try container.decode(String.self, forKey: .text)
        sentence = try container.decode(String.self, forKey: .sentence)
        // Shown only: a way of matching this app does not know yet reads as a word match instead of failing the answer.
        match = (try? container.decode(Match.self, forKey: .match)) ?? .words
    }
}
