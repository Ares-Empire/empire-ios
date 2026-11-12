import Foundation

/// Editable item filters. Number text remains intact until conversion, so malformed input cannot silently clear a filter.
struct ItemSearchDraft: Codable, Equatable {
    /// The search words added as chips (brief 149), in order: the first is sent as `query`, the rest as `more_queries`.
    var words: [String] = []
    /// What is typed in the words' field and not added yet. It counts as the next word (`sentWords`), so one word typed
    /// without Return still saves.
    private(set) var typedWord = ""
    var exclude: [String] = []
    var priceMin = ""
    var priceMax = "" {
        didSet { if !vbOverMaxTouched { updateVBDefault() } }
    }
    private var vbText = "0"
    private(set) var vbOverMaxTouched = false
    var vbOverMax: String {
        get { vbText }
        set { vbText = newValue; vbOverMaxTouched = true }
    }
    var conditionMin: Condition?
    var forParts = false
    /// Auctions on the sites that have them (eBay); the form's switch shows only while such a site is chosen.
    var auctions = true
    var delivery: Delivery = .either
    var places: [Place] = []
    var radiusKm = "20"
    var seller: SearchSeller = .any
    /// Must have ("Muss sein", sent as `extra`): a listing that clearly breaks one is filtered out.
    var extra = ""
    /// Nice to have ("Wäre schön", sent as `nice`, brief 187): never filters a listing out.
    var nice = ""
    // Preserved on edit; this brief adds no editor controls for photo judgments.
    var look = ""
    var lookMin = 6
    var sources: Set<Source> = [.kleinanzeigen]
    /// The hunt's own name (brief 135); empty = named after its words.
    var name = ""

    init() {}
    init(_ search: ItemSearch, name: String? = nil) {
        self.name = name ?? ""
        words = search.words
        exclude = search.exclude
        priceMin = Self.text(search.priceMin)
        priceMax = Self.text(search.priceMax)
        vbText = Self.text(search.vbOverMax)
        // A saved value is intentional, even when it equals the suggested default.
        vbOverMaxTouched = true
        conditionMin = search.conditionMin
        forParts = search.forParts
        auctions = search.auctions
        delivery = search.delivery
        places = search.places
        radiusKm = Self.text(search.radiusKm)
        seller = search.seller
        extra = search.extra
        nice = search.nice
        look = search.look
        lookMin = search.lookMin
        sources = Set(search.sources)
    }

    enum Problem: Equatable {
        case words, exclude, priceMin, priceMax, priceOrder, vbOverMax, condition, radius, places, extra, nice, sources
    }
    /// The most either wish may hold (the server's limit for `extra` and `nice`).
    static let maxWishLength = 1000
    var problems: [Problem] {
        var result: [Problem] = []
        if wordsProblem != nil { result.append(.words) }
        if exclude.count > 20 || exclude.contains(where: { $0.count > 40 }) { result.append(.exclude) }
        if !priceMin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Self.number(priceMin) == nil { result.append(.priceMin) }
        if !priceMax.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Self.number(priceMax) == nil { result.append(.priceMax) }
        if let min = Self.number(priceMin), let max = Self.number(priceMax), min > max { result.append(.priceOrder) }
        if Self.number(vbText).map({ $0 >= 0 }) != true { result.append(.vbOverMax) }
        if conditionMin == .forParts { result.append(.condition) }
        if Self.number(radiusKm).map({ (0...200).contains($0) }) != true { result.append(.radius) }
        if places.count > 5 || (delivery != .shipping && places.isEmpty) { result.append(.places) }
        if extra.count > Self.maxWishLength { result.append(.extra) }
        if nice.count > Self.maxWishLength { result.append(.nice) }
        if sources.isEmpty { result.append(.sources) }
        return result
    }
    var isValid: Bool { problems.isEmpty }

