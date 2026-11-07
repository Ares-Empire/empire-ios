import Foundation

/// What a thing search's page and its listings show of the asking prices (brief 256). The server's own sentences come
/// in both languages (`LocalizedText`); these pick the app's language and add only the app's few words around them
/// (the card's title and period, a site's count, "No prices yet"). Kept apart from the price monitor's words
/// (`PriceWords`): a monitor follows one product's price, this is what fitting listings of a search usually ask.

/// When a thing search's asking prices are asked for again: with its page, after a newer scan, and when its search
/// changed (which restarts the server's record). Nil for every other kind of search: only Dinge searches have them.
struct PriceRecordRead: Equatable {
    let hunt: Int
    let search: ItemSearch
    let lastScan: String?

    init?(_ card: HuntCard) {
        guard let search = card.hunt.search.item else { return nil }
        hunt = card.id
        self.search = search
        lastScan = card.hunt.lastScan
    }
}

/// The "Asking prices" card on a thing search's page.
struct PriceRecordCard: Equatable {
    /// One site's own numbers in the breakdown: its usual range once it has enough offers, else how many it had.
    struct Site: Equatable, Identifiable {
        let id: Source
        let name: String
        /// "€24–31", "24,00–30,50 €"; nil below 8 offers (the server sends no range then).
        let range: String?
        /// "8 listings" / "8 Angebote".
        let count: String
    }

    /// "Asking prices" / "Angebotspreise".
    let title: String
    /// "Last 30 days" / "Letzte 30 Tage", beside the title.
    let period: String
    /// The server's overall line, one fact per line: the count, the usual range, the cheapest of the last 7 days and
    /// the weekly trend, as the server has them. Empty while no fitting listing had a price (`empty` instead).
    let lines: [String]
    /// "No prices yet. …", in place of the numbers while the record is empty (a new search, or one just changed).
    let empty: String?
    /// One row per site while two or more sites have offers; none otherwise (the overall line says it all).
    let sites: [Site]
    /// The server's note: asking prices of fitting listings within the search's limits, no fees, not sale prices.
    let note: String?

    init(_ summary: ItemPriceSummary, names: SiteNames, language: AppLanguage = .current) {
        title = language.string("Asking prices")
        period = language.string("Last \(summary.days) days")
        let filled = summary.overall.count > 0
        let shown = Self.lines(summary.overall.display.text(language))
        lines = !filled ? [] : shown.isEmpty ? [language.string("\(summary.overall.count) listings")] : shown
        empty = filled ? nil : language.string("No prices yet. They come with the first fitting listings.")
        let withOffers = summary.sites.filter { $0.count > 0 && $0.source != nil }
        sites = filled && withOffers.count >= 2 ? withOffers.compactMap { stats in
            stats.source.map { source in
                Site(id: source, name: names.name(source),
                     range: stats.usual.map { Self.range($0.lowerBound, $0.upperBound, language: language) },
                     count: language.string("\(stats.count) listings"))
            }
        } : []
        let note = summary.note.text(language).trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = filled && !note.isEmpty ? note : nil
    }

    /// The server joins its facts with " · " ("16 fitting listings · Usually €23.50–€30.00 asked · …"); the card shows
    /// one per line. A line without that mark stays one line.
    static func lines(_ display: String) -> [String] {
        display.components(separatedBy: " · ")
            .map { PriceText.keepingNumbersTogether($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
    }

    /// A site's usual range: whole euros when both ends are whole ("€395–460" / "395–460 €"), else to the cent
    /// ("€21.50–28.50" / "21,50–28,50 €").
    static func range(_ low: Double, _ high: Double, language: AppLanguage = .current) -> String {
        let whole = low.rounded() == low && high.rounded() == high
        guard !whole else { return Format.moneyRange(low, high, language: language) }
        func amount(_ euros: Double) -> String {
            euros.formatted(.number.precision(.fractionLength(2)).locale(language.locale))
        }
        let range = amount(low) + "–" + amount(high)
        return language == .german ? range + "\u{a0}€" : "€" + range
    }

    /// What VoiceOver reads for the card: the facts as sentences, then each site.
    var spoken: String {
        let facts = empty.map { [$0] } ?? lines
        let siteLines = sites.map { site in [site.name, site.range, site.count].compactMap { $0 }.joined(separator: ", ") }
        return ([title + ", " + period] + facts + siteLines).joined(separator: ". ")
    }
}

/// A listing's verdict as the app shows it: on its row a small label, on its page the server's line with its note.
struct PriceVerdictWords: Equatable {
    /// How the label looks: cheap in the accent, expensive neutral, unusually cheap cautious (amber, never alarm red: it
    /// means "check").
    enum Tone: Equatable { case accent, neutral, caution }

    let kind: ItemPriceVerdict.Kind
    /// "Cheap" / "Günstig", "Expensive" / "Teuer", "Unusually cheap – check carefully" / "Ungewöhnlich günstig – genau
    /// prüfen": the server's label.
    let label: String
    /// "Cheap: usually €23.50–€30.00 asked within your search limits": the server's line.
    let line: String
    /// Asking prices of fitting listings within the search's limits, not sale prices: the server's note.
    let note: String
    /// The line in two parts where it starts with the label, as the server writes it: the label (shown in the verdict's
    /// tone) and the rest (": usually …", quiet). Nil when the line does not start with it: then the line is shown whole.
    let lead: String?
    let rest: String

    var tone: Tone {
        switch kind {
        case .cheap: .accent
        case .expensive: .neutral
        case .unusuallyCheap: .caution
        }
    }

    /// A small mark beside the words, so the three differ by more than colour.
    var symbol: String {
        switch kind {
        case .cheap: "arrow.down"
        case .expensive: "arrow.up"
        case .unusuallyCheap: "exclamationmark.circle"
        }
    }

    init(_ verdict: ItemPriceVerdict, language: AppLanguage = .current) {
        kind = verdict.verdict
        label = verdict.label.text(language).trimmingCharacters(in: .whitespacesAndNewlines)
        let display = verdict.display.text(language).trimmingCharacters(in: .whitespacesAndNewlines)
        line = PriceText.keepingNumbersTogether(display.isEmpty ? label : display)
        note = verdict.note.text(language).trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty, line.hasPrefix(label) {
            lead = label
            rest = String(line.dropFirst(label.count))
        } else {
            lead = nil
            rest = line
        }
    }

    /// The words a listing shows, or nil: only a thing for sale with a verdict whose label is not empty has them. Most
    /// listings have none, and then nothing shows (no placeholder).
    static func shown(for match: Match, kind: SearchKind, language: AppLanguage = .current) -> PriceVerdictWords? {
        guard kind == .item, let verdict = match.priceVerdict else { return nil }
        let words = PriceVerdictWords(verdict, language: language)
        return words.label.isEmpty ? nil : words
    }
}

enum PriceText {
    /// A space after a digit becomes a non-breaking one, so a wrapped line never parts a number from its word or its
    /// currency ("letzten 7 / Tage", "450,00 / €"); the server's texts use plain spaces.
    static func keepingNumbersTogether(_ text: String) -> String {
        var result = ""
        var previous: Character?
        var characters = text.makeIterator()
        var next = characters.next()
        while let character = next {
            next = characters.next()
            if character == " ", previous?.isNumber == true, let following = next, !following.isWhitespace {
                result.append("\u{a0}")
            } else {
                result.append(character)
            }
            previous = character
        }
        return result
    }
}
