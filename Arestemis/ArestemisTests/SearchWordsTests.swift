import Foundation
import Testing
@testable import Arestemis

/// Brief 149: several search words in one thing search (the Arestemis repo's brief 148, `ItemSearch.more_queries`):
/// reading the field leniently, the chips the form adds and removes (Return, a comma, five at most, no repeats), what is
/// sent, the server's refusals placed at their word, and the names and card lines in both languages.
@MainActor
struct SearchWordsTests {
    private func spaces(_ value: String?) -> String? {
        value?.replacingOccurrences(of: "\u{a0}", with: " ").replacingOccurrences(of: "\u{2060}", with: "")
    }

    private func itemJSON(moreQueries: String?) -> Data {
        let more = moreQueries.map { #""more_queries": \#($0), "# } ?? ""
        return Data("""
            {"query": "Hermès Krawatte", \(more)"exclude": [], "price_min": null, "price_max": 150, "vb_over_max": 15,
             "condition_min": "like_new", "for_parts": false, "auctions": true, "delivery": "shipping", "places": [],
             "radius_km": 20, "seller": "any", "extra": "Hermès only in blue", "sources": ["kleinanzeigen", "vinted"]}
            """.utf8)
    }

    // MARK: reading and sending

    @Test func moreWordsAreReadLenientlyAndAlwaysSent() throws {
        // A server from before brief 148 sends no more_queries: none.
        let older = try JSONDecoder().decode(ItemSearch.self, from: itemJSON(moreQueries: nil))
        #expect(older.moreQueries.isEmpty && older.words == ["Hermès Krawatte"])
        let none = try JSONDecoder().decode(ItemSearch.self, from: itemJSON(moreQueries: "[]"))
        #expect(none == older)
        let three = try JSONDecoder().decode(ItemSearch.self,
                                             from: itemJSON(moreQueries: #"["Ferragamo Krawatte", "Kiton Krawatte"]"#))
        #expect(three.query == "Hermès Krawatte" && three.moreQueries == ["Ferragamo Krawatte", "Kiton Krawatte"])
        #expect(three.words == ["Hermès Krawatte", "Ferragamo Krawatte", "Kiton Krawatte"])
        // Encoding always sends the field, an empty list too.
        for search in [older, three] {
            let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(search)) as? [String: Any])
            #expect(object["more_queries"] as? [String] == search.moreQueries)
            #expect(try JSONDecoder().decode(ItemSearch.self, from: JSONEncoder().encode(search)) == search)
        }
        // "Describe it"'s answer may carry them too.
        let partial = try JSONDecoder().decode(PartialItemSearch.self, from: Data(#"{"query": "A tie", "more_queries": ["B tie"]}"#.utf8))
        #expect(partial.query == "A tie" && partial.moreQueries == ["B tie"])
    }

    @Test func theSampleThingHuntHasThreeWords() throws {
        let overview = try sample(Overview.self, "overview")
        let jeans = try #require(overview.hunts.first { $0.id == 5 }?.hunt.search.item)
        #expect(jeans.words == ["Denimwerk jeans", "Levi's 501", "Lee Rider"] && !jeans.extra.isEmpty)
        let hunts = try sample([Hunt].self, "hunts")
        #expect(hunts.first { $0.id == 5 }?.search.item == jeans)
        // The other thing hunts have one word.
        #expect(overview.hunts.compactMap(\.hunt.search.item).filter { $0.moreQueries.isEmpty }.count == 2)
    }

    @Test func whatIsSent() throws {
        var draft = ItemSearchDraft()
        draft.delivery = .shipping
        draft.add(word: "Hermès Krawatte")
        draft.add(word: "Ferragamo Krawatte")
        draft.type("  Kiton Krawatte ")                   // typed, not added: it still counts
        let search = try #require(draft.search())
        #expect(search.query == "Hermès Krawatte" && search.moreQueries == ["Ferragamo Krawatte", "Kiton Krawatte"])
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(search)) as? [String: Any])
        #expect(object["query"] as? String == "Hermès Krawatte")
        #expect(object["more_queries"] as? [String] == ["Ferragamo Krawatte", "Kiton Krawatte"])
        // A saved search opens with its words as chips and an empty field.
        let opened = ItemSearchDraft(search)
        #expect(opened.words == ["Hermès Krawatte", "Ferragamo Krawatte", "Kiton Krawatte"] && opened.typedWord.isEmpty)
        #expect(opened.search() == search)
        // A typed repeat adds nothing to what is sent.
        var repeated = opened
        repeated.removeWord(at: 2)
        repeated.type("hermes  KRAWATTE")
        #expect(repeated.search()?.moreQueries == ["Ferragamo Krawatte"])
        // One word: none more.
        var one = ItemSearchDraft()
        one.delivery = .shipping
        one.type("Kallax")
        #expect(one.search()?.query == "Kallax" && one.search()?.moreQueries == [])
    }

    // MARK: adding and removing chips

    @Test func returnAndACommaAddTheTypedWord() {
        var draft = ItemSearchDraft()
        draft.type("Hermès Krawatte")
        #expect(draft.typed == .adds && draft.words.isEmpty)
        let added = draft.addTypedWord()                   // Return, the field's +, leaving the field
        #expect(added)
        #expect(draft.words == ["Hermès Krawatte"] && draft.typedWord.isEmpty && draft.typed == .empty)
        let addedNothing = draft.addTypedWord()            // nothing typed: nothing added
        #expect(!addedNothing)

        draft.type("Ferragamo Krawatte,")                  // a comma ends the word
        #expect(draft.words == ["Hermès Krawatte", "Ferragamo Krawatte"] && draft.typedWord.isEmpty)
        draft.type(",")                                    // a comma alone goes
        #expect(draft.typedWord.isEmpty && draft.words.count == 2)

        // Pasted with commas: each word a chip, the last still typed.
        var pasted = ItemSearchDraft()
        pasted.type("Hermès Krawatte, Ferragamo Krawatte , Kiton")
        #expect(pasted.words == ["Hermès Krawatte", "Ferragamo Krawatte"] && pasted.typedWord == "Kiton")

        // Removing a chip.
        draft.removeWord(at: 0)
        #expect(draft.words == ["Ferragamo Krawatte"])
        draft.removeWord(at: 5)                            // not there: nothing happens
        #expect(draft.words == ["Ferragamo Krawatte"])
    }

    @Test func fiveAtMost() {
        var draft = ItemSearchDraft()
        for word in ["One tie", "Two tie", "Three tie", "Four tie"] {
            let added = draft.add(word: word)
            #expect(added)
        }
        #expect(draft.takesWords && draft.wordsNote(language: .english) == nil)
        draft.type("Five tie")
        #expect(draft.sentWords.count == 5)
        let fifth = draft.addTypedWord()
        #expect(fifth)
        // Five: the field goes, a quiet line says why, nothing more is added.
        #expect(!draft.takesWords && draft.typedWord.isEmpty)
        #expect(draft.wordsNote(language: .english) == "At most 5 search words.")
        #expect(draft.wordsNote(language: .german) == "Höchstens 5 Suchbegriffe.")
        let sixth = draft.add(word: "Six tie")
        #expect(!sixth)
        draft.type("Six tie")
        #expect(draft.typedWord.isEmpty && draft.words.count == 5 && draft.isValid == draft.problems.isEmpty)
        #expect(draft.fieldLine(.words, language: .english) == nil)
        // Removing one brings the field back.
        draft.removeWord(at: 4)
        #expect(draft.takesWords && draft.wordsNote(language: .english) == nil)
        // A search with more than five (a newer server) says so and is not sent as it is.
        var more = ItemSearchDraft()
        more.delivery = .shipping
        more.words = ["A tie", "B tie", "C tie", "D tie", "E tie", "F tie"]
        #expect(more.problems == [.words] && more.search() == nil && more.wordsNote(language: .english) == nil)
        #expect(more.fieldLine(.words, language: .german) == "Höchstens 5 Suchbegriffe.")
    }

    @Test(arguments: [AppLanguage.english, .german])
    func aRepeatIsNotAddedAndAQuietLineSaysWhy(_ language: AppLanguage) {
        let de = language == .german
        var draft = ItemSearchDraft()
        draft.add(word: "Hermès Krawatte")
        // Case, accents and spaces do not count, as on the server.
        for typed in ["hermès krawatte", "HERMES KRAWATTE", "Hermes  Krawatte "] {
            draft.type(typed)
            #expect(draft.typed == .repeats("Hermès Krawatte"))
            let added = draft.addTypedWord()
            #expect(!added && draft.words == ["Hermès Krawatte"] && draft.typedWord == typed)
            #expect(draft.wordsNote(language: language)
                    == (de ? "„Hermès Krawatte“ ist schon dabei." : "“Hermès Krawatte” is there already."))
        }
        // With a comma it stays in the field (without the comma) so the line can say why.
        draft.type("hermes krawatte,")
        #expect(draft.words == ["Hermès Krawatte"] && draft.typedWord == "hermes krawatte")
        let again = draft.add(word: "HERMÈS KRAWATTE")
        #expect(!again)
        // Another word clears the line.
        draft.type("Hermès Krawatte blau")
        #expect(draft.typed == .adds && draft.wordsNote(language: language) == nil)
        #expect(SearchWords.key("Straße") == SearchWords.key("STRASSE"))
    }

