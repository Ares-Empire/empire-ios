import Foundation
import Security
import Testing
@testable import Arestia

// How the app knows it is talking to flatd: the pin (the SHA-256 of flatd's public key, from the pairing code) against
// the certificate a server presents; the pairing code; and that an address from Bonjour is only somewhere to look.

/// Made-up certificates, generated for these tests with throwaway keys that were deleted at once (the public halves
/// only; no flatd ever used them). `a`, `aRenewed` and `aExpired` share one P-256 key; `b` has another.
enum MadeUpCertificates {
    /// `openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | shasum -a 256` of `a`.
    static let pinA = FlatdPin("29d819b9fa55faa381f7de497d72bcffa9c2fbf9d25afca2ac25d27ed5a77b65")!
    static let pinB = FlatdPin("2da630a95e90ac0a8594988b53c3fffa4a945949e7f1a1a6f6e51855eada1283")!

    static let a = certificate(
            "MIIBDjCBtgIJAISJXEeNfAh2MAoGCCqGSM49BAMCMBAxDjAMBgNVBAMMBWZsYXRkMB4XDTI2MTExOTIyNDMxMloXDTM2MTEx" +
            "NjIyNDMxMlowEDEOMAwGA1UEAwwFZmxhdGQwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAASQej6RGumQ20x4a0aG83+DnVpW" +
            "uO8ehT08A4fIjGUx7rkfGevZfm6+Go552IHAmq9KIkqORWUBBohW6PbxmqT6MAoGCCqGSM49BAMCA0cAMEQCIFbw/qE5aYBm" +
            "w1OxsOy54S7k+W8swxGbsg5Y8ymvMJTuAiAYATaoZj049eXvn2RvB1su2X8bfPK/eBDUh50/S2/9gQ==")
    static let aRenewed = certificate(
            "MIIBDjCBtgIJAJyTsk2k1SGEMAoGCCqGSM49BAMCMBAxDjAMBgNVBAMMBWZsYXRkMB4XDTI2MTExOTIyNDMxMloXDTI2MTIx" +
            "OTIyNDMxMlowEDEOMAwGA1UEAwwFZmxhdGQwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAASQej6RGumQ20x4a0aG83+DnVpW" +
            "uO8ehT08A4fIjGUx7rkfGevZfm6+Go552IHAmq9KIkqORWUBBohW6PbxmqT6MAoGCCqGSM49BAMCA0cAMEQCIEfYvAS1fcpN" +
            "9jsG2AnLgU4B4MYMbLonhnFogcaPPEgOAiB+sb2zoP3PUXH2mh8y2ywrUxSgvvbaSE9jm1BDS4lySg==")
    static let aExpired = certificate(
            "MIIBIDCBxqADAgECAhRhMCBhVwDYo0fFmMiw6wRZVpI9izAKBggqhkjOPQQDAjAQMQ4wDAYDVQQDDAVmbGF0ZDAeFw0yMDAx" +
            "MDEwMDAwMDBaFw0yMTAxMDEwMDAwMDBaMBAxDjAMBgNVBAMMBWZsYXRkMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEkHo+" +
            "kRrpkNtMeGtGhvN/g51aVrjvHoU9PAOHyIxlMe65Hxnr2X5uvhqOediBwJqvSiJKjkVlAQaIVuj28Zqk+jAKBggqhkjOPQQD" +
            "AgNJADBGAiEA8PpPMKmb+lwD/rw5QIIPhZ27Dq+VT31dm6y+5APpko8CIQC/56bm9eT3Ywb0vCpu6dlWZ0T32d87NdDD3fw4" +
            "Xid1aw==")
    static let b = certificate(
            "MIIBDzCBtgIJAOY32wPwnH7eMAoGCCqGSM49BAMCMBAxDjAMBgNVBAMMBWZsYXRkMB4XDTI2MTExOTIyNDMxMloXDTM2MTEx" +
            "NjIyNDMxMlowEDEOMAwGA1UEAwwFZmxhdGQwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAATXg29Z4YeXMHcPsI3ivdaCB+eZ" +
            "+OoFI9+tlqXubWlba6iaU/D582ntEC0ZT5XfIRIMOLQBLmOLC7J1rD3HQJFOMAoGCCqGSM49BAMCA0gAMEUCIB4iZXUVBi57" +
            "WMc46Rvn71DDpwrnfWlD9YDd9VXCdU0LAiEA/WNo6bnTRQlksa+jQHtEh4J1J4kDBb3Yb7picmt/DAg=")
    static let rsa = certificate(
            "MIICrDCCAZSgAwIBAgIUQvggkWdkQ540YHPDtm6I2hkY7VQwDQYJKoZIhvcNAQELBQAwEDEOMAwGA1UEAwwFZmxhdGQwHhcN" +
            "MjYwMTAxMDAwMDAwWhcNMzYwMTAxMDAwMDAwWjAQMQ4wDAYDVQQDDAVmbGF0ZDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCC" +
            "AQoCggEBAL10lCLo1J2IT1mQq99GAES08/yMfsm8BFgN3TVZTlW4eojT0AFAFJCFyYKN4kPp9AyfVTKiXt0B1NlkoUFXpAoX" +
            "ut5CVXbBPnJjCuYFp8tKe2Enn1oF9hj9ADn0LnfdwcrNC9/knNu5ODKFfC81lBjOMTBUvNFf3nvd+tlfGkuEJX0iURNlM7Lo" +
            "B81ZwRCnb1glBRvpZ1VrKTXg61jHKbWNEk8WGkpRsodLH4mTJ+fjvu0TC48LM9HL00fJ9K9BHoskDNF/LH3Eyy3xxDm29+pn" +
            "pYpjpSAcWovoO7MmFIxGjQZ1XcBR/ynII4GmW567GjglVfV/qkhftqgv+gF2SHUCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEA" +
            "J5RUcplX6PqqppvWzi7MRQv9W/org+VY2tCD5QXwO8nFl0RIgaynjqnaJSDQJtIDmTnvfO1OBlX7s+HKYW1rhyrlaVLYmFUn" +
            "nOpROvx6DtfAj+rtvcUg26McmiozNMdUDe2rZTleJ60F+qtBgkA+0MkhZf23M5Mz2MZEcD5rP2yDco03guqhjjESJu5wVbsH" +
            "W7d+RXX+EtVojxsup7U+eXSzM/DwuT8yI6bZeblUICKUH2Ng2VCbYyASwaJGunIVVE0QKzSbcwwO0O0RirPnZS7T6cymNxXQ" +
            "d50HpsVcmNljW39DgNkKYAO/jeSrNuKsuBfyvWHX+Z+V+wvZgHevvA==")
    static let p384 = certificate(
            "MIIBXDCB46ADAgECAhQbPaR9W81wnZRZPo86vMtpUMj6dzAKBggqhkjOPQQDAjAQMQ4wDAYDVQQDDAVmbGF0ZDAeFw0yNjAx" +
            "MDEwMDAwMDBaFw0zNjAxMDEwMDAwMDBaMBAxDjAMBgNVBAMMBWZsYXRkMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAE1TlpYVJT" +
            "cMPYaIsAK02dtfDGod0vwtYTXih5O2Q0WVOhGr9wzEH6TNYenlTn8/qdaZdvyCYx0AmPOoVAU2hpwBYC69UWAVrOBqVIUAmo" +
            "DW+Y5ykOdQhxjMgYtAJ4MZHUMAoGCCqGSM49BAMCA2gAMGUCMB0e6ns2YOfN3Ahr/+EWcDPp5udde4xZewyCCwX1RKPopex1" +
            "8dLoAt/gxSIRptJ9qgIxAIa/JqSc9Fw9pFvU8pcIp60LrvLMl2rwbvqozN8HByGrlea/rCxauKlq3f8/pDVb7A==")

