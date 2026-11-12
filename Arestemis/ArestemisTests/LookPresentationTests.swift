import Foundation
import Testing
@testable import Arestemis

/// Brief 268's design pass: a listing's photos (`photo_urls`, server brief 267), how the page frames them, the look
/// line's words and the score at the start of a filtered-out listing's reason.
@MainActor
struct LookPresentationTests {
    /// The Vinted sample listing as JSON, with `photo_urls` set to `value` (or left out for nil).
    private func listing(photoURLs value: Any?, imageURL: Any? = NSNull()) throws -> Listing {
        let match = try sample(Match.self, "vinted-match")
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(match.listing)) as? [String: Any])
        object.removeValue(forKey: "photo_urls")
        if let value { object["photo_urls"] = value }
        object["image_url"] = imageURL
        return try JSONDecoder().decode(Listing.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test func photoURLsDecodeLenientlyAndSurviveEncoding() throws {
        let given = ["https://images.example.invalid/1.jpg", "https://images.example.invalid/2.jpg"]
        let read = try listing(photoURLs: given)
        #expect(read.photoURLs == given)
        #expect(try JSONDecoder().decode(Listing.self, from: JSONEncoder().encode(read)).photoURLs == given)
        // A server from before brief 267, null, or something that is not a list of texts: none, and the listing loads.
        #expect(try listing(photoURLs: nil).photoURLs.isEmpty)
        #expect(try listing(photoURLs: NSNull()).photoURLs.isEmpty)
        #expect(try listing(photoURLs: "https://images.example.invalid/1.jpg").photoURLs.isEmpty)
        #expect(try listing(photoURLs: [1, 2]).photoURLs.isEmpty)
        // The contract's own samples have none.
        #expect(try sample(Match.self, "vinted-match").listing.photoURLs.isEmpty)
        #expect(try sample(RejectedPage.self, "rejected").items.allSatisfy { $0.listing.photoURLs.isEmpty })
    }

    @Test func photosPreferTheListThenTheOneImage() throws {
        let image = "https://images.example.invalid/first.jpg"
        let list = ["https://images.example.invalid/a.jpg", " https://images.example.invalid/b.jpg ",
                    "https://images.example.invalid/a.jpg", "", "not a photo", "file:///etc/hosts", "javascript:alert(1)"]
        #expect(try listing(photoURLs: list, imageURL: image).photos.map(\.absoluteString)
                == ["https://images.example.invalid/a.jpg", "https://images.example.invalid/b.jpg"])
        #expect(try listing(photoURLs: [], imageURL: image).photos.map(\.absoluteString) == [image])
        #expect(try listing(photoURLs: nil, imageURL: image).photos.map(\.absoluteString) == [image])
        #expect(try listing(photoURLs: nil).photos.isEmpty)
        #expect(try listing(photoURLs: [String](), imageURL: "  ").photos.isEmpty)
        // Sample mode's bundled photos keep their own scheme.
        #expect(try listing(photoURLs: ["sample://look-coat-front.jpg"]).photos.map(\.absoluteString)
                == ["sample://look-coat-front.jpg"])
    }

    @Test func theLookSampleShowsOnlyBundledPhotos() throws {
        let content = try LookSample.content(SampleContent.contract(now: Clock.now))
        let listings = content.matches.filter { $0.huntID == 5 }.map(\.listing)
            + content.rejected.filter { $0.huntID == 5 }.map(\.listing)
        let photos = listings.flatMap(\.photos)
        #expect(photos.count == 5)
        #expect(photos.allSatisfy { $0.scheme == SamplePhotoScheme.name })
        // Every one is in the app's Debug bundle.
        #expect(photos.allSatisfy { Bundle.main.url(forResource: $0.host(), withExtension: nil) != nil })
    }

    @Test func aLookHuntsPhotosStandTall() throws {
        let hunt = try #require(sample([Hunt].self, "hunts").first { $0.id == 5 }?.search.item)
        var look = hunt
        look.look = "Long coat."
        #expect(PhotoFrame.of(kind: .item, search: look) == .tall)
        #expect(PhotoFrame.of(kind: .item, search: hunt) == .square)
        look.look = "  \n"
        #expect(PhotoFrame.of(kind: .item, search: look) == .square)
        #expect(PhotoFrame.of(kind: .item, search: nil) == .square)
        #expect(PhotoFrame.of(kind: .flat, search: nil) == .wide)
        #expect(PhotoFrame.tall.showsWholePhoto && PhotoFrame.square.showsWholePhoto && !PhotoFrame.wide.showsWholePhoto)
        #expect(PhotoFrame.tall.aspect < 1 && PhotoFrame.square.aspect == 1 && PhotoFrame.wide.aspect > 1)
    }

    @Test func theLookLinesWordsInBothLanguages() {
        let verdict = LookVerdict(score: 8, length: .long, cut: .men, fur: .real, reason: "A broad collar.",
                                  reasonDE: "Ein breiter Kragen.")
        #expect(verdict.scoreLabel(language: .english) == "Look 8/10")
        #expect(verdict.scoreLabel(language: .german) == "Look 8/10")
        #expect(verdict.facts(language: .english) == "Long · Men's cut · Real fur")
        #expect(verdict.facts(language: .german) == "Lang · Herrenschnitt · Echtpelz")
        let partly = LookVerdict(score: 3, length: .mid, cut: .unknown, fur: .faux, reason: "", reasonDE: "")
        #expect(partly.facts(language: .english) == "Mid-length · Faux fur")
        #expect(partly.facts(language: .german) == "Mittellang · Kunstpelz")
        let other = LookVerdict(score: 5, length: .short, cut: .women, fur: .unknown, reason: "", reasonDE: "")
        #expect(other.facts(language: .german) == "Kurz · Damenschnitt")
        let unisex = LookVerdict(score: 5, length: .unknown, cut: .unisex, fur: .unknown, reason: "", reasonDE: "")
        #expect(unisex.facts(language: .english) == "Unisex")
        let none = LookVerdict(score: 5, length: .unknown, cut: .unknown, fur: .unknown, reason: "", reasonDE: "")
        #expect(none.facts(language: .english) == nil)
        // VoiceOver's one line: each part ends in one stop.
        #expect(verdict.spoken(language: .english) == "Look 8/10. A broad collar. Long · Men's cut · Real fur.")
        #expect(verdict.spoken(language: .german) == "Look 8/10. Ein breiter Kragen. Lang · Herrenschnitt · Echtpelz.")
        let bare = LookVerdict(score: 7, length: .unknown, cut: .unknown, fur: .unknown, reason: "Broad collar ", reasonDE: "")
        #expect(bare.spoken(language: .english) == "Look 7/10. Broad collar.")
        #expect(none.spoken(language: .english) == "Look 5/10.")
    }

    @Test func theLookChecksReasonsLeadWithTheirScore() {
        func parts(_ reason: String) -> [String?] {
            let read = RejectedReason(reason)
            return [read.lead, read.rest]
        }
        #expect(parts("Look 4/10: Zu kurz.") == ["Look 4/10", "Zu kurz."])
        #expect(parts("Look 10/10: Genau so.") == ["Look 10/10", "Genau so."])
        #expect(parts("Look not judged: refusal") == ["Look not judged", "refusal"])
        #expect(parts("Look 3/10: Erste Zeile.\nZweite Zeile.") == ["Look 3/10", "Erste Zeile.\nZweite Zeile."])
        // Anything else stays whole, as the server wrote it.
        for reason in ["Flat swap, not a rental.", "Look 4/10:", "Looks fine: but sublet", "Look 123/10: x", "look 4/10: x"] {
            #expect(parts(reason) == [nil, reason])
        }
    }
}