    /// Invalid input has no contract value; the form can show `problems` without losing what was typed.
    func search() -> ItemSearch? {
        guard isValid, let vb = Self.number(vbText), let radius = Self.number(radiusKm), let query = sentWords.first
        else { return nil }
        return ItemSearch(query: query, moreQueries: Array(sentWords.dropFirst()), exclude: exclude,
                          priceMin: Self.number(priceMin), priceMax: Self.number(priceMax), vbOverMax: vb,
                          conditionMin: conditionMin, forParts: forParts, auctions: auctions, delivery: delivery,
                          places: places, radiusKm: radius, seller: seller,
                          extra: extra.trimmingCharacters(in: .whitespacesAndNewlines),
                          nice: nice.trimmingCharacters(in: .whitespacesAndNewlines),
                          look: look, lookMin: lookMin, sources: Source.ordered(sources))
    }

    /// Like the flat form: omitted/null fields stay; places and words merge (search words up to five, none repeated);
    /// empty wishes/sites do not erase edits. "Describe it" fills both wishes (server brief 185): the hard ones under
    /// Must have, the soft ones under Nice to have.
    mutating func apply(_ partial: PartialItemSearch) {
        for word in [partial.query].compactMap({ $0 }) + (partial.moreQueries ?? []) { add(word: word) }
        if let exclude = partial.exclude {
            for word in exclude where !self.exclude.contains(word) { self.exclude.append(word) }
        }
        if let value = partial.priceMin { priceMin = Self.text(value) }
        if let value = partial.priceMax { priceMax = Self.text(value) }
        if let value = partial.vbOverMax { vbOverMax = Self.text(value) }
        if let value = partial.conditionMin { conditionMin = value }
        if let value = partial.forParts { forParts = value }
        if let value = partial.auctions { auctions = value }
        if let value = partial.delivery { delivery = value }
        if let places = partial.places {
            for place in places where !self.places.contains(where: { $0.id == place.id }) { self.places.append(place) }
        }
        if let value = partial.radiusKm { radiusKm = Self.text(value) }
        if let value = partial.seller { seller = value }
        if let value = partial.extra, !value.isEmpty { extra = value }
        if let value = partial.nice, !value.isEmpty { nice = value }
        if let value = partial.look { look = value }
        if let value = partial.lookMin { lookMin = value }
        if let value = partial.sources, !value.isEmpty { sources = Set(value) }
    }

    private enum CodingKeys: String, CodingKey {
        case words, typedWord, exclude, priceMin, priceMax, vbText, vbOverMaxTouched, conditionMin, forParts, auctions
        case delivery, places, radiusKm, seller, extra, nice, look, lookMin, sources, name
    }
    /// A kept draft from before brief 149: the one search field's text.
    private enum EarlierKeys: String, CodingKey { case query }

    /// A draft kept by a build from before brief 119 has no `auctions`: on, as a new search; one from before brief 135
    /// no `name`: none; one from before brief 149 its one field's text as `query`: a word when it is one, else still
    /// typed; one from before brief 187 no `nice`: none (its text stays under Must have).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let words = try c.decodeIfPresent([String].self, forKey: .words) {
            self.words = words
            typedWord = try c.decodeIfPresent(String.self, forKey: .typedWord) ?? ""
        } else {
            let query = try decoder.container(keyedBy: EarlierKeys.self).decodeIfPresent(String.self, forKey: .query) ?? ""
            let word = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if SearchWords.lengths.contains(word.count) { words = [word] } else { typedWord = query }
        }
        exclude = try c.decode([String].self, forKey: .exclude)
        priceMin = try c.decode(String.self, forKey: .priceMin)
        priceMax = try c.decode(String.self, forKey: .priceMax)
        vbText = try c.decode(String.self, forKey: .vbText)
        vbOverMaxTouched = try c.decode(Bool.self, forKey: .vbOverMaxTouched)
        conditionMin = try c.decodeIfPresent(Condition.self, forKey: .conditionMin)
        forParts = try c.decode(Bool.self, forKey: .forParts)
        auctions = try c.decodeIfPresent(Bool.self, forKey: .auctions) ?? true
        delivery = try c.decode(Delivery.self, forKey: .delivery)
        places = try c.decode([Place].self, forKey: .places)
        radiusKm = try c.decode(String.self, forKey: .radiusKm)
        seller = try c.decode(SearchSeller.self, forKey: .seller)
        extra = try c.decode(String.self, forKey: .extra)
        nice = try c.decodeIfPresent(String.self, forKey: .nice) ?? ""
        look = try c.decodeIfPresent(String.self, forKey: .look) ?? ""
        lookMin = try c.decodeIfPresent(Int.self, forKey: .lookMin) ?? 6
        sources = try c.decode(Set<Source>.self, forKey: .sources)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    }

    private mutating func updateVBDefault() {
        vbText = Self.number(priceMax).map { Self.text(($0 * 0.1).rounded()) } ?? "0"
    }
    private static func number(_ text: String) -> Double? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }
    private static func text(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.fractionLength(0...10)))
    }
}

