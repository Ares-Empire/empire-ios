#if DEBUG
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// A made-up German supermarket receipt drawn into an image, for the tests, `-sampleReceipt` (the simulator has no
/// camera) and the simulator's Photos. Nothing on it is real: the shop, the address, the tax number, the terminal and
/// the register's signed QR code are invented. Monospaced like a till's print, on paper slightly tilted on a table.
enum ReceiptSample {
    /// The receipt's total, as printed on its SUMME row and carried by its QR code.
    static let total = "27,65"
    static let shop = "MUSTERMARKT LINDE"
    /// The register's QR code in the DSFinV-K layout (version;serial;process type;process data;transaction;signature
    /// counter;start;end;algorithm;time format;signature;public key), with made-up values throughout.
    static let code = "V0;FIKTIV-KASSE-02;Kassenbeleg-V1;Beleg^2.10_25.55_0.00_0.00_0.00^27.65:Unbar;4711;9421;"
        + "2026-10-26T13:31:02.000Z;2026-10-26T13:31:05.000Z;ecdsa-plain-SHA384;unixTime;"
        + "ZmlrdGl2ZSBTaWduYXR1ciwga2VpbmUgZWNodGU=;ZmlrdGl2ZXIgU2NobMO8c3NlbA=="

    /// A row of the receipt.
    enum Row {
        case title(String)
        case centered(String)
        /// Left text and its right-aligned amount.
        case item(String, String)
        case total(String, String)
        case line(String)
        case rule(Character)
        case gap
        case qr(String)
    }

    static let rows: [Row] = top + bottom

    /// Up to the total (the first page of a two-page scan).
    static let top: [Row] = [
        .gap,
        .title(shop),
        .centered("Beispielweg 7"),
        .centered("80999 Musterstadt"),
        .centered("USt-IdNr. DE000000000"),
        .gap,
        .item("", "EUR"),
        .item("BIO VOLLMILCH 1L", "1,29 A"),
        .item("DINKELBROT 500G", "3,49 A"),
        .item("ÄPFEL ELSTAR 1KG", "2,99 A"),
        .item("GOUDA JUNG 400G", "4,79 A"),
        .item("KAFFEE BOHNEN 1KG", "12,99 A"),
        .item("SPÜLMITTEL 500ML", "1,85 B"),
        .item("PFAND", "0,25 B"),
        .rule("-"),
        .total("SUMME", "EUR \(total)"),
        .rule("="),
    ]

    /// After the total (the second page).
    static let bottom: [Row] = [
        .item("Geg. girocard", "EUR \(total)"),
        .gap,
        .line("Steuer      Netto   Steuer  Brutto"),
        .line("A  7,0%     23,88     1,67   25,55"),
        .line("B 19,0%      1,76     0,34    2,10"),
        .gap,
        .line("26.10.2026 14:31  Bon 4711  Kasse 2"),
        .gap,
        .centered("*** Kundenbeleg ***"),
        .item("girocard", "kontaktlos"),
        .item("Terminal-ID", "00000000"),
        .item("Betrag EUR", total),
        .centered("Zahlung erfolgt"),
        .gap,
        .qr(code),
        .gap,
        .centered("Vielen Dank für Ihren Einkauf!"),
        .gap,
    ]

    /// A made-up café receipt Aresium cannot be sure of: no register code, no payment line, the total without its word
    /// (the check window's "Please check" fields). Its day is printed clearly.
    static let unsureRows: [Row] = [
        .gap,
        .title("CAFE FIKTIVA"),
        .centered("Am Beispielplatz 3"),
        .gap,
        .item("Cappuccino", "3,40"),
        .item("Croissant", "2,20"),
        .item("Apfelschorle", "2,80"),
        .rule("-"),
        .item("", "8,40"),
        .gap,
        .line("27.10.2026 08:12  Bon 0815"),
        .gap,
        .centered("Danke und bis bald!"),
        .gap,
    ]

    /// The whole receipt on one page; `shop` prints another name on top (a chain the shop list knows reads as sure:
    /// `-sampleReceiptShop REWE`).
    static func image(shop: String? = nil) -> CGImage {
        render(rows.map { row in
            if case .title = row, let shop { return .title(shop) }
            return row
        })
    }

    /// The café receipt with fields to check.
    static func unsureImage() -> CGImage { render(unsureRows, tilt: 1.1) }

    /// Paper with nothing readable on it: the check window with empty fields.
    static func blankImage() -> CGImage { render(Array(repeating: .gap, count: 30), tilt: -0.8) }

