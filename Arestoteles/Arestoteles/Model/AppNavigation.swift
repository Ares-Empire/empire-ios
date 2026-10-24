import Foundation
import Observation

enum AppTab: String, Hashable, CaseIterable {
    case positions, topics, library, search
}

/// A page pushed on a tab: a note (scrolled to a heading when the link names one), or a position.
enum Route: Hashable {
    case note(NoteLink)
    case position(String)
}

/// The Library tab's four parts.
enum LibraryPart: String, CaseIterable, Identifiable, Hashable {
    case mechanisms, events, questions, actors
    var id: String { rawValue }

    var title: String {
        switch self {
        case .mechanisms: String(localized: "Mechanisms")
        case .events: String(localized: "Events")
        case .questions: String(localized: "Questions")
        case .actors: String(localized: "Actors")
        }
    }
}

/// The sheets shown over the tabs.
enum AppSheet: Identifiable, Equatable {
    case brief(String)                      // a topic overview's brief
    case editor(String)                     // the free editor of a note
    case discuss(DiscussSubject)
    case quickNote
    case position(PositionDraft.Kind)       // reword, change, drop, add

    var id: String {
        switch self {
        case let .brief(note): "brief:" + note
        case let .editor(note): "editor:" + note
        case let .discuss(.note(note)): "discuss-note:" + note
        case let .discuss(.position(position)): "discuss-position:" + position
        case .quickNote: "quicknote"
        case let .position(kind): "position:" + kind.id
        }
    }
}

/// Where the user is: the tab, each tab's pushed pages, the Library's part and filter, the search, the open sheet.
/// Links (in notes, from outside, from Spotlight) all go through `open(_:)`.
@MainActor @Observable
final class AppNavigation {
    var tab: AppTab = .positions
    var positionsPath: [Route] = []
    var topicsPath: [Route] = []
    var libraryPath: [Route] = []
    var searchPath: [Route] = []
    var libraryPart: LibraryPart = .mechanisms
    /// The events timeline's region filter; nil = every region.
    var region: String?
    var query = ""
    /// The search's type filter; nil = every type.
    var searchType: NoteType?
    var sheet: AppSheet?
    /// A heading to scroll to in the note already on top (a link within the same note).
    private(set) var scrollRequest: NoteLink?
    /// A link from outside, waiting for the tabs to be on screen.
    private(set) var pendingLink: NoteLink?
    /// A sheet to show once the pending link is open.
    private var pendingSheet: AppSheet?

    /// The pages of the tab on screen.
    var path: [Route] {
        get {
            switch tab {
            case .positions: positionsPath
            case .topics: topicsPath
            case .library: libraryPath
            case .search: searchPath
            }
        }
        set {
            switch tab {
            case .positions: positionsPath = newValue
            case .topics: topicsPath = newValue
            case .library: libraryPath = newValue
            case .search: searchPath = newValue
            }
        }
    }

    /// A deep link or a Spotlight result: queued until the tabs are on screen, then `open(_:)`, then `sheet` if given.
    func follow(_ link: NoteLink, then sheet: AppSheet? = nil) {
        pendingLink = link
        pendingSheet = sheet
    }

    func openPendingLink() {
        guard let link = pendingLink else { return }
        pendingLink = nil
        open(link)
        if let pendingSheet { sheet = pendingSheet }
        pendingSheet = nil
    }

    /// Opens a note on the tab on screen (closing a sheet first). A link to a heading of the note already on top
    /// scrolls there instead of opening the note again.
    func open(_ link: NoteLink) {
        sheet = nil
        if case let .note(top)? = path.last, top.note == link.note {
            if link.anchor != nil { scrollRequest = link }
            return
        }
        path.append(.note(link))
    }

    func showPosition(_ id: String) {
        sheet = nil
        if path.last == .position(id) { return }
        path.append(.position(id))
    }

    /// After a position was dropped: its page closes (the server renumbered the rest, so its id may now name another).
    func closePosition(_ id: String) {
        func cut(_ path: inout [Route]) {
            if let index = path.firstIndex(of: .position(id)) { path.removeSubrange(index...) }
        }
        cut(&positionsPath)
        cut(&topicsPath)
        cut(&libraryPath)
        cut(&searchPath)
    }

