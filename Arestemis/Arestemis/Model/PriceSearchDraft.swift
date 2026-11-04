import Foundation

/// The Preismonitor's form as typed (brief 137, the sketch's mockup; brief 157 "Ein Shop | Überall"): its mode, its
/// name, the product's link (Ein Shop) or the product in words with optional details, the product the preview found for
/// them and the sites switched off (Überall), what it should do (the history, the alarm with its two conditions; at least
/// one of the two on) and how often. Each mode keeps its own fields while the other is shown, so switching back finds
/// them as they were; the name, the switches and how often are the monitor's in both. Only what the contract asks is
/// checked here; whether a link or a product can be read is the server's to say (its preview, its refusal on save).
struct PriceSearchDraft {
    /// Ein Shop or Überall; a new form opens on Überall (Patrik's case: a product in words, no link to find first).
    var mode: PriceSearch.Mode = .everywhere
    /// The monitor's own name; empty = the product's name once read, else the host (Ein Shop) or the words (Überall).
    var name = ""
    /// Ein Shop: the product page's link.
    var url = ""
    /// Überall: the product in words and the optional details (colour, size, variant).
    var product = "" { didSet { if Self.trimmed(product) != Self.trimmed(oldValue) { clearConfirmation() } } }
    var details = "" { didSet { if Self.trimmed(details) != Self.trimmed(oldValue) { clearConfirmation() } } }
    /// Überall: the product the preview found, and the words it was found for: saving needs it found for the words as
    /// they are now, and sends it as the confirmed identity.
    var identity: ProductIdentity?
    var identityWords: ProductWords?
    /// Überall: the sites switched off on "Where it looks".
    var sourcesOff: [String] = []
    var includeUsed = false
    var delivery: Delivery = .shipping
    var places: [Place] = []
    var radiusKm: Double = 20
    /// Records the price and the availability as a curve. A new form starts with it on.
    var history = true
    var alarm = false
    /// The price condition's limit in euros; nil: no price condition.
    var below: Double?
    var backInStock = false
    /// How often, as chosen; Überall reads at most hourly (`effectiveEvery`), so a page's 15 minutes come back when
    /// switching back.
    var every = WatchSearch.defaultEvery

    init() {}

    init(_ search: PriceSearch, name: String?) {
        self.name = name ?? ""
        mode = search.mode
        url = search.url ?? ""
        product = search.product ?? ""
        details = search.details
        identity = search.identity
        identityWords = search.identity == nil ? nil : ProductWords(product: product, details: details)
        sourcesOff = search.sourcesOff
        includeUsed = search.includeUsed
        delivery = search.delivery
        places = search.places
        radiusKm = search.radiusKm
        history = search.history
        alarm = search.alarm != nil
        below = search.alarm?.below
        backInStock = search.alarm?.backInStock ?? false
        every = search.every
    }

    enum Problem: Equatable {
        /// No link, or one over 2,000 characters (Ein Shop).
        case url
        /// No product, or one under 2 or over 100 characters (Überall).
        case product
        /// Details over 300 characters (Überall).
        case details
        /// The product is not found yet for the words as they are now (Überall).
        case unconfirmed
        case places, radius
        /// Neither the history nor the alarm.
        case neither
        /// The alarm without a condition.
        case alarmCondition
    }

    var problems: [Problem] {
        var result: [Problem] = []
        switch mode {
        case .page:
            let url = Self.trimmed(url)
            if url.isEmpty || url.count > WatchSearchDraft.maxURL { result.append(.url) }
        case .everywhere:
            if !ProductWords.productLengths.contains(words.product.count) { result.append(.product) }
            if words.details.count > ProductWords.maxDetails { result.append(.details) }
            if result.isEmpty && !isConfirmed { result.append(.unconfirmed) }
            if !validPlaces { result.append(.places) }
            if !radiusKm.isFinite || !(0...200).contains(radiusKm) { result.append(.radius) }
        }
        if !history && !alarm { result.append(.neither) }
        if alarm && !conditions.isComplete { result.append(.alarmCondition) }
        return result
    }
    var isValid: Bool { problems.isEmpty }

