import Foundation
import Observation

/// The Preismonitor form's look before saving: the server reads what was typed once and says what it found, or why not,
/// in its words. Two of them: a shop's product page from its link (brief 137, `PricePreviewModel`, "Found: NINTENDO
/// Switch 2 · €483.99 · in stock") and a product in words on every site that sells it (brief 157,
/// `ProductPreviewModel`, "Found: Apple AirPods Max (2nd gen.) · in 11 shops, from €529.00").
///
/// Both ask the same way (`PacedPreview`): once typing pauses, one at a time, never sooner than 5 seconds after the last
/// (the server allows one preview per account every 5 seconds), and only for what is typed now: something typed
/// meanwhile waits its turn, an answer for words no longer in the field is dropped, a 429 (another device asked just
/// now) waits its turn again quietly.
enum PreviewPacing {
    /// The pause in typing before a link is read.
    static let pause: Duration = .milliseconds(700)
    /// The pause in typing before a product is looked for: longer, as words come with pauses between them and each look
    /// searches several sites.
    static let productPause: Duration = .seconds(1)
    /// The server's spacing between two previews of one account.
    static let spacing: Duration = .seconds(5)
}

/// A preview that waits for typing to pause and asks the server at the pace it allows (`PreviewPacing`): `ask` with
/// what is typed now (nil: nothing to ask, which clears the line), and `phase` says how the answer for it stands.
@MainActor @Observable
final class PacedPreview<Query: Equatable, Answer: Equatable> {
    enum Phase: Equatable {
        /// Nothing to ask yet (no link, or one that does not look complete; no product).
        case idle
        /// Being read (or waiting for its turn).
        case reading
        /// What the server found.
        case found(Answer)
        /// The server's refusal, in its words.
        case refused(String)
        /// The preview failed (offline, the AI down): a calm line; the form still works.
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// What the phase is about.
    private(set) var query: Query?
    /// Retain capability metadata while a new selection is paced; displayed prices still use only the current answer.
    private(set) var lastFound: (query: Query, answer: Answer)?
    /// Kept only for the current refusal, so optional product choices follow the same lifetime as its words.
    private(set) var fieldRefusal: FieldRefusal?

    /// The pause after the last keystroke, before the query is handed to the worker.
    @ObservationIgnored private var waiting: Task<Void, Never>?
    /// The one worker asking, one query after the other.
    @ObservationIgnored private var worker: Task<Void, Never>?
    /// The newest query the worker should ask; nil when there is none (or it was taken).
    @ObservationIgnored private var wanted: (query: Query, revision: Int)?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var lastAsked: ContinuousClock.Instant?
    @ObservationIgnored private let now: () -> ContinuousClock.Instant
    @ObservationIgnored private let sleep: (Duration) async throws -> Void
    private let pause: Duration
    private let spacing: Duration
    private let fetch: (Query) async throws -> Answer

    init(pause: Duration = PreviewPacing.pause, spacing: Duration = PreviewPacing.spacing,
         now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now },
         sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         fetch: @escaping (Query) async throws -> Answer) {
        self.now = now
        self.sleep = sleep
        self.pause = pause
        self.spacing = spacing
        self.fetch = fetch
    }

    /// What is typed now: asked once typing pauses (unless it is what was asked already); nil clears the line.
    func ask(_ query: Query?) {
        guard let query else {
            revision += 1
            fieldRefusal = nil
            waiting?.cancel()
            waiting = nil
            wanted = nil
            self.query = nil
            phase = .idle
            return
        }
        guard query != self.query || phase == .idle else { return }
        revision += 1
        let revision = revision
        fieldRefusal = nil
        wanted = nil
        waiting?.cancel()
        self.query = query
        phase = .reading
        waiting = Task { [pause] in
            try? await sleep(pause)
            guard !Task.isCancelled else { return }
            self.wanted = (query, revision)
            self.startWorker()
        }
    }

    /// Waits until nothing waits or is read (tests).
    func settle() async {
        await waiting?.value
        while let worker { await worker.value }
    }

    /// Waits for the latest typing pause to hand its query to the worker (tests).
    func typingSettled() async { await waiting?.value }

    private func startWorker() {
        guard worker == nil else { return }
        worker = Task { await self.work() }
    }

