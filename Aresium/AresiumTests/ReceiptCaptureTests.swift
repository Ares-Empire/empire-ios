import CoreGraphics
import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
import VisionKit
@testable import Aresium

/// Receipts, the capture (brief 31): Vision's boxes become the engine's (top left, pages below each other), the JSON is
/// exactly the engine's input, and the made-up receipt read through the real Vision path gives its shop line, its
/// SUMME row's amount and its register's QR code: scanned (one page or two), and picked as a photo.
@MainActor
struct ReceiptCaptureTests {
    // MARK: the box conversion

    private func expectBox(_ rect: CGRect, page: Int, _ x: Double, _ y: Double, _ width: Double, _ height: Double,
                           sourceLocation: SourceLocation = #_sourceLocation) {
        let box = ReceiptBox.topLeft(rect, page: page)
        for (got, wanted) in [(box.x, x), (box.y, y), (box.width, width), (box.height, height)] {
            #expect(abs(got - wanted) < 1e-9, "\(box) ≠ \((x, y, width, height))", sourceLocation: sourceLocation)
        }
    }

    @Test func visionsBoxesBecomeTopLeftWithPagesBelowEachOther() {
        // Vision: origin bottom left, y up. A line a quarter from the top: its top edge at 0.75, so y = 0.25.
        expectBox(CGRect(x: 0.1, y: 0.7, width: 0.5, height: 0.05), page: 0, 0.1, 0.25, 0.5, 0.05)
        // The same line on the second page starts one page further down.
        expectBox(CGRect(x: 0.1, y: 0.7, width: 0.5, height: 0.05), page: 1, 0.1, 1.25, 0.5, 0.05)
        // At the very top and at the very bottom of the third page.
        expectBox(CGRect(x: 0.3, y: 0.9, width: 0.4, height: 0.1), page: 0, 0.3, 0.0, 0.4, 0.1)
        expectBox(CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.1), page: 2, 0.0, 2.9, 0.2, 0.1)
        // A box reaching past the image's edges is cut at them.
        expectBox(CGRect(x: -0.02, y: 0.95, width: 0.5, height: 0.1), page: 0, 0.0, 0.0, 0.48, 0.05)
        expectBox(CGRect(x: 0.9, y: -0.03, width: 0.2, height: 0.06), page: 1, 0.9, 1.97, 0.1, 0.03)
    }

    // MARK: the engine's input

    @Test func theJSONIsTheEnginesInput() throws {
        let capture = ReceiptCapture(observations: [.init(text: "SUMME", x: 0.1, y: 0.25, width: 0.2, height: 0.03)],
                                     codes: ["V0;FIKTIV"])
        let json = try JSONSerialization.jsonObject(with: try capture.json()) as? [String: Any]
        #expect(Set(json?.keys ?? [:].keys) == ["observations", "codes"])
        let observation = (json?["observations"] as? [[String: Any]])?.first
        #expect(Set(observation?.keys ?? [:].keys) == ["text", "x", "y", "width", "height"])
        #expect(observation?["text"] as? String == "SUMME")
        #expect(observation?["y"] as? Double == 0.25)
        #expect(json?["codes"] as? [String] == ["V0;FIKTIV"])
        #expect(try JSONDecoder().decode(ReceiptCapture.self, from: try capture.json()) == capture)
    }

    // MARK: reading the made-up receipt

    /// The observation whose text is `text` (or contains it).
    private func piece(_ capture: ReceiptCapture, _ text: String) -> ReceiptCapture.Observation? {
        capture.observations.first { $0.text == text } ?? capture.observations.first { $0.text.contains(text) }
    }

    /// The shop line, the SUMME row's amount on SUMME's row to its right, the order top to bottom, and the QR code.
    private func expectReceipt(_ capture: ReceiptCapture, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let shop = try #require(piece(capture, ReceiptSample.shop), sourceLocation: sourceLocation)
        let summe = try #require(piece(capture, "SUMME"), sourceLocation: sourceLocation)
        let amount = try #require(capture.observations.first {
            $0.text.contains(ReceiptSample.total) && abs(($0.y + $0.height / 2) - (summe.y + summe.height / 2)) < summe.height
        }, "no amount on SUMME's row", sourceLocation: sourceLocation)
        #expect(amount.x > summe.x + summe.width, "the amount stands right of SUMME", sourceLocation: sourceLocation)
        let thanks = try #require(piece(capture, "Vielen Dank"), sourceLocation: sourceLocation)
        #expect(shop.y < summe.y && summe.y < thanks.y, "top to bottom", sourceLocation: sourceLocation)
        #expect(capture.codes == [ReceiptSample.code], sourceLocation: sourceLocation)
    }

    @Test func readsTheMadeUpReceipt() async throws {
        let capture = try await ReceiptReader.read([ReceiptPage(image: ReceiptSample.image())])
        try expectReceipt(capture)
        #expect(capture.observations.allSatisfy { $0.x >= 0 && $0.y >= 0 && $0.x + $0.width <= 1 && $0.y + $0.height <= 1 })
        #expect(capture.observations.count > 30)
    }

    @Test func aLongReceiptInTwoPagesContinuesBelowTheFirst() async throws {
        let capture = try await ReceiptReader.read(ReceiptSample.pages().map { ReceiptPage(image: $0) })
        try expectReceipt(capture)
        let summe = try #require(piece(capture, "SUMME"))
        let paid = try #require(piece(capture, "Geg. girocard"))
        let thanks = try #require(piece(capture, "Vielen Dank"))
        #expect(summe.y < 1, "the total is on page 1")
        #expect(paid.y >= 1 && thanks.y + thanks.height <= 2, "the payment lines are on page 2, below it")
        #expect(capture.observations.map(\.y) == capture.observations.map(\.y).sorted(), "pieces in reading order")
    }

    @Test func readsAPickedPhoto() async throws {
        try expectReceipt(try await ReceiptReader.read(photo: ReceiptSample.png()))
    }

    /// iPhone photos are stored as the sensor saw them with an orientation to show them by: the photo is turned upright
    /// before it is read.
    @Test func turnsAPhotoUprightBeforeReading() async throws {
        let receipt = ReceiptSample.image()
        // The pixels turned a quarter to the left, saved with "turn right to show" (EXIF 6), as a phone held upright does.
        let size = CGSize(width: receipt.height, height: receipt.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let turned = UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.rotate(by: -.pi / 2)
            UIImage(cgImage: receipt).draw(at: .zero)
        }.cgImage!
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, turned, [kCGImagePropertyOrientation: CGImagePropertyOrientation.right.rawValue,
                                                         kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        try expectReceipt(try await ReceiptReader.read(photo: data as Data))
    }

    @Test func somethingThatIsNotAnImageIsNotRead() async {
        await #expect(throws: ReceiptReadingError.self) { try await ReceiptReader.read(photo: Data("no image".utf8)) }
    }

    // MARK: the flow

    /// Reading, then the check window with the engine's reading of what Vision saw.
    @Test func theSheetShowsTheReadingThenTheCheckWindow() async throws {
        let phone = try await PhoneTest.backend(chosen: ["groceries"])
        let model = ReceiptCaptureModel { phone }
        model.read([ReceiptPage(image: ReceiptSample.image())])
        guard case .reading? = model.reading?.phase else { Issue.record("not reading"); return }
        await model.finished()
        guard case .checking(let check)? = model.reading?.phase else { Issue.record("no check window"); return }
        #expect(check.reading.total == 27.65 && check.reading.from == "code")
        #expect(check.fieldsToCheck == [.shop], "only the shop is not sure on the made-up receipt")
        model.close()
        #expect(model.reading == nil)
    }

    /// Nothing seen on the paper: the same window with empty fields, never a dead end.
    @Test func nothingReadGivesTheEmptyWindow() async throws {
        let phone = try await PhoneTest.backend()
        let model = ReceiptCaptureModel { phone }
        model.read([ReceiptPage(image: ReceiptSample.blankImage())])
        await model.finished()
        guard case .checking(let check)? = model.reading?.phase else { Issue.record("no check window"); return }
        #expect(check.nothingRead && check.shop.isEmpty && check.totalText.isEmpty)
    }

    /// Closing the sheet cancels the reading: the reader stops, and a reading closed before it ended never shows up in
    /// a newer one.
    @Test func closingTheSheetCancelsTheReading() async throws {
        let reading = Task { try await ReceiptReader.read([ReceiptPage(image: ReceiptSample.image())]) }
        reading.cancel()
        await #expect(throws: CancellationError.self) { try await reading.value }

        let phone = try await PhoneTest.backend()
        let model = ReceiptCaptureModel { phone }
        model.read([ReceiptPage(image: ReceiptSample.unsureImage())])
        let first = model.reading?.id
        model.close()
        #expect(model.reading == nil)
        model.read(ReceiptSample.pages().map { ReceiptPage(image: $0) })
        #expect(model.reading?.id != first)
        await model.finished()
        guard case .checking(let check)? = model.reading?.phase else { Issue.record("no check window"); return }
        #expect(check.reading.rows.contains { $0.contains("Geg. girocard") }, "the newer (two-page) reading, not the closed one")
    }

    @Test func aScannerThatStopsSaysSo() async throws {
        let model = ReceiptCaptureModel()
        model.scannerFinished(.failure(CocoaError(.fileReadCorruptFile)))
        #expect(model.scanning == false && model.reading == nil, "the scanner closes first")
        model.scannerClosed(cameraAllowed: true)
        guard case .failed(let line)? = model.reading?.phase else { Issue.record("no failure shown"); return }
        #expect(line == "The scanner stopped. Try again.")
        // Stopped because the camera was refused: where to allow it.
        model.close()
        model.scannerFinished(.failure(CocoaError(.featureUnsupported)))
        model.scannerClosed(cameraAllowed: false)
        guard case .failed(let refused)? = model.reading?.phase else { Issue.record("no failure shown"); return }
        #expect(refused == "Aresium may not use the camera. Allow it in Settings → Apps → Aresium.")
        // A cancelled scanner shows nothing.
        model.close()
        model.scannerFinished(nil)
        model.scannerClosed()
        #expect(model.reading == nil)
    }

    // MARK: the menu

    @Test func importOffersTheReceiptChoices() {
        var answered = 0
        let tour = ImportChoices.tour { answered += 1 }
        tour.chooseFile()
        tour.choosePhoto()
        tour.scanReceipt?()
        // Scan receipt only where VisionKit's document camera is supported (the iOS 27 simulator says it is).
        #expect((tour.scanReceipt != nil) == VNDocumentCameraViewController.isSupported)
        #expect(answered == (VNDocumentCameraViewController.isSupported ? 3 : 2), "in the tour each choice only answers its step")
    }

    /// The made-up receipt as a PNG in build/, for the simulator's Photos (`xcrun simctl addmedia`, Choose photo).
    @Test func theMadeUpReceiptAsAPhoto() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "build", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let png = ReceiptSample.png()
        #expect(UIImage(data: png) != nil)
        try png.write(to: folder.appending(path: "31-made-up-receipt.png"))
    }
}
