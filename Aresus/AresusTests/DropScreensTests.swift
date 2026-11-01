import Foundation
import Testing
@testable import Aresus

/// Brief 91: what the drop screens show, from the row of each state to the folder tree, its search and the send draft.
@MainActor
struct DropRowTests {
    private let now = at("2026-11-01T18:00:00Z")

    private func drop(_ state: DropState, note: String? = nil, landed: String? = nil, fallback: Bool = false,
                      name: String = "sketch.pdf", updated: String = "2026-11-01T15:07:00Z") -> Drop {
        Drop(id: 4, kind: .file, name: name, size: 10, target: nil, state: state, landed: landed, fallback: fallback,
             note: note, created: at("2026-11-01T15:00:00Z"), updated: at(updated))
    }

    private func local(_ state: DropOutboxItem.State, error: String? = nil, serverID: Int? = nil,
                       cancelling: Bool = false) -> DropOutboxItem {
        var item = DropOutboxItem(id: UUID(), drop: NewDrop(kind: .file, name: "IMG_0001.heic", size: 0, sha256: "",
                                                           target: nil, receipt: nil),
                                  localFile: "x.file", serverID: serverID, created: now)
        item.state = state
        item.lastError = error
        item.cancellationRequested = cancelling
        return item
    }

    private func row(_ item: DropsItem, local: DropOutboxItem? = nil, language: AppLanguage = .english) -> DropRow {
        DropRow(item, local: local, now: now, calendar: berlin, language: language)
    }

    @Test func phoneItemsSayWhereTheyAre() {
        let waiting = row(.phone(local(.onPhone)))
        #expect(waiting.line == "On the phone · waits for a connection" && waiting.tone == .normal)
        #expect(!waiting.canRetry && waiting.canRemove)
        #expect(row(.phone(local(.uploading))).line == "Uploading …")
        let failed = row(.phone(local(.failed, error: "This file is too large.")))
        #expect(failed.line == "Not sent: This file is too large." && failed.tone == .warning)
        #expect(failed.canRetry && failed.canRemove)
        let removing = row(.phone(local(.onPhone, cancelling: true)))
        #expect(removing.line == "Removing …" && removing.tone == .muted && !removing.canRemove && !removing.canRetry)
        #expect(row(.phone(local(.onPhone))).name == "IMG_0001.heic")
        #expect(row(.phone(local(.onPhone))).kind == .photo)
    }

    @Test func serverStatesHaveTheirLines() {
        #expect(row(.server(drop(.uploading))).line == "Uploading …")
        let waiting = row(.server(drop(.waiting)))
        #expect(waiting.line == "Waiting for the MacBook" && waiting.tone == .normal && waiting.canRemove && !waiting.canRetry)
        let failed = row(.server(drop(.failed, note: "The MacBook could not write the file.")))
        #expect(failed.line == "The MacBook could not write the file." && failed.tone == .warning)
        #expect(failed.canRemove && !failed.canRetry, "the Mac tries a failed drop again by itself; there is no route")
        #expect(row(.server(drop(.failed))).line == "The MacBook could not save it.")
        #expect(row(.server(drop(.failed, note: " "))).line == "The MacBook could not save it.")
        let cancelled = row(.server(drop(.cancelled)))
        #expect(cancelled.line == "Cancelled" && cancelled.tone == .muted && cancelled.isQuiet && !cancelled.canRemove)
    }

    @Test func landedSaysTheFolderAndTheTimeAndKeepsItsNote() {
        let landed = row(.server(drop(.landed, landed: "Documents/Receipts/sketch.pdf")))
        #expect(landed.line == "In Receipts · 16:07" && landed.note == nil)
        #expect(!landed.canRemove && !landed.canRetry)
        let moved = row(.server(drop(.landed, note: "The folder EIST is gone, so it went to Zu sortieren.",
                                     landed: "Documents/Zu sortieren/sketch.pdf", fallback: true)))
        #expect(moved.line == "In Zu sortieren · 16:07")
        #expect(moved.note == "The folder EIST is gone, so it went to Zu sortieren.")
        let yesterday = row(.server(drop(.landed, landed: "Downloads/x.pdf", updated: "2026-10-31T21:57:00Z")))
        #expect(yesterday.line == "In Downloads · yesterday 22:57")
        #expect(row(.server(drop(.landed, landed: "Documents/x.pdf")), language: .german).line == "In Dokumente · 16:07")
        #expect(row(.server(drop(.landed, landed: "x.pdf"))).line == "On the MacBook · 16:07")
        #expect(row(.server(drop(.landed))).line == "On the MacBook · 16:07")
    }

