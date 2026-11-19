import os
import SwiftUI
import UIKit
import WebKit

/// The second tab: the flat in 3D, full-bleed, made for a thumb (Patrik: "the flat model but well made for easy
/// navigation on an iphone … phone model actions should affect things too … live state yes, also displayed in model").
/// The page is flatd's `GET /viewer` (private, never bundled), loaded with the key; it talks only to the app through
/// the bridge in the viewer's BRIDGE.md: taps come in as messages and go to flatd through the store, live state goes
/// back with `flat3d.receive`. While the page loads or flatd is out of reach, a calm line over the app's wall.
struct FlatScreen: View {
    let store: FlatStore
    let isShown: Bool
    @State private var page = FlatPage()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ProvinceWall(accent: .arestia)
                if store.link != .notSetUp {
                    // The safe area's bottom here is the tab bar and the home indicator; the page sees only the latter.
                    FlatWebView(store: store, page: page, coveredBottom: proxy.safeAreaInsets.bottom,
                                load: page.wanted ? "\(page.loads)-\(store.pairingGeneration)" : nil)
                        .ignoresSafeArea()
                        .opacity(page.isReady ? 1 : 0)
                        .animation(.easeOut(duration: 0.3), value: page.isReady)
                }
                overlay
            }
        }
        .onChange(of: isShown, initial: true) { _, shown in
            if shown { page.wanted = true }
        }
    }

    @ViewBuilder private var overlay: some View {
        if !page.isReady {
            VStack(spacing: 14) {
                switch page.problem {
                case .none:
                    ProgressView().tint(Ink.secondary)
                    Text("Loading the flat").font(AppFont.text(14)).foregroundStyle(Ink.secondary)
                case let .some(problem):
                    CalmCard(symbol: "cube.transparent", title: String(localized: "The 3D flat isn't here right now"),
                             text: problem, action: (String(localized: "Try again"), { page.reload() }))
                        .padding(.horizontal, 18)
                }
            }
            .transition(.opacity)
        }
    }
}

/// The page's state, shared by the screen and the web view's coordinator.
@MainActor @Observable
final class FlatPage {
    /// The page sent `ready` and has its state.
    var isReady = false
    /// Why the page is not shown (flatd out of reach, no viewer configured); nil while it loads.
    var problem: String?
    /// The tab was shown at least once: the page loads only then (it is heavy).
    var wanted = false
    /// Counts up to ask the web view to load again.
    private(set) var loads = 0

    func reload() {
        problem = nil
        isReady = false
        loads += 1
    }
}

/// The web view and its bridge (BRIDGE.md v1): the handler `flat3d`, `flat3d.receive(…)`, one result per request.
private struct FlatWebView: UIViewRepresentable {
    let store: FlatStore
    let page: FlatPage
    /// How much of the screen's bottom the app's bars and the home indicator cover.
    let coveredBottom: CGFloat
    /// Which load the page should show (nil: not yet, the tab was never opened): a new value loads it again (Try
    /// again, or a new pairing: a page of the old flatd never stays).
    let load: String?
    @Environment(\.colorScheme) private var scheme
    @AppStorage(PageScript.alwaysDaylightKey) private var alwaysDaylight = false

    func makeCoordinator() -> Coordinator { Coordinator(store: store, page: page) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()       // nothing of the flat stays on disk
        configuration.userContentController.add(WeakHandler(context.coordinator), name: "flat3d")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        webView.allowsLinkPreview = false
        #if DEBUG
        webView.isInspectable = true
        #endif
        context.coordinator.webView = webView
        context.coordinator.dark = scheme == .dark
        context.coordinator.alwaysDaylight = alwaysDaylight
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.dark != (scheme == .dark) || coordinator.coveredBottom != coveredBottom
            || coordinator.alwaysDaylight != alwaysDaylight {
            coordinator.dark = scheme == .dark
            coordinator.coveredBottom = coveredBottom
            coordinator.alwaysDaylight = alwaysDaylight
            coordinator.sendConfig()
        }
        coordinator.sendConnection(store.link)
        if let load, coordinator.loadedCount != load {
            coordinator.load(load)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "flat3d")
        coordinator.stopListening()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let store: FlatStore
        let page: FlatPage
        weak var webView: WKWebView?
        var dark = true
        var coveredBottom: CGFloat = 0
        var alwaysDaylight = false
        private(set) var loadedCount: String?
        /// Ends a load whose page never says `ready` (it failed while starting, or never finished loading): the calm
        /// card with Try again.
        private var readyDeadline: Task<Void, Never>?
        /// Counts the documents loaded: a request's result goes only to the document that asked (a reloaded page may
        /// reuse its request ids).
        private var document = 0
        private var listener: UUID?
        private var lastConnection: FlatStore.Link?
        private var pageOrigin: URL?
        private static let log = Logger(subsystem: "de.ares-empire.arestia", category: "viewer")

        init(store: FlatStore, page: FlatPage) {
            self.store = store
            self.page = page
        }

        /// Loads flatd's viewer page with the key (the page loads nothing else), once the address answered like flatd
        /// without it. The old page's subscription ends first; the page has half a minute to say `ready`.
        func load(_ count: String? = nil) {
            if let count { loadedCount = count }
            stopListening()
            readyDeadline?.cancel()
            document += 1
            let loading = document
            guard let client = store.connection.client else { return }
            pageOrigin = client.baseURL
            page.isReady = false
            page.problem = nil
            webView?.stopLoading()
            readyDeadline = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard let self, !Task.isCancelled, loading == document, !page.isReady, page.problem == nil else { return }
                webView?.stopLoading()
                page.problem = String(localized: "The 3D flat didn't start.")
            }
            Task { [weak self] in
                do {
                    try await client.verify()
                } catch {
                    guard let self, loading == document else { return }
                    readyDeadline?.cancel()
                    page.problem = (error as? FlatdError ?? .unreachable).message()
                    return
                }
                guard let self, loading == document else { return }
                webView?.load(client.viewerRequest)
            }
        }

