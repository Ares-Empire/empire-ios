import PhotosUI
import SwiftUI
import VisionKit

// Receipts, the capture (brief 31): Apple's own pieces (the document scanner, the photo picker) and one sheet that
// reads what they give on the phone, then shows the check window ("Does this look right?") and, when the bank
// statement has payments to ask about, "Is this the same payment?" (ReceiptCheckView.swift). The flow is
// `ReceiptCaptureModel`, the reading `ReceiptReader`.

extension View {
    /// Import's receipts: the document scanner, the photo picker and the sheet that reads, checks and keeps them.
    func receiptCapture(_ model: ReceiptCaptureModel, palette: Palette) -> some View {
        modifier(ReceiptCapturePresenter(model: model, palette: palette))
    }
}

private struct ReceiptCapturePresenter: ViewModifier {
    @Bindable var model: ReceiptCaptureModel
    let palette: Palette
    @State private var photo: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $model.scanning, onDismiss: { model.scannerClosed() }) {
                DocumentScanner(finished: model.scannerFinished).ignoresSafeArea()
            }
            // One photo; the picker runs outside the app, so it needs no access to the photo library.
            .photosPicker(isPresented: $model.pickingPhoto, selection: $photo, matching: .images,
                          preferredItemEncoding: .current)
            .onChange(of: photo) { _, picked in
                guard let picked else { return }
                photo = nil
                model.read(picked)
            }
            .sheet(isPresented: Binding(get: { model.reading != nil }, set: { if !$0 { model.close() } })) {
                ReceiptSheet(model: model, palette: palette)
            }
    }
}

/// Apple's document scanner: it finds the receipt's edges and straightens it; a long receipt can take several pages.
struct DocumentScanner: UIViewControllerRepresentable {
    /// The pages scanned, or why the scanner stopped; nil when the person cancelled.
    let finished: (Result<[ReceiptPage], Error>?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let finished: (Result<[ReceiptPage], Error>?) -> Void

        init(finished: @escaping (Result<[ReceiptPage], Error>?) -> Void) { self.finished = finished }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            finished(.success((0..<scan.pageCount).compactMap { ReceiptPage(scanned: scan.imageOfPage(at: $0)) }))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { finished(nil) }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            finished(.failure(error))
        }
    }
}

/// The receipt's sheet: "Reading the receipt…" while Vision and the engine read it, then the check window, then (with
/// payments to ask about) the question. Cancel or a swipe while it reads stops the reading; the check window closes only
/// with Cancel (typed values are not lost by accident).
struct ReceiptSheet: View {
    let model: ReceiptCaptureModel
    let palette: Palette

    var body: some View {
        NavigationStack {
            Group {
                switch model.reading?.phase {
                case .checking(let check)?:
                    ReceiptCheckView(model: check, palette: palette) { await model.save(check) }
                case .asking(let question)?:
                    ReceiptQuestionView(question: question, palette: palette, problem: model.problem) { paymentID in
                        await model.answer(question, with: paymentID)
                    }
                case .failed(let message)?:
                    CalmReceiptState(symbol: "exclamationmark", text: Text(verbatim: message), busy: false)
                default:
                    CalmReceiptState(symbol: "doc.viewfinder", text: Text("Reading the receipt…"), busy: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { Ink.background.ignoresSafeArea() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isFailed {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { model.close() } label: { Text("Done", tableName: "Shared") }
                    }
                } else if !isAsking {               // the question is answered in the window; a swipe lets it wait
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { model.close() }
                    }
                }
            }
        }
        .tint(Ink.primary)
        .presentationBackground(Ink.background)
        .interactiveDismissDisabled(isChecking)
    }

    private var isChecking: Bool {
        if case .checking? = model.reading?.phase { true } else { false }
    }

    private var isAsking: Bool {
        if case .asking? = model.reading?.phase { true } else { false }
    }

    private var isFailed: Bool {
        if case .failed? = model.reading?.phase { true } else { false }
    }

    private var title: Text {
        switch model.reading?.phase {
        case .checking?: Text("Check the receipt")
        default: Text("Receipt")
        }
    }
}

/// The store's calm state in the sheet: a mark in a thin circle and one line, a little above the middle.
private struct CalmReceiptState: View {
    let symbol: String
    let text: Text
    let busy: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Ink.card2)
                Circle().strokeBorder(Ink.line, lineWidth: 1)
                Image(systemName: symbol).font(.system(size: 21, weight: .medium)).foregroundStyle(Ink.secondary)
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)
            HStack(spacing: 10) {
                if busy { ProgressView().tint(Ink.secondary) }
                text.font(AppFont.text(15, weight: .semibold)).foregroundStyle(Ink.primary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 22)
        }
        .accessibilityElement(children: .combine)
        .padding(.horizontal, 32)
        .padding(.bottom, 80)
    }
}