    /// Überall: the words as typed, trimmed.
    var words: ProductWords { ProductWords(product: product, details: details) }

    /// Überall: the product was found for the words as they are now.
    var isConfirmed: Bool { identity != nil && identityWords == words }

    mutating func clearConfirmation() {
        identity = nil
        identityWords = nil
    }

    mutating func selectProduct(_ suggestion: String) {
        product = suggestion
        clearConfirmation()
    }

    /// The preview found a product for these words: it becomes the one saving confirms (an answer for other words, an
    /// older one, changes nothing).
    mutating func confirm(_ found: ProductIdentity, for words: ProductWords) {
        guard words == self.words else { return }
        identity = found
        identityWords = words
    }

    /// How often the monitor reads: as chosen, at least hourly for Überall.
    var effectiveEvery: Int { mode == .everywhere ? max(every, PriceSearch.everywhereEvery) : every }

    /// The alarm's conditions as typed.
    private var conditions: PriceSearch.Alarm {
        PriceSearch.Alarm(below: below.flatMap { $0 > 0 ? $0 : nil }, backInStock: backInStock)
    }

    /// What is sent, trimmed; nil while something is missing. The alarm's conditions are sent only while it is on (they
    /// stay in the form meanwhile, so turning it on again brings them back).
    func search() -> PriceSearch? {
        guard isValid else { return nil }
        let alarm = alarm ? conditions : nil
        switch mode {
        case .page:
            return PriceSearch(url: Self.trimmed(url), history: history, alarm: alarm, every: every)
        case .everywhere:
            return PriceSearch(product: words.product, details: words.details, identity: identity,
                               sourcesOff: sourcesOff, history: history, alarm: alarm, every: effectiveEvery,
                               delivery: delivery, places: places, radiusKm: radiusKm, includeUsed: includeUsed)
        }
    }

    /// The name sent: trimmed and at most 60 characters; nil when empty, so the server names it.
    var sentName: String? { HuntName.cleaned(name) }

    /// The link field after a change: a whole shared text pasted into it keeps only its first link, as the watch form.
    mutating func takeAddress(_ text: String) {
        let kept = WatchAddress.fromField(text)
        if kept != url { url = kept }
    }

    /// The alarm switched on: when it has no condition yet, both come on, the price a little under the price found
    /// (`PriceLimit`), as the sketch's form shows them. Returns whether the price still waits for a price to be found.
    @discardableResult
    mutating func turnAlarmOn(price: Double?, currency: String? = "EUR") -> Bool {
        alarm = true
        guard below == nil && !backInStock else { return false }
        backInStock = true
        below = PriceLimit.suggested(under: price, currency: currency)
        return below == nil
    }

    /// The price found later fills the limit when the alarm is on and it is still empty (the form's example, or an alarm
    /// switched on before the preview came). Returns whether it filled it.
    @discardableResult
    mutating func prefillLimit(price: Double?, currency: String? = "EUR") -> Bool {
        guard alarm, below == nil, let limit = PriceLimit.suggested(under: price, currency: currency) else { return false }
        below = limit
        return true
    }

    /// What the name field shows while it is empty: Ein Shop: the product's name the server found, else the host of the
    /// link; Überall: the product found, else the words; else "Optional".
    func namePlaceholder(product found: String?, language: AppLanguage = .current) -> String {
        switch mode {
        case .page: HuntName.placeholder(HuntText.text(found) ?? WatchAddress.host(url), language: language)
        case .everywhere: HuntName.placeholder(HuntText.text(found) ?? HuntText.text(words.product), language: language)
        }
    }

