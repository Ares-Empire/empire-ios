import Foundation
import Testing
@testable import Aresium

struct NameSearchTests {
    private func group(_ name: String, names: [String] = [], count: Int = 1, date: String = "2026-10-02") -> PaymentNameGroup {
        let rows = (0..<count).map { index in
            Transaction(id: "payment-\(index)", date: date, day: 2, month: "2026-10", amount: -12,
                        categoryName: "Fictional groceries", tags: [], place: name, city: "",
                        categoriesIn: ["Fictional groceries"], incomeBuckets: [])
        }
        return PaymentNameGroup(rows: rows, amounts: PaymentNameAmounts(moneyOut: Double(count) * 12, moneyIn: 3),
                                months: [:], names: names)
    }

    @Test func allFiveTiersInOrder() {
        let groups = ["exact": group("Luma"), "prefix": group("Luma market"),
                      "words": group("The Luma market"), "inside": group("Pluma shop"), "spelling": group("Lumi")]
        #expect(NameSearch.results(for: "luma", in: groups).map(\.key) == ["exact", "prefix", "words", "inside", "spelling"])
    }

    @Test func foldingPunctuationWordOrderAndEveryWord() {
        let groups = ["fold": group("Große—LÚMA, Café!"), "split": group("Luma", names: ["Other café"])]
        #expect(NameSearch.results(for: " GROSSE...luma café ", in: groups).map(\.key) == ["fold"])
        #expect(NameSearch.results(for: "cafe gro", in: groups).map(\.key) == ["fold"], "prefixes may be in any word order")
        #expect(NameSearch.results(for: "uma afe", in: groups).map(\.key) == ["fold"], "substrings in any order")
        #expect(NameSearch.results(for: "luma cafe", in: groups).map(\.key) == ["fold"], "all words must match one spelling")
        #expect(NameSearch.results(for: "luma absent", in: groups).isEmpty)
        for query in ["", " \n\t ", "---"] { #expect(NameSearch.results(for: query, in: groups).isEmpty) }
    }

    @Test func closeSpellingAllowsOneSubstitutionInsertionOrDeletionPerLongWord() {
        let groups = ["shop": group("Lumen market")]
        for query in ["lumon", "lumn", "lumenn", "lumen markat", "lumon markat", "ma lumon"] {
            #expect(NameSearch.results(for: query, in: groups).map(\.key) == ["shop"], "\(query)")
        }
        for query in ["lmn", "lomon", "lmu en", "lumon missing", "marx"] {
            #expect(NameSearch.results(for: query, in: groups).isEmpty, "\(query)")
        }
    }

    @Test func tiesPreferShownNameThenCountThenNewestDateAndAreDeterministic() {
        let groups = ["alias": group("Different", names: ["Luma"], count: 20),
                      "many": group("Luma", count: 3, date: "2026-09-01"),
                      "newer": group("Luma", count: 2, date: "2026-10-03"),
                      "older": group("Luma", count: 2, date: "2026-10-01"),
                      "prefix": group("Luma shop", count: 100)]
        #expect(NameSearch.results(for: "Luma", in: groups).map(\.key) == ["many", "newer", "older", "alias", "prefix"])
        let tied = ["b": group("Luma"), "a": group("Luma")]
        #expect(NameSearch.results(for: "Luma", in: tied).map(\.key) == ["a", "b"])
    }

    @Test func olderBankLineAndOtherOwnNamesCarryTheMatchedSpellingAndMetadata() throws {
        let groups = ["merchant:made-up": group("Luma, Ltd", names: ["MGP Luma - Old Market", "Our favourite shop"], count: 5)]
        let hit = try #require(NameSearch.results(for: "mgp luma", in: groups).first)
        #expect(hit.key == "merchant:made-up" && hit.shownName == "Luma, Ltd" && hit.matchedName == "MGP Luma - Old Market")
        #expect(hit.count == 5 && hit.moneyOut == 60 && hit.moneyIn == 3)
        #expect(hit.newestDate == "2026-10-02" && hit.categoryName == "Fictional groceries")
        #expect(NameSearch.results(for: "favourite", in: groups).first?.matchedName == "Our favourite shop")
        #expect(NameSearch.results(for: "luma ltd", in: groups).first?.matchedName == nil)
    }

    @Test func aStrongerAliasBeatsAWeakerShownNameWithinOneGroup() {
        let groups = ["one": group("Luma market", names: ["Luma"]),
                      "two": group("Lumi", names: ["The Luma market"])]
        let hits = NameSearch.results(for: "luma", in: groups)
        #expect(hits.map(\.key) == ["one", "two"])
        #expect(hits.map(\.matchedName) == ["Luma", "The Luma market"])
    }

    @Test func atMostFiftyGroups() {
        let groups = Dictionary(uniqueKeysWithValues: (1...80).map { ("shop-\($0)", group("Luma", count: $0)) })
        let hits = NameSearch.results(for: "luma", in: groups)
        #expect(hits.count == 50 && hits.first?.count == 80 && hits.last?.count == 31)
    }

    @MainActor @Test func indexedSearchOfFiveThousandPaymentsTakesUnderTenMilliseconds() {
        let groups = Dictionary(uniqueKeysWithValues: (0..<1000).map { index in
            ("shop-\(index)", group("Lumen Market \(index)", names: ["Old Lumen \(index)", "Our Lumen \(index)"], count: 5))
        })
        let index = NameSearch.Index(groups: groups)
        let queries = ["lumen", "old lumen", "market lumen", "umen arket", "lumon markat", "absent"]
        var worst = 0.0
        for query in queries {
            _ = index.results(for: query) // Warm up the code, outside the timed keystrokes.
            var elapsed = 0.0
            for _ in 0..<10 {
                let start = CFAbsoluteTimeGetCurrent()
                let results = index.results(for: query)
                elapsed += CFAbsoluteTimeGetCurrent() - start
                #expect(results.count == (query == "absent" ? 0 : 50))
            }
            let milliseconds = elapsed * 100 // Ten keystrokes, seconds to milliseconds.
            worst = max(worst, milliseconds)
            print("NameSearch 1000 groups / 5000 payments, '\(query)': \(milliseconds) ms per indexed query")
        }
        #expect(worst < 10, "Worst mean indexed search: \(worst) ms")
    }
}