    /// Asks for the newest wanted query, one at a time, never sooner than `spacing` after the last ask began.
    private func work() async {
        while wanted != nil {
            if let lastAsked {
                let ready = lastAsked.advanced(by: spacing)
                let remaining = now().duration(to: ready)
                if remaining > .zero { try? await sleep(remaining) }
            }
            // The newest query after the wait: one typed meanwhile replaces the one that waited.
            guard let target = wanted else { break }
            wanted = nil
            guard target.query == query, target.revision == revision else { continue }
            lastAsked = now()
            await read(target.query, revision: target.revision)
        }
        worker = nil
    }

    private func read(_ target: Query, revision: Int) async {
        let outcome: Phase
        var fieldRefusal: FieldRefusal?
        do {
            outcome = .found(try await fetch(target))
        } catch is CancellationError {
            // Dropped (a login that ended meanwhile).
            if self.revision == revision { phase = .idle }
            return
        } catch let refusal as FieldRefusal {
            outcome = .refused(refusal.message)
            fieldRefusal = refusal
        } catch HTTPError.server(429, _) {
            // Another device asked just now: this query waits its turn again, quietly.
            if self.revision == revision, wanted == nil { wanted = (target, revision) }
            return
        } catch {
            outcome = .failed(error.localizedDescription)
        }
        // An answer for words no longer in the field is dropped.
        guard self.revision == revision else { return }
        self.fieldRefusal = fieldRefusal
        if case .found(let answer) = outcome { lastFound = (target, answer) }
        phase = outcome
    }

    /// What was found for the words in the field.
    var answer: Answer? {
        if case .found(let answer) = phase { answer } else { nil }
    }

    /// The server's refusal, in its words.
    var refusal: String? {
        if case .refused(let message) = phase { message } else { nil }
    }
}

// MARK: - a shop's page (brief 137)

/// The link's preview: once the link looks complete, the server reads the page once.
typealias PricePreviewModel = PacedPreview<String, PricePreview>

extension PacedPreview where Query == String, Answer == PricePreview {
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

    /// The link field changed: a link that looks complete is read once typing pauses (unless it is the one already
    /// read); anything else clears the line.
    func update(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        ask(Self.looksComplete(trimmed) ? trimmed : nil)
    }

    /// The link the phase is about.
    var link: String? { query }

    /// What was found, for the name's placeholder and the alarm's limit.
    var preview: PricePreview? { answer }

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
}

// MARK: - a product everywhere (brief 157)

/// The words an everywhere monitor looks for: the product and its details, trimmed (what the preview is asked for, and
/// what its answer was found for).
struct ProductWords: Codable, Equatable, Hashable, Sendable {
    let product: String
    let details: String

    /// The server's limits: a product of 2 to 100 characters, details up to 300.
    static let productLengths = 2...100
    static let maxDetails = 300

    init(product: String, details: String = "") {
        self.product = product.trimmingCharacters(in: .whitespacesAndNewlines)
        self.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the server would look for these words (else the preview waits for more).
    var canBeAsked: Bool { Self.productLengths.contains(product.count) && details.count <= Self.maxDetails }
}

/// The product's preview: once the product has two letters and typing pauses, the server looks for it on the sites.
typealias ProductPreviewModel = PacedPreview<ProductPreviewQuery, ProductPreview>

extension PacedPreview where Query == ProductPreviewQuery, Answer == ProductPreview {
    func suggestions(for words: ProductWords) -> ProductSuggestions? {
        query?.words == words ? fieldRefusal?.productSuggestions : nil
    }

    /// A choice is a new request, even if these words have been asked before. The old identity cannot be saved.
    func select(_ suggestion: String, in draft: inout PriceSearchDraft) {
        draft.selectProduct(suggestion)
        ask(nil)
        update(draft.previewQuery)
    }

    /// The product or its details changed: words the server would look for are asked once typing pauses (unless they
    /// are the ones asked already); anything else clears the line.
    func update(product: String, details: String) {
        update(ProductPreviewQuery(product: product, details: details))
    }

    func update(_ selection: ProductPreviewQuery) {
        ask(selection.words.canBeAsked ? selection : nil)
    }

    /// The line under the product: "Looking for the product…", "Found: … · in 2 shops, from €215.00", or the failure;
    /// a refusal is a problem line (`refusal`).
    func line(language: AppLanguage = .current) -> String? {
        switch phase {
        case .idle, .refused: nil
        case .reading: language.string("Looking for the product…")
        case .found(let preview): EverywhereWords.found(preview, language: language).text
        case .failed(let message): message
        }
    }
}