        func stopListening() {
            if let listener { store.unlisten(listener) }
            listener = nil
            lastConnection = nil
        }

        // MARK: page → app

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            // Only flatd's own page, in the main frame, may speak to the app.
            guard message.frameInfo.isMainFrame, isFlatd(message.frameInfo.securityOrigin),
                  let parsed = PageMessage.parse(message.body) else { return }
            switch parsed {
            case .ready:
                readyDeadline?.cancel()
                page.isReady = true
                page.problem = nil
                sendConfig()
                lastConnection = nil
                sendConnection(store.link)
                send(store.snapshot.json)
                if listener == nil {
                    listener = store.listen { [weak self] event in self?.send(event.json) }
                }
                #if DEBUG
                if LaunchArguments.current.contains("-probeViewer") { probe() }
                #endif
            case let .request(reqId, id, body):
                let asking = document
                Task {
                    let error = await store.pageRequest(id, body: body)
                    if asking == document { send(PageScript.result(reqId: reqId, error: error)) }
                }
            case let .mode(reqId, id, body):
                let asking = document
                Task {
                    let error = await store.pageMode(id, body: body)
                    if asking == document { send(PageScript.result(reqId: reqId, error: error)) }
                }
            case let .invalid(reqId):
                send(PageScript.result(reqId: reqId, error: .failed(status: 400, message: nil)))
            case let .haptic(style):
                switch style {
                case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
                case "error": UINotificationFeedbackGenerator().notificationOccurred(.error)
                case "medium": UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                default: UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            case let .log(text):
                #if DEBUG
                Self.log.error("page: \(text, privacy: .public)")
                #else
                Self.log.error("page: \(text, privacy: .private)")
                #endif
            case .other:
                break
            }
        }

        #if DEBUG
        /// `-probeViewer`: whether the web view has WebGL2, and what the page shows, every 5 s for half a minute (the
        /// device log, category `viewer`), to check the 3D page in a real web view.
        private func probe() {
            let script = """
            (() => { const c = document.createElement('canvas'); const gl = c.getContext('webgl2');
              window.__frames = window.__frames || 0;
              if (!window.__counting) { window.__counting = true;
                const tick = () => { window.__frames++; requestAnimationFrame(tick); }; requestAnimationFrame(tick); }
              const loading = document.getElementById('loading');
              return JSON.stringify({webgl2: !!gl, renderer: gl ? gl.getParameter(gl.RENDERER) : null,
                frames: window.__frames, hidden: document.hidden, visibility: document.visibilityState,
                loading: loading ? loading.className : null,
                text: (document.body && document.body.innerText || '').slice(0, 120)}); })()
            """
            Task {
                for _ in 0..<6 {
                    let answer = try? await webView?.evaluateJavaScript(script) as? String
                    Self.log.notice("probe: \(answer ?? "nil", privacy: .public)")
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
        #endif

        // MARK: app → page

        func sendConfig() {
            guard page.isReady else { return }
            // The tab bar over the page's bottom, beyond the safe area the page sees itself (the home indicator).
            let bars = max(0, coveredBottom - (webView?.window?.safeAreaInsets.bottom ?? 0))
            send(PageScript.config(dark: dark, language: .current, accent: PageScript.accentHex,
                                   alwaysDaylight: alwaysDaylight, bottomBar: Double(bars)))
        }

        func sendConnection(_ link: FlatStore.Link) {
            guard page.isReady, link != lastConnection else { return }
            lastConnection = link
            send(PageScript.connection(link))
            if link == .live { send(store.snapshot.json) }     // after every reconnect to flatd (BRIDGE.md)
        }

        private func send(_ json: Data?) {
            guard let json, let webView else { return }
            webView.evaluateJavaScript(PageScript.receive(json)) { _, error in
                if let error { Self.log.notice("receive failed: \(error.localizedDescription, privacy: .public)") }
            }
        }

        /// The page's origin is flatd's address (scheme, host and port).
        private func isFlatd(_ origin: WKSecurityOrigin) -> Bool {
            guard let base = pageOrigin else { return false }
            return origin.protocol == base.scheme && origin.host == base.host()
                && origin.port == (base.port ?? (base.scheme == "https" ? 443 : 80))
        }

        // MARK: navigation: only flatd's own page

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url, let origin = pageOrigin else { return .cancel }
            let sameOrigin = url.scheme == origin.scheme && url.host() == origin.host() && url.port == origin.port
            return sameOrigin || url.scheme == "about" ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            if let http = response.response as? HTTPURLResponse, response.isForMainFrame, http.statusCode != 200 {
                page.problem = switch http.statusCode {
                case 401: FlatdError.refused.message()
                case 404: String(localized: "flatd has no 3D flat set up yet.")
                default: FlatdError.failed(status: http.statusCode, message: nil).message()
                }
                return .cancel
            }
            return .allow
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard page.problem == nil, (error as NSError).code != NSURLErrorCancelled else { return }
            page.problem = FlatdError.unreachable.message()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard page.problem == nil, (error as NSError).code != NSURLErrorCancelled else { return }
            page.problem = FlatdError.unreachable.message()
        }

        /// WebKit may end the page's process in the background: load it again (BRIDGE.md).
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            page.isReady = false
            load()
        }
    }
}

/// The content controller keeps its handler strongly; this breaks the cycle with the coordinator.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?
    init(_ target: any WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