    /// What is wrong, in a sentence: the switches' rule in the sketch's words, an alarm without a condition in the
    /// server's.
    func message(_ problem: Problem, language: AppLanguage = .current) -> String {
        switch problem {
        case .url:
            Self.trimmed(url).count > WatchSearchDraft.maxURL ? language.string("At most 2,000 characters.")
                : language.string("Paste the product's link.")
        case .product:
            words.product.isEmpty ? language.string("Type the product.")
                : words.product.count < ProductWords.productLengths.lowerBound ? language.string("At least 2 characters.")
                : language.string("At most 100 characters.")
        case .details: language.string("At most 300 characters.")
        case .unconfirmed: language.string("First the product has to be found.")
        case .places: places.count > ItemSearchDraft.maxPlaces ? language.string("At most 5 places.")
            : language.string("Choose a place, or Shipping.")
        case .radius: language.string("The radius goes up to 200 km.")
        case .neither: language.string("At least one of the two.")
        case .alarmCondition: language.string("Say when the alarm should ring.")
        }
    }

    /// The one quiet line under the switches: the switches' rule, or an alarm without a condition.
    func switchesLine(language: AppLanguage = .current) -> String? {
        problems.first { $0 == .neither || $0 == .alarmCondition }.map { message($0, language: language) }
    }

    /// The line under the link: only a link that is too long (an empty one says so under Save).
    func urlLine(language: AppLanguage = .current) -> String? {
        mode == .page && Self.trimmed(url).count > WatchSearchDraft.maxURL ? message(.url, language: language) : nil
    }

    /// The line under the product: one too short or too long (an empty one says so under Save).
    func productLine(language: AppLanguage = .current) -> String? {
        guard mode == .everywhere, !words.product.isEmpty, problems.contains(.product) else { return nil }
        return message(.product, language: language)
    }

    /// The line under the details: too long.
    func detailsLine(language: AppLanguage = .current) -> String? {
        mode == .everywhere && problems.contains(.details) ? message(.details, language: language) : nil
    }

    /// One calm line under Save: a missing link or product, or a product not found yet (the switches say their own line
    /// where they are).
    func hint(language: AppLanguage = .current) -> String? {
        switch mode {
        case .page:
            return Self.trimmed(url).isEmpty ? message(.url, language: language) : nil
        case .everywhere:
            if words.product.isEmpty { return message(.product, language: language) }
            if problems.contains(.unconfirmed) { return message(.unconfirmed, language: language) }
            return problems.contains(.places) ? message(.places, language: language) : nil
        }
    }

    private static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension PriceSearchDraft: Codable {
    enum CodingKeys: String, CodingKey {
        case mode, name, url, product, details, identity, identityWords, sourcesOff, history, alarm, below, backInStock
        case every, delivery, places, radiusKm, includeUsed
    }

    /// A kept draft from a build before brief 157 has no mode: it was a page monitor's.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(PriceSearch.Mode.self, forKey: .mode) ?? .page
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        product = try c.decodeIfPresent(String.self, forKey: .product) ?? ""
        details = try c.decodeIfPresent(String.self, forKey: .details) ?? ""
        identity = try c.decodeIfPresent(ProductIdentity.self, forKey: .identity)
        identityWords = try c.decodeIfPresent(ProductWords.self, forKey: .identityWords)
        sourcesOff = try c.decodeIfPresent([String].self, forKey: .sourcesOff) ?? []
        includeUsed = try c.decodeIfPresent(Bool.self, forKey: .includeUsed) ?? false
        delivery = (try c.decodeIfPresent(String.self, forKey: .delivery)).flatMap(Delivery.init(rawValue:)) ?? .shipping
        places = try c.decodeIfPresent([Place].self, forKey: .places) ?? []
        radiusKm = try c.decodeIfPresent(Double.self, forKey: .radiusKm) ?? 20
        history = try c.decodeIfPresent(Bool.self, forKey: .history) ?? true
        alarm = try c.decodeIfPresent(Bool.self, forKey: .alarm) ?? false
        below = try c.decodeIfPresent(Double.self, forKey: .below)
        backInStock = try c.decodeIfPresent(Bool.self, forKey: .backInStock) ?? false
        every = try c.decodeIfPresent(Int.self, forKey: .every) ?? WatchSearch.defaultEvery
    }
}

