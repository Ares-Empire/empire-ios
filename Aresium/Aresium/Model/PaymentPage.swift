import Foundation

/// How a payment's page reads (`TransactionDetailSheet`): the stored values of both modes in plain words in the app's
/// language. Phone mode and server mode store different values (the category source, the server's place types); a value
/// this page does not know gives no line, so nothing internal (storage words, ISO dates, ids) reaches the screen.
/// The data and the backends stay as they are; only this type decides how they read.
struct PaymentPage {
    /// The account the payment was booked on: its name, its IBAN in groups of four, and a line on where it came from
    /// when the name does not say so already.
    struct Account: Equatable {
        let name: String?
        let iban: String?
        let note: String?
    }

    /// The booking date written out ("Sunday, 4 October 2026" / "Sonntag, 4. Oktober 2026").
    let date: String
    /// Why the payment is in its category, as one short sentence; nil when there is nothing to say.
    let categoryReason: String?
    let account: Account?
    /// The plain rows under the account: the other party, the payment text, the balance after it, the value date, and
    /// the server's own rows (location, trip, kind of place, recurring), each only when it says something.
    let rows: [DetailRow]
    /// The title of the bank's own row (the disclosure), closed by default.
    let originalTitle: String

    init(_ detail: TransactionDetail, language: AppLanguage = .current) {
        let words = PaymentWording.self
        date = words.date(detail.bookingDate, language: language) ?? detail.bookingDate
        categoryReason = detail.categorized ? words.categoryReason(detail.categorySource, language: language) : nil
        let name = words.accountName(detail.account, source: detail.source)
        let iban = words.groupedIBAN(detail.iban)
        let note = words.sourceNote(detail.source, accountName: name, language: language)
        account = name == nil && iban == nil && note == nil ? nil : Account(name: name, iban: iban, note: note)
        originalTitle = words.originalTitle(detail.source, language: language)

        let text = detail.description.trimmingCharacters(in: .whitespacesAndNewlines)
        // The bank's name too (under an own name, brief 44): a payment text that only repeats it says nothing new.
        let repeated = [detail.place, detail.bankName ?? "", detail.counterparty ?? ""].contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(text) == .orderedSame
        }
        rows = [
            DetailRow(label: words.otherPartyLabel(amount: detail.amount, language: language),
                      value: detail.counterparty?.trimmingCharacters(in: .whitespacesAndNewlines)),
            DetailRow(label: language.string("Payment text"), value: repeated ? nil : text),
            DetailRow(label: language.string("Balance after"),
                      value: detail.balance.map { Money.precise($0, language: language) }),
            DetailRow(label: language.string("Value date"),
                      value: words.valueDate(detail.valueDate, booked: detail.bookingDate, language: language)),
            DetailRow(label: language.string("Location"),
                      value: words.location(city: detail.city, country: detail.country, language: language)),
            DetailRow(label: language.string("Trip"),
                      value: words.trip(detail.trip, kind: detail.tripKind, language: language)),
            DetailRow(label: language.string("Kind of place"), value: words.placeType(detail.placeType, language: language)),
            DetailRow(label: language.string("Recurring"), value: detail.recurring ? language.string("Yes") : nil)
        ].filter { !$0.value.isEmpty }
    }
}