    static func certificate(_ base64: String) -> SecCertificate {
        SecCertificateCreateWithData(nil, Data(base64Encoded: base64)! as CFData)!
    }

    /// What a server presenting this certificate hands the app in the TLS handshake.
    static func trust(_ certificate: SecCertificate) -> SecTrust {
        var trust: SecTrust?
        SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust)
        return trust!
    }
}

struct PinTests {
    typealias Made = MadeUpCertificates

    @Test func thePinIsTheHashOfTheCertificatesPublicKey() {
        #expect(FlatdPin.of(Made.a) == Made.pinA)             // the same value OpenSSL computes
        #expect(FlatdPin.of(Made.b) == Made.pinB)
        #expect(Made.pinA != Made.pinB)
    }

    @Test func aServerWithFlatdsKeyIsAccepted() {
        #expect(Made.pinA.matches(Made.trust(Made.a)))
        let (disposition, credential) = PinnedServer(pin: Made.pinA)
            .verdict(method: NSURLAuthenticationMethodServerTrust, trust: Made.trust(Made.a))
        #expect(disposition == .useCredential && credential != nil)
    }

    @Test func aServerWithAnotherKeyIsRejected() {
        #expect(!Made.pinA.matches(Made.trust(Made.b)))
        let server = PinnedServer(pin: Made.pinA)
        let (disposition, credential) = server.verdict(method: NSURLAuthenticationMethodServerTrust,
                                                       trust: Made.trust(Made.b))
        #expect(disposition == .cancelAuthenticationChallenge && credential == nil)
        // No certificate at all: rejected too.
        #expect(server.verdict(method: NSURLAuthenticationMethodServerTrust, trust: nil).0 == .cancelAuthenticationChallenge)
    }