// MARK: - the form's helpers and lines

extension ItemSearchDraft {
    static let maxPlaces = 5

    /// Adds a place (up to five); false when it is there already or five are chosen.
    @discardableResult
    mutating func add(_ place: Place) -> Bool {
        guard places.count < Self.maxPlaces, !places.contains(where: { $0.id == place.id }) else { return false }
        places.append(place)
        return true
    }

    // MARK: the search words (brief 149)

    /// How the typed word stands: nothing typed, a word that can be added, one too short or too long, one that repeats a
    /// chip (the chip as written), or no room left (five chips).
    enum Typed: Equatable {
        case empty, adds, tooShort, tooLong, repeats(String), full
    }

    var typed: Typed {
        let word = typedWord.trimmingCharacters(in: .whitespacesAndNewlines)
        if word.isEmpty { return .empty }
        if words.count >= SearchWords.maxCount { return .full }
        if let chip = SearchWords.repeated(word, in: words) { return .repeats(chip) }
        if word.count < SearchWords.lengths.lowerBound { return .tooShort }
        if word.count > SearchWords.lengths.upperBound { return .tooLong }
        return .adds
    }

    /// The words the search is sent with: the chips, then the typed word unless it repeats one or there is no room
    /// (one too short or too long is sent too, so the form says what is wrong instead of losing it).
    var sentWords: [String] {
        let word = typedWord.trimmingCharacters(in: .whitespacesAndNewlines)
        switch typed {
        case .adds, .tooShort, .tooLong: return words + [word]
        case .empty, .repeats, .full: return words
        }
    }

    /// Whether the field for another word shows: not once there are five.
    var takesWords: Bool { words.count < SearchWords.maxCount }

    /// Adds the typed word as a chip (Return, the field's +, leaving the field); false keeps it in the field (empty, too
    /// short or too long, a repeat, five already).
    @discardableResult
    mutating func addTypedWord() -> Bool {
        guard typed == .adds else { return false }
        words.append(typedWord.trimmingCharacters(in: .whitespacesAndNewlines))
        typedWord = ""
        return true
    }

    /// Adds a word as a chip (an example, "Describe it", a kept draft); false for an empty, repeated or wrong-length one,
    /// or when five are there.
    @discardableResult
    mutating func add(word text: String) -> Bool {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard words.count < SearchWords.maxCount, SearchWords.lengths.contains(word.count),
              SearchWords.repeated(word, in: words) == nil else { return false }
        words.append(word)
        if words.count == SearchWords.maxCount { typedWord = "" }
        return true
    }