    @Test(arguments: [AppLanguage.english, .german])
    func aWordTooShortStaysInTheField(_ language: AppLanguage) {
        let de = language == .german
        var draft = ItemSearchDraft()
        draft.delivery = .shipping
        draft.add(word: "Kiton Krawatte")
        draft.type("K")
        let added = draft.addTypedWord()
        #expect(draft.typed == .tooShort && !added && draft.typedWord == "K")
        // It is not lost on Save: the form says what is wrong instead.
        #expect(draft.problems == [.words] && draft.search() == nil)
        #expect(draft.fieldLine(.words, language: language) == (de ? "Mindestens 2 Zeichen." : "At least 2 characters."))
        draft.type("K,")
        #expect(draft.words == ["Kiton Krawatte"] && draft.typedWord == "K")
        // The field keeps at most 100 characters.
        draft.type(String(repeating: "x", count: 140))
        #expect(draft.typedWord.count == 100 && draft.typed == .adds)
        // A new form is empty and quiet; Save says what is missing.
        let empty = ItemSearchDraft()
        #expect(empty.fieldLine(.words, language: language) == nil)
        #expect(empty.hint(language: language) == (de ? "Gib ein, was du suchst." : "Type what you look for."))
    }

    @Test func describeItMergesWords() {
        var draft = ItemSearchDraft()
        draft.add(word: "Hermès Krawatte")
        draft.apply(PartialItemSearch(query: "hermes krawatte", moreQueries: ["Kiton Krawatte", "x", "Brioni Krawatte"]))
        #expect(draft.words == ["Hermès Krawatte", "Kiton Krawatte", "Brioni Krawatte"])
        draft.apply(PartialItemSearch(moreQueries: ["A tie", "B tie", "C tie"]))
        #expect(draft.words.count == 5 && draft.words.last == "B tie")
        draft.apply(PartialItemSearch(query: nil, moreQueries: nil))
        #expect(draft.words.count == 5)
    }

