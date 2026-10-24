import Foundation

struct TransactionDetail: Codable {
    var id: String
    var place: String
    var amount: Double
    let currency: String
    var bookingDate: String
    let valueDate: String?
    let balance: Double?
    let category: String
    let categoryColor: String
    let tags: [String]
    let categorySource: String?
    let categorized: Bool
    let description: String
    let counterparty: String?
    let account: String?
    let iban: String?
    let source: String
    let city: String?
    let country: String?
    let trip: String?
    let tripKind: String?
    let placeType: String?
    let recurring: Bool
    let externalId: String
    let raw: JSONValue

    var signedAmount: String {
        Money.transaction(amount) + (currency.isEmpty || currency == "EUR" ? "" : " " + currency)
    }

    var accountLabel: String? {
        guard let account, !account.isEmpty else { return nil }
        return account + ((iban?.isEmpty == false) ? " · \(iban!)" : "")
    }

    var rows: [DetailRow] {
        let location = [city, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        let tripLabel = trip.map { $0 + ((tripKind?.isEmpty == false) ? " (\(tripKind!))" : "") }
        return [
            DetailRow(label: String(localized: "Source"), value: source),
            DetailRow(label: String(localized: "Booking date"), value: bookingDate),
            DetailRow(label: String(localized: "Value date"), value: valueDate),
            DetailRow(label: String(localized: "Balance after"), value: balance.map { Money.precise($0) }),
            DetailRow(label: String(localized: "Counterparty"), value: counterparty),
            DetailRow(label: String(localized: "Description"), value: description),
            DetailRow(label: String(localized: "Location"), value: location),
            DetailRow(label: String(localized: "Trip"), value: trip?.isEmpty == false ? tripLabel : nil),
            DetailRow(label: String(localized: "Place type"), value: placeType == "unknown" ? nil : placeType),
            DetailRow(label: String(localized: "Recurring"), value: recurring ? String(localized: "Yes") : nil),
            DetailRow(label: String(localized: "External ID"), value: externalId)
        ].filter { !$0.value.isEmpty }
    }

    var originalRows: [DetailRow]? {
        switch raw {
        case let .object(values):
            values.keys.sorted().map { DetailRow(label: $0, value: values[$0]!.displayValue) }
        case let .array(values):
            values.enumerated().map { DetailRow(label: String($0.offset), value: $0.element.displayValue) }
        default: nil
        }
    }

    static func sample(for transaction: Transaction) throws -> TransactionDetail {
        var detail = try bundledSample()
        detail.id = transaction.id
        detail.place = transaction.place
        detail.amount = transaction.amount
        detail.bookingDate = transaction.date
        return detail
    }

    static func bundledSample() throws -> TransactionDetail {
        guard let url = Bundle.main.url(forResource: "transaction-detail.sample", withExtension: "json") else {
            throw DashboardError.missingSample
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}

struct DetailRow: Identifiable {
    let label: String
    let value: String
    var id: String { label }
    init(label: String, value: String?) { self.label = label; self.value = value ?? "" }
}

// `raw` is the service's arbitrary JSON export row, not a fixed bank schema.
enum JSONValue: Codable, Equatable {
    case null, string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    var displayValue: String {
        switch self {
        case .null, .string(""): "—"
        case let .string(value): value
        case let .number(value): NSNumber(value: value).stringValue
        case let .bool(value): value ? "true" : "false"
        case .array, .object:
            String(decoding: (try? JSONEncoder().encode(self)) ?? Data(), as: UTF8.self)
        }
    }
}
