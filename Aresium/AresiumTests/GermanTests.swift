import Foundation
import Testing
@testable import Aresium

/// Money and month names in German (ares-empire/docs/LANGUAGES.md); English stays the server's own wording.
struct GermanTests {
    @Test func money() {
        #expect(Money.total(1339, language: .german) == "1.339\u{a0}€")
        #expect(Money.precise(12.4, language: .german) == "12,40\u{a0}€")
        #expect(Money.transaction(-1234.5, language: .german) == "−1.234,50")
        #expect(Money.total(1339, language: .english) == "€1,339")
    }

    @Test func monthNames() throws {
        let month = try JSONDecoder().decode(Month.self, from: Data("""
            {"key": "2025-10", "label": "Oct 2025", "short": "Oct", "year": 2025, "month": 10, "days": 31, "partial": false}
            """.utf8))
        #expect(month.title(.english) == "Oct 2025" && month.shortTitle(.english) == "Oct")
        #expect(month.title(.german) == "Okt. 2025" && month.shortTitle(.german) == "Okt")
    }
}
