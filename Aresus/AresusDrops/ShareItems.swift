import Foundation
import UIKit
import UniformTypeIdentifiers

/// Copies each provider's temporary representation inside its callback, before iOS revokes access. File-backed
/// items are never read into Data. Only providers with no usable file representation use their data/image object.
@MainActor
struct ShareItems {
    struct Answer {
        var files: [DropFile]
        var unreadable: Int
    }
    let temporary: SendTemporaryFiles

    func read(_ items: [NSExtensionItem]) async -> Answer {
        await read(providers: items.flatMap { $0.attachments ?? [] })
    }

    func read(providers: [NSItemProvider]) async -> Answer {
        var answer = Answer(files: [], unreadable: max(0, providers.count - 20))
        for provider in providers.prefix(20) {
            guard let type = provider.registeredTypeIdentifiers.first(where: {
                UTType($0)?.conforms(to: .item) == true
            }) else { answer.unreadable += 1; continue }
            let suggested = provider.suggestedName
            do {
                let folder = try temporary.folder()
                let url: URL
                do { url = try await Self.file(provider, type: type, suggested: suggested, folder: folder) }
                catch {
                    // A file-read or connection failure is unreadable, never a reason to load its bytes into memory.
                    let failure = error as NSError
                    if let underlying = failure.userInfo[NSUnderlyingErrorKey] as? NSError,
                       underlying.domain == NSCocoaErrorDomain || underlying.domain == NSURLErrorDomain { throw error }
                    if failure.domain == NSCocoaErrorDomain || failure.domain == NSURLErrorDomain { throw error }
                    url = try await Self.object(provider, type: type, suggested: suggested, folder: folder)
                }
                let media = UTType(type).map { $0.conforms(to: .image) || $0.conforms(to: .movie) } ?? false
                let date = media ? await PhotoDate.captured(url) ?? .now : .now
                answer.files.append(DropFile(content: .file(url), suggestedName: url.lastPathComponent,
                                             source: media ? .photo : .file, date: date))
            } catch { answer.unreadable += 1 }
        }
        return answer
    }

    nonisolated static func name(suggested: String?, loaded: String?, type: String) -> String {
        func clean(_ text: String?) -> String? {
            guard let text else { return nil }
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
            return value.isEmpty || value == "." || value == ".." ? nil : value
        }
        let base = clean(suggested) ?? clean(loaded) ?? String(localized: LocalizedStringResource("File", table: "AresusDrops", locale: .appLanguage))
        let ext = (base as NSString).pathExtension
        if !ext.isEmpty, let actual = UTType(filenameExtension: ext),
           let expected = UTType(type), actual.conforms(to: expected) { return base }
        let loadedExtension = loaded.map { ($0 as NSString).pathExtension }.flatMap { $0.isEmpty ? nil : $0 }
        guard let suffix = loadedExtension ?? UTType(type)?.preferredFilenameExtension else { return base }
        return base + "." + suffix
    }

    private nonisolated static func file(_ provider: NSItemProvider, type: String, suggested: String?, folder: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                do {
                    guard let url else { throw error ?? DropLocalError.unreadableFile }
                    let name = name(suggested: suggested, loaded: url.lastPathComponent, type: type)
                    // ProviderFiles.copy is the same short-lived representation copy Aresium's drop uses.
                    continuation.resume(returning: try ProviderFiles.copy(url, name: name, into: folder))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private nonisolated static func object(_ provider: NSItemProvider, type: String, suggested: String?, folder: URL) async throws -> URL {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                    do {
                        guard let data else { throw error ?? DropLocalError.unreadableFile }
                        let destination = folder.appendingPathComponent(name(suggested: suggested, loaded: nil, type: type))
                        try data.write(to: destination, options: .atomic)
                        continuation.resume(returning: destination)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } catch {
            guard provider.canLoadObject(ofClass: UIImage.self) else { throw error }
            return try await withCheckedThrowingContinuation { continuation in
                _ = provider.loadObject(ofClass: UIImage.self) { object, error in
                    do {
                        guard let image = object as? UIImage, let data = image.pngData() else {
                            throw error ?? DropLocalError.unreadableFile
                        }
                        let destination = folder.appendingPathComponent(name(suggested: suggested, loaded: nil, type: UTType.png.identifier))
                        try data.write(to: destination, options: .atomic)
                        continuation.resume(returning: destination)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }
    }
}
