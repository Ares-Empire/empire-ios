import Foundation

/// What a listing's photos and a look hunt's verdicts show (brief 268, on the server's brief 267): the page's gallery,
/// the look line's quiet facts, and the score at the start of a filtered-out listing's reason. Decided here, so the
/// screens only lay it out (`Screens/LookViews.swift`, `Screens/ListingGallery.swift`).

extension Listing {
    /// The photos to show, in the site's order: `photo_urls` (up to four, brief 267), else the one `image_url`; each
    /// address once, empty or unreadable ones left out. Empty: the page shows no photo at all.
    var photos: [URL] {
        var seen = Set<String>()
        let given = photoURLs.isEmpty ? [imageURL].compactMap { $0 } : photoURLs
        return given.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { seen.insert($0).inserted }
            .compactMap(Self.photoAddress)
    }

    /// A photo's address: a web address (http or https), or in sample mode a bundled made-up one (`sample://<file>`,
    /// `SamplePhotos`); anything else is none.
    private static func photoAddress(_ text: String) -> URL? {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), url.host() != nil else { return nil }
        return ["http", "https", SamplePhotoScheme.name].contains(scheme) ? url : nil
    }
}

/// Sample mode's photos are bundled, never fetched (a look hunt's samples must not reach a real site from the Mac):
/// `sample://look-coat-1.jpg` names a file in `Samples/`, which only Debug builds carry.
enum SamplePhotoScheme {
    static let name = "sample"
}

/// How a listing's photos are framed on its page: a look hunt's tall (clothes are photographed upright, and the whole
/// garment is what the look is judged by), another thing's square, a flat's wide (rooms). Things show the whole photo on
/// a quiet mat, never cropped; a flat's fills its frame as before.
enum PhotoFrame: Equatable {
    case tall, square, wide

    /// Width over height.
    var aspect: CGFloat {
        switch self {
        case .tall: 4 / 5
        case .square: 1
        case .wide: 16 / 10
        }
    }

    /// Whether the whole photo shows (on a mat) rather than filling the frame.
    var showsWholePhoto: Bool { self != .wide }

    static func of(kind: SearchKind, search: ItemSearch?) -> PhotoFrame {
        guard kind == .item else { return .wide }
        return search?.hasLook == true ? .tall : .square
    }
}

extension ItemSearch {
    /// A look hunt (brief 267): the server judges its listings' photos against `look`.
    var hasLook: Bool { !look.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

extension LookVerdict {
    /// "Look 8/10": the score as the line's label.
    func scoreLabel(language: AppLanguage = .current) -> String {
        language.string("Look \(score)/10")
    }

    /// What VoiceOver reads for the look line: "Look 8/10. <reason> Long · Men's cut · Real fur.", each part ending in
    /// one stop.
    func spoken(language: AppLanguage = .current) -> String {
        [scoreLabel(language: language), reason(language: language), facts(language: language) ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { part in part.last.map { ".!?…".contains($0) } == true ? part : part + "." }
            .joined(separator: " ")
    }

    /// The verdict's quiet facts, "Long · Men's cut · Real fur", the ones the judge could not tell left out; nil when it
    /// could tell none.
    func facts(language: AppLanguage = .current) -> String? {
        let length: String? = switch length {
        case .long: language.string("Long")
        case .mid: language.string("Mid-length")
        case .short: language.string("Short")
        case .unknown: nil
        }
        let cut: String? = switch cut {
        case .men: language.string("Men's cut")
        case .unisex: language.string("Unisex")
        case .women: language.string("Women's cut")
        case .unknown: nil
        }
        let fur: String? = switch fur {
        case .real: language.string("Real fur")
        case .faux: language.string("Faux fur")
        case .unknown: nil
        }
        let shown = [length, cut, fur].compactMap { $0 }
        return shown.isEmpty ? nil : shown.joined(separator: " · ")
    }
}

/// A filtered-out listing's reason in two parts when the look check wrote it (brief 267: "Look 4/10: <reason>" or
/// "Look not judged: <cause>"): the label, shown a little stronger, and the rest. Any other reason is shown whole, as the
/// server wrote it.
struct RejectedReason: Equatable {
    /// "Look 4/10" or "Look not judged"; nil for a reason the look check did not write.
    let lead: String?
    let rest: String

    init(_ reason: String) {
        let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = text.firstMatch(of: /^(Look (?:\d{1,2}\/10|not judged)):\s*(.+)$/.dotMatchesNewlines()) {
            lead = String(match.1)
            rest = String(match.2)
        } else {
            lead = nil
            rest = text
        }
    }
}
