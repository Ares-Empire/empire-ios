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
    /// Whether the app has a symbol for this icon name (else it draws the tag).
    static func knows(_ icon: String) -> Bool { symbols[icon] != nil }
    private static let symbols = [
        "Beer": "mug", "CircleHelp": "questionmark.circle", "Code": "chevron.left.forwardslash.chevron.right",
        "Dumbbell": "dumbbell", "GraduationCap": "graduationcap", "Handshake": "hands.clap",
        "House": "house", "Laptop": "laptopcomputer", "Palmtree": "tree", "Pill": "pills",
        "Receipt": "receipt", "Repeat": "repeat", "RotateCcw": "arrow.counterclockwise",
        "Scissors": "scissors", "Shirt": "tshirt", "ShoppingBag": "bag", "ShoppingCart": "cart",
        "SprayCan": "bubbles.and.sparkles", "Tag": "tag", "TrainFront": "tram",
        "TrendingUp": "chart.line.uptrend.xyaxis", "Tv": "tv", "Users": "person.2",
        "Trash2": "trash", "Utensils": "fork.knife", "Wallet": "wallet.bifold",
        // The default categories of Aresium for other people (aresium/src/engine/categories.ts → CATEGORY_LOOK).
        "Baby": "figure.child", "Banknote": "banknote", "BookOpen": "book", "Briefcase": "briefcase",
        "CarTaxiFront": "car", "Coffee": "cup.and.saucer", "Coins": "eurosign.circle", "Ellipsis": "ellipsis.circle",
        "Fuel": "fuelpump", "Gift": "gift", "HandHeart": "heart", "HeartHandshake": "figure.2.and.child.holdinghands",
        "Landmark": "building.columns", "Package": "shippingbox", "Palette": "paintpalette", "PawPrint": "pawprint",
        "Percent": "percent", "Plane": "airplane", "Shield": "shield", "Smartphone": "iphone", "Sofa": "sofa",
        "Ticket": "ticket", "Zap": "bolt",
        // One's own categories (brief 36, `OwnCategoryLook` in the app): icons that fit a name, then the spare marks.
        "Bike": "bicycle", "Book": "book.closed", "Cake": "birthday.cake", "Camera": "camera", "Car": "car.side",
        "Cat": "cat", "Dice5": "die.face.5", "Dog": "dog", "Drama": "theatermasks", "Film": "film",
        "Flower2": "camera.macro", "Gamepad2": "gamecontroller", "Glasses": "eyeglasses", "Guitar": "guitars",
        "Hammer": "hammer", "Headphones": "headphones", "Lamp": "lamp.desk", "Luggage": "suitcase.rolling",
        "Mountain": "mountain.2", "Music": "music.note", "PartyPopper": "party.popper", "Popcorn": "popcorn",
        "Puzzle": "puzzlepiece", "Sparkles": "sparkles", "Sprout": "leaf", "Stethoscope": "stethoscope",
        "Tent": "tent", "Trophy": "trophy", "Waves": "water.waves", "Wine": "wineglass",
        "Wrench": "wrench.and.screwdriver",
        "Bell": "bell", "Bookmark": "bookmark", "Diamond": "diamond", "Flag": "flag", "Hexagon": "hexagon",
        "Key": "key", "Lightbulb": "lightbulb", "Shapes": "square.on.circle", "Star": "star"
    ]
}
