import Foundation
import Testing
import UIKit
@testable import Aresium

/// One's own categories' looks (brief 36, Patrik's phone test 2026-10-30: every own category had the same grey tag): an
/// icon that fits the name (English and German words), else a spare one; a colour of its own; chosen once and stored
/// with the category; given to the own categories of an older store (schema 3) in the order they were made.
@MainActor
struct OwnCategoryLookTests {
    private let none = BackendAuth(token: nil)

    private func icon(_ name: String, besides taken: [String] = []) -> String {
        OwnCategoryLook.icon(for: name, besides: taken)
    }

    // MARK: the word list

    @Test func aKnownWordGivesAFittingIcon() {
        // The brief's words, both languages.
        for name in ["Fitness", "Fitnessstudio", "Sport", "Gym", "Kraftsport", "Yoga Studio"] {
            #expect(icon(name) == "Dumbbell", "\(name)")
        }
        for name in ["Haustier", "Pet", "Tierarzt"] { #expect(icon(name) == "PawPrint", "\(name)") }
        for name in ["Kaffee", "Coffee to go", "Café"] { #expect(icon(name) == "Coffee", "\(name)") }
        for name in ["Gift", "Weihnachtsgeschenke", "Geschenk für Oma", "Christmas"] {
            #expect(icon(name) == "Gift", "\(name)")
        }
        for name in ["Auto", "Car repairs", "Autoversicherung", "TÜV"] { #expect(icon(name) == "Car", "\(name)") }
        for name in ["Kinder", "Kids", "Kita", "Spielzeug"] { #expect(icon(name) == "Baby", "\(name)") }
        for name in ["Garten", "Garden", "Pflanzen"] { #expect(icon(name) == "Flower2", "\(name)") }
        for name in ["Musik", "Music", "Konzerte"] { #expect(icon(name) == "Music", "\(name)") }
        for name in ["Spiele", "Games", "Brettspiele", "Gaming"] { #expect(icon(name) == "Gamepad2", "\(name)") }
        for name in ["Reisen", "Urlaub", "Travel", "Dienstreise"] { #expect(icon(name) == "Luggage", "\(name)") }
        for name in ["Weiterbildung", "Learning", "Uni", "Universität", "Sprachkurs"] {
            #expect(icon(name) == "GraduationCap", "\(name)")
        }
        for name in ["Spende", "Donations", "Charity"] { #expect(icon(name) == "HandHeart", "\(name)") }
        // A few more, folded the same way (case, accents, ß).
        #expect(icon("Hund") == "Dog" && icon("Katze") == "Cat" && icon("Climbing") == "Mountain")
        #expect(icon("Bücher") == "Book" && icon("BUECHER") == "Book" && icon("Fußball") == "Dumbbell")
        #expect(icon("E-Bike") == "Bike" && icon("Friseur") == "Scissors" && icon("Kino") == "Film")
    }

    @Test func onlyWordBeginningsAndWholeShortWordsCount() {
        // "car" is a whole word only; stems never match a word's end ("Transport", "Preise", "Beispiel").
        #expect(icon("Card games") == "Gamepad2")
        for name in ["Transport", "Preise", "Cards", "Fictional club", "", "  "] {
            #expect(icon(name) == "Tag", "\(name)")
        }
        // Within one word the longest match: a toy, not a game.
        #expect(OwnCategoryLook.meanings(of: "Spielzeug").first?.icons.first == "Baby")
        #expect(OwnCategoryLook.words(of: "Weihnachts-Geschenke & Co.") == ["weihnachts", "geschenke", "co"])
    }

    // MARK: never alike

    @Test func twoOwnCategoriesNeverShareAnIconUntilAllAreTaken() {
        // A meaning's next icon, then the spare ones in order.
        #expect(icon("Hund", besides: ["Dog"]) == "PawPrint")
        #expect(icon("Kaffee", besides: ["Coffee"]) == "Tag")
        #expect(icon("Fictional club", besides: ["Tag", "Star"]) == "Bookmark")
        // Compared as drawn: an icon the app draws as the tag takes the tag.
        #expect(icon("Fictional", besides: ["NoSuchIcon"]) == "Star")

        var looks: [CategoryLook] = []
        for index in 0..<OwnCategoryLook.spareIcons.count {
            looks.append(OwnCategoryLook.look(for: "Fictional \(index)", besides: looks))
        }
        #expect(looks.map(\.icon) == OwnCategoryLook.spareIcons)
        #expect(Set(looks.map { CategorySymbol.name(for: $0.icon) }).count == looks.count)
        // Used up: the spare one fewest have (the first again), or for a known word its fitting icon.
        #expect(OwnCategoryLook.look(for: "Fictional more", besides: looks).icon == "Tag")
        #expect(OwnCategoryLook.look(for: "Kaffee", besides: looks).icon == "Coffee")
        #expect(OwnCategoryLook.look(for: "Kaffee", besides: looks + [CategoryLook(icon: "Coffee", color: "#FF9F1C")]).icon
                == "Coffee")
    }

    @Test func eachOwnCategoryGetsAColourOfItsOwn() {
        var looks: [CategoryLook] = []
        for index in 0..<OwnCategoryLook.colors.count {
            looks.append(OwnCategoryLook.look(for: "Fictional \(index)", besides: looks))
        }
        #expect(looks.map(\.color) == OwnCategoryLook.colors)
        // All taken: the least used, the first again; lower case counts as the same colour.
        #expect(OwnCategoryLook.color(besides: OwnCategoryLook.colors) == OwnCategoryLook.colors[0])
        #expect(OwnCategoryLook.color(besides: ["#ff9f1c"]) == OwnCategoryLook.colors[1])
    }

    @Test func theColoursAreNotTheDefaultCategories() async throws {
        let catalog = try await PhoneTest.engine().catalog()
        let defaults = Set(catalog.looks.values.map { $0.color.uppercased() } + [catalog.custom.color.uppercased()])
        #expect(OwnCategoryLook.colors.allSatisfy { !defaults.contains($0.uppercased()) })
        #expect(Set(OwnCategoryLook.colors).count == OwnCategoryLook.colors.count)
        #expect(OwnCategoryLook.colors.allSatisfy { OwnCategoryLook.isUsable(CategoryLook(icon: "Tag", color: $0)) })
    }

    @Test func everyIconIsDrawnWithASymbolOfItsOwn() {
        let icons = OwnCategoryLook.meanings.flatMap(\.icons) + OwnCategoryLook.spareIcons
        for icon in icons {
            #expect(CategorySymbol.knows(icon), "\(icon) has no symbol")
            #expect(UIImage(systemName: CategorySymbol.name(for: icon)) != nil, "\(icon)")
        }
        // The spare marks are all different symbols, and the words' lists are well formed.
        #expect(Set(OwnCategoryLook.spareIcons.map(CategorySymbol.name(for:))).count == OwnCategoryLook.spareIcons.count)
        #expect(OwnCategoryLook.meanings.allSatisfy { !$0.icons.isEmpty && !($0.stems + $0.words).isEmpty })
        #expect(!OwnCategoryLook.isUsable(CategoryLook(icon: "NoSuchIcon", color: "#FF9F1C")))
        #expect(!OwnCategoryLook.isUsable(CategoryLook(icon: "Tag", color: "red")))
    }

    @Test func fillKeepsLooksAndGivesTheRestInOrder() {
        let kept = CategoryLook(icon: "Dog", color: "#2DD4BF")
        let looks = OwnCategoryLook.fill([("Hund", nil), ("Katze", kept), ("Fictional", nil), ("Hund 2", nil)])
        #expect(looks[1] == kept)
        // The first Hund's dog is taken by the kept look: the paw, then the first free colour.
        #expect(looks[0] == CategoryLook(icon: "PawPrint", color: "#FF9F1C"))
        #expect(looks[2] == CategoryLook(icon: "Tag", color: "#818CF8"))
        #expect(looks[3].icon == "Star" && looks[3].color == "#F472B6")
    }

    // MARK: stored with the category

    @Test func anOwnCategoryKeepsTheLookItWasGiven() async throws {
        let storage = PhoneTest.storage()
        let phone = try await PhoneTest.backend(storage: storage, chosen: ["groceries"])
        _ = try await phone.importFiles([PhoneTest.vrBank([("21.10.2026", "Fictional Gym Nord", "Beitrag", -2990)])],
                                        auth: none)
        let gym = try await phone.addCustom(named: "Fitness", side: .spend)
        let dog = try await phone.addCustom(named: "Hund", side: .spend)
        let club = try await phone.addCustom(named: "Fictional club", side: .spend)
        let list = try await phone.categories()
        #expect(list.look(of: gym) == CategoryLook(icon: "Dumbbell", color: "#FF9F1C"))
        #expect(list.look(of: dog) == CategoryLook(icon: "Dog", color: "#2DD4BF"))
        #expect(list.look(of: club) == CategoryLook(icon: "Tag", color: "#818CF8"))
        #expect(list.look(of: "groceries") == list.catalog.look("groceries"), "the default categories keep the engine's")

        // The picker, the dashboard and a payment's page show the stored look.
        let picker = CategoryPickerModel(phone: phone) {}
        await picker.load()
        #expect(picker.custom.map(\.look.icon) == ["Dumbbell", "Dog", "Tag"])
        let payment = try #require(try await phone.ledger.payments().first)
        _ = try await phone.switchCategory(id: payment.id, to: "Fitness", auth: none)
        let dashboard = try await phone.dashboard(auth: none)
        let fitness = try #require(dashboard.categories.first { $0.name == "Fitness" })
        #expect(fitness.icon == "Dumbbell" && fitness.color == "#FF9F1C")
        #expect(try await phone.transactionDetail(id: payment.id, auth: none).categoryColor == "#FF9F1C")

        // Removing one frees its icon for the next; the others never change, also after the store is opened again.
        try await phone.unchoose(dog, moveTo: nil)
        let cat = try await phone.addCustom(named: "Hund", side: .spend)
        let reopened = try await PhoneTest.backend(storage: storage)
        let again = try await reopened.categories()
        #expect(again.look(of: gym) == CategoryLook(icon: "Dumbbell", color: "#FF9F1C"))
        #expect(again.look(of: club) == CategoryLook(icon: "Tag", color: "#818CF8"))
        #expect(again.look(of: cat) == CategoryLook(icon: "Dog", color: "#2DD4BF"))
    }

    @Test func exportAndRestoreCarryTheLooks() async throws {
        let phone = try await PhoneTest.backend(chosen: ["groceries"])
        try await phone.addCustom(named: "Fictional club", side: .spend)
        try await phone.addCustom(named: "Kaffee", side: .spend)
        let export = try await phone.export()
        #expect(export.categories.compactMap(\.look?.icon) == ["Tag", "Coffee"])
        let file = try export.encoded()

        let other = try await PhoneTest.backend()
        try await other.restore(file)
        #expect(try await other.ledger.chosen() == export.categories)

        // An export made before brief 36 (no looks) and one with a look the app cannot draw: looks are given in order.
        var old = try JSONSerialization.jsonObject(with: file) as! [String: Any]
        var categories = old["categories"] as! [[String: Any]]
        for index in categories.indices { categories[index].removeValue(forKey: "look") }
        categories[2]["look"] = ["icon": "NoSuchIcon", "color": "#123456"]
        old["categories"] = categories
        let third = try await PhoneTest.backend()
        try await third.restore(try JSONSerialization.data(withJSONObject: old))
        let restored = try await third.ledger.chosen()
        #expect(restored.map(\.look) == [nil, CategoryLook(icon: "Tag", color: "#FF9F1C"),
                                         CategoryLook(icon: "Coffee", color: "#2DD4BF")])
    }

    // MARK: a store made before (schema 3)

    /// A store made by schema version 3's code (AresiumTests/Fixtures/ledger-v3.store, made 2026-10-30 by today's main
    /// before schema 4: 3 payments, 1 account, 1 learned shop, 2 default categories and 4 own ones made in this order:
    /// Fitnessstudio, Hund, Fictional club, Coffee to go; a payment in each of the first two) opens, keeps everything,
    /// and gives the own categories their looks in that order, kept when it is opened again.
    @Test func aVersion3StoreOpensAndItsOwnCategoriesGetTheirLooks() async throws {
        let storage = PhoneTest.storage()
        try FileManager.default.createDirectory(at: storage.directory, withIntermediateDirectories: true)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/ledger-v3.store")
        try FileManager.default.copyItem(at: fixture, to: storage.storeURL)

        let ledger = try await Task.detached { try storage.open() }.value
        let summary = try await ledger.summary()
        #expect(summary.payments == 3 && summary.accounts == 1 && summary.learned == 1)
        let chosen = try await ledger.chosen()
        #expect(chosen.map { $0.name ?? $0.id }
                == ["groceries", "eating-out", "Fitnessstudio", "Hund", "Fictional club", "Coffee to go"])
        #expect(chosen.prefix(2).allSatisfy { $0.look == nil }, "the default categories keep the engine's look")
        #expect(chosen.dropFirst(2).map(\.look) == [CategoryLook(icon: "Dumbbell", color: "#FF9F1C"),
                                                     CategoryLook(icon: "Dog", color: "#2DD4BF"),
                                                     CategoryLook(icon: "Tag", color: "#818CF8"),
                                                     CategoryLook(icon: "Coffee", color: "#F472B6")])
        let payments = try await ledger.payments()
        let dog = try #require(chosen.first { $0.name == "Hund" })
        #expect(payments.first { $0.counterparty == "Fictional Pet Shop" }?.category == dog.id)
        #expect(try await ledger.learned() == ["fictional pet shop": dog.id])

        // Schema 4 keeps them: a new own category takes the next free look, the old ones stay.
        try await ledger.choose("custom-new", name: "Garten")
        let reopened = try await Task.detached { try storage.open() }.value
        let again = try await reopened.chosen()
        #expect(again.dropLast().map(\.look) == chosen.map(\.look))
        #expect(again.last?.look == CategoryLook(icon: "Flower2", color: "#4ADE80"))
    }
}
