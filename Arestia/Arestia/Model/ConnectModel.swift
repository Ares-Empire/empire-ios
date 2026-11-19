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

/// The connect screen's state: which flatd (found, or an address typed in), the key, and what Connect answered.
@MainActor @Observable
final class ConnectModel {
    enum Target: Equatable {
        case service(String)
        case address(URL)
    }

    var key = ""
    var typedAddress = ""
    var chosenService: String?
    var typesAddress = false
    private(set) var isConnecting = false
    private(set) var problem: String?
    let browser = FlatdBrowser()

    init(code: PairingCode? = nil, current: FlatdLink? = nil) {
        if let code {
            key = code.token
            if let url = code.baseURL {
                typedAddress = url.absoluteString
                typesAddress = true
            }
        } else if let current {
            if let name = current.serviceName { chosenService = name } else {
                typedAddress = current.baseURL.absoluteString
                typesAddress = true
            }
        }
    }

    /// The flatd to connect to: a typed address wins while the field is open, else the service chosen (or the only
    /// one found).
    var target: Target? {
        if typesAddress {
            return PairingCode.serviceURL(addressWithScheme).map(Target.address)
        }
        if let chosenService, browser.found.contains(chosenService) { return .service(chosenService) }
        if browser.found.count == 1 { return .service(browser.found[0]) }
        return nil
    }

    /// "192.168.1.20:8787" as typed gets its scheme.
    private var addressWithScheme: String {
        let text = typedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.contains("://") ? text : "http://" + text
    }

    var canConnect: Bool { target != nil && PairingCode.cleanToken(key) != nil && !isConnecting }

    /// A pasted or scanned text: a key alone, or a code that also says where flatd is.
    func take(_ text: String) {
        guard let code = PairingCode.parse(text) else {
            problem = String(localized: "That isn't a key from the flat service.")
            return
        }
        problem = nil
        key = code.token
        if let url = code.baseURL {
            typedAddress = url.absoluteString
            typesAddress = true
        }
    }

    /// Finds the address (resolving a Bonjour name), then lets the store check it with flatd and keep it.
    func connect(store: FlatStore) async -> Bool {
        guard let target, let token = PairingCode.cleanToken(key) else { return false }
        isConnecting = true
        problem = nil
        defer { isConnecting = false }
        let url: URL, name: String?
        switch target {
        case let .address(address):
            url = address
            name = nil
        case let .service(service):
            guard let resolved = await FlatdBonjour.resolve(name: service) else {
                problem = FlatdError.unreachable.message()
                return false
            }
            url = resolved
            name = service
        }
        if let error = await store.connect(to: url, serviceName: name, token: token) {
            problem = error == .refused
                ? String(localized: "The flat service doesn't know this key.")
                : error.message()
            return false
        }
        return true
    }
}