    @Test func aServerRowStillUploadingFromThisPhoneShowsThePhonesState() {
        let item = DropsItem.server(drop(.uploading))
        let hidden = local(.failed, error: "No connection.", serverID: 4)
        #expect(DropRow.hidden(for: item, in: [local(.onPhone, serverID: 9), hidden]) == hidden)
        #expect(DropRow.hidden(for: .phone(hidden), in: [hidden]) == nil)
        let shown = row(item, local: hidden)
        #expect(shown.line == "Not sent: No connection." && shown.canRetry && shown.canRemove)
        #expect(shown.name == "sketch.pdf")
    }

    @Test func germanLines() {
        #expect(row(.phone(local(.onPhone)), language: .german).line == "Auf dem iPhone · wartet auf Verbindung")
        #expect(row(.server(drop(.waiting)), language: .german).line == "Wartet auf das MacBook")
        #expect(row(.server(drop(.failed)), language: .german).line == "Das MacBook konnte die Datei nicht speichern.")
        #expect(row(.server(drop(.cancelled)), language: .german).line == "Abgebrochen")
    }

    @Test func kindsFromTheExtension() {
        #expect(DropFileKind(name: "IMG_0001.HEIC") == .photo)
        #expect(DropFileKind(name: "scan.jpeg") == .photo)
        #expect(DropFileKind(name: "clip.MOV") == .video)
        #expect(DropFileKind(name: "2026-11-01 Shop - Lamp - 12,34 EUR.pdf") == .pdf)
        #expect(DropFileKind(name: "notes") == .other)
        #expect(DropFileKind(name: "archive.zip").symbol == "doc")
    }

    @Test func daysGroupTheFullList() throws {
        let answer: DropsAnswer = try sample("drops")
        var older = answer.drops[0]
        older.id = 9
        older.created = at("2026-10-30T10:00:00Z")
        let items = [DropsItem.phone(local(.onPhone))] + answer.drops.map(DropsItem.server) + [.server(older)]
        let days = DropDay.group(items, now: now, calendar: berlin, language: .english)
        #expect(days.map(\.title) == ["Today", "Fri 30 Oct"])
        #expect(days[0].items.count == 6 && days[1].items == [.server(older)])
        #expect(DropDay.group([], now: now).isEmpty)
    }
}

struct DropPathTextTests {
    @Test func pathsReadAsFinderShowsThem() {
        #expect(DropPathText.path(.documents, "Studium/EIST") == "Documents › Studium › EIST")
        #expect(DropPathText.path(.downloads, "") == "Downloads")
        #expect(DropPathText.path(Target(root: .documents, folder: "Studium", newFolder: "EIST")) == "Documents › Studium › EIST")
        #expect(DropPathText.path(.documents, "Studium", newFolder: "") == "Documents › Studium")
        #expect(DropPathText.path(.documents, "Studium/EIST", language: .german) == "Dokumente › Studium › EIST")
        #expect(DropPathText.name(.documents, "Studium/EIST") == "EIST")
        #expect(DropPathText.name(.documents, "", language: .german) == "Dokumente")
        #expect(DropPathText.name(Target(root: .downloads, folder: "Examples", newFolder: "Diagrams")) == "Diagrams")
        #expect(DropPathText.name(Target(root: .downloads, folder: "", newFolder: nil)) == "Downloads")
    }

    @Test func theLandedFolder() {
        #expect(DropPathText.lastFolder(ofLanded: "Documents/Zu sortieren/x.jpg") == "Zu sortieren")
        #expect(DropPathText.lastFolder(ofLanded: "Documents/x.jpg", language: .german) == "Dokumente")
        #expect(DropPathText.lastFolder(ofLanded: "Downloads/x.jpg") == "Downloads")
        #expect(DropPathText.lastFolder(ofLanded: "x.jpg") == nil)
    }

