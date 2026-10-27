import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Aresium

/// What phone mode's screens show (brief 18): "Uncategorised" in the app's words, the column check's rows and formats,
/// the import line in German, the untick question's looks, the shop list's licence notice and the MT940 share type.
@MainActor
struct PhoneLookTests {
    // MARK: Uncategorised

    @Test func uncategorisedIsShownAsNotSorted() {
        #expect(CategoryName.shown("Uncategorised", language: .english) == "Not sorted")
        #expect(CategoryName.shown("Uncategorised", language: .german) == "Nicht sortiert")
        #expect(CategoryName.shown("Groceries", language: .german) == "Groceries")
        #expect(CategoryName.shown("uncategorised", language: .english) == "uncategorised")
    }

    @Test func theDashboardKeepsTheRealName() throws {
        // The phone's dashboard and a payment's detail use the dashboard's own name; only the screens translate it.
        let category = Category(name: CategoryName.uncategorised, icon: "CircleHelp", color: "#9ca3af", kind: .spend)
        #expect(category.name == "Uncategorised" && category.id == "Uncategorised")
        #expect(PhoneDashboard.uncategorised.name == CategoryName.uncategorised)
    }

    // MARK: the column check

    @Test func previewRowsReadTheDateAndWhoPaid() {
        let payment = BankTxn(externalId: "x", bookingDate: "2026-10-03T00:00:00.000Z", amount: "-12.30", currency: "EUR",
                              description: "Brötchen", counterparty: "Fiktiv Bäckerei")
        let english = PreviewPayment(payment, language: .english)
        #expect(english.day == 3 && english.date == "3 Oct 2026")
        #expect(english.title == "Fiktiv Bäckerei" && english.detail == "Brötchen" && english.amount == -12.3)
        #expect(PreviewPayment(payment, language: .german).date == "3. Okt. 2026")

        let textOnly = BankTxn(externalId: "y", bookingDate: "2026-10-04", amount: "1181.60", currency: "EUR",
                               description: "Gehalt", counterparty: " ")
        let row = PreviewPayment(textOnly, language: .english)
        #expect(row.title == "Gehalt" && row.detail == nil && row.amount == 1181.6 && row.day == 4)

        let odd = BankTxn(externalId: "z", bookingDate: "unknown", amount: "x", currency: "EUR", description: "Text")
        let unread = PreviewPayment(odd, language: .english)
        #expect(unread.day == nil && unread.date == "unknown" && unread.amount == 0)
    }

    @Test func formatsAreShownAsExamples() {
        #expect(LayoutDraft.dateFormats.map(LayoutDraft.example(of:))
                == ["31.12.2026", "31.12.26", "2026-12-31", "31/12/2026", "12/31/2026", "31-12-2026", "20261231"])
        #expect(LayoutDraft.numberFormats.map(LayoutDraft.example(ofNumberFormat:)) == ["1.234,56", "1,234.56"])
    }

    // MARK: words

    @Test func theImportLineInGerman() {
        let result = PhoneImportResult(name: "Umsaetze.csv", added: 42, already: 3, sorted: 38, waiting: 4)
        #expect(ImportWording.summary([result], language: .english) == "42 new · 3 already there · 38 sorted · 4 not sorted")
        #expect(ImportWording.summary([result], language: .german) == "42 neu · 3 schon da · 38 sortiert · 4 nicht sortiert")
    }

    @Test func theUntickQuestionCarriesTheLooks() async throws {
        let phone = try await PhoneTest.backend(chosen: ["groceries", "rent"])
        _ = try await phone.importFiles([PhoneTest.vrBank([("01.10.2026", "REWE Markt GmbH", "REWE", -2000)])],
                                        auth: BackendAuth(token: nil))
        let picker = CategoryPickerModel(phone: phone) {}
        await picker.load()
        await picker.toggle("groceries")
        let untick = try #require(picker.untick)
        let catalog = try await PhoneTest.engine().catalog()
        #expect(untick.look == catalog.look("groceries") && untick.notSortedLook == catalog.look(CategoryCatalog.notSorted))
        #expect(untick.targets.map(\.look) == [catalog.look("rent")])
    }

    // MARK: About and the share sheet

    @Test func shipsTheShopListsLicenceNotice() throws {
        let licence = BundledLicence.shopList()
        #expect(licence.name == "name-suggestion-index" && licence.licenceName == "BSD-3-Clause")
        let text = try #require(licence.text())
        let paragraphs = LicenceParagraph.paragraphs(text)
        #expect(paragraphs.first?.text == "Copyright 2026, name-suggestion-index contributors")
        #expect(paragraphs.contains { $0.text.hasPrefix("Redistribution and use in source and binary forms") })
        #expect(paragraphs.last?.text.hasSuffix("EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.") == true)
        // The notice is the one the bundled shop list carries (scripts/aresium-engine.sh writes both): every line of
        // the licence is in the engine bundle.
        let engineURL = try #require(Bundle.main.url(forResource: "aresium-engine", withExtension: "js"))
        let engine = try String(contentsOf: engineURL, encoding: .utf8).replacingOccurrences(of: "\\\"", with: "\"")
        for paragraph in paragraphs where !paragraph.text.hasPrefix("Aresium sorts payments") {
            #expect(engine.contains(paragraph.text), "not in the engine's shop list: \(paragraph.text.prefix(40))")
        }
    }

    @Test func theShareSheetOffersAresiumForMT940() throws {
        let info = try #require(Bundle.main.infoDictionary)
        let imported = try #require(info["UTImportedTypeDeclarations"] as? [[String: Any]])
        let mt940 = try #require(imported.first { $0["UTTypeIdentifier"] as? String == UTType.mt940.identifier })
        let tags = try #require(mt940["UTTypeTagSpecification"] as? [String: Any])
        #expect(tags["public.filename-extension"] as? [String] == ["sta", "mt940"])
        let documents = try #require(info["CFBundleDocumentTypes"] as? [[String: Any]])
        let types = documents.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        #expect(types.contains(UTType.mt940.identifier))
        #expect(!types.contains(UTType.plainText.identifier) && !types.contains(UTType.text.identifier))
        #expect(PhoneImportTypes.all.contains(.mt940) && UTType.mt940.conforms(to: .plainText))
    }
}