extension PriceSearchDraft: Equatable {
    /// Two drafts are the same monitor when they would send the same: the alarm's conditions count only while it is on,
    /// and only the shown mode's own fields (the other mode's are kept, not sent).
    static func == (a: PriceSearchDraft, b: PriceSearchDraft) -> Bool {
        guard a.mode == b.mode, a.name == b.name, a.history == b.history, a.alarm == b.alarm,
              a.effectiveEvery == b.effectiveEvery,
              !a.alarm || (a.below == b.below && a.backInStock == b.backInStock) else { return false }
        switch a.mode {
        case .page: return a.url == b.url
        case .everywhere:
            return a.product == b.product && a.details == b.details && a.identity == b.identity
                && Set(a.sourcesOff) == Set(b.sourcesOff) && a.includeUsed == b.includeUsed
                && a.delivery == b.delivery && a.places == b.places && a.radiusKm == b.radiusKm
        }
    }
}

/// The two switches on a monitor's page (brief 137, Patrik: "changeable anytime in the app"): each change makes the whole
/// search that is saved at once (`PUT`), or is refused with the switches' line. Turning off the last of the two is
/// refused ("At least one of the two."); an alarm whose conditions are both off cannot be saved ("Say when the alarm
/// should ring.") and is kept on the page until it has one.
struct MonitorSwitches: Equatable {
    /// What the page shows: the saved search, with the alarm's conditions as last typed.
    var history: Bool
    var alarm: Bool
    var below: Double?
    var backInStock: Bool

    init(_ search: PriceSearch) {
        history = search.history
        alarm = search.alarm != nil
        below = search.alarm?.below
        backInStock = search.alarm?.backInStock ?? false
    }

    enum Outcome: Equatable {
        /// Save this search.
        case save(PriceSearch)
        /// Shown, not saved, with the line: an alarm without a condition yet.
        case hold(PriceSearch.Alarm)
        /// Not changed, with the line: the last switch turned off.
        case refused
    }

    /// The history switched.
    mutating func setHistory(_ on: Bool, in search: PriceSearch) -> Outcome {
        guard on || alarm else { return .refused }
        history = on
        return outcome(search)
    }

    /// The alarm switched; switched on without a condition, both come on with the limit a little under `price`.
    mutating func setAlarm(_ on: Bool, in search: PriceSearch, price: Double?, currency: String?) -> Outcome {
        guard on || history else { return .refused }
        alarm = on
        if on, below == nil, !backInStock {
            backInStock = true
            below = PriceLimit.suggested(under: price, currency: currency)
        }
        return outcome(search)
    }

    /// The limit typed (nil: no price condition).
    mutating func setBelow(_ value: Double?, in search: PriceSearch) -> Outcome {
        below = value.flatMap { $0 > 0 ? $0 : nil }
        return outcome(search)
    }

    mutating func setBackInStock(_ on: Bool, in search: PriceSearch) -> Outcome {
        backInStock = on
        return outcome(search)
    }

    private func outcome(_ search: PriceSearch) -> Outcome {
        var changed = search
        changed.history = history
        let conditions = PriceSearch.Alarm(below: below, backInStock: backInStock)
        changed.alarm = alarm ? conditions : nil
        if alarm && !conditions.isComplete { return .hold(conditions) }
        return .save(changed)
    }

    /// The line under the switches after an outcome: the rule's words, nil when saved.
    static func line(_ outcome: Outcome, language: AppLanguage = .current) -> String? {
        switch outcome {
        case .save: nil
        case .hold: language.string("Say when the alarm should ring.")
        case .refused: language.string("At least one of the two.")
        }
    }
}
