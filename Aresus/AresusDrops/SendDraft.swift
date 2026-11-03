import AVFoundation
import CryptoKit
import CoreTransferable
import Foundation
import ImageIO
import Observation
import UIKit
import UniformTypeIdentifiers

/// One thing picked to send: what `DropsStore.send` takes, and what the sheet shows of it.
struct PickedFile: Identifiable {
    let id = UUID()
    var file: DropFile
    /// The file's own name ("IMG_0412.HEIC", "Exercise sheet 3.pdf").
    var displayName: String
    /// Photos: a small picture for the strip (made off the main thread).
    var thumbnail: UIImage?
}

/// The send sheet's state (brief 91): what was picked, the folder (nil = Sort later) with a new folder inside it when
/// one was made in the picker (brief 93), the name (one file), the rules as you type, and Send. The sheet only shows it.
@MainActor @Observable
final class SendDraft {
    private(set) var picked: [PickedFile] = []
    private(set) var source: DropSource = .file
    /// The folder on the Mac; nil = the fallback folder ("Sort later"). Never carries the new folder (that is `newFolder`).
    private(set) var target: Target?
    /// A folder to make inside `target` as the files land, set by the picker's New folder (or a recent folder made
    /// that way and not listed by the Mac yet); "" for none. One per send: the server takes one name.
    private(set) var newFolder = ""
    /// One file: its name, edited without its extension.
    var name = DropNameParts("")
    /// The Mac's folders as a tree (`DropsStore.folders`), kept here so every page of the sheet follows it.
    var tree = DropFolderTree(nil)
    private(set) var isSending = false
    private(set) var isLoading = false
    /// Why the last Send (or a pick) did not go through: one line under Send.
    private(set) var failure: String?
    private let temporary: SendTemporaryFiles

    init(files: [DropFile] = [], temporary: SendTemporaryFiles = SendTemporaryFiles()) {
        self.temporary = temporary
        use(files.map { PickedFile(file: $0, displayName: $0.suggestedName) }, source: files.first?.source ?? .file, last: nil)
    }

    var hasPicked: Bool { !picked.isEmpty }

    /// The sheet's one height (brief 93, so one swipe down closes it at any height): medium for the three choices,
    /// large once something is picked.
    enum Height: Equatable { case medium, large }
    var height: Height { hasPicked ? .large : .medium }

    /// Use what was picked; the folder starts where this kind of file went last (`DropRecentFolders.lastBySource`), else
    /// Sort later.
    func use(_ files: [PickedFile], source: DropSource, last: Target?) {
        guard !files.isEmpty else { return }
        let wasEmpty = picked.isEmpty
        var identities = Set(picked.map { Self.identity($0.file) })
        let added = files.filter { identities.insert(Self.identity($0.file)).inserted }
        picked.append(contentsOf: added)
        guard !added.isEmpty else { return }
        failure = nil
        if wasEmpty {
            self.source = source
            (target, newFolder) = DropFolderTree.start(from: last, in: tree)
        }
        if picked.count == 1 { name = DropNameParts(Self.defaultName(picked[0].file)) }
    }

    private static func identity(_ file: DropFile) -> String {
        if let identity = file.identity { return identity }
        switch file.content {
        case .file(let url): return url.standardizedFileURL.absoluteString
        case .data(let data): return SHA256.hash(data: data).description + file.suggestedName
        }
    }

    /// Takes one picked item out (its badge on the picked row, brief 100). Removing the last goes back to the three
    /// choices without a line left from an earlier pick; the copies stay until the sheet closes (a photo may still be
    /// loading into the same folder).
    func remove(_ id: PickedFile.ID) {
        picked.removeAll { $0.id == id }
        if picked.count == 1 { name = DropNameParts(Self.defaultName(picked[0].file)) }
        if picked.isEmpty { failure = nil }
    }

    /// Whether the picked items show their remove badges (brief 100): in the app always, since removing the last goes
    /// back to the three choices; in the share sheet only while more than one is left, as it has no choices to go back
    /// to (its close button cancels the share).
    func canRemove(sharing: Bool) -> Bool {
        hasPicked && !isSending && (!sharing || picked.count > 1)
    }

    /// Back to the three choices; the copies made for this pick go.
    func startOver() {
        picked = []
        failure = nil
        newFolder = ""
        name = DropNameParts("")
        temporary.clear()
    }

    /// A folder from the picker, with the new folder made there (`DropNewFolder.target`); a recent one brings the new
    /// folder it was sent with, unless the Mac now lists it (ignoring case: then that folder is chosen).
    func choose(_ target: Target?) {
        (self.target, newFolder) = DropFolderTree.start(from: target, in: tree)
    }