    /// The field's text as typed or pasted: a comma ends a word, which becomes a chip ("Hermès tie, Kiton tie" two
    /// chips, or one and the second still typed). The first ended word that cannot be added (a repeat, too short or
    /// too long, no room) stays in the field without its comma, so the form can say why; then what follows the last
    /// comma is added if it can be. At most 100 characters stay in the field.
    mutating func type(_ text: String) {
        var parts = text.components(separatedBy: ",")
        // After a comma the next word starts at its first letter.
        var field = parts.count > 1 ? String(parts.removeLast().drop(while: \.isWhitespace)) : parts.removeLast()
        var refused: String?
        for part in parts {
            let word = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if word.isEmpty || add(word: word) { continue }
            if refused == nil { refused = word }
        }
        if let refused {
            add(word: field)
            field = refused
        }
        typedWord = takesWords ? String(field.prefix(SearchWords.lengths.upperBound)) : ""
    }

    /// Removes the chip at `index`.
    mutating func removeWord(at index: Int) {
        guard words.indices.contains(index) else { return }
        words.remove(at: index)
    }

    /// A spelling suggestion taken (brief 178): the entry written exactly `word` (a chip, or the word still typed, as
    /// `sentWords` sends it) becomes `replacement` in its place; nothing else changes. When the replacement repeats
    /// another entry, this entry goes instead, since the other one is there already. False when no entry is written so,
    /// or the replacement is not a word the search can take.
    @discardableResult
    mutating func replace(word: String, with replacement: String) -> Bool {
        let new = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SearchWords.lengths.contains(new.count) else { return false }
        let sent = sentWords
        guard let index = sent.firstIndex(of: word) else { return false }
        var others = sent
        others.remove(at: index)
        let repeats = SearchWords.repeated(new, in: others) != nil
        if index < words.count {
            if repeats { words.remove(at: index) } else { words[index] = new }
        } else {
            typedWord = repeats ? "" : new
        }
        return true
    }

    /// What is wrong with the words, if anything: none yet, one too short or too long, more than five (a search saved
    /// by a newer server).
    private var wordsProblem: LocalizedStringResource? {
        let sent = sentWords
        if sent.isEmpty { return "Type what you look for." }
        if sent.count > SearchWords.maxCount { return "At most 5 search words." }
        if sent.contains(where: { $0.count > SearchWords.lengths.upperBound }) { return "At most 100 characters." }
        if sent.contains(where: { $0.count < SearchWords.lengths.lowerBound }) { return "At least 2 characters." }
        return nil
    }

    /// The quiet line under the words: why the typed word is not added (it repeats a chip), or, at five, why the field
    /// went (more than five is a problem, `fieldLine`, and says so there).
    func wordsNote(language: AppLanguage = .current) -> String? {
        if case .repeats(let chip) = typed { return language.string("“\(chip)” is there already.") }
        if words.count == SearchWords.maxCount { return language.string("At most 5 search words.") }
        return nil
    }

