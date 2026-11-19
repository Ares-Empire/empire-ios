import AVFoundation
import SwiftUI
import Vision
import VisionKit

/// Connecting once: flatd's pairing code, scanned from the QR code `flatd pair` shows on flatd's own machine (or pasted).
/// The code holds flatd's key and its identity (`FlatdPin`); the app then talks only to the server that proves that
/// identity, wherever Bonjour or the code's address say it is. No account (Patrik, 2026-11-19: "no account needed, just
/// me"): the pairing is flatd's own and stays on this iPhone, in the Keychain. Full screen while the app has no
/// pairing; a sheet from Settings to pair again.
struct ConnectScreen: View {
    let store: FlatStore
    @State private var model: ConnectModel
    /// Shown from Settings: it can be closed.
    var closable = false
    var onConnected: () -> Void = {}
    @State private var scanning = false
    /// The Connect in progress: it ends with the screen, so a slow attempt never keeps a pairing after it was closed.
    @State private var attempt: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    init(store: FlatStore, code: PairingCode? = nil, closable: Bool = false, onConnected: @escaping () -> Void = {}) {
        self.store = store
        self.closable = closable
        self.onConnected = onConnected
        _model = State(initialValue: ConnectModel(code: code))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ArestiaMark(size: 56).frame(maxWidth: .infinity).padding(.top, closable ? 4 : 28)
                    Text("Connect to the flat").font(AppFont.text(26, weight: .bold)).foregroundStyle(Ink.primary)
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 18)
                    Text("Arestia talks to flatd, the flat service on your home network. No account, only flatd's pairing code.")
                        .font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(3)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8).padding(.horizontal, 10)

                    SectionTitle(text: String(localized: "Pairing code")).padding(.top, 30).padding(.bottom, 10)
                    codeCard
                    FormNote(text: String(localized: "On the computer flatd runs on, run “flatd pair” in Terminal. It shows the code. Arestia then talks only to that flatd, encrypted."))
                        .padding(.top, 10)
                    if model.browser.state == .denied {
                        FormProblem(text: String(localized: "Arestia may not use the local network. Allow it in iOS Settings → Privacy → Local Network."))
                            .padding(.top, 14)
                    }
                    if let problem = model.problem {
                        FormProblem(text: problem).padding(.top, 14)
                    }
                    Button { connect() } label: {
                        BusyLabel(text: Text("Connect"), busy: model.isConnecting)
                    }
                    .buttonStyle(FormButtonStyle(accent: .arestia, busy: model.isConnecting))
                    .disabled(!model.canConnect)
                    .padding(.top, 22)
                }
                .padding(.horizontal, 18).padding(.bottom, 34)
                .animation(.easeOut(duration: 0.2), value: model.problem)
            }
            .scrollIndicators(.hidden)
            .background { ProvinceWall(accent: .arestia) }
            .toolbar {
                if closable {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .close) {
                            attempt?.cancel()          // at once, before the sheet is gone
                            dismiss()
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Ink.primary)
        .interactiveDismissDisabled(model.isConnecting)
        .onAppear {
            model.browser.start()
            if model.code != nil { connect() }       // a code handed in: connect with it
        }
        .onDisappear {
            model.browser.stop()
            attempt?.cancel()
        }
        .sheet(isPresented: $scanning) {
            QRScanSheet { text in
                scanning = false
                take(text)
            }
        }
    }

    /// A scanned or pasted code connects at once: there is nothing else to enter.
    private func take(_ text: String) {
        if model.take(text) { connect() }
    }

    private func connect() {
        attempt?.cancel()
        attempt = Task {
            if await model.connect(store: store), !Task.isCancelled {
                onConnected()
                if closable { dismiss() }
            }
        }
    }

    // MARK: the code

    @ViewBuilder private var codeCard: some View {
        VStack(spacing: 0) {
            if DataScannerViewController.isSupported {
                Button { scanning = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "qrcode.viewfinder").font(.system(size: 16)).foregroundStyle(Ink.secondary)
                        Text("Scan flatd's QR code").font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
                }
                .buttonStyle(SettingsRowStyle())
                .disabled(model.isConnecting)
                SettingsDivider()
            }
            HStack(spacing: 12) {
                Image(systemName: "doc.on.clipboard").font(.system(size: 15)).foregroundStyle(Ink.secondary)
                Group {
                    if DataScannerViewController.isSupported { Text("Or paste the code") } else { Text("Paste the code") }
                }
                .font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                Spacer()
                PasteButton(payloadType: String.self) { strings in
                    if let text = strings.first { Task { @MainActor in take(text) } }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)
                .tint(Ink.secondary)
                .disabled(model.isConnecting)
            }
            .padding(.leading, 16).padding(.trailing, 10).frame(minHeight: 52)
            if let code = model.code {
                SettingsDivider()
                HStack(spacing: 12) {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppAccent.arestia.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Code read").font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                        Text(verbatim: code.pin.short).font(AppFont.number(12)).foregroundStyle(Ink.muted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).frame(minHeight: 58)
                .accessibilityElement(children: .combine)
            }
        }
        .glassCard()
    }
}

/// The camera, reading one QR code. Asks iOS for the camera first (with the switcher cover held back, `SystemPrompt`).
private struct QRScanSheet: View {
    let found: (String) -> Void
    @State private var allowed: Bool?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch allowed {
                case true?:
                    QRScanner(found: found).ignoresSafeArea()
                case false?:
                    CalmCard(symbol: "camera", title: String(localized: "No camera"),
                             text: String(localized: "Allow the camera for Arestia in iOS Settings, or paste the code instead."))
                        .padding(18)
                case nil:
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { ProvinceWall(accent: .arestia) }
            .navigationTitle(Text("flatd's QR code"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } } }
        }
        .task {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: allowed = true
            case .notDetermined:
                SystemPrompt.begin()
                allowed = await AVCaptureDevice.requestAccess(for: .video)
                SystemPrompt.end()
            default: allowed = false
            }
        }
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    let found: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        private var done = false
        init(found: @escaping (String) -> Void) { self.found = found }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in items {
                guard !done, case let .barcode(code) = item, let text = code.payloadStringValue,
                      PairingCode.parse(text) != nil else { continue }
                done = true
                scanner.stopScanning()
                found(text)
            }
        }
    }
}
