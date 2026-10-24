import Foundation

// Match panels.jsx: whole euros for totals, two decimals without a currency sign for activities. In the app's language:
// "€1,339" / "1.339 €", "−12.40" / "−12,40".
nonisolated enum Money {
    static func total(_ value: Double, language: AppLanguage = .current) -> String {
        euros(formatted(value, digits: 0, language: language), language)
    }
    static func precise(_ value: Double, language: AppLanguage = .current) -> String {
        euros(formatted(value, digits: 2, language: language), language)
    }
    static func transaction(_ value: Double, language: AppLanguage = .current) -> String {
        (value < 0 ? "−" : "+") + formatted(abs(value), digits: 2, language: language)
    }
    private static func euros(_ amount: String, _ language: AppLanguage) -> String {
        language == .german ? amount + "\u{a0}€" : "€" + amount
    }
    private static func formatted(_ value: Double, digits: Int, language: AppLanguage) -> String {
        let formatter = NumberFormatter()
        formatter.locale = language.locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

nonisolated enum CategorySymbol {
    static func name(for icon: String) -> String {
        symbols[icon] ?? "tag"
    }
    private static let symbols = [
        "Beer": "mug", "CircleHelp": "questionmark.circle", "Code": "chevron.left.forwardslash.chevron.right",
        "Dumbbell": "dumbbell", "GraduationCap": "graduationcap", "Handshake": "hands.clap",
        "House": "house", "Laptop": "laptopcomputer", "Palmtree": "tree", "Pill": "pills",
        "Receipt": "receipt", "Repeat": "repeat", "RotateCcw": "arrow.counterclockwise",
        "Scissors": "scissors", "Shirt": "tshirt", "ShoppingBag": "bag", "ShoppingCart": "cart",
        "SprayCan": "bubbles.and.sparkles", "Tag": "tag", "TrainFront": "tram",
        "TrendingUp": "chart.line.uptrend.xyaxis", "Tv": "tv", "Users": "person.2",
        "Trash2": "trash", "Utensils": "fork.knife", "Wallet": "wallet.bifold"
    ]
}
