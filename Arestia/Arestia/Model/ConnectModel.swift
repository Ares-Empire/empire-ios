import Foundation
import Network
import Observation
import os

/// Looks for flatd on the home network while the connect screen is open (`_flatd._tcp`). iOS asks once for the local
/// network; refused, the screen says how to allow it.
@MainActor @Observable
final class FlatdBrowser {
    enum State: Equatable { case idle, searching, denied, failed }

    private(set) var state: State = .idle
    /// The services' names, as flatd advertises itself ("flatd", "flatd (2)").
    private(set) var found: [String] = []
    private var browser: NWBrowser?
    private var promptOpen = false
    private static let log = Logger(subsystem: "de.ares-empire.arestia", category: "bonjour")
    /// Set once the iPhone has been asked about the local network (then no prompt can come up any more).
    private static let askedKey = "arestia.localNetworkAsked"

    func start() {
        guard browser == nil else { return }
        state = .searching
        // The first browse may bring iOS's local network question over the app: hold the switcher cover back for it
        // (`SystemPrompt`, as every place that asks iOS for something).
        if !UserDefaults.standard.bool(forKey: Self.askedKey) {
            UserDefaults.standard.set(true, forKey: Self.askedKey)
            SystemPrompt.begin()
            promptOpen = true
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                self?.endPrompt()
            }
        }
        let browser = NWBrowser(for: .bonjour(type: FlatdBonjour.type, domain: FlatdBonjour.domain), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.update(state) }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let names = results.compactMap { result -> String? in
                if case let .service(name, _, _, _) = result.endpoint { name } else { nil }
            }
            Task { @MainActor in self?.update(names) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        if state == .searching { state = .idle }
        endPrompt()
    }

    private func update(_ state: NWBrowser.State) {
        switch state {
        case let .waiting(error), let .failed(error):
            if case let .dns(code) = error, code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) {
                self.state = .denied
            } else if case .failed = state {
                self.state = .failed
            }
            Self.log.notice("browse: \(String(describing: error), privacy: .public)")
            endPrompt()
        case .ready:
            if self.state != .denied { self.state = .searching }
        default:
            break
        }
    }

    private func update(_ names: [String]) {
        found = names.sorted()
        if !names.isEmpty { endPrompt() }
    }

    private func endPrompt() {
        guard promptOpen else { return }
        promptOpen = false
        SystemPrompt.end()
    }
}

/// The connect screen's state: flatd's pairing code (scanned or pasted) and what connecting with it answered.
@MainActor @Observable
final class ConnectModel {
    /// The code read, until it connected.
    private(set) var code: PairingCode?
    private(set) var isConnecting = false
    private(set) var problem: String?
    let browser = FlatdBrowser()
    /// Where else flatd may be, when it is not at the code's address (Bonjour; candidates only, `FlatdBonjour`).
    private let candidates: @Sendable () async -> [URL]
    /// Counts the attempts: only the newest one says how it went (an earlier one, cancelled when the code changed, may
    /// still be on its way out).
    private var attempts = 0

    init(code: PairingCode? = nil, candidates: @escaping @Sendable () async -> [URL] = { await FlatdBonjour.candidates() }) {
        self.code = code
        self.candidates = candidates
    }

    var canConnect: Bool { code != nil && !isConnecting }

    /// A scanned or pasted text: flatd's pairing code, or not. Returns the code it was (nil: none).
    @discardableResult
    func take(_ text: String) -> PairingCode? {
        guard let code = PairingCode.parse(text) else {
            self.code = nil                    // whatever was read before is not what is on screen now
            problem = String(localized: "That isn't a pairing code from flatd.")
            return nil
        }
        problem = nil
        self.code = code
        return code
    }

    /// Looks for the flatd of exactly this code at its address, then at the ones Bonjour offers, and lets the store
    /// keep the pairing at the first where flatd answered: a first pairing, or a fresh code of the flat paired now. A
    /// code of another flat while one is paired is refused at once, nothing asked anywhere (one flat per install: Forget
    /// first). Every attempt goes through the transport pinned to the code's identity, so an address is only somewhere
    /// to look: a server without flatd's key gets nothing, and the next address is tried. The code is the one handed in
    /// from start to end, whatever is scanned meanwhile, and the store is the one the attempt began with.
    func connect(_ code: PairingCode, store: FlatStore) async -> Bool {
        attempts += 1
        let attempt = attempts
        problem = nil
        if store.isAnotherFlat(code.pin) {
            problem = FlatdError.anotherFlat.message()
            return false
        }
        isConnecting = true
        defer { if attempt == attempts { isConnecting = false } }
        var tried: [URL] = []
        var failure = FlatdError.unreachable

        /// True: connected. False: flatd answered and said no (looking elsewhere is pointless). Nil: not there.
        func attemptAt(_ url: URL) async -> Bool? {
            tried.append(url)
            guard let error = await store.connect(to: url, token: code.token, pin: code.pin) else { return true }
            failure = error
            return error == .unreachable || error == .noAnswer ? nil : false
        }

        var outcome: Bool?
        if let hint = code.baseURL { outcome = await attemptAt(hint) }
        if outcome == nil, !Task.isCancelled {
            // Bonjour's addresses are asked side by side, without the key (`FlatStore.locate`): forged ones cannot use
            // up the time, and the key goes out once, to the address where the code's identity answered.
            let others = await candidates().filter { !tried.contains($0) }
            guard !Task.isCancelled else { return false }
            if let found = await store.locate(code, among: others) { outcome = await attemptAt(found) }
        }
        if outcome == true {
            if self.code == code { self.code = nil }
            return true
        }
        guard !Task.isCancelled, attempt == attempts else { return false }
        problem = switch failure {
        case .refused:
            String(localized: "flatd has a new key. Run “flatd pair” again and scan the new code.")
        case .unreachable, .noAnswer:
            String(localized: "The flat service isn't answering. Check that this iPhone is on the home Wi-Fi and flatd is running. If flatd was set up anew, scan a new code.")
        default:
            failure.message()
        }
        return false
    }
}