/// The page's words for single stored values, each a pure function of the value and the language.
nonisolated enum PaymentWording {
    /// Why a payment is in its category. Phone mode stores `structural | learned | starter | manual | receipt | none`
    /// (`CategorySource`), the server `rule | llm | manual`; `manual` means the same in both. `none`, an empty or an
    /// unknown value gives nil (the chip already says Not sorted when nothing sorted it).
    static func categoryReason(_ source: String?, language: AppLanguage = .current) -> String? {
        switch source {
        // Phone mode (`CategorySource`).
        case "structural": language.string("A transfer between your own accounts.")
        case "learned": language.string("Aresium learned this from a change you made.")
        case "starter": language.string("Sorted by Aresium's built-in list.")
        case "receipt": language.string("Sorted by its receipt.")
        // Both modes.
        case "manual": language.string("You chose this category.")
        // Server mode (aresium `src/data/queries.ts` → `getTransactionDetail`).
        case "rule": language.string("Sorted by a rule.")
        case "llm": language.string("Sorted automatically.")
        default: nil
        }
    }

    /// A stored day (`YYYY-MM-DD`, or a timestamp whose first ten characters are the day) written out in the app's
    /// language: "Sunday, 4 October 2026" / "Sonntag, 4. Oktober 2026". nil when it is not a day.
    static func date(_ value: String?, language: AppLanguage = .current) -> String? {
        guard let day = day(value) else { return nil }
        let calendar = WidgetFormatting.calendar
        return day.formatted(Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale, calendar: calendar,
                                              timeZone: calendar.timeZone).weekday(.wide).day().month(.wide).year())
    }

    /// The value date, written out, only when it is another day than the booking date (most payments: the same day).
    static func valueDate(_ value: String?, booked: String, language: AppLanguage = .current) -> String? {
        guard let valueDay = day(value), valueDay != day(booked) else { return nil }
        return date(value, language: language)
    }

    /// The other party's row: who got the money ("To") or who sent it ("From").
    static func otherPartyLabel(amount: Double, language: AppLanguage = .current) -> String {
        amount < 0 ? language.string("To") : language.string("From")
    }

    /// An IBAN in groups of four, as banks print it: "DE12 3456 7890 1234 5678 90". nil when there is none.
    static func groupedIBAN(_ iban: String?) -> String? {
        let compact = (iban ?? "").filter { !$0.isWhitespace }.uppercased()
        guard !compact.isEmpty else { return nil }
        return stride(from: 0, to: compact.count, by: 4).map { start in
            let from = compact.index(compact.startIndex, offsetBy: start)
            let to = compact.index(from, offsetBy: 4, limitedBy: compact.endIndex) ?? compact.endIndex
            return String(compact[from..<to])
        }.joined(separator: " ")
    }

    /// The account's name; a PayPal export without one is the PayPal account.
    static func accountName(_ name: String?, source: String) -> String? {
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        return source == "paypal" ? "PayPal" : nil
    }

    /// Where the payment came from, said only when it tells something: a payment from a PayPal export on an account whose
    /// name does not say PayPal. A bank's payment, or an unknown source, gives nil (the account row names the account).
    static func sourceNote(_ source: String, accountName: String?, language: AppLanguage = .current) -> String? {
        guard source == "paypal", accountName?.localizedCaseInsensitiveContains("paypal") != true else { return nil }
        return language.string("From your PayPal file")
    }

    /// The title of the bank's own row: the file the payment was read from.
    static func originalTitle(_ source: String, language: AppLanguage = .current) -> String {
        source == "paypal" ? language.string("As in your PayPal file") : language.string("As in your bank's file")
    }

    /// The server's location (city and a two-letter country code): "Hamburg, Germany" / "Hamburg, Deutschland". A
    /// country the locale does not know is left out.
    static func location(city: String?, country: String?, language: AppLanguage = .current) -> String? {
        let parts = [city?.trimmingCharacters(in: .whitespacesAndNewlines), countryName(country, language: language)]
            .compactMap { $0 }.filter { !$0.isEmpty && $0 != "?" }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// The server's trip: its label ("Hamburg, DE (2026-02)", aresium `src/enrich/trips.ts`) with the country and the
    /// month written out, and how long it was (`vacation`: several days away, `travel`: one day). A label of another
    /// shape is the server's name for the trip and stays as it is; an unknown kind is left out.
    static func trip(_ label: String?, kind: String?, language: AppLanguage = .current) -> String? {
        let label = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !label.isEmpty else { return nil }
        var parts = [label]
        if let match = label.wholeMatch(of: /(.+?)(?:, ([A-Z]{2}))? \((\d{4})-(\d{2})\)/),
           let month = WidgetFormatting.monthDate("\(match.3)-\(match.4)") {
            let calendar = WidgetFormatting.calendar
            // The server writes "?" for a trip without a city.
            let place = [String(match.1), countryName(match.2.map(String.init), language: language)]
                .compactMap { $0 }.filter { $0 != "?" }
            parts = [place.joined(separator: ", "),
                     month.formatted(Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale,
                                                      calendar: calendar, timeZone: calendar.timeZone).month(.wide).year())]
        }
        switch kind {
        case "vacation": parts.append(language.string("several days"))
        case "travel": parts.append(language.string("one day"))
        default: break
        }
        return parts.joined(separator: " · ")
    }

    /// What the server found the place to be (aresium `src/enrich/places.ts` → `TYPE_MAP`; `supermarket` from its
    /// sample). Only the known ones are shown; `unknown`, OpenStreetMap's other words and nothing give nil.
    static func placeType(_ value: String?, language: AppLanguage = .current) -> String? {
        switch value {
        case "restaurant": language.string("Restaurant")
        case "cafe": language.string("Café")
        case "bar": language.string("Bar")
        case "museum": language.string("Museum or gallery")
        case "attraction": language.string("Sight")
        case "entertainment": language.string("Theatre or cinema")
        case "pharmacy": language.string("Pharmacy")
        case "health": language.string("Doctor or clinic")
        case "groceries": language.string("Food shop")
        case "supermarket": language.string("Supermarket")
        case "bakery": language.string("Bakery")
        case "clothes": language.string("Clothes shop")
        case "personal_care": language.string("Hairdresser or beauty")
        case "fuel": language.string("Petrol station")
        case "hotel": language.string("Hotel")
        case "fitness": language.string("Gym")
        default: nil
        }
    }

    /// A two-letter country code's name in the app's language; nil for anything else.
    private static func countryName(_ code: String?, language: AppLanguage) -> String? {
        guard let code, code.count == 2, code.allSatisfy({ $0.isASCII && $0.isUppercase }) else { return nil }
        return language.locale.localizedString(forRegionCode: code)
    }

    private static func day(_ value: String?) -> Date? {
        guard let value, value.count >= 10 else { return nil }
        return WidgetFormatting.date(String(value.prefix(10)))
    }
}
