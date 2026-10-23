import Foundation

struct Dashboard: Codable {
    let version: Int
    let months: [Month]
    let categories: [Category]
    let incomeBuckets: [Category]
    let transactions: [Transaction]
    let overview: Overview
    let total: Totals
    let byMonth: [String: MonthData]
    let spend: [String: Series]
    let income: [String: Series]
    let pick: CategoryChoices

    static func decode(_ data: Data) throws -> Dashboard {
        let dashboard = try JSONDecoder().decode(Dashboard.self, from: data)
        guard dashboard.version == 2 else { throw DashboardError.unsupportedVersion }
        return dashboard
    }

    static func sample() throws -> Dashboard {
        guard let url = Bundle.main.url(forResource: "dashboard.sample", withExtension: "json") else {
            throw DashboardError.missingSample
        }
        return try decode(Data(contentsOf: url))
    }
}

struct CategoryChoices: Codable {
    let spend: [String]
    let income: [String]
}

extension Dashboard {
    func recategorisationChoices(amount: Double) -> [Category] {
        (amount > 0 ? pick.income : pick.spend).compactMap { name in
            categories.first { $0.name == name }
        }
    }
}

struct Month: Codable, Identifiable {
    let key: String
    let label: String
    let short: String
    let year: Int
    let month: Int
    let days: Int
    let partial: Bool
    var id: String { key }
}

struct Category: Codable, Identifiable {
    enum Kind: String, Codable { case spend, income, transfer }
    let name: String
    let icon: String
    let color: String
    let kind: Kind
    var id: String { name }
}

struct Transaction: Codable, Identifiable {
    let id: String
    let date: String
    let day: Int
    let month: String
    let amount: Double
    let categoryName: String
    let tags: [String]
    let place: String
    let city: String
    let categoriesIn: [String]
    let incomeBuckets: [String]
}

struct Overview: Codable {
    let expense: [Double]
    let income: [Double]
    let balance: [Double]
}

struct CategoryTotal: Codable, Identifiable {
    let name: String
    let total: Double
    var id: String { name }
}

struct Totals: Codable {
    let expense: Double
    let income: Double
    let categories: [CategoryTotal]
    let incomeBuckets: [CategoryTotal]
}

struct MonthData: Codable {
    let expense: Double
    let income: Double
    let categories: [CategoryTotal]
    let incomeBuckets: [CategoryTotal]
    let endBalance: Double
    let dayExpense: [Double]
    let dayIncome: [Double]
    let dayBalance: [Double]

    var totals: Totals {
        Totals(expense: expense, income: income, categories: categories, incomeBuckets: incomeBuckets)
    }
}

struct Series: Codable {
    let months: [Double]
    let days: [String: [Double]]
}

enum DashboardError: LocalizedError {
    case unsupportedVersion, missingSample
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "This dashboard version is not supported."
        case .missingSample: "The bundled sample dashboard is missing."
        }
    }
}
