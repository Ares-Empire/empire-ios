import AVFoundation
import Foundation
import Observation
import PhotosUI
import SwiftUI

/// Receipts, the flow (brief 31): Import's menu opens Apple's document scanner or the photo picker; what they give is
/// read on the phone (`ReceiptReader`, then the engine's `readReceipt`) while a sheet shows it, then checked
/// (`ReceiptCheckModel`, "Does this look right?"), kept, and joined to its bank payment or asked about ("Is this the
/// same payment?"). Closing the sheet while it reads cancels the reading. No image is kept: the scanner's pages go
/// straight to the reading, a photo's bytes live only inside it, and both are released when it ends. Phone mode only.
@MainActor @Observable
final class ReceiptCaptureModel {
    /// What the sheet shows: the reading under way, the check window, the question, or why it could not be read.
    struct Reading: Identifiable {
        enum Phase {
            case reading
            case checking(ReceiptCheckModel)
            case asking(ReceiptQuestion)
            case failed(String)
        }
        let id = UUID()
        var phase: Phase = .reading
    }

    /// Apple's document scanner is open.
    var scanning = false
    /// The photo picker is open.
    var pickingPhoto = false
    /// The sheet's reading; nil: no sheet.
    private(set) var reading: Reading?
    /// Why an answer to the question could not be kept.
    private(set) var problem: String?
    /// The scanner's pages (or its failure) from the moment it finishes until its cover has closed.
    @ObservationIgnored private var scanned: Result<[ReceiptPage], Error>?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Phone mode's backend, which reads with the engine and keeps the receipt.
    @ObservationIgnored private let phone: () -> PhoneBackend?
    /// Told once a receipt is kept: the line for the result banner (the owner also builds the dashboard again).
    @ObservationIgnored var saved: (String) async -> Void = { _ in }

    init(phone: @escaping () -> PhoneBackend? = { nil }) {
        self.phone = phone
    }

    /// Import → Scan receipt.
    func scan() { scanning = true }

    /// Import → Choose photo.
    func choosePhoto() { pickingPhoto = true }

    /// The scanner finished (nil: the person cancelled it). It closes now; the pages are read once it has closed.
    func scannerFinished(_ result: Result<[ReceiptPage], Error>?) {
        scanned = result
        scanning = false
    }

    /// The scanner's cover has closed: its pages are read in the sheet (which cannot open while the cover still
    /// closes). When the scanner stopped because Aresium may not use the camera, the sheet says where to allow it.
    func scannerClosed(cameraAllowed: Bool = ReceiptCaptureModel.cameraAllowed) {
        let result = scanned
        scanned = nil
        switch result {
        case .success(let pages) where !pages.isEmpty:
            start(failure: String(localized: "The receipt could not be read.")) { try await ReceiptReader.read(pages) }
        case .failure:
            let line = cameraAllowed ? String(localized: "The scanner stopped. Try again.")
                                     : String(localized: "Aresium may not use the camera. Allow it in Settings → Apps → Aresium.")
            reading = Reading(phase: .failed(line))
        default:
            break
        }
    }

    /// The person has not refused the camera (or not been asked yet).
    static var cameraAllowed: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status != .denied && status != .restricted
    }

    /// The photo picked: its bytes are loaded into memory and read.
    func read(_ photo: PhotosPickerItem) {
        start(failure: String(localized: "This photo could not be read.")) {
            guard let data = try await photo.loadTransferable(type: Data.self) else { throw ReceiptReadingError.notAnImage }
            return try await ReceiptReader.read(photo: data)
        }
    }

    /// Pages read at once (`-sampleReceipt`; tests).
    func read(_ pages: [ReceiptPage]) {
        start(failure: String(localized: "The receipt could not be read.")) { try await ReceiptReader.read(pages) }
    }

    /// Save in the check window: kept, then joined (or waiting, or cash) and the sheet closes with its line; with
    /// payments to ask about, the question follows in the same sheet.
    func save(_ check: ReceiptCheckModel) async {
        guard let saved = await check.save() else { return }
        if case let .question(question) = saved { reading?.phase = .asking(question) }
        else { await finish(ReceiptWording.saved(saved)) }
    }

    /// "Is this the same payment?" answered in the sheet: a payment, or nil ("None of these": it waits).
    func answer(_ question: ReceiptQuestion, with paymentID: String?) async {
        guard let phone = phone() else { return }
        problem = nil
        do {
            try await phone.answer(question, with: paymentID)
            await finish(ReceiptWording.answered(joined: paymentID != nil))
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Later on "Is this the same payment?" after Save (brief 40): the receipt was kept on Save and now waits for the bank
    /// statement; nothing is declined, so the next import asks again. Its line goes to the banner and the dashboard is
    /// built again, as after an answer.
    func later() {
        guard case .asking? = reading?.phase else { return }
        close()
        Task { await saved(ReceiptWording.answered(joined: false)) }
    }

    /// The sheet was swiped away: on the question that is Later; anywhere else (reading, a failure) the reading stops.
    func swipedAway() {
        if case .asking? = reading?.phase { later() } else { close() }
    }

    /// The sheet closed: the reading stops and nothing of it stays.
    func close() {
        task?.cancel()
        task = nil
        reading = nil
    }

    /// Waits for the reading under way (tests).
    func finished() async { await task?.value }

    private func finish(_ line: String) async {
        close()
        await saved(line)
    }

    private func start(failure: String, _ work: @escaping () async throws -> ReceiptCapture) {
        task?.cancel()
        problem = nil
        let shown = Reading()
        reading = shown
        task = Task {
            let phase: Reading.Phase
            do {
                phase = await check(try await work())
            } catch {
                phase = .failed(failure)
            }
            // A closed sheet, or a newer reading, takes nothing from this one.
            guard !Task.isCancelled, reading?.id == shown.id else { return }
            reading?.phase = phase
        }
    }

    /// What Vision saw → the check window. The engine's reading; with nothing seen, or should the engine fail, the same
    /// window with empty fields to type in (never a dead end).
    private func check(_ capture: ReceiptCapture) async -> Reading.Phase {
        guard let phone = phone() else { return .failed(String(localized: "The receipt could not be read.")) }
        var reading = ReceiptReading.nothing
        if !capture.observations.isEmpty || !capture.codes.isEmpty {
            do { reading = try await phone.readReceipt(capture) }
            catch { reading.rows = capture.observations.map(\.text) }
        }
        let check = ReceiptCheckModel(reading: reading, phone: phone)
        await check.load()
        return .checking(check)
    }
}
