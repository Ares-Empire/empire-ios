import Foundation
import Testing
@testable import Aresium

/// A payment's page in plain words (brief 28): no storage values, ISO dates or ids on the screen, in both languages and
/// for both modes' values.
@MainActor
struct PaymentPageTests {
    /// A made-up payment as either backend fills it.
    private func payment(amount: Double = -42.5, bookingDate: String = "2026-10-04", valueDate: String? = nil,
                         categorySource: String? = "starter", categorized: Bool = true,
                         description: String = "Card payment 1234", counterparty: String? = "Sample Market",
                         account: String? = "Giro", iban: String? = nil, source: String = "bank",
                         city: String? = nil, country: String? = nil, trip: String? = nil, tripKind: String? = nil,
                         placeType: String? = nil, recurring: Bool = false) -> TransactionDetail {
        TransactionDetail(
            id: "made-up", place: counterparty ?? description, amount: amount, currency: "EUR", bookingDate: bookingDate,
            valueDate: valueDate, balance: 1420.75, category: "Groceries", categoryColor: "#22c55e", tags: [],
            categorySource: categorySource, categorized: categorized, description: description,
            counterparty: counterparty, account: account, iban: iban, source: source, city: city, country: country,
            trip: trip, tripKind: tripKind, placeType: placeType, recurring: recurring,
            externalId: "fictional-external-id-0000000000000000", raw: .object(["Betrag": .string("-42,50")]))
    }