    /// The note scrolled to the requested heading.
    func scrolled() { scrollRequest = nil }

    /// Back to the start (after logging out).
    func reset() {
        tab = .positions
        positionsPath = []
        topicsPath = []
        libraryPath = []
        searchPath = []
        libraryPart = .mechanisms
        region = nil
        query = ""
        searchType = nil
        sheet = nil
        scrollRequest = nil
        pendingLink = nil
        pendingSheet = nil
    }
}

/// DEBUG launch arguments for screenshots (in a release build all are ignored):
/// `-sampleData` (the bundled samples; edits answered with `edit-result.json`), `-sampleEditConflict` /
/// `-sampleEditInvalid` (edits answered 409 / 422), `-samplePushLater` (edits saved with `pushed: false`),
/// `-sampleOffline` (the samples as the saved vault, the server unreachable), `-tab positions|topics|library|search`,
/// `-library mechanisms|events|questions|actors`, `-search <query>`, `-openNote <id>[#<heading>]`,
/// `-openPosition <id>`, `-openSheet brief|edit|quicknote|discuss|reword|change|drop|add`.
struct LaunchOptions {
    var sample = false
    var editConflict = false
    var editInvalid = false
    var pushLater = false
    var offline = false
    var tab: AppTab?
    var library: LibraryPart?
    var search: String?
    var openNote: NoteLink?
    var openPosition: String?
    var openSheet: String?

    init(arguments: [String]) {
        #if DEBUG
        func value(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        sample = arguments.contains("-sampleData")
        editConflict = arguments.contains("-sampleEditConflict")
        editInvalid = arguments.contains("-sampleEditInvalid")
        pushLater = arguments.contains("-samplePushLater")
        offline = arguments.contains("-sampleOffline")
        tab = value("-tab").flatMap(AppTab.init(rawValue:))
        library = value("-library").flatMap(LibraryPart.init(rawValue:))
        search = value("-search")
        openNote = value("-openNote").map { text in
            let parts = text.split(separator: "#", maxSplits: 1).map(String.init)
            return NoteLink(note: parts[0], anchor: parts.count > 1 ? parts[1] : nil)
        }
        openPosition = value("-openPosition")
        openSheet = value("-openSheet")
        #endif
    }

    /// Puts the navigation where the arguments ask (sample mode only), once the vault is there.
    func apply(to navigation: AppNavigation, index: VaultIndex) {
        guard sample else { return }
        if let tab { navigation.tab = tab }
        if let library {
            navigation.tab = .library
            navigation.libraryPart = library
        }
        if let search {
            navigation.tab = .search
            navigation.query = search
        }
        if let openPosition { navigation.showPosition(openPosition) }
        let note = openNote?.note
        let position = openPosition ?? index.positionTargets.lazy.compactMap { index.positions($0.positions).first?.id }.first
        var sheet: AppSheet?
        switch openSheet {
        case "brief":
            sheet = (note ?? index.topics.first(where: { $0.brief != nil })?.id).map(AppSheet.brief)
        case "edit":
            sheet = (note ?? index.topics.first?.id).map(AppSheet.editor)
        case "quicknote":
            sheet = .quickNote
        case "discuss":
            let subject = openPosition.map(DiscussSubject.position) ?? note.map(DiscussSubject.note)
                ?? position.map(DiscussSubject.position)
            sheet = subject.map(AppSheet.discuss)
        case "reword", "change", "drop":
            sheet = position.map { openSheet == "reword" ? .position(.reword($0))
                                   : openSheet == "change" ? .position(.change($0)) : .position(.drop($0)) }
        case "add":
            sheet = (note ?? index.positionTargets.first?.id).map { .position(.add(note: $0)) }
        default:
            break
        }
        // A note to open first: the sheet comes once the note is there (opening a link closes sheets).
        if let openNote {
            navigation.follow(openNote, then: sheet)
        } else {
            navigation.sheet = sheet
        }
    }
}