    @Test func rulesInPlainWords() {
        let rules: [DropNames.Rule] = [.empty, .tooLong, .forbiddenCharacter, .dot, .leadingDot, .trailingSpaceOrDot, .tooManyParts]
        let english = rules.map { DropRuleWording.text($0, language: .english) }
        let german = rules.map { DropRuleWording.text($0, language: .german) }
        #expect(english[0] == "Enter a name." && german[0] == "Gib einen Namen ein.")
        #expect(english[2] == "A name cannot contain a slash, a backslash or a colon.")
        #expect(Set(english).count == rules.count && Set(german).count == rules.count)
        #expect(zip(english, german).allSatisfy { $0 != $1 }, "every rule has its German")
    }

    @Test func theNameIsEditedWithoutItsExtension() {
        var parts = DropNameParts("2026-11-01 19-03-04.HEIC")
        #expect(parts.stem == "2026-11-01 19-03-04" && parts.ext == "HEIC")
        parts.stem = "  Garden  "
        #expect(parts.name == "Garden.HEIC" && parts.rule == nil)
        parts.stem = "   "
        #expect(parts.rule == .empty)
        parts.stem = "a/b"
        #expect(parts.rule == .forbiddenCharacter)
        parts.stem = "Notes."
        #expect(parts.rule == nil, "the extension follows, so the edited part may end in a dot")
        #expect(DropNameParts("archive.tar.gz").stem == "archive.tar")
        let plain = DropNameParts("README")
        #expect(plain.ext.isEmpty && plain.name == "README")
        #expect(DropNameParts(".hidden").ext.isEmpty && DropNameParts(".hidden").rule == .leadingDot)
        var trailing = DropNameParts("name.")
        #expect(trailing.ext.isEmpty && trailing.rule == .trailingSpaceOrDot)
        trailing.stem = "name"
        #expect(trailing.rule == nil)
    }
}

struct DropFolderTreeTests {
    private func list(documents: [String], downloads: [String] = []) -> FolderList {
        FolderList(updated: at("2026-11-01T15:00:00Z"), documents: documents, downloads: downloads, fallback: "Zu sortieren",
                   fallbackCount: 0, receipts: nil)
    }

    @Test func theSampleOpensFolderByFolder() throws {
        let tree = DropFolderTree(try sample("drop-folders", as: FolderList.self))
        #expect(tree.folders(in: .documents).map(\.path) == ["Examples", "Receipts", "To sort"])
        #expect(tree.folders(in: .documents, under: "Examples").map(\.path) == ["Examples/Sketches: old"])
        #expect(tree.folders(in: .downloads).map(\.path) == ["Examples"])
        #expect(tree.hasFolders(in: .documents, under: "Receipts") && !tree.hasFolders(in: .documents, under: "To sort"))
        #expect(tree.contains(.documents, "Examples/Sketches: old") && tree.contains(.downloads, ""))
        #expect(!tree.contains(.downloads, "Receipts"))
    }

    @Test func foldersAboveListedOnesExistAndFinderOrdersByNumber() {
        let tree = DropFolderTree(list(documents: ["Studium/Week 10", "Studium/Week 2", "studium old", "Ärzte"]))
        #expect(tree.folders(in: .documents).map(\.path) == ["Ärzte", "Studium", "studium old"])
        #expect(tree.folders(in: .documents, under: "Studium").map(\.path) == ["Studium/Week 2", "Studium/Week 10"])
        #expect(tree.contains(.documents, "Studium"))
        #expect(DropFolderTree(nil).folders(in: .documents).isEmpty)
    }