    @Test func theKeyCountsNotTheCertificate() {
        // flatd renewed its certificate, or its certificate ran out: the same key, the same flatd, no new pairing.
        #expect(Made.pinA.matches(Made.trust(Made.aRenewed)))
        #expect(Made.pinA.matches(Made.trust(Made.aExpired)))
        #expect(!Made.pinB.matches(Made.trust(Made.aRenewed)))
    }

    @Test func onlyAP256KeyCanBeFlatds() {
        #expect(FlatdPin.of(Made.rsa) == nil)
        #expect(FlatdPin.of(Made.p384) == nil)
        // Even with the hash of its own key pinned, such a server is not accepted.
        for (pin, certificate) in [("74e8161d41e1bf9a01890fc5ccbb3d25db23ec0f840613eccff61d329fd23c05", Made.rsa), ("45537789b28eb32390138322976faaabd695bd6c894ad00e9d2786ec5d8074d9", Made.p384)] {
            #expect(!FlatdPin(pin)!.matches(Made.trust(certificate)))
        }
    }

    @Test func otherChallengesAreNotAnsweredWithTrust() {
        let (disposition, credential) = PinnedServer(pin: Made.pinA)
            .verdict(method: NSURLAuthenticationMethodHTTPBasic, trust: Made.trust(Made.a))
        #expect(disposition == .performDefaultHandling && credential == nil)
    }

    @Test func aPinIs64HexDigits() throws {
        let hex = Made.pinA.hex
        #expect(FlatdPin(hex.uppercased()) == Made.pinA)
        #expect(FlatdPin("  " + hex + "\n") == Made.pinA)
        #expect(FlatdPin("") == nil)
        #expect(FlatdPin(String(hex.dropLast())) == nil)
        #expect(FlatdPin(hex + "0") == nil)
        #expect(FlatdPin("g" + hex.dropFirst()) == nil)
        #expect(FlatdPin("sha256/" + hex) == nil)
        #expect(Made.pinA.short == "29d8 19b9 fa55 faa3")
        let coded = try JSONEncoder().encode(Made.pinA)
        #expect(String(decoding: coded, as: UTF8.self) == "\"" + hex + "\"")
        #expect(try JSONDecoder().decode(FlatdPin.self, from: coded) == Made.pinA)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(FlatdPin.self, from: Data("\"abc\"".utf8)) }
    }