    @Test func keptDraftsFromBeforeStillOpen() throws {
        var draft = ItemSearchDraft()
        draft.add(word: "Hermès Krawatte")
        draft.type("Kit")
        #expect(try JSONDecoder().decode(ItemSearchDraft.self, from: JSONEncoder().encode(draft)) == draft)

        // A draft kept before brief 149 had the one field's text as `query`: a word becomes a chip, so a kept baseline
        // (the saved hunt as a draft) still equals the saved hunt opened now, and its kept edits stay.
        let saved = try JSONDecoder().decode(ItemSearch.self, from: itemJSON(moreQueries: nil))
        let opened = ItemSearchDraft(saved, name: nil)
        func earlier(_ draft: ItemSearchDraft, query: String) throws -> ItemSearchDraft {
            var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
            object.removeValue(forKey: "words")
            object.removeValue(forKey: "typedWord")
            object["query"] = query
            return try JSONDecoder().decode(ItemSearchDraft.self, from: JSONSerialization.data(withJSONObject: object))
        }
        #expect(try earlier(opened, query: "Hermès Krawatte") == opened)
        let spaced = try earlier(ItemSearchDraft(), query: " Herman Miller Aeron ")
        #expect(spaced.words == ["Herman Miller Aeron"] && spaced.typedWord.isEmpty)
        // A text that is no word yet stays typed.
        let short = try earlier(ItemSearchDraft(), query: "H")
        #expect(short.words.isEmpty && short.typedWord == "H")
    }

