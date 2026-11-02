import Foundation
import Observation

/// The form's look at the product before it is saved (brief 137, `POST /price/preview`): once the link looks complete
/// and typing pauses, the server reads the page once and says what it found ("Found: NINTENDO Switch 2 · €483.99 · in
/// stock"), or why not, in its words. The server allows one preview per account every 5 seconds, so the model asks for
/// one at a time, never sooner than 5 seconds after the last, and only for the newest link: a link typed meanwhile waits
/// its turn, and an answer for a link no longer in the field is dropped.
@MainActor @Observable
final class PricePreviewModel {
    /// The pause in typing before the link is read.
    nonisolated static let pause: Duration = .milliseconds(700)
    /// The server's spacing between two previews of one account.
    nonisolated static let spacing: Duration = .seconds(5)

    enum Phase: Equatable {
        /// No link yet, or one that does not look complete.
        case idle
        /// The link is being read (or waits for its turn).
        case reading
        /// What the server found on the page.
        case found(PricePreview)
        /// The server's refusal of the link, in its words.
        case refused(String)
        /// The preview failed (offline, the AI down): a calm line; saving still works.
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// The link the phase is about.
    private(set) var link: String?

    /// Whether a text looks like a whole link: a host with a dot and a top-level part of two letters or more, and
    /// something after it (a path or a query: a shop's product page, not its front page). Spaces mean it is not one yet.
    static func looksComplete(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              trimmed.count <= WatchSearchDraft.maxURL else { return false }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let parts = URLComponents(string: withScheme), let host = parts.host,
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""), host.contains("."),
              let top = host.split(separator: ".").last, top.count >= 2, top.allSatisfy(\.isLetter) else { return false }
        let path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return !path.isEmpty || !(parts.query ?? "").isEmpty
    }

    /// The pause after the last keystroke, before the link is handed to the worker.
    @ObservationIgnored private var waiting: Task<Void, Never>?
    /// The one worker reading links, one after the other.
    @ObservationIgnored private var worker: Task<Void, Never>?
    /// The newest link the worker should read; nil when there is none (or it was taken).
    @ObservationIgnored private var wanted: String?
    @ObservationIgnored private var lastAsked: ContinuousClock.Instant?
    @ObservationIgnored private let clock = ContinuousClock()
    private let pause: Duration
    private let spacing: Duration
    private let fetch: (String) async throws -> PricePreview

    init(pause: Duration = PricePreviewModel.pause, spacing: Duration = PricePreviewModel.spacing,
         fetch: @escaping (String) async throws -> PricePreview) {
        self.pause = pause
        self.spacing = spacing
        self.fetch = fetch
    }

    /// The link field changed: a link that looks complete is read once typing pauses (unless it is the one already
    /// read); anything else clears the line.
    func update(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.looksComplete(trimmed) else {
            waiting?.cancel()
            waiting = nil
            wanted = nil
            link = nil
            phase = .idle
            return
        }
        guard trimmed != link || phase == .idle else { return }
        waiting?.cancel()
        link = trimmed
        phase = .reading
        waiting = Task { [pause] in
            try? await Task.sleep(for: pause)
            guard !Task.isCancelled else { return }
            self.wanted = trimmed
            self.startWorker()
        }
    }

    /// Waits until nothing waits or is read (tests).
    func settle() async {
        await waiting?.value
        while let worker { await worker.value }
    }

    private func startWorker() {
        guard worker == nil else { return }
        worker = Task { await self.work() }
    }

    /// Reads the newest wanted link, one at a time, never sooner than `spacing` after the last read began.
    private func work() async {
        while wanted != nil {
            if let lastAsked {
                let ready = lastAsked.advanced(by: spacing)
                if clock.now < ready { try? await clock.sleep(until: ready) }
            }
            // The newest link after the wait: one typed meanwhile replaces the one that waited.
            guard let target = wanted else { break }
            wanted = nil
            guard target == link else { continue }
            lastAsked = clock.now
            await read(target)
        }
        worker = nil
    }

    private func read(_ target: String) async {
        let outcome: Phase
        do {
            outcome = .found(try await fetch(target))
        } catch is CancellationError {
            // Dropped (a login that ended meanwhile).
            if link == target { phase = .idle }
            return
        } catch let refusal as FieldRefusal {
            outcome = .refused(refusal.message)
        } catch HTTPError.server(429, _) {
            // Another device asked just now: this link waits its turn again, quietly.
            if link == target, wanted == nil { wanted = target }
            return
        } catch {
            outcome = .failed(error.localizedDescription)
        }
        // An answer for a link no longer in the field is dropped.
        guard link == target else { return }
        phase = outcome
    }

    /// What was found, for the name's placeholder and the alarm's limit.
    var preview: PricePreview? {
        if case .found(let preview) = phase { preview } else { nil }
    }

    /// The line under the link: "Found: …", "Reading the page…", or the failure; a refusal is a problem line
    /// (`refusal`).
    func line(language: AppLanguage = .current) -> String? {
        switch phase {
        case .idle, .refused: nil
        case .reading: language.string("Reading the page…")
        case .found(let preview): PriceWords.found(preview, language: language)
        case .failed(let message): message
        }
    }

    /// The server's refusal of the link, in its words.
    var refusal: String? {
        if case .refused(let message) = phase { message } else { nil }
    }
}
