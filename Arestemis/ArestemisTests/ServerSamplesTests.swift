import Foundation
import Testing
@testable import Arestemis

/// The Arestemis server's own sample answers (copies of `~/Arestemis/docs/samples/`, made by its contract tests) decode
/// with the app's models. The app's `Samples/` are hand-made for sample mode; these pin the real contract. Copy them
/// again when the server's contract changes.
@MainActor
struct ServerSamplesTests {
    private final class Token {}

    private func data(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: Token.self).url(forResource: "server-\(name)", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    @Test func overviewWithEveryHunt() throws {
        let overview = try JSONDecoder().decode(Overview.self, from: data("overview"))
        #expect(!overview.hunts.isEmpty)
        #expect(overview.hunts.contains { $0.hunt.kind == .item })
        #expect(overview.hunts.allSatisfy { card in
            if case .unsupported = card.hunt.search { return false }
            return true
        })
    }

    @Test func huntsOfBothKinds() throws {
        let hunts = try JSONDecoder().decode([Hunt].self, from: data("hunts"))
        #expect(Set(hunts.map(\.kind)) == [.flat, .item])
    }

    @Test func matchesWithThingDetails() throws {
        let page = try JSONDecoder().decode(MatchPage.self, from: data("matches"))
        let things = page.items.filter { $0.listing.item != nil }
        #expect(!things.isEmpty)
        #expect(things.contains { $0.atStart })
    }

    @Test func theOtherAnswers() throws {
        _ = try JSONDecoder().decode(Match.self, from: data("match"))
        _ = try JSONDecoder().decode(RejectedPage.self, from: data("rejected"))
        _ = try JSONDecoder().decode(Settings.self, from: data("settings"))
        _ = try JSONDecoder().decode([Place].self, from: data("places"))
    }
}