    // MARK: the server's refusals

    @Test func aRefusalNamesItsWord() {
        #expect(SearchWords.wordIndex(field: "search.query") == 0)
        #expect(SearchWords.wordIndex(field: "search.more_queries[0]") == 1)
        #expect(SearchWords.wordIndex(field: "search.more_queries[3]") == 4)
        for field in ["search.more_queries", "search.more_queries[]", "search.more_queries[-1]", "search.more_queries[+1]", "search.more_queries[x]",
                      "search.extra", "more_queries[1]"] {
            #expect(SearchWords.wordIndex(field: field) == nil)
        }
        #expect(SearchWords.isWordsField("search.more_queries") && SearchWords.isWordsField("search.more_queries[2]"))
        #expect(SearchWords.isWordsField("search.query") && !SearchWords.isWordsField("search.extra")
                && !SearchWords.isWordsField(nil))
        #expect(SearchWords.refusalFields.isSuperset(of: ["search.query", "search.more_queries", "search.more_queries[0]",
                                                          "search.more_queries[3]"]))

        let words = ["Hermès Krawatte", "Ferragamo Krawatte", "Kiton Krawatte"]
        #expect(SearchWords.refusalLine("Duplicate search words", field: "search.more_queries[1]", words: words,
                                        language: .english) == "“Kiton Krawatte”: Duplicate search words")
        #expect(SearchWords.refusalLine("Doppelte Suchbegriffe", field: "search.more_queries[1]", words: words,
                                        language: .german) == "„Kiton Krawatte“: Doppelte Suchbegriffe")
        #expect(SearchWords.refusalLine("Zu kurz", field: "search.query", words: words, language: .german)
                == "„Hermès Krawatte“: Zu kurz")
        // A refusal of all the more words, or of a word no longer there: the sentence alone.
        #expect(SearchWords.refusalLine("Too many", field: "search.more_queries", words: words) == "Too many")
        #expect(SearchWords.refusalLine("Gone", field: "search.more_queries[3]", words: words) == "Gone")
    }

    @Test func theFormShowsTheServersRefusalAtTheWords() async throws {
        let transport = FakeTransport()
        let (store, _, _) = try await makeStore(transport: transport)
        await store.reloadOverview()
        transport.answer("POST /hunts", 400, json: Data("""
            {"error": "Doppelte Suchbegriffe", "field": "search.more_queries[1]"}
            """.utf8))
        var draft = ItemSearchDraft()
        draft.delivery = .shipping
        for word in ["Hermès Krawatte", "Ferragamo Krawatte", "Kiton Krawatte"] { draft.add(word: word) }
        let search = try #require(draft.search())
        #expect(await store.saveHunt(id: nil, kind: .item, name: nil, search: .item(search),
                                     fieldsShown: SearchWords.refusalFields) == nil)
        // At the words, not over the tabs.
        #expect(store.searchError == "Doppelte Suchbegriffe" && store.searchErrorField == "search.more_queries[1]")
        #expect(store.notice == nil)
        #expect(SearchWords.refusalLine(try #require(store.searchError), field: try #require(store.searchErrorField),
                                        words: draft.sentWords, language: .german)
                == "„Kiton Krawatte“: Doppelte Suchbegriffe")
        let sent = try #require(try body(transport.requests("POST /hunts").first)?["search"] as? [String: Any])
        #expect(sent["query"] as? String == "Hermès Krawatte")
        #expect(sent["more_queries"] as? [String] == ["Ferragamo Krawatte", "Kiton Krawatte"])
    }

    @Test func theSampleImitatesTheServersRules() async throws {
        let session = EmpireSession(app: .arestemis, storage: MemoryTokens(), restoreOnLaunch: false)
        let store = ArestemisStore(session: session, backend: try SampleBackend(), sample: true, placeDelay: .zero)
        await store.reloadOverview()
        var search = try #require(store.card(5)?.hunt.search.item)
        search.moreQueries = ["Levi's 501", "LEVI'S  501"]
        #expect(await store.saveHunt(id: 5, kind: .item, name: nil, search: .item(search),
                                     fieldsShown: SearchWords.refusalFields) == nil)
        #expect(store.searchErrorField == "search.more_queries[1]" && store.searchError == "Duplicate search words")
        search.moreQueries = ["Levi's 501"]
        #expect(await store.saveHunt(id: 5, kind: .item, name: nil, search: .item(search)) != nil)
        #expect(store.card(5)?.hunt.search.item?.words == ["Denimwerk jeans", "Levi's 501"])
    }

    // MARK: names and cards

    @Test(arguments: [AppLanguage.english, .german])
    func theNameIsTheFirstWordAndHowManyMore(_ language: AppLanguage) throws {
        let de = language == .german
        #expect(SearchWords.title([]) == nil && SearchWords.title(["Kallax"]) == "Kallax")
        #expect(SearchWords.title(["Hermès Krawatte", "Ferragamo Krawatte", "Kiton Krawatte"]) == "Hermès Krawatte + 2")

        // The Name field's grey placeholder follows the words, the typed one too.
        var draft = ItemSearchDraft()
        draft.add(word: "Hermès Krawatte")
        #expect(draft.namePlaceholder(language: language) == "Hermès Krawatte")
        draft.type("Ferragamo Krawatte")
        #expect(draft.namePlaceholder(language: language) == "Hermès Krawatte + 1")
        draft.type("hermes krawatte")                      // a repeat is no word more
        #expect(draft.namePlaceholder(language: language) == "Hermès Krawatte")

        // The cards: the name, else the first word and "+ 2"; the details as for one word.
        let overview = try sample(Overview.self, "overview")
        let sites = SiteNames(statuses: overview.sources)
        let jeans = try #require(overview.hunts.first { $0.id == 5 })
        let card = HuntText(jeans, sites: sites, language: language)
        #expect(card.title == "Denimwerk jeans + 2" && jeans.hunt.displayName(language: language) == "Denimwerk jeans + 2")
        #expect(HuntText.automaticTitle(jeans.hunt.search, language: language) == "Denimwerk jeans + 2")
        #expect(spaces(card.details) == (de ? "bis 40 € · Versand · Kleinanzeigen · Vinted"
                                            : "up to €40 · Shipping · Kleinanzeigen · Vinted"))
        // The page lists every word where it lists the search's settings.
        let page = HuntText(jeans, sites: sites, allWords: true, language: language)
        #expect(page.title == "Denimwerk jeans + 2")
        #expect(spaces(page.details) == (de ? "Denimwerk jeans, Levi's 501, Lee Rider · bis 40 € · Versand · Kleinanzeigen · Vinted"
                                            : "Denimwerk jeans, Levi's 501, Lee Rider · up to €40 · Shipping · Kleinanzeigen · Vinted"))
        // Each word stays on one line; the lines break after a comma or between the parts.
        #expect(page.details?.hasPrefix("Denimwerk\u{a0}jeans, Levi's\u{a0}501, Lee\u{a0}Rider · ") == true)

        // Under an own name the card leads with the words in short, the page with all of them.
        var named = jeans
        named.hunt.name = "Jeans"
        #expect(HuntText(named, sites: sites, language: language).title == "Jeans")
        #expect(spaces(HuntText(named, sites: sites, language: language).details)?.hasPrefix("Denimwerk jeans + 2 · ") == true)
        #expect(spaces(HuntText(named, sites: sites, allWords: true, language: language).details)?
            .hasPrefix("Denimwerk jeans, Levi's 501, Lee Rider · ") == true)

        // One word: as before, on the page too.
        let chair = try #require(overview.hunts.first { $0.id == 2 })
        #expect(HuntText(chair, sites: sites, allWords: true, language: language) == HuntText(chair, sites: sites, language: language))
    }
}