    /// The receipt as a long one scanned in two pages: up to the total, then the rest.
    static func pages() -> [CGImage] { [render(top, tilt: 0.8), render(bottom, tilt: -1.2)] }

    /// The receipt's lines as text (what a kept receipt carries instead of a photo).
    static var textRows: [String] {
        rows.compactMap { row in
            switch row {
            case .title(let text), .centered(let text), .line(let text): text
            case .item(let left, let right), .total(let left, let right): [left, right].filter { !$0.isEmpty }.joined(separator: " ")
            case .rule, .gap, .qr: nil
            }
        }
    }

    /// The receipt as PNG bytes (for the simulator's Photos: `xcrun simctl addmedia`).
    static func png() -> Data { UIImage(cgImage: image()).pngData() ?? Data() }

    // MARK: drawing

    private static let paperWidth: CGFloat = 640
    private static let margin: CGFloat = 44
    private static let lineHeight: CGFloat = 36
    private static let font = UIFont(name: "Courier-Bold", size: 25) ?? .monospacedSystemFont(ofSize: 25, weight: .semibold)
    private static let titleFont = UIFont(name: "Courier-Bold", size: 34) ?? .monospacedSystemFont(ofSize: 34, weight: .bold)
    private static let totalFont = UIFont(name: "Courier-Bold", size: 30) ?? .monospacedSystemFont(ofSize: 30, weight: .bold)
    // An image of paper on a table, not app ink: its colours are fixed.
    private static let ink = UIColor(red: 0.13, green: 0.12, blue: 0.12, alpha: 1)
    private static let paper = UIColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1)
    private static let table = UIColor(red: 0.42, green: 0.40, blue: 0.37, alpha: 1)
    private static let qrSide: CGFloat = 230

    private static func height(of row: Row) -> CGFloat {
        switch row {
        case .title: lineHeight * 1.4
        case .total: lineHeight * 1.25
        case .gap: lineHeight * 0.6
        case .qr: qrSide + 16
        default: lineHeight
        }
    }

    /// Draws the rows on paper, turned by `tilt` degrees, on a table around it.
    static func render(_ rows: [Row], tilt: CGFloat = -1.6) -> CGImage {
        let paperHeight = rows.reduce(40) { $0 + height(of: $1) }
        let size = CGSize(width: paperWidth + 220, height: paperHeight + 200)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            table.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            cg.translateBy(x: size.width / 2, y: size.height / 2)
            cg.rotate(by: tilt * .pi / 180)
            cg.translateBy(x: -paperWidth / 2, y: -paperHeight / 2)
            cg.setShadow(offset: CGSize(width: 0, height: 6), blur: 18, color: UIColor(white: 0, alpha: 0.35).cgColor)
            paper.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: paperWidth, height: paperHeight))
            cg.setShadow(offset: .zero, blur: 0)
            var y: CGFloat = 20
            for row in rows {
                draw(row, at: y, in: cg)
                y += height(of: row)
            }
        }
        return image.cgImage!
    }

    private static func draw(_ row: Row, at y: CGFloat, in context: CGContext) {
        func text(_ string: String, font: UIFont, x: CGFloat? = nil, right: Bool = false) {
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
            let width = (string as NSString).size(withAttributes: attributes).width
            let left = x ?? (right ? paperWidth - margin - width : (paperWidth - width) / 2)
            (string as NSString).draw(at: CGPoint(x: left, y: y), withAttributes: attributes)
        }
        switch row {
        case .title(let string): text(string, font: titleFont)
        case .centered(let string): text(string, font: font)
        case .line(let string): text(string, font: font, x: margin)
        case .item(let left, let right):
            if !left.isEmpty { text(left, font: font, x: margin) }
            text(right, font: font, right: true)
        case .total(let left, let right):
            text(left, font: totalFont, x: margin)
            text(right, font: totalFont, right: true)
        case .rule(let character):
            let count = Int((paperWidth - 2 * margin) / (font.pointSize * 0.6))
            text(String(repeating: character, count: count), font: font, x: margin)
        case .gap: break
        case .qr(let payload):
            guard let code = qrImage(payload) else { return }
            context.interpolationQuality = .none
            // UIKit's context is flipped; drawing through UIImage keeps the code the right way up.
            UIImage(cgImage: code).draw(in: CGRect(x: (paperWidth - qrSide) / 2, y: y + 8, width: qrSide, height: qrSide))
        }
    }

    private static func qrImage(_ payload: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
#endif