    @Test func nothingLeavesWithoutTLS() async {
        // The real transport and the real event stream refuse a plain address before anything is sent.
        var request = URLRequest(url: URL(string: "http://192.0.2.10:8787/api/devices")!)
        request.setValue("Bearer " + Flat.key, forHTTPHeaderField: "Authorization")
        await #expect(throws: URLError.self) { _ = try await FlatdTransport(pin: Made.pinA).send(request) }
        let plain = FlatdClient(baseURL: URL(string: "http://192.0.2.10:8787")!, token: Flat.key, pin: Made.pinA)
        await #expect(throws: FlatdError.unreachable) { _ = try await plain.devices() }
        var stream = URLRequest(url: URL(string: "ws://192.0.2.10:8787/api/events")!)
        stream.setValue("Bearer " + Flat.key, forHTTPHeaderField: "Authorization")
        await #expect(throws: FlatdError.unreachable) {
            for try await _ in WebSocketEvents().events(from: stream, pin: Made.pinA) {}
        }
    }
}

/// The QR code or pasted text that pairs the app once.
struct PairingCodeTests {
    let key = "abcdefghijklmnop0123456789"
    let pin = MadeUpCertificates.pinA

    func code(url: String? = "https://192.0.2.20:8788", token: String? = nil, pin: String? = nil) -> String {
        var object: [String: Any] = ["token": token ?? key, "spki_sha256": pin ?? self.pin.hex]
        if let url { object["url"] = url }
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    @Test func flatdsCode() {
        #expect(PairingCode.parse(code())
                == PairingCode(token: key, pin: pin, baseURL: URL(string: "https://192.0.2.20:8788")))
        // As `flatd pair --text` prints it (compact), with spaces or a line break around it from the paste.
        let compact = #"{"url":"https://192.0.2.20:8788","token":"\#(key)","spki_sha256":"\#(pin.hex)"}"#
        #expect(PairingCode.parse("  " + compact + "\n")?.pin == pin)
        // The address is cut down to the service; without one, Bonjour finds flatd.
        #expect(PairingCode.parse(code(url: "https://192.0.2.20:8788/viewer?x=1"))?.baseURL
                == URL(string: "https://192.0.2.20:8788"))
        #expect(PairingCode.parse(code(url: nil)) == PairingCode(token: key, pin: pin, baseURL: nil))
        // Fields a later flatd may add are ignored.
        #expect(PairingCode.parse(#"{"token":"\#(key)","spki_sha256":"\#(pin.hex)","name":"flatd","v":2}"#)?.token == key)
    }

    @Test func noCodeWithoutAnIdentity() {
        // Without the pin the app could not tell flatd from a device posing as it: such a code pairs nothing.
        #expect(PairingCode.parse(#"{"url": "https://192.0.2.20:8788", "token": "\#(key)"}"#) == nil)
        #expect(PairingCode.parse(code(pin: "")) == nil)
        #expect(PairingCode.parse(code(pin: String(pin.hex.dropLast(2)))) == nil)
        #expect(PairingCode.parse(code(pin: String(repeating: "z", count: 64))) == nil)
        #expect(PairingCode.parse(#"{"token":"\#(key)","spki_sha256":123}"#) == nil)
        // The forms older builds read: a key alone, an address with the key.
        #expect(PairingCode.parse(key) == nil)
        #expect(PairingCode.parse("https://192.0.2.20:8788/?token=\(key)") == nil)
        #expect(PairingCode.parse("http://192.0.2.20:8787/?flatd_token=\(key)") == nil)
    }

    @Test func neverAPlainAddress() {
        #expect(PairingCode.parse(code(url: "http://192.0.2.20:8787")) == nil)
        #expect(PairingCode.parse(code(url: "ws://192.0.2.20:8788")) == nil)
        #expect(PairingCode.parse(code(url: "192.0.2.20:8788")) == nil)
        #expect(PairingCode.parse(code(url: "")) == nil)
        #expect(PairingCode.serviceURL("HTTPS://Mac.local:8788/api/devices?x=1") == URL(string: "https://Mac.local:8788"))
        #expect(PairingCode.serviceURL("https://user:secret@192.0.2.20:8788") == URL(string: "https://192.0.2.20:8788"))
        #expect(PairingCode.serviceURL("http://192.0.2.20:8787") == nil)
        #expect(PairingCode.serviceURL("https://") == nil)
    }

    @Test func noLinkCarriesTheKey() {
        // Another app could claim arestia:// and would get the key when the camera opens the link.
        #expect(PairingCode.parse("arestia://connect?url=https://192.0.2.20:8788&token=\(key)&spki_sha256=\(pin.hex)") == nil)
        #expect(PairingCode.parse("arestia://flat") == nil)
    }

    @Test func notACode() {
        #expect(PairingCode.parse("") == nil)
        #expect(PairingCode.parse("two words that are long enough") == nil)
        #expect(PairingCode.parse("{") == nil)
        #expect(PairingCode.parse("[]") == nil)
        #expect(PairingCode.parse(code(token: "short")) == nil)
        #expect(PairingCode.parse(code(token: "has a space in it, long enough")) == nil)
        #expect(PairingCode.parse(code(token: String(repeating: "k", count: 5000))) == nil)
    }
}

