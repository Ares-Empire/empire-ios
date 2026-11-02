import Foundation

/// The Preismonitor's form as typed (brief 137, the sketch's mockup): its name, the product's link, what it should do
/// (the history, the alarm with its two conditions; at least one of the two on) and how often. Only what the contract
/// asks is checked here; whether a link can be read is the server's to say (its preview, its refusal on save).
struct PriceSearchDraft: Codable {
    /// The monitor's own name; empty = the product's name once read, else the host.
    var name = ""
    var url = ""
    /// Records the price and the availability as a curve. A new form starts with it on.
    var history = true
    var alarm = false
    /// The price condition's limit in euros; nil: no price condition.
    var below: Double?
    var backInStock = false
    var every = WatchSearch.defaultEvery

    init() {}

    init(_ search: PriceSearch, name: String?) {
        self.name = name ?? ""
        url = search.url
        history = search.history
        alarm = search.alarm != nil
        below = search.alarm?.below
        backInStock = search.alarm?.backInStock ?? false
        every = search.every
    }

    enum Problem: Equatable {
        /// No link, or one over 2,000 characters.
        case url
        /// Neither the history nor the alarm.
        case neither
        /// The alarm without a condition.
        case alarmCondition
    }

    var problems: [Problem] {
        var result: [Problem] = []
        let url = Self.trimmed(url)
        if url.isEmpty || url.count > WatchSearchDraft.maxURL { result.append(.url) }
        if !history && !alarm { result.append(.neither) }
        if alarm && !conditions.isComplete { result.append(.alarmCondition) }
        return result
    }
    var isValid: Bool { problems.isEmpty }

    /// The alarm's conditions as typed.
    private var conditions: PriceSearch.Alarm {
        PriceSearch.Alarm(below: below.flatMap { $0 > 0 ? $0 : nil }, backInStock: backInStock)
    }

    /// What is sent, trimmed; nil while something is missing. The alarm's conditions are sent only while it is on (they
    /// stay in the form meanwhile, so turning it on again brings them back).
    func search() -> PriceSearch? {
        guard isValid else { return nil }
        return PriceSearch(url: Self.trimmed(url), history: history, alarm: alarm ? conditions : nil, every: every)
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

    /// The price found later fills the limit when the alarm is on and it is still empty (the form's example "Price
    /// under …", or an alarm switched on before the preview came). Returns whether it filled it.
    @discardableResult
    mutating func prefillLimit(price: Double?, currency: String? = "EUR") -> Bool {
        guard alarm, below == nil, let limit = PriceLimit.suggested(under: price, currency: currency) else { return false }
        below = limit
        return true
    }

    /// What the name field shows while it is empty: the product's name the server found, else the host of the link,
    /// else "Optional".
    func namePlaceholder(product: String?, language: AppLanguage = .current) -> String {
        HuntName.placeholder(HuntText.text(product) ?? WatchAddress.host(url), language: language)
    }

    /// What is wrong, in a sentence: the switches' rule in the sketch's words, an alarm without a condition in the
    /// server's.
    func message(_ problem: Problem, language: AppLanguage = .current) -> String {
        switch problem {
        case .url:
            Self.trimmed(url).count > WatchSearchDraft.maxURL ? language.string("At most 2,000 characters.")
                : language.string("Paste the product's link.")
        case .neither: language.string("At least one of the two.")
        case .alarmCondition: language.string("Say when the alarm should ring.")
        }
    }

    /// The one quiet line under the switches: the switches' rule, or an alarm without a condition.
    func switchesLine(language: AppLanguage = .current) -> String? {
        problems.first { $0 != .url }.map { message($0, language: language) }
    }

    /// The line under the link: only a link that is too long (an empty one says so under Save).
    func urlLine(language: AppLanguage = .current) -> String? {
        Self.trimmed(url).count > WatchSearchDraft.maxURL ? message(.url, language: language) : nil
    }

    /// One calm line under Save: a missing link (the switches say their own line where they are).
    func hint(language: AppLanguage = .current) -> String? {
        Self.trimmed(url).isEmpty ? message(.url, language: language) : nil
    }

    private static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension PriceSearchDraft: Equatable {
    /// Two drafts are the same monitor when they would send the same: the alarm's conditions count only while it is on.
    static func == (a: PriceSearchDraft, b: PriceSearchDraft) -> Bool {
        a.name == b.name && a.url == b.url && a.history == b.history && a.alarm == b.alarm && a.every == b.every
            && (!a.alarm || (a.below == b.below && a.backInStock == b.backInStock))
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
