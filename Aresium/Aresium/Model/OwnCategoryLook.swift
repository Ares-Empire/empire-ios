import Foundation

/// The look of a category of one's own (brief 36, Patrik's first phone test, 2026-10-30): the engine gives every one
/// the same grey tag (`CUSTOM_CATEGORY_LOOK`), so they all looked alike. Now each gets an icon and a colour when it is
/// made, chosen here on the iPhone (nothing is sent anywhere), and kept with it (`StoredChosen.icon`/`color`), so it
/// never changes afterwards:
/// - **the icon** fits the name when a word of it is known (`meanings`, English and German: "Fitness" a dumbbell,
///   "Haustier" a paw), else it is the first of `spareIcons` that no other own category has. Two own categories share
///   an icon only once every fitting and spare icon is taken.
/// - **the colour** is the first of `colors` that no other own category has (once all are taken, the least used one):
///   bright colours of the dashboard's palette that the default categories do not use.
/// Icons are named as the engine names its own (Lucide names) and become SF Symbols in `CategorySymbol`, like the
/// default categories' icons, so the dashboard, the widget and every list draw them the same way.
nonisolated enum OwnCategoryLook {
    /// A kind of category the name may be about.
    struct Meaning: Sendable {
        /// Word beginnings (folded: lower case, no accents, "ß" as "ss"): "garten" fits "Garten" and "Gartenarbeit".
        let stems: [String]
        /// Whole words only, for short ones that begin other words ("car" fits "Car", not "Card").
        var words: [String] = []
        /// Its icons, the best first; the next one when another own category has the first.
        let icons: [String]
    }

    /// The known words. A name's known words are tried in their order; within one word the longest match first (so
    /// "Spielzeug" is a toy, not a game). Stems are word beginnings only, never word ends: German compounds would
    /// otherwise make "Transport" a sport and "Preise" a trip.
    static let meanings: [Meaning] = [
        // Sport and fitness
        Meaning(stems: ["fitness", "sport", "training", "workout", "kraftsport", "kampfsport", "fußball", "football",
                        "soccer", "tennis", "golf", "badminton", "volleyball", "basketball", "handball", "yoga",
                        "pilates", "laufen", "running", "jogging"],
                words: ["gym", "gyms"], icons: ["Dumbbell", "Trophy"]),
        Meaning(stems: ["kletter", "climb", "boulder", "bergsteig", "skifahr", "skiurlaub", "snowboard"],
                words: ["ski", "skiing", "berge", "mountains"], icons: ["Mountain"]),
        Meaning(stems: ["wander", "hiking", "camping", "zelt", "outdoor"], words: ["hike", "hikes"],
                icons: ["Tent", "Mountain"]),
        Meaning(stems: ["schwimm", "swim", "sauna", "therme"], icons: ["Waves"]),
        Meaning(stems: ["fahrrad", "radfahr", "radsport", "bicycle", "cycling", "ebike"],
                words: ["bike", "bikes", "rad", "velo"], icons: ["Bike"]),
        // Animals
        Meaning(stems: ["haustier", "tierarzt", "tierbedarf", "tierfutter", "futter"],
                words: ["tier", "tiere", "pet", "pets", "vet"], icons: ["PawPrint"]),
        Meaning(stems: ["hunde", "dogs"], words: ["hund", "dog", "doggy"], icons: ["Dog", "PawPrint"]),
        Meaning(stems: ["katze", "kitten"], words: ["kater", "cat", "cats", "kitty"], icons: ["Cat", "PawPrint"]),
        // Food and drink
        Meaning(stems: ["kaffee", "coffee", "café", "espresso", "cappuccino", "starbucks", "barista"],
                words: ["tee", "tea"], icons: ["Coffee"]),
        Meaning(stems: ["wein", "wine", "cocktail", "alkohol", "alcohol", "spirituosen", "drinks"], words: ["drink"],
                icons: ["Wine"]),
        Meaning(stems: ["lieferando", "lieferdienst", "takeaway", "delivery", "pizza", "döner", "burger", "sushi",
                        "mensa", "kantine", "canteen", "lunch", "mittagessen", "abendessen"],
                icons: ["Utensils"]),
        // Celebrations
        Meaning(stems: ["geburtstag", "birthday", "kuchen", "cake"], icons: ["Cake", "PartyPopper"]),
        Meaning(stems: ["party", "partys", "feier", "hochzeit", "wedding", "festival", "silvester"],
                words: ["fest", "feste", "parties"], icons: ["PartyPopper", "Cake"]),
        Meaning(stems: ["geschenk", "gift", "weihnacht", "christmas", "xmas", "mitbringsel"],
                words: ["present", "presents"], icons: ["Gift"]),
        // Getting around
        Meaning(stems: ["auto", "kfz", "werkstatt", "parken", "parkhaus", "parkplatz", "parking", "carsharing"],
                words: ["car", "cars", "pkw", "tüv"], icons: ["Car"]),
        Meaning(stems: ["reise", "dienstreise", "geschäftsreise", "urlaub", "travel", "holiday", "vacation", "ferien",
                        "hotel", "flug", "flight", "trip", "backpacking", "airbnb"],
                icons: ["Luggage", "Plane"]),
        // Family and home
        Meaning(stems: ["kinder", "kita", "baby", "babys", "babies", "spielzeug", "toys", "windel", "diaper"],
                words: ["kind", "kids", "kid", "children", "child", "sohn", "tochter", "son", "daughter", "toy"],
                icons: ["Baby"]),
        Meaning(stems: ["garten", "garden", "pflanze", "plant", "blume", "flower", "balkon", "gärtner"],
                icons: ["Flower2", "Sprout"]),
        Meaning(stems: ["heimwerk", "baumarkt", "werkzeug", "renovier", "reparatur", "repair", "tools", "handwerk"],
                words: ["diy"], icons: ["Hammer", "Wrench"]),
        Meaning(stems: ["möbel", "moebel", "furniture", "einrichtung", "deko", "decor", "ikea"], icons: ["Lamp", "Sofa"]),
        Meaning(stems: ["umzug", "umziehen", "moving"], icons: ["Package"]),
        Meaning(stems: ["freundeskreis", "kumpels"], words: ["freunde", "friends"], icons: ["Users"]),
        // Free time
        Meaning(stems: ["musik", "music", "konzert", "concert", "spotify", "gitarre", "guitar", "klavier", "piano",
                        "gesang", "singing"],
                words: ["band", "chor", "choir", "vinyl"], icons: ["Music", "Headphones", "Guitar"]),
        Meaning(stems: ["spiel", "game", "gaming", "zocken", "playstation", "xbox", "nintendo", "steam", "brettspiel",
                        "videospiel", "konsole", "console"],
                icons: ["Gamepad2", "Dice5", "Puzzle"]),
        Meaning(stems: ["kino", "cinema", "film", "movie", "netflix", "streaming", "serien", "disney"],
                icons: ["Film", "Popcorn"]),
        Meaning(stems: ["theater", "theatre", "musical", "kabarett", "comedy"], words: ["oper", "opera"],
                icons: ["Drama"]),
        Meaning(stems: ["foto", "photo", "kamera", "camera"], icons: ["Camera"]),
        Meaning(stems: ["technik", "tech", "gadget", "computer", "software", "hardware"], words: ["app", "apps"],
                icons: ["Laptop"]),
        // Learning
        Meaning(stems: ["bildung", "weiterbildung", "fortbildung", "lernen", "learning", "studium", "studien",
                        "student", "universit", "schule", "school", "kurs", "course", "nachhilfe", "tutor", "sprach",
                        "language", "seminar", "workshop", "semester"],
                words: ["uni"], icons: ["GraduationCap", "Book"]),
        Meaning(stems: ["bücher", "buecher", "books", "lesen", "reading", "bibliothek", "library", "kindle", "hörbuch",
                        "audible", "comic", "manga", "zeitschrift", "magazine", "zeitung", "newspaper"],
                words: ["buch", "book"], icons: ["Book", "BookOpen"]),
        // Care
        Meaning(stems: ["spende", "donation", "donate", "charity", "wohltät", "hilfsorganisation", "patenschaft"],
                icons: ["HandHeart"]),
        Meaning(stems: ["friseur", "frisör", "haare", "haarschnitt", "hair", "barber", "kosmetik", "cosmetic", "beauty",
                        "makeup", "nagel", "nails", "maniküre"],
                icons: ["Scissors", "Sparkles"]),
        Meaning(stems: ["arzt", "ärzte", "zahnarzt", "doctor", "dentist", "apotheke", "pharmacy", "therapie", "therapy",
                        "physio", "medizin", "krankenhaus", "hospital"],
                icons: ["Stethoscope"]),
        Meaning(stems: ["brille", "kontaktlinse", "glasses", "optiker", "optician"], words: ["linsen"],
                icons: ["Glasses"]),
        Meaning(stems: ["klamotten", "schuh", "shoe", "sneaker", "fashion"], words: ["mode"], icons: ["Shirt"]),
    ]

    /// For names without a known word, in this order: plain marks that suggest no particular kind of spending. The
    /// first is the engine's own tag.
    static let spareIcons = ["Tag", "Star", "Bookmark", "Flag", "Diamond", "Hexagon", "Shapes", "Lightbulb", "Bell",
                             "Key"]

    /// Bright colours from the dashboard's palette that no default category has, warm and cool in turn.
    static let colors = ["#FF9F1C", "#2DD4BF", "#818CF8", "#F472B6", "#4ADE80", "#38BDF8", "#C084FC", "#FF6B6B"]

    // MARK: choosing

    /// The look for a new own category called `name`, beside the looks the other own categories have.
    static func look(for name: String, besides others: [CategoryLook]) -> CategoryLook {
        CategoryLook(icon: icon(for: name, besides: others.map(\.icon)), color: color(besides: others.map(\.color)))
    }

    /// Looks for own categories in their creation order: each keeps the look it has; one without (made before brief 36,
    /// or from an older export) gets one as if they had been added one after the other.
    static func fill(_ categories: [(name: String, look: CategoryLook?)]) -> [CategoryLook] {
        var taken = categories.compactMap(\.look)
        return categories.map { category in
            if let look = category.look { return look }
            let look = look(for: category.name, besides: taken)
            taken.append(look)
            return look
        }
    }

    /// The icon: the first fitting one no other own category has, else the first spare one no other has; once all are
    /// taken, the fitting one, else the spare one fewest have. Compared as drawn (`CategorySymbol`), so two names for one
    /// symbol never count as two icons.
    static func icon(for name: String, besides taken: [String]) -> String {
        let used = taken.map(CategorySymbol.name(for:))
        let fitting = meanings(of: name).flatMap(\.icons)
        if let free = (fitting + spareIcons).first(where: { !used.contains(CategorySymbol.name(for: $0)) }) { return free }
        return fitting.first ?? leastUsed(spareIcons, among: used, as: CategorySymbol.name(for:))
    }

    /// The colour: the first no other own category has; once all are taken, the one fewest have.
    static func color(besides taken: [String]) -> String {
        let used = taken.map { $0.uppercased() }
        return colors.first { !used.contains($0) } ?? leastUsed(colors, among: used, as: { $0 })
    }

    /// The first of `options` that appears least often in `used` (each option compared as `key` makes it).
    private static func leastUsed(_ options: [String], among used: [String], as key: (String) -> String) -> String {
        let counts = Dictionary(used.map { ($0, 1) }, uniquingKeysWith: +)
        return options.min { (counts[key($0)] ?? 0) < (counts[key($1)] ?? 0) } ?? options[0]
    }

    // MARK: reading the name

    /// The meanings a name's words point to: the words in their order; for one word the longest match first.
    static func meanings(of name: String) -> [Meaning] {
        var found: [Int] = []
        for word in words(of: name) {
            let matches = folded.enumerated().compactMap { index, meaning -> (index: Int, length: Int)? in
                let lengths = meaning.words.filter { $0 == word }.map(\.count)
                    + meaning.stems.filter { word.hasPrefix($0) }.map(\.count)
                return lengths.max().map { (index, $0) }
            }
            for match in matches.sorted(by: { $0.length != $1.length ? $0.length > $1.length : $0.index < $1.index })
            where !found.contains(match.index) {
                found.append(match.index)
            }
        }
        return found.map { meanings[$0] }
    }

    /// A name's words, folded as the list is: "Weihnachts-Geschenke" → ["weihnachts", "geschenke"].
    static func words(of name: String) -> [String] {
        fold(name).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Lower case, without accents, "ß" as "ss": "Bücher" and "bucher", "Fußball" and "fussball" meet.
    static func fold(_ text: String) -> String {
        text.replacingOccurrences(of: "ß", with: "ss").replacingOccurrences(of: "ẞ", with: "ss")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// The list as it is compared: every word and stem folded.
    private static let folded: [Meaning] = meanings.map {
        Meaning(stems: $0.stems.map(fold), words: $0.words.map(fold), icons: $0.icons)
    }

    // MARK: checking a stored look

    /// A look from an export can be kept when the app draws its icon and its colour is `#RRGGBB`; another is chosen
    /// anew (`fill`).
    static func isUsable(_ look: CategoryLook) -> Bool {
        CategorySymbol.knows(look.icon) && look.color.wholeMatch(of: /#[0-9A-Fa-f]{6}/) != nil
    }
}