/// Bonjour and the saved address only say where to look: flatd is whoever holds the pinned key. The pinned transport
/// ends a connection to anything else before a request is sent (`PinTests`); here the fake transport fails such a host
/// the same way, and the tests check what the app does with that.
struct RediscoveryTests {
    let transport = FakeTransport()
    let impostor = URL(string: "https://192.0.2.66:8788")!
    let moved = URL(string: "https://192.0.2.77:8788")!

    /// The saved address is dead; at `impostor` something answers the TLS handshake without flatd's key.
    func scene() {
        transport.answer("GET 192.0.2.10/api/health", fails: true)
        transport.answer("GET 192.0.2.66/api/health", fails: true, failure: .serverCertificateUntrusted)
        transport.answer("POST 192.0.2.66/api/scenes/all_down", fails: true, failure: .serverCertificateUntrusted)
        transport.answer("POST /api/scenes/all_down", body: ["id": "all_down", "failed": [:]])
    }

    @Test func anAddressFromBonjourCountsOnlyWithFlatdsKey() async throws {
        scene()
        let connection = Flat.connection()
        let found = [impostor, moved]
        let reach = FlatdReach(connection: connection, transport: transport, rediscover: { found })
        try await FlatActions(reach: reach).runScene("all_down")
        // The work went to flatd only; the impostor was asked nothing but the handshake's health check, without the key.
        #expect(transport.requests(to: "192.0.2.77").contains { $0.httpMethod == "POST" })
        #expect(transport.requests(to: "192.0.2.66").allSatisfy {
            $0.httpMethod == "GET" && $0.value(forHTTPHeaderField: "Authorization") == nil
        })
        #expect(connection.pairing?.baseURL == moved)
        #expect(connection.pairing?.pin == Flat.pin && connection.token == Flat.key)
    }

    @Test func withOnlyAnImpostorFlatdStaysUnreachableAndTheAddressStays() async {
        scene()
        let connection = Flat.connection()
        let found = [impostor]
        let reach = FlatdReach(connection: connection, transport: transport, rediscover: { found })
        await #expect(throws: FlatdError.unreachable) { try await FlatActions(reach: reach).runScene("all_down") }
        #expect(transport.bodies(for: "POST /api/scenes/all_down").isEmpty)
        #expect(transport.sent.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        #expect(connection.pairing?.baseURL == Flat.base)
    }

    @Test func aPlainAddressIsNeverACandidate() async {
        scene()
        let connection = Flat.connection()
        let reach = FlatdReach(connection: connection, transport: transport,
                               rediscover: { [URL(string: "http://192.0.2.77:8787")!] })
        await #expect(throws: FlatdError.unreachable) { try await FlatActions(reach: reach).runScene("all_down") }
        #expect(transport.requests(to: "192.0.2.77").isEmpty)
        connection.move(Flat.pairing(), to: URL(string: "http://192.0.2.77:8787")!)
        #expect(connection.pairing?.baseURL == Flat.base)
    }

    @Test @MainActor func theStoreFollowsFlatdToANewAddressPastAnImpostor() async throws {
        scene()
        transport.answer("GET /api/scenes", body: ["scenes": []])
        transport.answer("GET 192.0.2.10/api/scenes", fails: true)
        let connection = Flat.connection()
        let events = FakeEvents()
        let found = [impostor, moved]
        let store = FlatStore(connection: connection, transport: transport, eventSource: events,
                              rediscover: { found }, reloadControls: {})
        store.start()
        #expect(await eventually({ events.requests.last?.url?.host() == "192.0.2.77" }, timeout: .seconds(8)))
        events.send(try Flat.snapshot())
        #expect(await eventually { store.link == .live })
        #expect(connection.pairing?.baseURL == moved)
        #expect(events.requests.allSatisfy { $0.url?.host() == "192.0.2.77" && $0.url?.scheme == "wss" })
        #expect(transport.requests(to: "192.0.2.66").allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        store.stop()
    }

    @Test func aSavedPairingWithoutAnIdentityIsNoPairing() throws {
        // What a build before flatd had an identity saved: an address and a key. Never used again; pair anew.
        let keys = MemoryKeys()
        let connection = FlatdConnection(defaults: nil, keychain: keys)
        try keys.save(#"{"link":{"baseURL":"http://192.0.2.10:8787","serviceName":"flatd"},"token":"\#(Flat.key)","id":"\#(UUID().uuidString)"}"#,
                      label: "old")
        #expect(connection.pairing == nil && connection.client == nil && connection.token == nil)
        // Nor one whose address is plain HTTP, or whose pin is not one.
        for (url, pin) in [("http://192.0.2.10:8787", Flat.pin.hex), ("https://192.0.2.10:8788", "abc")] {
            try keys.save(#"{"baseURL":"\#(url)","token":"\#(Flat.key)","pin":"\#(pin)","id":"\#(UUID().uuidString)"}"#,
                          label: "odd")
            #expect(connection.pairing == nil)
        }
        try connection.save(Flat.pairing())
        #expect(connection.pairing?.pin == Flat.pin)
    }
}