    func update(_ thumbnail: UIImage, for id: PickedFile.ID) {
        guard let index = picked.firstIndex(where: { $0.id == id }) else { return }
        picked[index].thumbnail = thumbnail
    }

    // MARK: names and rules

    /// The names the files get on the Mac, as `DropsStore.send` would make them (several: not editable).
    var names: [String] {
        if picked.count == 1 { return [name.name] }
        return DropNames.unique(picked.map { Self.defaultName($0.file) })
    }

    /// One file: the rule its name breaks.
    var nameRule: DropNames.Rule? { picked.count == 1 ? name.rule : nil }

    /// The new folder's rule (the picker checked it as it was typed; a recent one was sent before); empty is fine, and
    /// there is none while the file goes to Sort later.
    var newFolderRule: DropNames.Rule? {
        guard target != nil, !trimmedNewFolder.isEmpty else { return nil }
        return DropNames.newName(trimmedNewFolder)
    }

    /// Where the files go: the folder with the new folder inside it, or nil for the fallback folder.
    var sendTarget: Target? {
        target.map { Target(root: $0.root, folder: $0.folder, newFolder: trimmedNewFolder.isEmpty ? nil : trimmedNewFolder) }
    }

    var canSend: Bool {
        hasPicked && !isSending && !isLoading && nameRule == nil && newFolderRule == nil
            && (target.map { DropNames.folderPath($0.folder) == nil } ?? true)
    }

    private var trimmedNewFolder: String { newFolder.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func defaultName(_ file: DropFile) -> String {
        file.name ?? DropNames.defaultName(suggested: file.suggestedName, source: file.source, date: file.date)
    }

    // MARK: sending

    /// Hands each file to the store (which copies it into its outbox), one at a time, so a file that cannot be read
    /// leaves the others sent and stays on the sheet with its line. True when every file went.
    func send(with store: DropsStore, prepareUploads: Bool = false) async -> Bool {
        guard canSend else { return false }
        isSending = true
        failure = nil
        defer { isSending = false }
        let target = sendTarget
        for (item, name) in zip(picked, names) {
            var file = item.file
            file.name = name
            // Files from the Files app are only readable inside their security scope, also while the store copies them.
            let scoped: URL? = if case .file(let url) = file.content, url.startAccessingSecurityScopedResource() { url } else { nil }
            defer { scoped?.stopAccessingSecurityScopedResource() }
            do {
                try await store.send(files: [file], target: target)
                picked.removeAll { $0.id == item.id }
            } catch {
                let message = DropOutbox.message(error)
                failure = picked.count > 1 ? name + ": " + message : message
                if picked.count == 1 { self.name = DropNameParts(name) }
                return false
            }
        }
        if prepareUploads { await store.outbox?.process() }
        temporary.clear()
        return true
    }

    // MARK: picking

    /// Photos from the library: each copied as it is (original data, its own extension) into a folder of the app's
    /// own (`PickedLibraryFile`), its capture date read for the default name.
    func load<Item>(_ items: [Item], with load: (Item) async throws -> URL?, last: Target?, identity: (Item) -> String? = { _ in nil }) async {
        guard !items.isEmpty else { return }
        isLoading = true
        failure = nil
        defer { isLoading = false }
        var files: [PickedFile] = []
        var missing = 0
        for item in items {
            do {
                guard let url = try await load(item) else { missing += 1; continue }
                let date = await PhotoDate.captured(url) ?? .now
                let photoIdentity: String?
                if let known = identity(item) { photoIdentity = known }
                else { photoIdentity = try? await DropFileIO.fingerprint(url).sha256 }
                files.append(PickedFile(file: DropFile(content: .file(url), suggestedName: url.lastPathComponent,
                                                       source: .photo, date: date,
                                                       identity: photoIdentity),
                                        displayName: url.lastPathComponent))
            } catch { missing += 1 }
        }
        use(files, source: .photo, last: last)
        if missing > 0 {
            failure = missing == 1 ? String(localized: LocalizedStringResource("A photo could not be loaded.", table: "AresusDrops", locale: .appLanguage))
                                   : String(localized: LocalizedStringResource("\(missing) photos could not be loaded.", table: "AresusDrops", locale: .appLanguage))
        }
    }

    /// A photo just taken with the camera: kept as JPEG, named by the moment it was taken.
    func useCamera(_ image: UIImage, last: Target?, now: Date = .now) {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            failure = String(localized: LocalizedStringResource("The photo could not be kept.", table: "AresusDrops", locale: .appLanguage))
            return
        }
        let file = DropFile(content: .data(data), suggestedName: "Photo.jpg", source: .camera, date: now)
        use([PickedFile(file: file, displayName: DropNames.defaultName(suggested: "Photo.jpg", source: .camera, date: now),
                        thumbnail: image.preparingThumbnail(of: CGSize(width: 240, height: 240)))],
            source: .camera, last: last)
    }

