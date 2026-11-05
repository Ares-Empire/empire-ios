import Foundation

/// The watch form's fields as typed (brief 131): the page's address, the change in the user's words, how often, and an
/// optional name. Only what the contract asks is checked here (something in the address, the change's length); whether
/// an address can be watched is the server's to say.
struct WatchSearchDraft: Codable, Equatable {
    var url = ""
    var change = ""
    var every = WatchSearch.defaultEvery
    /// The watch's own name; empty = the page's title once read, else the host.
    var name = ""

    static let changeLength = 3...500
    static let maxURL = 2000

    init() {}

    init(_ search: WatchSearch, name: String?) {
        url = search.url
        change = search.change
        every = search.every
        self.name = name ?? ""
    }

    enum Problem: Equatable { case url, change }

    var problems: [Problem] {
        var result: [Problem] = []
        let url = Self.trimmed(url)
        if url.isEmpty || url.count > Self.maxURL { result.append(.url) }
        if !Self.changeLength.contains(Self.trimmed(change).count) { result.append(.change) }
        return result
    }
    var isValid: Bool { problems.isEmpty }

    /// What is sent, trimmed; nil while something is missing or too long (the form shows `problems` meanwhile).
    func search() -> WatchSearch? {
        guard isValid else { return nil }
        return WatchSearch(url: Self.trimmed(url), change: Self.trimmed(change), every: every)
    }

    /// The name sent: trimmed and at most 60 characters (as Rename); nil when empty, so the server names it.
    var sentName: String? { HuntName.cleaned(name) }

    /// The watch with its suggested page's address in place of its own (brief 178, "Watch this page"); its name, the
    /// change it waits for and how often stay. Unsaved: the form shows it, and Save sends it as any changed address.
    func adopting(address: String) -> WatchSearchDraft {
        var draft = self
        draft.url = address.trimmingCharacters(in: .whitespacesAndNewlines)
        return draft
    }

    /// The address field after a change: a whole shared text pasted into it keeps only its first link
    /// (`WatchAddress.fromField`).
    mutating func takeAddress(_ text: String) {
        let kept = WatchAddress.fromField(text)
        if kept != url { url = kept }
    }

    /// What the name field shows while it is empty: what the watch will be called. The page's title once the saved
    /// address was read (`savedURL`, `pageTitle` from its card), else the host of the address typed, else "Optional".
    func namePlaceholder(savedURL: String? = nil, pageTitle: String? = nil, language: AppLanguage = .current) -> String {
        let title = pageTitle.map(Self.trimmed) ?? ""
        if !title.isEmpty, let savedURL, Self.trimmed(savedURL) == Self.trimmed(url) { return title }
        return HuntName.placeholder(WatchAddress.host(url), language: language)
    }

    /// What is wrong, in a sentence. A missing description says it in the server's words.
    func message(_ problem: Problem, language: AppLanguage = .current) -> String {
        let l = language
        switch problem {
        case .url:
            return Self.trimmed(url).count > Self.maxURL ? l.string("At most 2,000 characters.")
                : l.string("Paste the page's address.")
        case .change:
            let count = Self.trimmed(change).count
            if count == 0 { return l.string("Describe the change to watch for.") }
            return count < Self.changeLength.lowerBound ? l.string("At least 3 characters.")
                : l.string("At most 500 characters.")
        }
    }

    /// The line under a field: what is wrong with what is there. A field that is simply still empty says so only under
    /// Save (`hint`), so a new form opens without warnings (as the thing form).
    func fieldLine(_ problem: Problem, language: AppLanguage = .current) -> String? {
        guard problems.contains(problem) else { return nil }
        switch problem {
        case .url where Self.trimmed(url).isEmpty: return nil
        case .change where Self.trimmed(change).isEmpty: return nil
        default: return message(problem, language: language)
        }
    }

    /// One calm line under Save: the first thing still missing or wrong.
    func hint(language: AppLanguage = .current) -> String? {
        problems.first.map { message($0, language: language) }
    }

    private static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}