@MainActor
struct ConnectModelTests {
    let pin = Flat.pin
    let hint = URL(string: "https://192.0.2.20:8788")!
    let moved = URL(string: "https://192.0.2.77:8788")!

    func text(url: String? = "https://192.0.2.20:8788", token: String = Flat.key) -> String {
        var object: [String: Any] = ["token": token, "spki_sha256": pin.hex]
        if let url { object["url"] = url }
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    @Test func aCodePairsAtItsAddress() async throws {
        let connection = Flat.connection(linked: false)
        let (store, transport, _, _) = Flat.store(connection: connection)
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1)]])
        transport.answer("GET /api/scenes", body: ["scenes": []])
        let model = ConnectModel(candidates: { [] })
        #expect(!model.canConnect)
        #expect(model.take(text()) && model.canConnect)
        #expect(await model.connect(store: store))
        #expect(connection.pairing?.baseURL == hint && connection.pairing?.pin == pin)
        #expect(model.code == nil && model.problem == nil)
        store.stop()
    }

    @Test func flatdElsewhereIsFoundOverBonjourAndOnlyWithItsKey() async throws {
        let connection = Flat.connection(linked: false)
        let (store, transport, _, _) = Flat.store(connection: connection)
        transport.answer("GET 192.0.2.20/api/health", fails: true)                     // the code's address is stale
        transport.answer("GET 192.0.2.66/api/health", fails: true, failure: .serverCertificateUntrusted)
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1)]])
        transport.answer("GET /api/scenes", body: ["scenes": []])
        let found = [URL(string: "https://192.0.2.66:8788")!, moved]
        let model = ConnectModel(candidates: { found })
        model.take(text())
        #expect(await model.connect(store: store))
        #expect(connection.pairing?.baseURL == moved)
        #expect(transport.requests(to: "192.0.2.66").allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        #expect(transport.requests(to: "192.0.2.20").allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        store.stop()
    }

    @Test func aKeyFlatdRefusesStopsTheSearch() async {
        let connection = Flat.connection(linked: false)
        let (store, transport, _, _) = Flat.store(connection: connection)
        transport.answer("GET /api/devices", status: 401, body: ["error": "missing or wrong token"])
        let found = [moved]
        let model = ConnectModel(candidates: { found })
        model.take(text())
        #expect(await model.connect(store: store) == false)
        #expect(model.problem?.contains("flatd pair") == true)
        #expect(transport.requests(to: "192.0.2.77").isEmpty)          // flatd itself said no: nowhere else to ask
        #expect(connection.pairing == nil && model.code != nil)
    }

    @Test func noFlatdAnywhereKeepsNothing() async {
        let connection = Flat.connection(linked: false)
        let (store, transport, _, _) = Flat.store(connection: connection)
        transport.answer("GET /api/health", fails: true)
        let found = [moved]
        let model = ConnectModel(candidates: { found })
        model.take(text(url: nil))
        #expect(await model.connect(store: store) == false)
        #expect(model.problem != nil && connection.pairing == nil)
        #expect(transport.sent.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
    }

    @Test func somethingElseScannedIsNotACode() {
        let model = ConnectModel(candidates: { [] })
        #expect(model.take("https://example.com") == false)
        #expect(model.take(Flat.key) == false)                         // a key alone no longer pairs
        #expect(model.code == nil && model.problem != nil && !model.canConnect)
    }
}

