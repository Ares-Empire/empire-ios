import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UIKit
import Vision

// Receipts, the capture (brief 31, D8 in ares-empire/docs/ARESIUM-FOR-OTHERS.md → part 6): the iPhone reads a scanned
// or picked receipt with Vision, on the phone, into the engine's input (`readReceipt` in the engine, brief 30). No photo
// is kept: the images live only while they are read, never on disk.

/// What Vision saw on a receipt, exactly as the engine's `readReceipt` takes it:
/// `{ observations: [{ text, x, y, width, height }], codes: [string] }`. Boxes are normalised 0–1 with the origin at the
/// top left and y growing downwards; page n of a scan starts at y = n (page 2, the index 1, at y = 1).
nonisolated struct ReceiptCapture: Codable, Equatable, Sendable {
    /// One piece of recognised text and where it sits.
    struct Observation: Codable, Equatable, Sendable {
        var text: String
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    var observations: [Observation]
    /// The payloads of the QR codes on the receipt (the register's signed data, when there is one).
    var codes: [String]

    /// The JSON the engine reads.
    func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

/// The one place where Vision's boxes become the engine's: Vision normalises to the image with the origin at the
/// bottom left and y growing upwards; the engine wants the top left, y growing downwards, each page below the one
/// before it.
nonisolated enum ReceiptBox {
    /// `rect`: Vision's normalised box on page `page` (0 for the first). Parts outside the image are cut off.
    static func topLeft(_ rect: CGRect, page: Int) -> (x: Double, y: Double, width: Double, height: Double) {
        let minX = min(max(rect.minX, 0), 1), maxX = min(max(rect.maxX, 0), 1)
        let minY = min(max(rect.minY, 0), 1), maxY = min(max(rect.maxY, 0), 1)
        return (x: minX, y: Double(page) + (1 - maxY), width: maxX - minX, height: maxY - minY)
    }
}

/// One page to read: an upright image, held only until it is read.
nonisolated struct ReceiptPage: @unchecked Sendable {
    // CGImage is immutable; it is passed to the reading task and dropped with it.
    let image: CGImage
    let orientation: CGImagePropertyOrientation

    /// The longest side a photo is read at: a 12-megapixel photo stays whole, a 48-megapixel one is scaled down (Vision
    /// reads receipt print well below this; it keeps the memory of a reading small).
    static let longestSide = 4032

    init(image: CGImage, orientation: CGImagePropertyOrientation = .up) {
        self.image = image
        self.orientation = orientation
    }

    /// A page scanned by the document scanner (already straightened by it).
    init?(scanned image: UIImage) {
        guard let cgImage = image.cgImage else { return nil }
        self.init(image: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
    }

    /// A photo's bytes (Choose photo), decoded in memory and turned upright; nil when they are not an image.
    init?(photo data: Data) {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else { return nil }
        let thumbnail: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,        // the photo's own orientation applied
            kCGImageSourceThumbnailMaxPixelSize: Self.longestSide,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnail as CFDictionary) else { return nil }
        self.init(image: image)
    }
}

extension CGImagePropertyOrientation {
    nonisolated init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// Reads receipt pages with Vision on the phone: the text (accurate, the language detected by itself) and the QR codes.
/// Runs off the main actor; a cancelled task stops between steps and returns nothing.
///
/// `RecognizeTextRequest`, not iOS 26's `RecognizeDocumentsRequest` (tried both on the made-up receipt, 2026-10-27):
/// both gave the same 50 pieces with the same boxes, the documents request took a third longer, and what it adds (tables,
/// paragraphs) is not part of the engine's input; its tables also stacked two pieces of a tax row into one cell.
nonisolated enum ReceiptReader {
    /// Pages from the document scanner (or `-sampleReceipt`), page 1 first.
    @concurrent
    static func read(_ pages: [ReceiptPage]) async throws -> ReceiptCapture {
        var capture = ReceiptCapture(observations: [], codes: [])
        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            let read = try await self.read(page, number: index)
            capture.observations += read.observations
            for code in read.codes where !capture.codes.contains(code) { capture.codes.append(code) }
        }
        try Task.checkCancellation()
        return capture
    }

    /// A photo's bytes (Choose photo): decoded and read here, off the main actor; nothing is kept.
    @concurrent
    static func read(photo data: Data) async throws -> ReceiptCapture {
        guard let page = ReceiptPage(photo: data) else { throw ReceiptReadingError.notAnImage }
        try Task.checkCancellation()
        return try await read([page])
    }

    private static func read(_ page: ReceiptPage, number: Int) async throws -> ReceiptCapture {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        // A long receipt's print is under 1 % of the photo's height; Vision's default (1/32) left out 21 of 122 pieces
        // of a made-up receipt three times the usual length.
        request.minimumTextHeightFraction = 0.005
        let handler = ImageRequestHandler(page.image, orientation: page.orientation)
        let text = try await handler.perform(request)
        try Task.checkCancellation()
        let observations = text.compactMap { observation -> ReceiptCapture.Observation? in
            guard let string = observation.topCandidates(1).first?.string
                .trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else { return nil }
            let box = ReceiptBox.topLeft(observation.boundingBox.cgRect, page: number)
            return ReceiptCapture.Observation(text: string, x: box.x, y: box.y, width: box.width, height: box.height)
        }
        .sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        return ReceiptCapture(observations: observations, codes: await codes(on: page, handler: handler))
    }

    /// The QR codes' payloads, top first. A receipt without a readable code is still read from its text.
    private static func codes(on page: ReceiptPage, handler: ImageRequestHandler) async -> [String] {
        var request = DetectBarcodesRequest()
        request.symbologies = [.qr]
        do {
            let found = try await handler.perform(request)
            return found.sorted { $0.boundingBox.cgRect.maxY > $1.boundingBox.cgRect.maxY }
                .compactMap(\.payloadString).filter { !$0.isEmpty }
        } catch {
            // The detector's model does not load on the simulator ("Failed to create barcode detector", measured
            // 2026-10-27, Xcode 27.1); Core Image's QR detector reads the same codes without it.
            let image = CIImage(cgImage: page.image).oriented(page.orientation)
            let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                      options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
            return (detector?.features(in: image) ?? [])
                .compactMap { ($0 as? CIQRCodeFeature)?.messageString }.filter { !$0.isEmpty }
        }
    }
}

/// Why a picked photo could not be read (the sheet says it in the app's words).
nonisolated enum ReceiptReadingError: Error {
    case notAnImage
}