    /// Files from the Files app (security-scoped URLs, read when sent).
    func useFiles(_ urls: [URL], last: Target?) {
        use(urls.map { PickedFile(file: DropFile(content: .file($0), suggestedName: $0.lastPathComponent, source: .file),
                                  displayName: $0.lastPathComponent) },
            source: .file, last: last)
    }

    func show(_ failure: String) { self.failure = failure }
}

/// The camera's permission, asked the first time (iOS's own question, so the app switcher cover stays back:
/// `SystemPrompt`).
enum CameraAccess {
    enum Answer { case allowed, refused }

    static func ask() async -> Answer {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .allowed
        case .notDetermined:
            SystemPrompt.begin()
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            SystemPrompt.end()
            return allowed ? .allowed : .refused
        default: return .refused
        }
    }
}

/// The folder the sheet copies picked photos into until they are handed to the outbox (which keeps its own copy).
nonisolated final class SendTemporaryFiles: Sendable {
    let base: URL

    init(base: URL = FileManager.default.temporaryDirectory.appending(path: "Aresus-send", directoryHint: .isDirectory)) {
        self.base = base
    }

    /// A new empty folder for one file, so two photos with the same name never meet.
    func folder() throws -> URL {
        let folder = base.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func clear() { try? FileManager.default.removeItem(at: base) }
}

/// A photo or video from the photo picker as its original file, copied out of the picker's short-lived one into a
/// folder of `SendTemporaryFiles` (the sheet's draft clears them).
nonisolated struct PickedLibraryFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in try copy(received.file) }
        FileRepresentation(importedContentType: .movie) { received in try copy(received.file) }
    }

    private static func copy(_ file: URL) throws -> PickedLibraryFile {
        let url = try SendTemporaryFiles().folder().appending(path: file.lastPathComponent)
        try FileManager.default.copyItem(at: file, to: url)
        return PickedLibraryFile(url: url)
    }
}

/// When a photo was taken: the camera's own time in its EXIF (with its offset when the camera wrote one), a video's
/// creation date; nil when the file has none.
nonisolated enum PhotoDate {
    @concurrent static func captured(_ url: URL) async -> Date? {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            return parse(text, offset: exif[kCGImagePropertyExifOffsetTimeOriginal] as? String)
        }
        let asset = AVURLAsset(url: url)
        guard let item = try? await asset.load(.creationDate) else { return nil }
        return try? await item.load(.dateValue)
    }

    /// EXIF's "2026:11:01 19:03:04" with an optional "+01:00"; without one, the phone's time zone.
    static func parse(_ text: String, offset: String?, timeZone: TimeZone = .current) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = offset.flatMap(zone) ?? timeZone
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }

    private static func zone(_ offset: String) -> TimeZone? {
        let parts = offset.dropFirst().split(separator: ":")
        guard let sign = offset.first, sign == "+" || sign == "-", parts.count == 2,
              let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
        return TimeZone(secondsFromGMT: (sign == "-" ? -1 : 1) * (hours * 3600 + minutes * 60))
    }
}

/// A small picture of a photo for the strip (an 88 pt tile, so 264 pixels), read from the file without loading it whole.
/// The share extension has little memory (iOS closes it at about 120 MB), and on the iPhone the photo decoder can hold a
/// whole picture while it shrinks it, so the thumbnails are made one at a time and from the small picture a photo
/// carries when it has one (measured with six 24-megapixel HEIC photos on the simulator, 2026-11-03: the peak rose by
/// 19 MB made all at once from the full pictures, by 5 MB this way).
nonisolated enum DropThumbnail {
    static func make(_ url: URL, pixels: Int = 264) async -> UIImage? {
        if let image = await queue.run({ still(url, pixels: pixels) }) { return image }
        return await video(url)
    }

    private static let queue = Queue()

    /// Runs one thumbnail at a time, off the main actor.
    private actor Queue {
        func run(_ work: @Sendable () -> UIImage?) -> UIImage? { work() }
    }

    private static func still(_ url: URL, pixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceShouldCacheImmediately: true,
                                        kCGImageSourceThumbnailMaxPixelSize: pixels]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(UIImage.init(cgImage:))
    }

    private static func video(_ url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        guard let image = try? await generator.image(at: .zero).image else { return nil }
        return UIImage(cgImage: image)
    }
}
