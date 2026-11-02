import Foundation

/// One name's search hit. `matchedName` is the original spelling that matched when the shown name did not win.
nonisolated struct NameSearchResult: Identifiable, Equatable {
    let key: String
    let shownName: String
    let matchedName: String?
    let count: Int
    let moneyOut: Double
    let moneyIn: Double
    let newestDate: String
    /// The newest payment's category, as named by the dashboard.
    let categoryName: String
    var id: String { key }
}

nonisolated enum NameSearch {
    static func results(for query: String, in groups: [String: PaymentNameGroup]) -> [NameSearchResult] {
        Index(groups: groups).results(for: query)
    }

    /// Fold once per dashboard; keystrokes only compare already folded names. No dependency on a store or a view.
    struct Index {
        private struct Name {
            let original: String
            let folded: String
            let words: [String]
            let letters: [[Character]]

            init(_ original: String) {
                self.original = original
                folded = NameSearch.fold(original)
                words = folded.split(separator: " ").map(String.init)
                letters = words.map(Array.init)
            }
        }

        private struct Entry {
            let result: NameSearchResult
            let names: [Name] // The shown name first, then the other spellings, newest first.
        }
        private let entries: [Entry]

        init(groups: [String: PaymentNameGroup]) {
            entries = groups.compactMap { key, group in
                guard let newest = group.rows.first else { return nil }
                var seen = Set<String>()
                let spellings = [newest.place] + (group.names ?? []) + group.rows.flatMap { [$0.place, $0.bankName].compactMap { $0 } }
                let names = spellings.compactMap { spelling -> Name? in
                    let name = Name(spelling)
                    guard !name.folded.isEmpty, seen.insert(name.folded).inserted else { return nil }
                    return name
                }
                return Entry(result: NameSearchResult(key: key, shownName: newest.place, matchedName: nil,
                                                      count: group.count, moneyOut: group.moneyOut, moneyIn: group.moneyIn,
                                                      newestDate: newest.date, categoryName: newest.categoryName), names: names)
            }
        }

        func results(for query: String) -> [NameSearchResult] {
            let folded = NameSearch.fold(query)
            guard !folded.isEmpty else { return [] }
            let words = folded.split(separator: " ").map(String.init)
            let letters = words.map(Array.init)
            var hits: [(result: NameSearchResult, tier: Int, shown: Bool)] = []
            for entry in entries {
                var best: (tier: Int, shown: Bool, name: String)?
                for name in entry.names {
                    let tier: Int
                    if name.folded == folded { tier = 1 }
                    else if name.folded.hasPrefix(folded) { tier = 2 }
                    else if (best?.tier ?? 6) > 3 && words.allSatisfy({ word in name.words.contains { $0.hasPrefix(word) } }) { tier = 3 }
                    else if (best?.tier ?? 6) > 4 && words.allSatisfy({ name.folded.contains($0) }) { tier = 4 }
                    else if best == nil && words.indices.allSatisfy({ index in
                        name.folded.contains(words[index]) || (letters[index].count >= 4 && name.letters.contains {
                            NameSearch.oneEdit(letters[index], $0)
                        })
                    }) { tier = 5 }
                    else { continue }
                    let shown = name.original == entry.result.shownName
                    if best == nil || tier < best!.tier || (tier == best!.tier && shown && !best!.shown) {
                        best = (tier, shown, name.original)
                    }
                    if tier == 1 && shown { break }
                }
                guard let best else { continue }
                let value = entry.result
                hits.append((NameSearchResult(key: value.key, shownName: value.shownName,
                                              matchedName: best.shown ? nil : best.name, count: value.count,
                                              moneyOut: value.moneyOut, moneyIn: value.moneyIn,
                                              newestDate: value.newestDate, categoryName: value.categoryName), best.tier, best.shown))
            }
            hits.sort {
                if $0.tier != $1.tier { return $0.tier < $1.tier }
                if $0.shown != $1.shown { return $0.shown }
                if $0.result.count != $1.result.count { return $0.result.count > $1.result.count }
                if $0.result.newestDate != $1.result.newestDate { return $0.result.newestDate > $1.result.newestDate }
                return $0.result.key < $1.result.key
            }
            return hits.prefix(50).map(\.result)
        }
    }

    /// The same spelling and fuzzy matching rules, without the normal name search's 50-group cap.
    static func matches(_ query: String, names: [String]) -> Bool {
        let folded = fold(query)
        guard !folded.isEmpty else { return false }
        let words = folded.split(separator: " ").map(String.init)
        let letters = words.map(Array.init)
        return names.contains { original in
            let name = fold(original)
            if words.allSatisfy({ name.contains($0) }) { return true }
            let nameLetters = name.split(separator: " ").map { Array($0) }
            return words.indices.allSatisfy { index in
                name.contains(words[index]) || (letters[index].count >= 4 && nameLetters.contains {
                    oneEdit(letters[index], $0)
                })
            }
        }
    }

    private static func fold(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "ß", with: "ss")
        return String(folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " })
            .split(separator: " ").joined(separator: " ")
    }

    /// Levenshtein distance at most one, in linear time; a transposition is two edits.
    private static func oneEdit(_ query: [Character], _ word: [Character]) -> Bool {
        guard abs(query.count - word.count) <= 1 else { return false }
        var q = 0, w = 0, edits = 0
        while q < query.count && w < word.count {
            if query[q] == word[w] { q += 1; w += 1; continue }
            edits += 1
            if edits > 1 { return false }
            if query.count >= word.count { q += 1 }
            if word.count >= query.count { w += 1 }
        }
        return edits + (query.count - q) + (word.count - w) <= 1
    }
}

struct NameSearchCache {
    var revision = -1
    var index = NameSearch.Index(groups: [:])
}

extension DashboardStore {
    /// Phone mode only. The index is rebuilt on the first search after a new dashboard, then reused per keystroke.
    func searchNames(_ query: String) -> [NameSearchResult] {
        guard let groups = dashboard?.nameGroups else { return [] }
        if builtNameSearch.revision != revision {
            builtNameSearch = NameSearchCache(revision: revision, index: NameSearch.Index(groups: groups))
        }
        return builtNameSearch.index.results(for: query)
    }
}
