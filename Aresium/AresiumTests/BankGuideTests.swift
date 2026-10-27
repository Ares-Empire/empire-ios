import Foundation
import Testing
@testable import Aresium

/// "How do I get my file?" (brief 24): the bank guide's data as the app ships it (`Guide/bank-steps.json`), and the search.
@MainActor
struct BankGuideTests {
    private func guide() throws -> BankGuide { try BankGuide.bundled() }

    @Test func everyBankDecodesWithStepsOrAnExplicitNone() throws {
        let guide = try guide()
        #expect(guide.banks.count == 18)
        #expect(Set(guide.banks.map(\.id)).count == guide.banks.count, "bank ids are unique")
        for bank in guide.banks {
            // The website: German and English steps, or explicitly no export there.
            #expect(bank.website.hasSteps || bank.website.status == .none, "\(bank.id): website steps or none")
            for kind in BankGuide.PlaceKind.allCases {
                let place = bank.place(kind)
                // Steps come in both languages, one for one; a place without them has neither.
                #expect((place.de == nil) == (place.en == nil), "\(bank.id) \(kind): both languages or neither")
                #expect(place.de?.count == place.en?.count, "\(bank.id) \(kind): as many German as English steps")
                if place.status == .none { #expect(!place.hasSteps, "\(bank.id) \(kind): none has no steps") }
                for step in place.steps(.german) + place.steps(.english) { #expect(!step.isEmpty) }
            }
            #expect(!bank.placesWithSteps.isEmpty, "\(bank.id): somewhere to get the file")
            #expect(!bank.title(.german).isEmpty && !bank.title(.english).isEmpty)
            #expect(!bank.names.isEmpty)
            #expect(!bank.fileType.pick(.german).isEmpty && !bank.fileType.pick(.english).isEmpty)
            #expect(!bank.fileType.why(.german).isEmpty && !bank.fileType.why(.english).isEmpty)
            #expect(!bank.limits(.german).isEmpty && !bank.limits(.english).isEmpty)
            #expect(!bank.toAresium.isEmpty)
            for key in bank.toAresium { #expect(guide.ways[key] != nil, "\(bank.id): way \(key.rawValue)") }
        }
        for key in BankGuide.Way.Key.allCases {
            let way = try #require(guide.ways[key], "way \(key.rawValue)")
            #expect(way.de.count == 3 && way.en.count == 3)
            #expect((way.alsoDe == nil) == (way.alsoEn == nil))
        }
        #expect(guide.bank(BankGuide.Bank.otherID) != nil)
    }

    /// The screen's own sentences (why a file, how it reaches Aresium) never say "CSV": only a bank's or Numbers'
    /// label in quotes may.
    @Test func screenSentencesSayNoFormatOutsideALabel() throws {
        let guide = try guide()
        var sentences: [String] = []
        for bank in guide.banks { sentences += [bank.fileType.why(.german), bank.fileType.why(.english)] }
        for way in guide.ways.values { sentences += way.de + way.en + [way.alsoDe, way.alsoEn].compactMap { $0 } }
        for sentence in sentences {
            let unquoted = sentence.replacingOccurrences(of: #"[„“][^“”]*[“”]"#, with: "", options: .regularExpression)
            #expect(!unquoted.localizedCaseInsensitiveContains("csv"), "\(sentence)")
        }
    }

    @Test func pagesShowThePlacesWithStepsAndALineForTheOther() throws {
        let guide = try guide()
        let sparkasse = try #require(guide.bank("sparkasse-camt"))
        #expect(sparkasse.placesWithSteps == [.website])
        #expect(sparkasse.firstPlace == .website)
        #expect(sparkasse.otherPlaceLine(.german) == "In der App der Bank geht das nicht, nur auf der Website.")
        #expect(sparkasse.ways(for: .website) == [.safari, .computer, .desktopSite])

        // No source describes the app: said so, not "it doesn't work".
        let comdirect = try #require(guide.bank("comdirect"))
        #expect(comdirect.otherPlaceLine(.english) == "Aresium knows no way in the bank's app; the website works.")

        // App only: the page opens on the app, its way out is Share.
        let tradeRepublic = try #require(guide.bank("trade-republic"))
        #expect(tradeRepublic.placesWithSteps == [.app])
        #expect(tradeRepublic.firstPlace == .app)
        #expect(tradeRepublic.ways(for: .app) == [.share])
        #expect(tradeRepublic.otherPlaceLine(.english) == "This doesn't work on the website, only in the bank's app.")
        #expect(tradeRepublic.fileType.pick(.german) == ["Transaktionsexport"])
        #expect(tradeRepublic.fileType.pick(.english) == ["Transactions Export"])

        // Both: the usual way decides where the page opens (Revolut's file comes from its app).
        let revolut = try #require(guide.bank("revolut"))
        #expect(revolut.placesWithSteps == [.website, .app])
        #expect(revolut.firstPlace == .app)
        #expect(revolut.otherPlaceLine() == nil)
        let volksbank = try #require(guide.bank("volksbank"))
        #expect(volksbank.firstPlace == .website)
        #expect(volksbank.ways(for: .app) == [.share])
        #expect(volksbank.ways(for: .website) == [.safari, .computer])

        // A quiet line where a button may be called differently: not for the bank's own recent page.
        let commerzbank = try #require(guide.bank("commerzbank"))
        #expect(!commerzbank.mayDiffer(.website))
        #expect(volksbank.mayDiffer(.app))

        let other = try #require(guide.bank(BankGuide.Bank.otherID))
        #expect(other.title(.german) == "Andere Bank")
        #expect(other.title(.english) == "Another bank")
    }

    @Test func searchFindsBanksByTheirNamesWithAnotherBankLast() throws {
        let guide = try guide()
        func ids(_ query: String) -> [String] { guide.search(query).map(\.id) }

        #expect(ids("") == guide.banks.filter { !$0.isOther }.map(\.id) + ["other"])
        #expect(ids("").count == 18)
        #expect(ids("spark") == ["sparkasse-camt", "other"])
        #expect(ids("Kreissparkasse Heilbronn") == ["sparkasse-camt", "other"])     // a name among the words
        #expect(ids("sparkasse köln") == ["sparkasse-camt", "other"])
        #expect(ids("SPARKASSE KOLN") == ["sparkasse-camt", "other"])              // case and accents don't count
        #expect(ids("ing") == ["ing", "other"])                                    // not "VR Banking"
        #expect(ids("raiffeisen") == ["volksbank", "other"])
        #expect(ids("VR-Bank") == ["volksbank", "other"])
        #expect(ids("dkb visa") == ["dkb", "other"])
        #expect(ids("amex") == ["amex", "other"])
        #expect(ids("barclaycard") == ["barclays", "other"])
        #expect(ids("easybank") == ["barclays", "other"])
        #expect(ids("deutsche") == ["dkb", "deutsche-bank", "postbank", "other"])    // Deutsche Kreditbank too
        #expect(ids("Sparda-Bank") == ["other"])                                   // not in the list: Another bank
        #expect(ids("   ") == ids(""))
    }
}
