import Foundation
import Observation

/// A position being reworded, changed, dropped or added: what is typed, whether it can be sent, and the server's
/// answer. The sheet shows it; the store sends it.
@MainActor @Observable
final class PositionDraft {
    enum Kind: Equatable, Hashable {
        case reword(String)                 // position id
        case change(String)
        case drop(String)
        case add(note: String)              // the note to add it to (a topic overview, or "Positions")

        var id: String {
            switch self {
            case let .reword(position): "reword:" + position
            case let .change(position): "change:" + position
            case let .drop(position): "drop:" + position
            case let .add(note): "add:" + note
            }
        }

        var position: String? {
            switch self {
            case let .reword(position), let .change(position), let .drop(position): position
            case .add: nil
            }
        }
    }

    let kind: Kind
    /// The new sentence (reword, change, add); starts as the current one for a reword or change.
    var text: String
    /// Why the view changed or was dropped.
    var why = ""
    /// Add: where the position goes.
    var note: String
    /// Add: the evidence notes, in the order picked.
    var evidence: [String] = []
    private(set) var isSaving = false
    /// What the server said when it refused, or why sending failed.
    private(set) var problem: String?

    init(_ kind: Kind, index: VaultIndex) {
        self.kind = kind
        switch kind {
        case let .reword(position), let .change(position):
            text = index.position(position).map { InlineMarkdown.plain($0.text) } ?? ""
            note = Position.note(ofID: position)
        case let .drop(position):
            text = ""
            note = Position.note(ofID: position)
        case let .add(target):
            text = ""
            note = target
        }
    }

    var needsText: Bool { if case .drop = kind { false } else { true } }
    var needsWhy: Bool {
        switch kind {
        case .change, .drop: true
        case .reword, .add: false
        }
    }

    private static func filled(_ text: String) -> Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var canSave: Bool {
        !isSaving && (!needsText || Self.filled(text)) && (!needsWhy || Self.filled(why))
    }

    func toggleEvidence(_ id: String) {
        if let index = evidence.firstIndex(of: id) {
            evidence.remove(at: index)
        } else {
            evidence.append(id)
        }
    }

    /// Sends the draft; true when the server saved it (the sheet closes).
    func save(with store: VaultStore) async -> Bool {
        guard canSave else { return false }
        isSaving = true
        problem = nil
        defer { isSaving = false }
        let outcome: VaultStore.EditOutcome
        switch kind {
        case let .reword(position):
            outcome = await store.rewordPosition(position, text: text, reportsFailure: false)
        case let .change(position):
            outcome = await store.changePosition(position, text: text, why: why, reportsFailure: false)
        case let .drop(position):
            outcome = await store.dropPosition(position, why: why, reportsFailure: false)
        case .add:
            outcome = await store.addPosition(to: note, text: text, evidence: evidence, reportsFailure: false)
        }
        switch outcome {
        case .applied: return true
        case .conflict: problem = VaultStore.changedElsewhere
        case let .invalid(message), let .failed(message): problem = message
        }
        return false
    }
}

/// The free editor of one note: loads its Markdown (`GET /notes/{id}/source`), saves the whole body with the version
/// it was loaded at. When the note changed elsewhere meanwhile (409), the typed text stays on screen, saving stops,
/// and Patrik can load the current version (giving up his text, after copying it if he wants).
@MainActor @Observable
final class NoteEditor {
    enum State: Equatable {
        case loading
        case editing
        case failed(String)                 // the source could not be loaded
    }

    let note: String
    private let store: VaultStore
    private(set) var state: State = .loading
    var text = ""
    private(set) var original = ""
    private(set) var version: String?
    private(set) var isSaving = false
    /// The note changed elsewhere since it was loaded.
    private(set) var conflict = false
    /// The server's reason (422) or why saving failed.
    private(set) var problem: String?

    init(note: String, store: VaultStore) {
        self.note = note
        self.store = store
    }

    var hasChanges: Bool { text != original }
    var canSave: Bool { state == .editing && hasChanges && !isSaving && !conflict && version != nil }

    func load() async {
        state = .loading
        problem = nil
        switch await store.source(of: note) {
        case let .success(source):
            text = source.markdown
            original = source.markdown
            version = source.version
            conflict = false
            state = .editing
        case let .failure(failure):
            state = .failed(failure.message)
        }
    }

    /// True when saved (the sheet closes).
    func save() async -> Bool {
        guard canSave, let version else { return false }
        isSaving = true
        problem = nil
        defer { isSaving = false }
        switch await store.saveNote(note, markdown: text, version: version, reportsFailure: false) {
        case .applied:
            original = text
            return true
        case .conflict:
            conflict = true
            problem = String(localized: "This note changed elsewhere since you opened it. Your text is still here: copy it if you need it, then load the current version.")
        case let .invalid(message), let .failed(message):
            problem = message
        }
        return false
    }

    /// After a conflict: the current version replaces the typed text.
    func loadCurrentVersion() async { await load() }
}
