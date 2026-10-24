import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// The vault's notes in iPhone search (Spotlight): title, summary and type for every note, put in again after each
/// refresh that brought a new vault, removed on logout. A tapped result opens the app with the note's link as the
/// item's identifier (`NoteLink`), the same parser as every other link.
protocol SpotlightIndexing: Sendable {
    /// The vault's notes replace whatever the index held for the app.
    func replace(with notes: [Note]) async throws
    func removeAll() async throws
}

enum SpotlightItems {
    /// All the vault's items share this domain, so replacing them never touches anything else.
    static let domain = "de.ares-empire.arestoteles.notes"

    /// One item per note.
    static func make(_ notes: [Note], language: AppLanguage = .current) -> [CSSearchableItem] {
        notes.map { item(for: $0, language: language) }
    }

    static func item(for note: Note, language: AppLanguage = .current) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = note.title
        attributes.displayName = note.title
        let type = Format.type(note.type, language: language)
        attributes.contentDescription = note.summary.map { InlineMarkdown.plain($0) } ?? type
        attributes.keywords = [type, note.id] + note.tags
        let item = CSSearchableItem(uniqueIdentifier: NoteLink(note: note.id).url.absoluteString, domainIdentifier: domain,
                                    attributeSet: attributes)
        item.expirationDate = .distantFuture
        return item
    }

    /// The note a tapped Spotlight result stands for.
    static func link(from activity: NSUserActivity) -> NoteLink? {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
        return NoteLink(string: identifier)
    }
}

/// The device's Spotlight index.
struct DeviceSpotlight: SpotlightIndexing {
    func replace(with notes: [Note]) async throws {
        let index = CSSearchableIndex.default()
        try await index.deleteSearchableItems(withDomainIdentifiers: [SpotlightItems.domain])
        try await index.indexSearchableItems(SpotlightItems.make(notes))
    }

    func removeAll() async throws {
        try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [SpotlightItems.domain])
    }
}

/// No Spotlight (tests).
struct NoSpotlight: SpotlightIndexing {
    func replace(with notes: [Note]) async throws {}
    func removeAll() async throws {}
}