nonisolated enum LiveFlatd {
    static var code: PairingCode? {
        ProcessInfo.processInfo.environment["ARESTIA_LIVE_FLATD"].flatMap(PairingCode.parse)
    }
}

/// The real thing, against `scripts/fake-flatd.py` on this Mac (never the real flatd): the pinned URLSession and
/// WebSocket over real TLS. Runs only when the fake's pairing code is handed in:
///
///     TEST_RUNNER_ARESTIA_LIVE_FLATD="$(python3 scripts/fake-flatd.py --pairing)" bash scripts/test-unit.sh Arestia
@Suite(.enabled(if: LiveFlatd.code != nil), .serialized)
struct LiveFlatdTests {
    var code: PairingCode { LiveFlatd.code! }
    var base: URL { code.baseURL! }

    @Test func thePinnedSessionReachesFlatd() async throws {
        let client = FlatdClient(baseURL: base, token: code.token, pin: code.pin)
        try await client.verify()
        #expect(try await client.devices().isEmpty == false)
        #expect(try await client.viewerPage().isEmpty == false)
    }

    @Test func theEventStreamArrivesOverThePinnedSocket() async throws {
        let client = FlatdClient(baseURL: base, token: code.token, pin: code.pin)
        var first: FlatEvent?
        for try await event in WebSocketEvents().events(from: client.eventsRequest, pin: client.pin) {
            first = event
            break
        }
        guard case .snapshot = first else {
            Issue.record("no snapshot")
            return
        }
    }

    @Test func anotherPinEndsTheConnectionBeforeAnyRequest() async throws {
        // The same server, but the app expects another key: to the app it is not flatd.
        let wrong = MadeUpCertificates.pinB
        let client = FlatdClient(baseURL: base, token: code.token, pin: wrong)
        await #expect(throws: FlatdError.unreachable) { try await client.verify() }
        await #expect(throws: FlatdError.unreachable) { _ = try await client.devices() }
        await #expect(throws: FlatdError.unreachable) {
            for try await _ in WebSocketEvents().events(from: client.eventsRequest, pin: wrong) {}
        }
        // And the right pin still works afterwards (a session per pin: no connection is shared between them).
        #expect(try await FlatdClient(baseURL: base, token: code.token, pin: code.pin).health())
    }

    @Test func theUntrustedErrorIsNotACancellation() async {
        let request = URLRequest(url: base.appending(path: "api/health"))
        do {
            _ = try await FlatdTransport(pin: MadeUpCertificates.pinB).send(request)
            Issue.record("a server with another key was accepted")
        } catch let error as URLError {
            #expect(error.code == .serverCertificateUntrusted)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}
