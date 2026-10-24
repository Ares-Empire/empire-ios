import Foundation

/// The Search tab's editable copy of a search. The fields are the truth; "Describe it" only fills them in.
/// Every filter is optional on its own (`nil` = any); only a place and a portal are required. Converting back to the
/// contract's `Search` drops what does not apply to the chosen type (the flat's size and rooms for WG only, the room's
/// size and flatmates for flats only).
struct SearchDraft: Equatable {
    /// What the user looks for: either, a whole flat, or a room in a WG.
    enum OfferType: String, CaseIterable, Identifiable {
        case any, flat, wg
        var id: String { rawValue }

        init(_ kinds: [Kind]) {
            let set = Set(kinds)
            self = set == [.flat] ? .flat : set == [.wg] ? .wg : .any
        }

        var kinds: [Kind] {
            switch self {
            case .any: [.flat, .wg]
            case .flat: [.flat]
            case .wg: [.wg]
            }
        }
    }

    /// A min/max pair; either end may be empty.
    struct Range: Equatable {
        var min: Double?
        var max: Double?
        var isInOrder: Bool { guard let min, let max else { return true }; return min <= max }
    }

    static let people = 1...6

    var type: OfferType = .any
    var people = 1
    var flatmatesMax: Int?
    var places: [Place] = []
    var districts: [String] = []
    var flatSize = Range()
    var roomSize = Range()
    var roomsMin: Double?
    var coldRent = Range()
    var warmRent = Range()
    var moveInFrom: Date?
    var moveInUntil: Date?
    var sublet: Sublet = .exclude
    var extra = ""
    var sources: Set<Source> = Set(Source.allCases)

    /// A new search: flat or WG, one person, every portal, no temporary offers.
    init() {}

    init(_ search: Search, calendar: Calendar = .app) {
        type = OfferType(search.kinds)
        people = min(max(search.people, Self.people.lowerBound), Self.people.upperBound)
        flatmatesMax = search.flatmatesMax
        places = search.places
        districts = search.districts
        flatSize = Range(min: search.sqmMin, max: search.sqmMax)
        roomSize = Range(min: search.roomSqmMin, max: search.roomSqmMax)
        roomsMin = search.roomsMin
        coldRent = Range(min: search.rentColdMin, max: search.rentColdMax)
        warmRent = Range(min: search.rentWarmMin, max: search.rentWarmMax)
        moveInFrom = search.moveInFrom.flatMap { DateOnly.parse($0, calendar: calendar) }
        moveInUntil = search.moveInUntil.flatMap { DateOnly.parse($0, calendar: calendar) }
        sublet = search.sublet
        extra = search.extra
        sources = Set(search.sources)
    }

    /// Flat offers are possible: their size and rooms apply.
    var asksFlat: Bool { type != .wg }
    /// WG offers are possible: the room's size and the flatmates apply.
    var asksWG: Bool { type != .flat }

    // MARK: validation

    enum Problem: Equatable {
        case noPlace, noPortal, flatSizeOrder, roomSizeOrder, coldRentOrder, warmRentOrder, moveInOrder
    }

    var problems: [Problem] {
        var problems: [Problem] = []
        if places.isEmpty { problems.append(.noPlace) }
        if sources.isEmpty { problems.append(.noPortal) }
        if asksFlat && !flatSize.isInOrder { problems.append(.flatSizeOrder) }
        if asksWG && !roomSize.isInOrder { problems.append(.roomSizeOrder) }
        if !coldRent.isInOrder { problems.append(.coldRentOrder) }
        if !warmRent.isInOrder { problems.append(.warmRentOrder) }
        if let moveInFrom, let moveInUntil, moveInUntil < moveInFrom { problems.append(.moveInOrder) }
        return problems
    }

    var isValid: Bool { problems.isEmpty }

    /// One calm line under the save button saying what is still missing or wrong (the first problem).
    var hint: String? {
        let problems = problems
        if problems.contains(.noPlace) && problems.contains(.noPortal) { return "Choose a place and at least one portal." }
        switch problems.first {
        case .noPlace: return "Choose a place."
        case .noPortal: return "Choose at least one portal."
        case .flatSizeOrder: return "The flat's smallest size is above its largest."
        case .roomSizeOrder: return "The room's smallest size is above its largest."
        case .coldRentOrder: return "The lowest cold rent is above the highest."
        case .warmRentOrder: return "The lowest warm rent is above the highest."
        case .moveInOrder: return "The move-in \"until\" date is before the \"from\" date."
        case nil: return nil
        }
    }

    // MARK: to the contract

    func search(calendar: Calendar = .app) -> Search {
        Search(kinds: type.kinds,
               people: people,
               flatmatesMax: asksWG ? flatmatesMax : nil,
               places: places,
               districts: districts,
               sqmMin: asksFlat ? flatSize.min : nil,
               sqmMax: asksFlat ? flatSize.max : nil,
               roomSqmMin: asksWG ? roomSize.min : nil,
               roomSqmMax: asksWG ? roomSize.max : nil,
               roomsMin: asksFlat ? roomsMin : nil,
               rentColdMin: coldRent.min,
               rentColdMax: coldRent.max,
               rentWarmMin: warmRent.min,
               rentWarmMax: warmRent.max,
               moveInFrom: moveInFrom.map { DateOnly.string($0, calendar: calendar) },
               moveInUntil: moveInUntil.map { DateOnly.string($0, calendar: calendar) },
               sublet: sublet,
               extra: extra.trimmingCharacters(in: .whitespacesAndNewlines),
               sources: Source.allCases.filter(sources.contains))
    }

    /// Fills in what a sentence said (`POST /search/parse`); everything it did not mention stays as it is.
    mutating func apply(_ parsed: PartialSearch, calendar: Calendar = .app) {
        if let kinds = parsed.kinds, !kinds.isEmpty { type = OfferType(kinds) }
        if let people = parsed.people, Self.people.contains(people) { self.people = people }
        if let flatmates = parsed.flatmatesMax { flatmatesMax = flatmates }
        if let places = parsed.places, !places.isEmpty {
            for place in places where !self.places.contains(where: { $0.id == place.id }) { self.places.append(place) }
        }
        if let districts = parsed.districts {
            for district in districts where !self.districts.contains(district) { self.districts.append(district) }
        }
        if let value = parsed.sqmMin { flatSize.min = value }
        if let value = parsed.sqmMax { flatSize.max = value }
        if let value = parsed.roomSqmMin { roomSize.min = value }
        if let value = parsed.roomSqmMax { roomSize.max = value }
        if let rooms = parsed.roomsMin { roomsMin = rooms }
        if let value = parsed.rentColdMin { coldRent.min = value }
        if let value = parsed.rentColdMax { coldRent.max = value }
        if let value = parsed.rentWarmMin { warmRent.min = value }
        if let value = parsed.rentWarmMax { warmRent.max = value }
        if let from = parsed.moveInFrom.flatMap({ DateOnly.parse($0, calendar: calendar) }) { moveInFrom = from }
        if let until = parsed.moveInUntil.flatMap({ DateOnly.parse($0, calendar: calendar) }) { moveInUntil = until }
        if let sublet = parsed.sublet { self.sublet = sublet }
        if let extra = parsed.extra, !extra.isEmpty { self.extra = extra }
        if let sources = parsed.sources, !sources.isEmpty { self.sources = Set(sources) }
    }

    // MARK: editing helpers

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