    @Test func searchMatchesAnyPartBestFirst() {
        let tree = DropFolderTree(list(documents: ["Studium", "Studium/EIST", "Studium/EIST/Übungen", "Uni/Eisten",
                                                   "Archiv/Studium/EIST alt"],
                                       downloads: ["EIST"]))
        let names = { (query: String) in tree.search(query, language: .english).map { $0.root.rawValue + ":" + $0.path } }
        #expect(names("eist") == ["downloads:EIST", "documents:Studium/EIST", "documents:Uni/Eisten",
                                  "documents:Archiv/Studium/EIST alt", "documents:Studium/EIST/Übungen"])
        #expect(names("ubung") == ["documents:Studium/EIST/Übungen"], "accents and case are ignored")
        #expect(names("studium eist") == ["documents:Studium/EIST", "documents:Archiv/Studium/EIST alt",
                                          "documents:Studium/EIST/Übungen"])
        #expect(names("downloads eist") == ["downloads:EIST"], "the root's name counts as part of the path")
        #expect(tree.search("dokumente übungen", language: .german).map(\.path) == ["Studium/EIST/Übungen"])
        #expect(names("  ").isEmpty && names("nothing").isEmpty)
        #expect(tree.search("e", limit: 2, language: .english).count == 2)
    }

    @Test func aRecentNewFolderBecomesAFolderOnceTheMacListsIt() {
        let tree = DropFolderTree(list(documents: ["Studium", "Studium/EIST"]))
        let made = Target(root: .documents, folder: "Studium", newFolder: "EIST")
        #expect(DropFolderTree.resolve(made, in: tree) == Target(root: .documents, folder: "Studium/EIST"))
        #expect(DropFolderTree.start(from: made, in: tree) == (Target(root: .documents, folder: "Studium/EIST"), ""))
        let notYet = Target(root: .documents, folder: "Studium", newFolder: "GBS")
        #expect(DropFolderTree.resolve(notYet, in: tree) == notYet)
        #expect(DropFolderTree.start(from: notYet, in: tree) == (Target(root: .documents, folder: "Studium"), "GBS"))
        #expect(DropFolderTree.start(from: nil, in: tree) == (nil, ""))
        #expect(DropFolderTree.resolve(Target(root: .downloads, folder: "", newFolder: ""), in: tree)
                == Target(root: .downloads, folder: ""))
    }
}

@MainActor
struct SendDraftTests {
    private let tree = DropFolderTree(FolderList(updated: .now, documents: ["Studium", "Studium/EIST"], downloads: [],
                                                 fallback: "Zu sortieren", fallbackCount: 0, receipts: nil))

    private func photo(_ name: String = "IMG_0412.HEIC") -> PickedFile {
        PickedFile(file: DropFile(content: .data(Data("photo".utf8)), suggestedName: name, source: .photo,
                                  date: at("2026-11-01T18:03:04Z")), displayName: name)
    }

    private func draft() -> SendDraft {
        let draft = SendDraft(temporary: SendTemporaryFiles(base: FileManager.default.temporaryDirectory
            .appending(path: "SendDraftTests-\(UUID().uuidString)")))
        draft.tree = tree
        return draft
    }