    @Test func everyCategorySourceInBothLanguages() {
        let english: [String: String] = [
            // Phone mode (`CategorySource`).
            "structural": "A transfer between your own accounts.",
            "learned": "Aresium learned this from a change you made.",
            "starter": "Sorted by Aresium's built-in list.",
            "manual": "You chose this category.",
            // Server mode.
            "rule": "Sorted by a rule.",
            "llm": "Sorted automatically."
        ]
        let german: [String: String] = [
            "structural": "Eine Umbuchung zwischen deinen eigenen Konten.",
            "learned": "Aresium hat das aus einer Änderung von dir gelernt.",
            "starter": "Nach Aresiums eingebauter Liste sortiert.",
            "manual": "Du hast diese Kategorie gewählt.",
            "rule": "Nach einer Regel sortiert.",
            "llm": "Automatisch sortiert."
        ]
        let phone = CategorySource.allCases.map(\.rawValue)
        for source in phone + ["rule", "llm"] {
            #expect(PaymentWording.categoryReason(source, language: .english) == english[source], "\(source)")
            #expect(PaymentWording.categoryReason(source, language: .german) == german[source], "\(source)")
        }
        // Nothing sorted it, or a value this app does not know: no line, never the raw word.
        for source in ["none", "", "magic", "Starter"] {
            #expect(PaymentWording.categoryReason(source, language: .english) == nil, "\(source)")
            #expect(PaymentWording.categoryReason(source, language: .german) == nil, "\(source)")
        }
        #expect(PaymentWording.categoryReason(nil) == nil)
        // A payment that is not sorted gets no reason, whatever the source says.
        #expect(PaymentPage(payment(categorySource: "llm", categorized: false)).categoryReason == nil)
        #expect(PaymentPage(payment(categorySource: "learned"), language: .german).categoryReason
                == "Aresium hat das aus einer Änderung von dir gelernt.")
    }

    @Test func dateIsWrittenOutInBothLanguages() {
        #expect(PaymentWording.date("2026-10-04", language: .english) == "Sunday, 4 October 2026")
        #expect(PaymentWording.date("2026-10-04", language: .german) == "Sonntag, 4. Oktober 2026")
        // A timestamp counts by its day; anything else is no date.
        #expect(PaymentWording.date("2026-02-05T12:34:56Z", language: .english) == "Thursday, 5 February 2026")
        #expect(PaymentWording.date("04.10.2026") == nil && PaymentWording.date(nil) == nil)
        #expect(PaymentPage(payment(), language: .german).date == "Sonntag, 4. Oktober 2026")
        // The top never shows the stored form.
        #expect(!PaymentPage(payment(), language: .english).date.contains("2026-10"))
    }

    @Test func valueDateOnlyWhenItIsAnotherDay() {
        let same = PaymentPage(payment(valueDate: "2026-10-04"), language: .english)
        #expect(!same.rows.contains { $0.label == "Value date" })
        let sameDay = PaymentPage(payment(valueDate: "2026-10-04T08:00:00Z"), language: .english)
        #expect(!sameDay.rows.contains { $0.label == "Value date" })
        #expect(!PaymentPage(payment(valueDate: nil), language: .english).rows.contains { $0.label == "Value date" })
        let other = PaymentPage(payment(valueDate: "2026-10-05"), language: .english)
        #expect(other.rows.first { $0.label == "Value date" }?.value == "Monday, 5 October 2026")
        let german = PaymentPage(payment(valueDate: "2026-10-05"), language: .german)
        #expect(german.rows.first { $0.label == "Wertstellung" }?.value == "Montag, 5. Oktober 2026")
    }

    @Test func otherPartyIsLabelledByDirection() {
        #expect(PaymentWording.otherPartyLabel(amount: -12, language: .english) == "To")
        #expect(PaymentWording.otherPartyLabel(amount: 12, language: .english) == "From")
        #expect(PaymentWording.otherPartyLabel(amount: -12, language: .german) == "An")
        #expect(PaymentWording.otherPartyLabel(amount: 12, language: .german) == "Von")
        #expect(PaymentPage(payment(amount: -9), language: .english).rows.first?.label == "To")
        #expect(PaymentPage(payment(amount: 2450), language: .english).rows.first == DetailRow(label: "From",
                                                                                                value: "Sample Market"))
    }

    @Test func ibanInGroupsOfFour() {
        #expect(PaymentWording.groupedIBAN("DE12345678901234567890") == "DE12 3456 7890 1234 5678 90")
        #expect(PaymentWording.groupedIBAN(" de12 3456 7890 1234 5678 90 ") == "DE12 3456 7890 1234 5678 90")
        #expect(PaymentWording.groupedIBAN("AT611904300234573201") == "AT61 1904 3002 3457 3201")
        #expect(PaymentWording.groupedIBAN("") == nil && PaymentWording.groupedIBAN(nil) == nil)
        let page = PaymentPage(payment(iban: "DE12345678901234567890"))
        #expect(page.account == PaymentPage.Account(name: "Giro", iban: "DE12 3456 7890 1234 5678 90", note: nil))
    }

    @Test func noInternalValuesOnThePage() {
        let detail = payment(categorySource: "starter", placeType: "unknown")
        for language in [AppLanguage.english, .german] {
            let page = PaymentPage(detail, language: language)
            let shown = [page.date, page.categoryReason ?? "", page.originalTitle]
                + page.rows.flatMap { [$0.label, $0.value] }
                + [page.account?.name, page.account?.iban, page.account?.note].compactMap { $0 }
            #expect(!shown.contains { $0.contains(detail.externalId) })
            #expect(!shown.contains { ["External ID", "Externe ID", "Source", "Quelle", "starter", "bank", "unknown",
                                       "2026-10-04"].contains($0) })
        }
    }

    @Test func sourceLineOnlyWhenItTellsSomething() {
        // A bank's payment: the account row names the account, nothing more.
        #expect(PaymentWording.sourceNote("bank", accountName: "Giro") == nil)
        #expect(PaymentPage(payment(source: "bank")).account?.note == nil)
        // PayPal's export without an account name is the PayPal account; with "PayPal" in the name no line either.
        let paypal = PaymentPage(payment(account: nil, source: "paypal"), language: .english)
        #expect(paypal.account == PaymentPage.Account(name: "PayPal", iban: nil, note: nil))
        #expect(PaymentWording.sourceNote("paypal", accountName: "PayPal Konto") == nil)
        // An account named otherwise: say plainly where it came from.
        #expect(PaymentWording.sourceNote("paypal", accountName: "Giro", language: .english) == "From your PayPal file")
        #expect(PaymentWording.sourceNote("paypal", accountName: "Giro", language: .german) == "Aus deiner PayPal-Datei")
        // An unknown source gives no line and never shows itself.
        #expect(PaymentWording.sourceNote("camt", accountName: "Giro") == nil)
        #expect(PaymentPage(payment(account: nil, source: "camt")).account == nil)
        // The bank's own row names the file.
        #expect(PaymentWording.originalTitle("bank", language: .english) == "As in your bank's file")
        #expect(PaymentWording.originalTitle("bank", language: .german) == "So steht es in der Bankdatei")
        #expect(PaymentWording.originalTitle("paypal", language: .english) == "As in your PayPal file")
        #expect(PaymentWording.originalTitle("paypal", language: .german) == "So steht es in der PayPal-Datei")
        #expect(PaymentWording.originalTitle("something", language: .english) == "As in your bank's file")
    }

    @Test func rowsInOrderAndPaymentTextNotRepeated() {
        let page = PaymentPage(payment(valueDate: "2026-10-06"), language: .english)
        #expect(page.rows.map(\.label) == ["To", "Payment text", "Balance after", "Value date"])
        #expect(page.rows.first { $0.label == "Payment text" }?.value == "Card payment 1234")
        let german = PaymentPage(payment(), language: .german)
        #expect(german.rows.map(\.label) == ["An", "Verwendungszweck", "Kontostand danach"])
        #expect(german.rows.first { $0.label == "Kontostand danach" }?.value == "1.420,75\u{a0}€")
        // The text that is already the title (no other party, or the same words) is not repeated.
        let title = PaymentPage(payment(description: "Sample Market", counterparty: nil), language: .english)
        #expect(title.rows.map(\.label) == ["Balance after"])
        let same = PaymentPage(payment(description: "SAMPLE MARKET ", counterparty: "Sample Market"), language: .english)
        #expect(!same.rows.contains { $0.label == "Payment text" })
    }

    @Test func serverRowsWithoutRawValues() {
        // Location: the country code written out; a code the locale does not know is left out.
        #expect(PaymentWording.location(city: "Hamburg", country: "DE", language: .english) == "Hamburg, Germany")
        #expect(PaymentWording.location(city: "Hamburg", country: "DE", language: .german) == "Hamburg, Deutschland")
        #expect(PaymentWording.location(city: "Wien", country: "XQ", language: .english) == "Wien")
        #expect(PaymentWording.location(city: nil, country: "AT", language: .german) == "Österreich")
        #expect(PaymentWording.location(city: " ", country: nil) == nil)
        // Trip: the server's label with the month written out, and how long it was.
        #expect(PaymentWording.trip("Hamburg, DE (2026-02)", kind: "vacation", language: .english)
                == "Hamburg, Germany · February 2026 · several days")
        #expect(PaymentWording.trip("Hamburg, DE (2026-02)", kind: "travel", language: .german)
                == "Hamburg, Deutschland · Februar 2026 · ein Tag")
        #expect(PaymentWording.trip("?, AT (2026-03)", kind: "odd", language: .english) == "Austria · March 2026")
        #expect(PaymentWording.trip("Ski week", kind: nil) == "Ski week")
        #expect(PaymentWording.trip(nil, kind: "travel") == nil && PaymentWording.trip("", kind: nil) == nil)
        // Kind of place: only the known ones.
        let known = ["restaurant", "cafe", "bar", "museum", "attraction", "entertainment", "pharmacy", "health",
                     "groceries", "supermarket", "bakery", "clothes", "personal_care", "fuel", "hotel", "fitness"]
        for value in known {
            #expect(PaymentWording.placeType(value, language: .english) != nil, "\(value)")
            #expect(PaymentWording.placeType(value, language: .german) != nil, "\(value)")
            #expect(PaymentWording.placeType(value, language: .english) != value, "\(value)")
        }
        #expect(PaymentWording.placeType("supermarket", language: .german) == "Supermarkt")
        #expect(PaymentWording.placeType("personal_care", language: .english) == "Hairdresser or beauty")
        for value in ["unknown", "nightclub", "", "theatre"] { #expect(PaymentWording.placeType(value) == nil, "\(value)") }
        #expect(PaymentWording.placeType(nil) == nil)
        // Phone mode fills none of them: no server rows there.
        let phone = PaymentPage(payment(), language: .english)
        #expect(!phone.rows.contains { ["Location", "Trip", "Kind of place", "Recurring"].contains($0.label) })
        let server = PaymentPage(payment(city: "Hamburg", country: "DE", placeType: "bakery", recurring: true),
                                 language: .german)
        #expect(server.rows.suffix(3).map(\.label) == ["Ort", "Art des Orts", "Wiederkehrend"])
        #expect(server.rows.suffix(3).map(\.value) == ["Hamburg, Deutschland", "Bäckerei", "Ja"])
    }
}
