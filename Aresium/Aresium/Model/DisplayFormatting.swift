import Foundation

// Match panels.jsx: whole euros for totals, two decimals without a currency sign for activities.
enum Money {
    static func total(_ value: Double) -> String { "€" + formatted(value, digits: 0) }
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

enum ChartAxis {
    static func ticks(_ points: [ChartPoint]) -> [Int] {
        if points.count <= 12 { return points.map(\.index) }
        return points.enumerated().filter {
            $0.offset.isMultiple(of: 5) || $0.offset == points.count - 1
        }.map(\.element.index)
    }
}

enum CategorySymbol {
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
        "Utensils": "fork.knife", "Wallet": "wallet.bifold"
    ]
}