    @Test func oneFileStartsWithItsDefaultNameAndTheLastFolder() {
        let draft = draft()
        #expect(!draft.hasPicked && !draft.canSend)
        let last = Target(root: .documents, folder: "Studium", newFolder: "EIST")
        draft.use([photo()], source: .photo, last: last)
        #expect(draft.target == Target(root: .documents, folder: "Studium/EIST") && draft.newFolder.isEmpty)
        #expect(draft.name.ext == "HEIC")
        #expect(draft.names == [DropNames.defaultName(suggested: "IMG_0412.HEIC", source: .photo,
                                                      date: at("2026-11-01T18:03:04Z"))])
        #expect(draft.canSend)
        draft.use([photo()], source: .photo, last: nil)
        #expect(draft.target == nil && draft.sendTarget == nil, "nothing used before: Sort later")
    }

    @Test func rulesHoldSendBack() {
        let draft = draft()
        draft.use([photo()], source: .photo, last: Target(root: .documents, folder: "Studium"))
        draft.name.stem = ""
        #expect(draft.nameRule == .empty && !draft.canSend)
        draft.name.stem = "Lecture board"
        draft.newFolder = ".notes"
        #expect(draft.newFolderRule == .leadingDot && !draft.canSend)
        draft.newFolder = "  Week 3  "
        #expect(draft.newFolderRule == nil && draft.canSend)
        #expect(draft.sendTarget == Target(root: .documents, folder: "Studium", newFolder: "Week 3"))
        draft.newFolder = "   "
        #expect(draft.sendTarget == Target(root: .documents, folder: "Studium", newFolder: nil))
        draft.choose(nil)
        #expect(draft.newFolder.isEmpty && draft.newFolderRule == nil && draft.sendTarget == nil)
    }

    @Test func severalFilesGetUniqueNamesNotEdited() {
        let draft = draft()
        let files = [PickedFile(file: DropFile(content: .data(Data()), suggestedName: "Plan.pdf"), displayName: "Plan.pdf"),
                     PickedFile(file: DropFile(content: .data(Data()), suggestedName: "Plan.pdf"), displayName: "Plan.pdf")]
        draft.use(files, source: .file, last: nil)
        #expect(draft.names == ["Plan.pdf", "Plan (2).pdf"])
        #expect(draft.nameRule == nil && draft.canSend)
    }

    @Test func choosingARecentBringsItsNewFolder() {
        let draft = draft()
        draft.use([photo()], source: .photo, last: nil)
        draft.choose(Target(root: .documents, folder: "Studium", newFolder: "GBS"))
        #expect(draft.target == Target(root: .documents, folder: "Studium") && draft.newFolder == "GBS")
        draft.choose(Target(root: .documents, folder: "Studium"))
        #expect(draft.newFolder.isEmpty)
        draft.startOver()
        #expect(!draft.hasPicked && draft.failure == nil)
    }

    @Test func sendHandsEveryFileToTheStoreAndRemembersTheFolder() async throws {
        let store = DropsStore(session: await signedInSession(), samples: AresusSamples(allGood: false), cacheURL: nil,
                               defaults: nil, automatic: false)
        await store.refresh()
        let before = store.items.count
        let draft = draft()
        draft.use([photo("a.heic"), photo("b.heic")], source: .photo, last: Target(root: .documents, folder: "Studium"))
        draft.newFolder = "Board"
        #expect(await draft.send(with: store))
        #expect(!draft.hasPicked && draft.failure == nil)
        #expect(store.items.count == before + 2)
        let target = Target(root: .documents, folder: "Studium", newFolder: "Board")
        #expect(store.recentFolders.lastBySource[.photo] == target)
    }

    @Test func aFileThatCannotBeReadStaysWithItsLine() async throws {
        let store = DropsStore(session: await signedInSession(), samples: AresusSamples(allGood: false), cacheURL: nil,
                               defaults: nil, automatic: false)
        let draft = draft()
        let missing = URL(fileURLWithPath: "/fictional/missing.pdf")
        draft.use([photo("a.heic"),
                   PickedFile(file: DropFile(content: .file(missing), suggestedName: "missing.pdf"), displayName: "missing.pdf")],
                  source: .file, last: nil)
        #expect(!(await draft.send(with: store)))
        #expect(draft.picked.map(\.displayName) == ["missing.pdf"], "the photo went, the unreadable file stays")
        #expect(draft.failure == "The file could not be read.")
        #expect(draft.name.name == "missing.pdf", "one file left: its name is editable again")
    }

    @Test func exifDatesWithAndWithoutTheirOffset() throws {
        let berlinZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        #expect(PhotoDate.parse("2026:11:01 19:03:04", offset: "+01:00") == at("2026-11-01T18:03:04Z"))
        #expect(PhotoDate.parse("2026:11:01 19:03:04", offset: "-05:30") == at("2026-11-02T00:33:04Z"))
        #expect(PhotoDate.parse("2026:07:01 19:03:04", offset: nil, timeZone: berlinZone) == at("2026-07-01T17:03:04Z"))
        #expect(PhotoDate.parse("2026:11:01 19:03:04", offset: "bad", timeZone: berlinZone) == at("2026-11-01T18:03:04Z"))
        #expect(PhotoDate.parse("not a date", offset: nil) == nil)
    }
}
