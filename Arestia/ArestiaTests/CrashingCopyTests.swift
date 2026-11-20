import Foundation
import Testing
import WebKit
@testable import Arestia

// Codex's review of the 3D page, finding 3: a kept copy that crashes WebKit again and again no longer stands in the
// way of its own repair.

private func cacheFolder() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "arestia-viewer-tests-" + UUID().uuidString)
}

@MainActor
struct CrashingCopyTests {
    @Test func earlyEndsCountPerPageAndALongLifeForgetsThem() {
        var ends = EarlyEnds()
        #expect(ends.trusts("a"))
        ends.ended("a")
        #expect(ends.trusts("a"))                                       // once may be WebKit's own doing
        ends.ended("a")
        #expect(!ends.trusts("a") && ends.trusts("b"))
        ends.ended(nil)                                                 // no document shown: not counted
        ends.lived("b")
        #expect(!ends.trusts("a"))
        ends.lived("a")                                                 // it lived longer once: afresh
        #expect(ends.trusts("a"))
        ends.ended("a")
        ends.ended("b")
        ends.ended("a")
        #expect(ends.trusts("a"))                                       // not in a row
    }

    /// The kept copy ends WebKit early, again and again, while flatd's page is slow to come: after two early ends the
    /// reloads stop showing the copy, they end in Try again, and Try again shows nothing of the copy, fetches flatd's
    /// page whole (no If-None-Match) and shows it once its slow answer arrives.
    @Test func tryAgainAfterACrashingCopyFetchesFlatdsPageWhole() async throws {
        let cache = ViewerPageCache(folder: cacheFolder())
        let broken = Data("<!doctype html><p>made-up page that ends WebKit</p>".utf8)
        let brokenHash = try #require(await cache.save(broken, etag: "\"v1\"", pairing: Flat.id, pin: Flat.pin))
        let (store, transport, _, _) = Flat.store()
        transport.answer("GET /viewer", body: ["page": "made up, healthy"], delay: .seconds(30))  // not in this part
        let viewerAsks = { transport.sent.filter { $0.url?.path() == "/viewer" } }
        let page = FlatPage()
        let coordinator = FlatWebView.Coordinator(store: store, page: page, cache: cache)
        let webView = WKWebView()
        coordinator.webView = webView

        coordinator.load("0-0")
        #expect(await eventually { coordinator.shown?.source == "copy" })
        #expect(await eventually { viewerAsks().count == 1 })
        #expect(viewerAsks().last?.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
        coordinator.webViewWebContentProcessDidTerminate(webView)        // 1: the copy again, it may have been WebKit
        #expect(await eventually { coordinator.shown?.source == "copy" && coordinator.shown?.sha256 == brokenHash })
        #expect(await eventually { viewerAsks().count == 2 })
        coordinator.webViewWebContentProcessDidTerminate(webView)        // 2: no copy any more, flatd's page whole
        #expect(await eventually { viewerAsks().count == 3 })
        #expect(viewerAsks().last?.value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(coordinator.shown == nil)
        for _ in 0..<(FlatWebView.Coordinator.maxAutomaticReloads - 1) {
            coordinator.webViewWebContentProcessDidTerminate(webView)
        }
        #expect(page.problem == String(localized: "The 3D flat didn't start."))

        // flatd has a fixed page now, slow to come. Try again: nothing of the copy, flatd's page asked for whole.
        transport.answer("GET /viewer", body: ["page": "made up, healthy"], delay: .milliseconds(700))
        let asked = viewerAsks().count
        page.reload()
        coordinator.load("1-0")
        #expect(await eventually { viewerAsks().count == asked + 1 })
        #expect(viewerAsks().last?.value(forHTTPHeaderField: "If-None-Match") == nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(coordinator.shown == nil && page.problem == nil)       // still waiting, the copy never shown
        #expect(await eventually({ coordinator.shown?.source == "flatd" }, timeout: .seconds(4)))
        let healthy = try #require(coordinator.shown?.sha256)
        #expect(healthy != brokenHash)
        #expect(await cache.page(pairing: Flat.id, pin: Flat.pin)?.sha256 == healthy)   // the copy is repaired
        coordinator.retire()
        _ = webView
    }
}
