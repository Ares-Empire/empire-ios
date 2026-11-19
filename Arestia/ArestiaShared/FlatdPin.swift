import CryptoKit
import Foundation
import Security

/// flatd's identity as the app knows it: the SHA-256 of its public key (the certificate's SubjectPublicKeyInfo, DER),
/// 64 hex digits, taken once from flatd's pairing code. On the home network flatd speaks HTTPS with a self-signed
/// certificate that no CA knows, so nothing about the certificate is trusted but its key: a server counts as flatd
/// only when the TLS handshake proved it holds the private key for this pin. Before that the app sends nothing, so a
/// device that merely sits at flatd's address (a forged Bonjour answer, ARP, the same address on another Wi-Fi) gets
/// neither the key nor a request.
///
/// The pin is the key, not the certificate: flatd may renew its certificate, change its address or its name, or move
/// to another machine with its key, and the pairing stays.
nonisolated struct FlatdPin: Hashable, Sendable, Codable {
    /// 64 lowercase hex digits.
    let hex: String

    /// Reads a pin as flatd prints it (`spki_sha256`); nil for anything that is not 64 hex digits.
    init?(_ text: String) {
        let hex = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard hex.utf8.count == 64, hex.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            return nil
        }
        self.hex = hex
    }

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let pin = FlatdPin(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a pin"))
        }
        self = pin
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }

    /// The first 16 digits in groups of four ("bf23 ef1e 84e6 d77b"), as `flatd pair` and flatd's log show them, to
    /// compare by eye.
    var short: String {
        let start = Array(hex.prefix(16))
        return stride(from: 0, to: start.count, by: 4).map { String(start[$0..<min($0 + 4, start.count)]) }
            .joined(separator: " ")
    }

    /// Whether the server that presented this trust (its leaf certificate) holds flatd's key. Only the key is
    /// compared; the handshake itself has proved the server owns it.
    func matches(_ trust: SecTrust) -> Bool {
        guard let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else { return false }
        return FlatdPin.of(leaf) == self
    }

    /// The pin of a certificate's key; nil unless it is an EC P-256 key (the only kind flatd has).
    static func of(_ certificate: SecCertificate) -> FlatdPin? {
        guard let key = SecCertificateCopyKey(certificate),
              let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
              let type = attributes[kSecAttrKeyType] as? String, type == kSecAttrKeyTypeECSECPrimeRandom as String,
              attributes[kSecAttrKeySizeInBits] as? Int == 256,
              let point = SecKeyCopyExternalRepresentation(key, nil) as Data?,
              point.count == 65, point.first == 0x04 else { return nil }
        // The Security framework gives the bare curve point; the pin is over the whole SubjectPublicKeyInfo, which for
        // P-256 is always this header followed by the point.
        let digest = SHA256.hash(data: Data(p256Header) + point)
        return FlatdPin(digest.map { String(format: "%02x", $0) }.joined())
    }

    /// DER: SEQUENCE { SEQUENCE { OID ecPublicKey, OID prime256v1 }, BIT STRING (65 bytes follow) }.
    private static let p256Header: [UInt8] = [
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
        0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
    ]
}
