import CryptoKit
import os
import SwiftUI
import UIKit
import WebKit

/// The second tab: the flat in 3D, full-bleed, made for a thumb (the owner: "the flat model but well made for easy
/// navigation on an iphone … phone model actions should affect things too … live state yes, also displayed in model").
/// The page is flatd's `GET /viewer` (private, never bundled): the app fetches it itself, over the connection pinned to
/// flatd's identity, keeps one copy for the pairing, and hands it to the web view, which never talks to the network.
/// The key never enters the web view. Through the viewer's BRIDGE.md, taps go to flatd through the store, live state goes
/// back with `flat3d.receive`. While the page loads or flatd is out of reach, a calm line over the app's wall.
struct FlatScreen: View {
    let store: FlatStore
    let isShown: Bool
    @State private var page = FlatPage()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ProvinceWall(accent: .arestia)
                if store.pairingID != nil {
                    // The safe area's bottom here is the tab bar and the home indicator; the page sees only the latter.
                    // The screens are made anew with every store (one flat per install), so this web view and its
                    // bridge only ever belong to this store's flat. A fresh code of the flat loads the page again.
                    FlatWebView(store: store, page: page, isShown: isShown, coveredBottom: proxy.safeAreaInsets.bottom,
                                load: page.wanted ? "\(page.loads)-\(store.credentials)" : nil)
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
struct FlatWebView: UIViewRepresentable {
    let store: FlatStore
    let page: FlatPage
    let isShown: Bool
    /// How much of the screen's bottom the app's bars and the home indicator cover.
    let coveredBottom: CGFloat
    /// Which load the page should show (nil: not yet, the tab was never opened): a new value loads it again (Try
    /// again, or a fresh code of the flat: the check runs with the new key).
    let load: String?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PageScript.alwaysDaylightKey) private var alwaysDaylight = false

    func makeCoordinator() -> Coordinator { Coordinator(store: store, page: page) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()       // WebKit keeps nothing on disk; the app keeps the copy.
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
        Coordinator.log.notice("makeUIView")
        #endif
        context.coordinator.webView = webView
        context.coordinator.dark = scheme == .dark
        context.coordinator.alwaysDaylight = alwaysDaylight
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        guard !store.isRetired else {
            coordinator.retire()
            return
        }
        if coordinator.dark != (scheme == .dark) || coordinator.coveredBottom != coveredBottom
            || coordinator.alwaysDaylight != alwaysDaylight {
            coordinator.dark = scheme == .dark
            coordinator.coveredBottom = coveredBottom
            coordinator.alwaysDaylight = alwaysDaylight
            coordinator.sendConfig()
        }
        coordinator.sendConnection(store.link)
        coordinator.update(load: load, isShown: isShown, isActive: scenePhase == .active)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        #if DEBUG
        Coordinator.log.notice("dismantleUIView")
        #endif
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "flat3d")
        coordinator.retire()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let store: FlatStore
        let page: FlatPage
        /// Whether this page may still be told and heard: its web view is in place and its store has not retired
        /// (Forget retires it before anything else, so an old page's messages or queued work command nothing).
        private var isCurrent: Bool { !retired && !store.isRetired }
        /// The web view is gone (or its pairing): nothing more is done for it.
        private var retired = false
        private let cache: ViewerPageCache
        weak var webView: WKWebView?
        var dark = true
        var coveredBottom: CGFloat = 0
        var alwaysDaylight = false
        private var loadedCount: String?
        private var isShown = true
        private var isActive = true
        /// Nil until a process ends and waits for the tab. True if that page ended within a minute of loading.
        private var pendingReload: Bool?
        private var canReloadNow: Bool {
            isShown && isActive && (webView?.window?.windowScene?.activationState ?? .foregroundActive) == .foregroundActive
        }
        /// Ends a load whose page never says `ready` (it failed while starting, or never finished loading): the calm
        /// card with Try again.
        private var readyDeadline: Task<Void, Never>?
        /// Which document may speak (`PageHandover`): a request's result goes only to the document that asked (a
        /// reloaded page may reuse its request ids), and only the load the app handed over, once in place, is heard.
        private var handover = PageHandover()
        private var document: Int { handover.document }
        private var listener: UUID?
        private var lastConnection: FlatStore.Link?
        /// The app navigation whose policy callback WebKit still owes us. A superseded callback can arrive late.
        private var pendingPolicy: (document: Int, navigation: WKNavigation?)?
        private var waitingPage: PreparedPage?
        /// The waits for the page's requests' results (`answer`): ended with the web view.
        private var requests: [UUID: Task<Void, Never>] = [:]
        /// The cache read and the page's fetch or check. One load can hand over both the copy and a new document.
        private var loadTask: Task<Void, Never>?
        private var activeLoad: Load?
        private var timing: DocumentTiming?
        /// Early process ends, bounded across `ready`. A long-lived page resets the count.
        private var automaticReloads = 0
        /// Which document ended WebKit early, and how often in a row: a kept copy that keeps doing so is not shown again.
        private var earlyEnds = EarlyEnds()
        static let maxAutomaticReloads = 3
        /// The page's address inside the web view: a name that never resolves (`.invalid`, RFC 2606), so the page has
        /// an ordinary origin of its own and nothing it does can reach a real server. Never flatd's address.
        static let pageURL = URL(string: "https://viewer.arestia.invalid/")!
        fileprivate static let log = Logger(subsystem: "de.ares-empire.arestia", category: "viewer")

        /// `cache`: the copy kept on the phone (the tests pass one of their own).
        init(store: FlatStore, page: FlatPage, cache: ViewerPageCache = .live) {
            self.store = store
            self.page = page
            self.cache = cache
        }

        /// The document handed over last, for the tests: where it came from (`copy`, `flatd`) and its SHA-256.
        var shown: (source: String, sha256: String?)? { timing.map { ($0.source.rawValue, $0.sha256) } }

        /// How long the page has to say `ready` once its load began.
        static let readyWithin: Duration = .seconds(30)

        private struct Load {
            let id: Int
            let credentials: Int
            let started: ContinuousClock.Instant
        }

        private enum Source: String { case copy, flatd }

        private struct PreparedPage {
            let html: Data
            let source: Source
            let sha256: String?
            let readOrDownload: Int64
            let load: Load
        }

        private struct DocumentTiming {
            let source: Source
            let sha256: String?
            let bytes: Int
            let readOrDownload: Int64
            let handedOver: ContinuousClock.Instant
            var committed: ContinuousClock.Instant?
        }

        func update(load: String?, isShown: Bool, isActive: Bool) {
            self.isShown = isShown
            self.isActive = isActive
            if let load, loadedCount != load, pendingReload == nil || canReloadNow {
                self.load(load)
            } else {
                reloadIfVisible()
            }
        }

        /// Displays the kept copy while the pinned client checks flatd, or fetches a page on the first visit.
        func load(_ count: String? = nil) {
            let started = ContinuousClock.now
            guard isCurrent else { return }
            pendingReload = nil
            if let count {
                loadedCount = count
                automaticReloads = 0                    // asked for (Try again, a fresh code): WebKit may retry again
            }
            cancelLoad()
            let loading = Load(id: document, credentials: store.credentials, started: started)
            activeLoad = loading
            let client: FlatdClient
            switch store.pageClient() {
            case let .success(found):
                client = found
            case let .failure(error):
                fail(error.message(), log: "no client for the page (\(String(describing: error)))")
                return
            }
            guard let pairing = store.pairingID else {
                fail(FlatdError.notPaired.message(), log: "no pairing for the page")
                return
            }
            startDeadline(loading)
            loadTask = Task { [weak self, cache] in
                guard self?.isLoading(loading) == true else { return }
                let readStarted = ContinuousClock.now
                let kept = await cache.page(pairing: pairing, pin: client.pin)
                let readTime = Self.milliseconds(since: readStarted)
                guard let self, isLoading(loading) else { return }
                defer { if activeLoad?.id == loading.id { loadTask = nil } }
                // A copy that ended WebKit early again and again is not shown, nor asked about: flatd's page is
                // fetched whole, so a fixed page repairs it (Codex's review of the 3D page, finding 3: every reload
                // and Try again reopened the same bytes first, and the page's end cancelled the fetch each time).
                guard let kept, earlyEnds.trusts(kept.sha256) else {
                    if kept != nil { Self.log.notice("3D page: the kept copy kept ending WebKit early; fetching flatd's") }
                    await fetchPage(client, pairing: pairing, kept: nil, loading: loading)
                    return
                }
                guard await handOver(kept.html, from: .copy, sha256: kept.sha256, took: readTime, loading: loading),
                      isLoading(loading) else { return }
                await fetchPage(client, pairing: pairing, kept: kept, loading: loading)
            }
        }

        private func fetchPage(_ client: FlatdClient, pairing: UUID, kept: ViewerPageCache.Kept?, loading: Load) async {
            let started = ContinuousClock.now
            let answer: FlatdClient.ViewerPage
            do {
                answer = try await client.viewerPage(ifNoneMatch: kept?.etag)
            } catch {
                guard isLoading(loading) else { return }
                if kept != nil {
                    logCheck("failed", since: started, loading: loading)
                } else {
                    let reason = error as? FlatdError ?? .unreachable
                    fail(reason == .unknown ? String(localized: "flatd has no 3D flat set up yet.") : reason.message(),
                         log: "the page could not be fetched (\(String(describing: reason)))")
                }
                return
            }
            guard isLoading(loading) else { return }
            switch answer {
            case .unchanged:
                if kept != nil {
                    logCheck("unchanged", since: started, loading: loading)
                } else {
                    fail(FlatdError.invalidAnswer.message(), log: "flatd returned 304 without a kept page")
                }
            case let .page(html, etag):
                let downloadTime = Self.milliseconds(since: started)
                let hash = await cache.save(html, etag: etag, pairing: pairing, pin: client.pin)
                guard isLoading(loading) else { return }
                if let kept {
                    let same = hash == kept.sha256
                    logCheck(same ? "same bytes" : "changed", since: started, loading: loading)
                    if same { return }
                }
                _ = await handOver(html, from: .flatd, sha256: hash, took: downloadTime, loading: loading)
            }
        }

        /// No document is loaded without its network fence. A replacement gets a new bridge and ready deadline.
        private func handOver(_ html: Data, from source: Source, sha256: String?, took elapsed: Int64,
                              loading: Load) async -> Bool {
            let blocked = await blockTheNetwork(loading)
            guard isLoading(loading) else { return false }
            guard blocked else {
                fail(String(localized: "The 3D flat didn't start."), log: "the network rules did not install")
                return false
            }
            return present(PreparedPage(html: html, source: source, sha256: sha256, readOrDownload: elapsed,
                                        load: loading))
        }

        private func present(_ next: PreparedPage) -> Bool {
            guard isLoading(next.load) else { return false }
            // The policy callback has no navigation identity on iOS 26. Let it answer before granting another
            // permit, even when stopLoading would leave the old callback queued in WebKit.
            if pendingPolicy != nil {
                waitingPage = next
                return true
            }
            if timing != nil {
                resetDocument()
                startDeadline(next.load)
            }
            let arriving = document
            pendingPolicy = (arriving, nil)
            timing = DocumentTiming(source: next.source, sha256: next.sha256, bytes: next.html.count,
                                    readOrDownload: next.readOrDownload, handedOver: .now)
            let navigation = webView?.load(next.html, mimeType: "text/html", characterEncodingName: "utf-8",
                                           baseURL: Self.pageURL)
            guard handover.loading(arriving, as: navigation) else {
                pendingPolicy = nil
                fail(String(localized: "The 3D flat didn't start."), log: "WebKit did not start the load")
                return false
            }
            if pendingPolicy?.document == arriving { pendingPolicy?.navigation = navigation }
            return true
        }

        @discardableResult
        private func presentWaitingPage() -> Bool {
            guard let waitingPage else { return false }
            self.waitingPage = nil
            return present(waitingPage)
        }

        private func isLoading(_ load: Load) -> Bool {
            isCurrent && !Task.isCancelled && activeLoad?.id == load.id && store.credentials == load.credentials
        }

        private func startDeadline(_ loading: Load) {
            let awaited = document
            readyDeadline = Task { [weak self] in
                try? await Task.sleep(for: Self.readyWithin)
                guard let self, isLoading(loading), awaited == document, !page.isReady else { return }
                fail(String(localized: "The 3D flat didn't start."), log: "the page did not say ready in time")
            }
        }

        private func resetDocument() {
            stopListening()
            readyDeadline?.cancel()
            readyDeadline = nil
            _ = handover.begin()
            timing = nil
            page.isReady = false
            if pendingPolicy == nil { webView?.stopLoading() }
        }

        private func cancelLoad() {
            activeLoad = nil
            waitingPage = nil
            loadTask?.cancel()
            loadTask = nil
            resetDocument()
            page.problem = nil
        }

        private func fail(_ problem: String, log reason: String) {
            cancelLoad()
            Self.log.error("3D page: \(reason, privacy: .public)")
            page.problem = problem
        }

        private static func milliseconds(since start: ContinuousClock.Instant, until end: ContinuousClock.Instant = .now) -> Int64 {
            let duration = start.duration(to: end).components
            return duration.seconds * 1_000 + duration.attoseconds / 1_000_000_000_000_000
        }

        private func logCheck(_ outcome: String, since start: ContinuousClock.Instant, loading: Load) {
            Self.log.notice("3D page check \(outcome, privacy: .public) \(Self.milliseconds(since: start), privacy: .public) ms, ended \(Self.milliseconds(since: loading.started), privacy: .public) ms after load")
        }

        private func logReady(_ loading: Load) {
            guard let timing, let committed = timing.committed else { return }
            let measure = timing.source == .copy ? "read" : "download"
            let handed = Self.milliseconds(since: loading.started, until: timing.handedOver)
            let commit = Self.milliseconds(since: loading.started, until: committed)
            let ready = Self.milliseconds(since: loading.started)
            Self.log.notice("3D page \(timing.source.rawValue, privacy: .public) \(timing.bytes, privacy: .public) bytes, \(measure, privacy: .public) \(timing.readOrDownload, privacy: .public) ms, handed over \(handed, privacy: .public) ms, committed \(commit, privacy: .public) ms, ready \(ready, privacy: .public) ms")
        }

        func stopListening() {
            if let listener { store.unlisten(listener) }
            listener = nil
            lastConnection = nil
        }

        /// The web view goes (its pairing ended, or the tab was rebuilt): its listener, its deadline, its fetch and the
        /// waits for its requests' results end, and nothing it still sends is heard.
        func retire() {
            guard !retired else { return }
            retired = true
            pendingReload = nil
            pendingPolicy = nil
            cancelLoad()
            requests.values.forEach { $0.cancel() }
            requests = [:]
        }

        /// A page request's one result, sent to the document that asked once the store's command ended. The wait ends
        /// with the web view; the command, given by a tap, goes on as one from Home would (the store cancels it only
        /// when it retires).
        private func answer(_ reqId: String, _ command: Task<FlatdError?, Never>) {
            let asking = document
            let token = UUID()
            #if DEBUG && ARESTIA_GATE
            let trace = GateAction.current
            #endif
            requests[token] = Task { [weak self] in
                let error = await command.value
                #if DEBUG && ARESTIA_GATE
                guard let self, !Task.isCancelled else {
                    trace?.ended(.cancelled)
                    return
                }
                requests[token] = nil
                guard asking == document else {
                    trace?.ended(.cancelled)
                    return
                }
                let result = PageScript.result(reqId: reqId, error: error)
                if let trace {
                    send(result, forDocument: asking, tracing: trace, outcome: error.map(GateOutcome.init) ?? .ok)
                } else {
                    send(result)
                }
                #else
                guard let self, !Task.isCancelled else { return }
                requests[token] = nil
                if asking == document { send(PageScript.result(reqId: reqId, error: error)) }
                #endif
            }
        }

        // MARK: page → app

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            // Only the page the app handed over, in the main frame, of a store that has not retired, may speak.
            guard let loading = activeLoad, isLoading(loading), handover.maySpeak, message.frameInfo.isMainFrame,
                  isThePage(message.frameInfo.securityOrigin),
                  let parsed = PageMessage.parse(message.body) else { return }
            switch parsed {
            case .ready:
                guard !page.isReady, let snapshot = store.snapshot else { return }
                readyDeadline?.cancel()
                readyDeadline = nil
                page.isReady = true
                page.problem = nil
                logReady(loading)
                sendConfig()
                lastConnection = nil
                sendConnection(store.link)
                send(snapshot.json)
                if listener == nil {
                    listener = store.listen { [weak self] event in self?.send(event.json) }
                }
                #if DEBUG
                Self.log.notice("ready")
                if LaunchArguments.current.contains("-probeViewer") { probe() }
                #endif
            // The store takes each command's place in line right here, in the order the page sent them (round 8: two
            // taps on one fan could otherwise reach flatd the other way round); the result follows when it ended.
            case let .request(reqId, id, body):
                answer(reqId, store.pageRequest(id, body: body))
            case let .mode(reqId, id, body):
                #if DEBUG && ARESTIA_GATE
                let trace = id == FlatMode.cookingID ? GateAction("ViewerCooking") : nil
                GateAction.$current.withValue(trace) {
                    answer(reqId, store.pageMode(id, body: body))
                }
                #else
                answer(reqId, store.pageMode(id, body: body))
                #endif
            case let .invalid(reqId):
                send(PageScript.result(reqId: reqId, error: .failed(status: 400, message: nil)))
            case let .haptic(style):
                switch style {
                case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
                case "error": UINotificationFeedbackGenerator().notificationOccurred(.error)
                case "medium": UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                default: UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            case let .log(level, text, timing):
                let type: OSLogType = switch level {
                case .error: .error
                case .warn: .default              // notice
                case .info: .info
                }
                #if DEBUG
                Self.log.log(level: type, "page: \(text, privacy: .public)")
                #else
                Self.log.log(level: type, "page: \(text, privacy: .private)")
                #endif
                if !timing.isEmpty {
                    let line = PageMessage.timingLine(timing)
                    Self.log.notice("page timing: \(line, privacy: .public)")
                }
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
            let probing = document
            Task { [weak self] in
                for _ in 0..<6 {
                    guard let self, isCurrent, probing == document else { return }
                    let answer = try? await webView?.evaluateJavaScript(script) as? String
                    guard isCurrent, probing == document else { return }
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
            if link == .live { send(store.snapshot?.json) }               // after every reconnect to flatd (BRIDGE.md)
        }

        private func send(_ json: Data?) {
            guard let loading = activeLoad, isLoading(loading), handover.maySpeak, let json, let webView else { return }
            webView.evaluateJavaScript(PageScript.receive(json)) { _, error in
                if let error { Self.log.notice("receive failed: \(error.localizedDescription, privacy: .public)") }
            }
        }
        #if DEBUG && ARESTIA_GATE
        /// Wait for WebKit to confirm that the current document's receive function ran.
        private func send(_ json: Data, forDocument asking: Int, tracing trace: GateAction, outcome: GateOutcome) {
            guard let loading = activeLoad, isLoading(loading), handover.maySpeak, let webView else {
                trace.ended(.cancelled)
                return
            }
            let script = """
                (() => {
                    if (typeof window.flat3d?.receive !== 'function') return false;
                    \(PageScript.receive(json))
                    return true;
                })()
                """
            webView.evaluateJavaScript(script) { [weak self] value, error in
                guard let self, asking == document, isLoading(loading), handover.maySpeak else {
                    trace.ended(.cancelled)
                    return
                }
                if error == nil, value as? Bool == true {
                    trace.resultReturned(outcome)
                } else {
                    trace.ended(.failed)
                }
            }
        }
        #endif

        /// The page is self-contained and the app is its only way out: nothing may be loaded or reached from it (no
        /// remote script, fetch or socket), whatever the page does. A content rule list; false when it could not be
        /// installed (then the web view keeps the rules it had, and the caller loads nothing).
        private func blockTheNetwork(_ loading: Load) async -> Bool {
            guard let webView else { return false }
            let list = await Self.noNetworkRules()
            guard isLoading(loading), let list else { return false }
            webView.configuration.userContentController.removeAllContentRuleLists()
            webView.configuration.userContentController.add(list)
            return true
        }

        /// The rule list that blocks every network load. Compiling it took about a quarter of a second of every load on
        /// the simulator, so it is compiled once and kept by WebKit under a name that carries the rules' own hash (a
        /// changed rule set is compiled anew, never an old one used), and held for the app's run.
        private static var noNetwork: WKContentRuleList?
        private static func noNetworkRules() async -> WKContentRuleList? {
            if let noNetwork { return noNetwork }
            let rules = """
            [{"trigger": {"url-filter": "^https?://"}, "action": {"type": "block"}},
             {"trigger": {"url-filter": "^wss?://"}, "action": {"type": "block"}}]
            """
            let digest = SHA256.hash(data: Data(rules.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
            let name = "arestia-viewer-no-network-" + digest, store = WKContentRuleListStore.default()
            let list: WKContentRuleList?
            if let kept = try? await store?.contentRuleList(forIdentifier: name) {
                list = kept
            } else {
                list = try? await store?.compileContentRuleList(forIdentifier: name, encodedContentRuleList: rules)
            }
            if noNetwork == nil { noNetwork = list }
            return noNetwork ?? list
        }

        /// The page's origin is the one the app gave it (WebKit reports a default port as 0).
        private func isThePage(_ origin: WKSecurityOrigin) -> Bool {
            origin.protocol == "https" && origin.host == Self.pageURL.host() && (origin.port == 0 || origin.port == 443)
        }

        // MARK: navigation: only the page the app hands over

        /// Only the one document `load()` hands over: the page itself never navigates or reloads (a new document would
        /// take the bridge without the app knowing; WebKit's own reload after its process ended goes through `load()`
        /// too). The web view never fetches a document from the network at all.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, isCurrent else {
                decisionHandler(.cancel)
                return
            }
            // Frames inside the page may be blank ones; the main frame is only ever the page handed over.
            if url.scheme == "about", action.targetFrame?.isMainFrame == false {
                decisionHandler(.allow)
                return
            }
            guard let pendingPolicy, action.targetFrame?.isMainFrame == true, action.navigationType == .other,
                  url == Self.pageURL else {
                decisionHandler(.cancel)
                return
            }
            self.pendingPolicy = nil
            let allowed = pendingPolicy.document == document && activeLoad.map(isLoading) == true
            decisionHandler(allowed ? .allow : .cancel)
            presentWaitingPage()
        }

        /// The page handed over is in place: from now on it is the one that may speak. Only the navigation `load()`
        /// started for the newest document counts (`PageHandover`).
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            guard let loading = activeLoad, isLoading(loading), handover.awaits(navigation) else { return }
            handover.committed(navigation)
            timing?.committed = .now
        }

        /// Never trust a server from inside the web view: the page has no business with one, and flatd's identity is
        /// checked in one place only (`FlatdTransport`).
        func webView(_ webView: WKWebView, respondTo challenge: URLAuthenticationChallenge)
            async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            (.cancelAuthenticationChallenge, nil)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if let navigation, pendingPolicy?.navigation === navigation {
                pendingPolicy = nil
                if presentWaitingPage() { return }
            }
            guard let loading = activeLoad, isLoading(loading), handover.concerns(navigation),
                  (error as NSError).code != NSURLErrorCancelled else { return }
            fail(FlatdError.unreachable.message(), log: "WebKit failed the load (\((error as NSError).code))")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard let loading = activeLoad, isLoading(loading), handover.concerns(navigation),
                  (error as NSError).code != NSURLErrorCancelled else { return }
            fail(FlatdError.unreachable.message(), log: "WebKit failed the page (\((error as NSError).code))")
        }

        /// In the background WebKit may reclaim the page. Reload once the tab can show it again.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            pendingPolicy = nil
            guard let loading = activeLoad, isLoading(loading) else { return }
            let age = (timing?.handedOver ?? loading.started).duration(to: .now)
            if age < .seconds(60) { earlyEnds.ended(timing?.sha256) } else { earlyEnds.lived(timing?.sha256) }
            cancelLoad()
            pendingReload = age < .seconds(60)
            reloadIfVisible()
        }

        private func reloadIfVisible() {
            guard isCurrent, canReloadNow, let endedEarly = pendingReload else { return }
            pendingReload = nil
            if endedEarly {
                guard automaticReloads < Self.maxAutomaticReloads else {
                    fail(String(localized: "The 3D flat didn't start."), log: "WebKit's page process kept ending")
                    return
                }
                automaticReloads += 1
            } else {
                automaticReloads = 0
            }
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

/// Which document ended WebKit's page process early (within a minute of being handed over), how often in a row. A kept
/// copy of the page that has done so `distrustAfter` times is not shown again while it stays the same bytes: the next
/// load, an automatic one or Try again, fetches flatd's page without asking about the copy (Codex's review of the 3D
/// page, finding 3). A document that lived longer than that, or another one ending early, starts the count afresh.
nonisolated struct EarlyEnds: Equatable, Sendable {
    static let distrustAfter = 2
    private(set) var page: String?
    private(set) var count = 0

    /// A document (its SHA-256; nil: unknown, not counted) ended WebKit early.
    mutating func ended(_ sha256: String?) {
        guard let sha256 else { return }
        if page == sha256 { count += 1 } else { (page, count) = (sha256, 1) }
    }

    /// A document ended WebKit after living longer: its early ends are forgotten.
    mutating func lived(_ sha256: String?) {
        if sha256 != nil, page == sha256 { (page, count) = (nil, 0) }
    }

    /// Whether a copy with these bytes may be shown.
    func trusts(_ sha256: String) -> Bool { page != sha256 || count < Self.distrustAfter }
}