    /// Adds a word to leave out; false for an empty or repeated one (any case).
    @discardableResult
    mutating func addExclude(_ text: String) -> Bool {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, !exclude.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) else { return false }
        exclude.append(word)
        return true
    }

    /// The name sent: trimmed and at most 60 characters; nil when empty, so the hunt is named after its words.
    var sentName: String? { HuntName.cleaned(name) }

    /// Whether Save has something to save: for a new search (`saved` nil) anything filled in; for a saved one a search
    /// or name, as they would be sent, that differs from the saved hunt's. Each wish counts like every other field.
    func isChanged(from saved: Hunt?) -> Bool {
        guard let saved else { return self != ItemSearchDraft() }
        return search() != saved.search.item || sentName != HuntName.cleaned(saved.name ?? "")
    }

    /// The Name field's grey placeholder: what the hunt is called while the field stays empty, its words as typed, the
    /// first and "+ 2" for two more (a thing is named after its words, `HuntSummary`; read here from the field, since a
    /// draft still missing something has no search yet), else "Optional".
    func namePlaceholder(language: AppLanguage = .current) -> String {
        HuntName.placeholder(SearchWords.title(sentWords), language: language)
    }

    /// Places and the radius apply unless the thing is only to be shipped.
    var asksPlaces: Bool { delivery != .shipping }

    /// Switches off the chosen sites that cannot serve the delivery (`SiteDelivery.serves`; `sites` is the form's list,
    /// `SiteChoices.sites`), since the server would refuse the search with them. The form calls it whenever the delivery
    /// or the server's sites change, also for a saved search it opens; switching the delivery back turns none on again.
    /// A site the list does not name serves every delivery. True when it switched one off.
    @discardableResult
    mutating func switchOffSitesThatCannotServe(_ sites: [KindSource]) -> Bool {
        let kept = sources.filter { source in sites.first { $0.source == source }?.delivery.serves(delivery) ?? true }
        guard kept.count != sources.count else { return false }
        sources = kept
        return true
    }

    /// What is wrong, in a sentence.
    func message(_ problem: Problem, language: AppLanguage = .current) -> String {
        let l = language
        switch problem {
        case .words: return l.string(wordsProblem ?? "Type what you look for.")
        case .exclude: return l.string("Up to 20 words, each at most 40 characters.")
        case .priceMin, .priceMax, .vbOverMax: return l.string("Type an amount in euros.")
        case .priceOrder: return l.string("The lowest price is above the highest.")
        case .condition: return l.string("Choose a condition.")
        case .radius: return l.string("The radius goes up to 200 km.")
        case .places:
            return places.count > Self.maxPlaces ? l.string("At most 5 places.") : l.string("Choose a place, or Shipping.")
        case .extra, .nice: return l.string("At most 1,000 characters.")
        case .sources: return l.string("Choose at least one portal.")
        }
    }

    /// The line under a field: what is wrong with what is there. A field that is simply still empty (the search words,
    /// the place) says so only under Save (`hint`), so a new form opens without warnings.
    func fieldLine(_ problem: Problem, language: AppLanguage = .current) -> String? {
        guard problems.contains(problem) else { return nil }
        switch problem {
        case .words where sentWords.isEmpty: return nil
        case .places where places.isEmpty: return nil
        default: return message(problem, language: language)
        }
    }

    /// One calm line under Save: the first thing still missing or wrong.
    func hint(language: AppLanguage = .current) -> String? {
        problems.first.map { message($0, language: language) }
    }
}

/// The thing form's two wishes (brief 187; Patrik, asked whether a wish like "Rot" must be or would be nice: the app
/// should ask the person). Must have is sent as `extra`: a listing that clearly breaks one is filtered out; Nice to have
/// as `nice`: it never filters one out (the server decides what each does, server brief 185). Their words are here, so
/// the form only lays them out, Must have first.
enum Wish: CaseIterable {
    case must, nice

    /// The draft's text for it.
    var text: WritableKeyPath<ItemSearchDraft, String> {
        switch self {
        case .must: \.extra
        case .nice: \.nice
        }
    }

    /// What is wrong with it (more than 1,000 characters).
    var problem: ItemSearchDraft.Problem {
        switch self {
        case .must: .extra
        case .nice: .nice
        }
    }

    /// The section's heading over both: "Wishes" / "Wünsche".
    static func heading(language: AppLanguage = .current) -> String { language.string("Wishes") }

    /// "Must have" / "Muss sein", "Nice to have" / "Wäre schön".
    func title(language: AppLanguage = .current) -> String {
        switch self {
        case .must: language.string("Must have")
        case .nice: language.string("Nice to have")
        }
    }

    /// The grey example, both from one search (a silk shirt): what must be, and what would be nice.
    func placeholder(language: AppLanguage = .current) -> String {
        switch self {
        case .must: language.string("Size 43, 100% silk")
        case .nice: language.string("Red or burgundy")
        }
    }

    /// The line under it: what it does.
    func caption(language: AppLanguage = .current) -> String {
        switch self {
        case .must: language.string("Listings that clearly don't match are filtered out.")
        case .nice: language.string("Never filters a listing out.")
        }
    }
}
