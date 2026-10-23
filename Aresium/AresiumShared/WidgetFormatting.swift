import Foundation

// Match panels.jsx: whole euros for totals, two decimals without a currency sign for activities.
nonisolated enum Money {
    static func total(_ value: Double) -> String { "€" + formatted(value, digits: 0) }
    static func precise(_ value: Double) -> String { "€" + formatted(value, digits: 2) }
    static func transaction(_ value: Double) -> String {
        (value < 0 ? "−" : "+") + formatted(abs(value), digits: 2)
    }
    private static func formatted(_ value: Double, digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
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
