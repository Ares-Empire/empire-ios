import Foundation

/// The Search tab's editable copy of a search. The fields are the truth; "Describe it" only fills them in.
/// Converting back to the contract's `Search` drops what does not apply (rooms only for an own flat, flatmates only
/// for a WG kind) and empty tiers.
struct SearchDraft: Equatable {
    struct Tier: Equatable, Identifiable {
        let id: UUID
        var sqmMin: Double?
        var rentMaxWarm: Double?
        init(id: UUID = UUID(), sqmMin: Double? = nil, rentMaxWarm: Double? = nil) {
            self.id = id
            self.sqmMin = sqmMin
            self.rentMaxWarm = rentMaxWarm
        }
        var isEmpty: Bool { sqmMin == nil && rentMaxWarm == nil }
        var isComplete: Bool { sqmMin != nil && rentMaxWarm != nil }
    }

    var kinds: Set<Kind> = []
    var places: [Place] = []
    var districts: [String] = []
    var rentMaxWarm: Double?
    var tiers: [Tier] = []
    var sqmMin: Double?
    var roomsMin: Double?
    var flatmatesMax: Int?
    var moveInFrom: Date?
    var moveInUntil: Date?
    var sublet: Sublet = .exclude
    var furnished: Furnished = .any
    var extra = ""
    var sources: Set<Source> = Set(Source.allCases)

    /// A new search: every portal on, no sublets, furnished or not.
    init() {}

    init(_ search: Search, calendar: Calendar = .app) {
        kinds = Set(search.kinds)
        places = search.places
        districts = search.districts
        rentMaxWarm = search.rentMaxWarm
        tiers = search.rentTiers.map { Tier(sqmMin: $0.sqmMin, rentMaxWarm: $0.rentMaxWarm) }
        sqmMin = search.sqmMin
        roomsMin = search.roomsMin
        flatmatesMax = search.flatmatesMax
        moveInFrom = search.moveInFrom.flatMap { DateOnly.parse($0, calendar: calendar) }
        moveInUntil = search.moveInUntil.flatMap { DateOnly.parse($0, calendar: calendar) }
        sublet = search.sublet
        furnished = search.furnished
        extra = search.extra
        sources = Set(search.sources)
    }

    var asksRooms: Bool { kinds.contains(.flat) }
    var asksFlatmates: Bool { kinds.contains { $0.isWG } }

    // MARK: validation

    enum Problem: Equatable {
        case noKind, noPlace, noPortal, incompleteTier, moveInOrder
    }

    var problems: [Problem] {
        var problems: [Problem] = []
        if kinds.isEmpty { problems.append(.noKind) }
        if places.isEmpty { problems.append(.noPlace) }
        if sources.isEmpty { problems.append(.noPortal) }
        if tiers.contains(where: { !$0.isEmpty && !$0.isComplete }) { problems.append(.incompleteTier) }
        if let moveInFrom, let moveInUntil, moveInUntil < moveInFrom { problems.append(.moveInOrder) }
        return problems
    }

    var isValid: Bool { problems.isEmpty }

    /// One calm line under the save button saying what is still missing.
    var hint: String? {
        let problems = problems
        let missing = [(Problem.noKind, "a kind"), (.noPlace, "a place"), (.noPortal, "a portal")]
            .filter { problems.contains($0.0) }.map(\.1)
        if !missing.isEmpty {
            let list = missing.count == 1 ? missing[0] : missing.dropLast().joined(separator: ", ") + " and " + missing.last!
            return "Choose at least \(list)."
        }
        if problems.contains(.incompleteTier) { return "Fill in both numbers of a size tier, or remove it." }
        if problems.contains(.moveInOrder) { return "The move-in \"until\" date is before the \"from\" date." }
        return nil
    }

    // MARK: to the contract

    func search(calendar: Calendar = .app) -> Search {
        Search(kinds: Kind.allCases.filter(kinds.contains),
               places: places,
               districts: districts,
               rentMaxWarm: rentMaxWarm,
               rentTiers: tiers.compactMap { tier in
                   guard let sqm = tier.sqmMin, let rent = tier.rentMaxWarm else { return nil }
                   return RentTier(sqmMin: sqm, rentMaxWarm: rent)
               },
               sqmMin: sqmMin,
               roomsMin: asksRooms ? roomsMin : nil,
               flatmatesMax: asksFlatmates ? flatmatesMax : nil,
               moveInFrom: moveInFrom.map { DateOnly.string($0, calendar: calendar) },
               moveInUntil: moveInUntil.map { DateOnly.string($0, calendar: calendar) },
               sublet: sublet,
               furnished: furnished,
               extra: extra.trimmingCharacters(in: .whitespacesAndNewlines),
               sources: Source.allCases.filter(sources.contains))
    }

    /// Fills in what a sentence said (`POST /search/parse`); everything it did not mention stays as it is.
    mutating func apply(_ parsed: PartialSearch, calendar: Calendar = .app) {
        if let kinds = parsed.kinds, !kinds.isEmpty { self.kinds = Set(kinds) }
        if let places = parsed.places, !places.isEmpty {
            for place in places where !self.places.contains(where: { $0.id == place.id }) { self.places.append(place) }
        }
        if let districts = parsed.districts {
            for district in districts where !self.districts.contains(district) { self.districts.append(district) }
        }
        if let rent = parsed.rentMaxWarm { rentMaxWarm = rent }
        if let tiers = parsed.rentTiers, !tiers.isEmpty {
            self.tiers = tiers.map { Tier(sqmMin: $0.sqmMin, rentMaxWarm: $0.rentMaxWarm) }
        }
        if let sqm = parsed.sqmMin { sqmMin = sqm }
        if let rooms = parsed.roomsMin { roomsMin = rooms }
        if let flatmates = parsed.flatmatesMax { flatmatesMax = flatmates }
        if let from = parsed.moveInFrom.flatMap({ DateOnly.parse($0, calendar: calendar) }) { moveInFrom = from }
        if let until = parsed.moveInUntil.flatMap({ DateOnly.parse($0, calendar: calendar) }) { moveInUntil = until }
        if let sublet = parsed.sublet { self.sublet = sublet }
        if let furnished = parsed.furnished { self.furnished = furnished }
        if let extra = parsed.extra, !extra.isEmpty { self.extra = extra }
        if let sources = parsed.sources, !sources.isEmpty { self.sources = Set(sources) }
    }

    // MARK: editing helpers

    mutating func toggle(_ kind: Kind) {
        if kinds.contains(kind) { kinds.remove(kind) } else { kinds.insert(kind) }
    }

    mutating func add(_ place: Place) {
        guard !places.contains(where: { $0.id == place.id }) else { return }
        places.append(place)
    }

    /// Adds a district word; returns false for an empty or repeated one.
    @discardableResult
    mutating func addDistrict(_ text: String) -> Bool {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, !districts.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) else { return false }
        districts.append(word)
        return true
    }
}
