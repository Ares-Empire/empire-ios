import AVFoundation
import SwiftUI
import Vision
import VisionKit

/// Connecting once: which flatd (found on the home network over Bonjour, or an address typed in) and its key (pasted,
/// or scanned from the QR code flatd shows). No account (Patrik, 2026-11-19: "no account needed, just me"): the key is
/// flatd's own and stays on this iPhone, in the Keychain. Full screen while the app has no key; a sheet from Settings to
/// change it.
struct ConnectScreen: View {
    let store: FlatStore
    @State private var model: ConnectModel
    /// Shown from Settings (or a connect link): it can be closed.
    var closable = false
    var onConnected: () -> Void = {}
    @State private var scanning = false
    /// The Connect in progress: it ends with the screen, so a slow attempt never keeps a pairing after it was closed.
    @State private var attempt: Task<Void, Never>?
    @FocusState private var keyFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(store: FlatStore, code: PairingCode? = nil, closable: Bool = false, onConnected: @escaping () -> Void = {}) {
        self.store = store
        self.closable = closable
        self.onConnected = onConnected
        _model = State(initialValue: ConnectModel(code: code, current: closable ? store.connection.link : nil))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ArestiaMark(size: 56).frame(maxWidth: .infinity).padding(.top, closable ? 4 : 28)
                    Text("Connect to the flat").font(AppFont.text(26, weight: .bold)).foregroundStyle(Ink.primary)
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 18)
                    Text("Arestia talks to flatd, the flat service on your Mac, over the home Wi-Fi. No account, only flatd's key.")
                        .font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(3)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8).padding(.horizontal, 10)

                    SectionTitle(text: String(localized: "Flat service")).padding(.top, 30).padding(.bottom, 10)
                    serviceCard
                    SectionTitle(text: String(localized: "Key")).padding(.top, 26).padding(.bottom, 10)
                    keyCard
                    FormNote(text: String(localized: "The key stays on this iPhone, in the Keychain.")).padding(.top, 10)
                    if let problem = model.problem {
                        FormProblem(text: problem).padding(.top, 14)
                    }
                    Button {
                        attempt?.cancel()
                        attempt = Task {
                            if await model.connect(store: store), !Task.isCancelled {
                                onConnected()
                                if closable { dismiss() }
                            }
                        }
                    } label: {
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
            .scrollDismissesKeyboard(.interactively)
            .background { ProvinceWall(accent: .arestia) }
            .toolbar {
                if closable {
                    ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Ink.primary)
        .onAppear { model.browser.start() }
        .onDisappear {
            model.browser.stop()
            attempt?.cancel()
        }
        .sheet(isPresented: $scanning) {
            QRScanSheet { text in
                scanning = false
                model.take(text)
            }
        }
    }

    // MARK: which flatd

    @ViewBuilder private var serviceCard: some View {
        VStack(spacing: 0) {
            if model.typesAddress {
                TextField("", text: $model.typedAddress,
                          prompt: Text("Address, e.g. 192.168.1.20:8787").foregroundStyle(Ink.muted))
                    .font(AppFont.text(15)).foregroundStyle(Ink.primary)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(.horizontal, 16).frame(minHeight: 52)
                SettingsDivider()
                Button { model.typesAddress = false } label: {
                    SettingsRow(title: String(localized: "Find it on the network instead"), trailing: .none,
                                tint: Ink.secondary)
                }
                .buttonStyle(SettingsRowStyle())
            } else {
                ForEach(model.browser.found, id: \.self) { name in
                    Button { model.chosenService = name } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "desktopcomputer").font(.system(size: 15)).foregroundStyle(Ink.secondary)
                            Text(verbatim: name).font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                            Spacer()
                            if model.target == .service(name) {
                                Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppAccent.arestia.color)
                            }
                        }
                        .padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
                    }
                    .buttonStyle(SettingsRowStyle())
                    .accessibilityAddTraits(model.target == .service(name) ? .isSelected : [])
                    SettingsDivider()
                }
                if model.browser.found.isEmpty {
                    HStack(spacing: 12) {
                        switch model.browser.state {
                        case .denied:
                            Image(systemName: "wifi.exclamationmark").foregroundStyle(FormProblem.ink)
                            Text("Arestia may not use the local network. Allow it in iOS Settings → Privacy → Local Network.")
                                .font(AppFont.text(13)).foregroundStyle(Ink.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        default:
                            ProgressView().tint(Ink.secondary)
                            Text("Looking on your network…").font(AppFont.text(14)).foregroundStyle(Ink.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14).frame(minHeight: 52)
                    SettingsDivider()
                }
                Button { model.typesAddress = true } label: {
                    SettingsRow(title: String(localized: "Enter an address"), trailing: .none, tint: Ink.secondary)
                }
                .buttonStyle(SettingsRowStyle())
            }
        }
        .glassCard()
    }

    // MARK: the key

    @ViewBuilder private var keyCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                SecureField("", text: $model.key, prompt: Text("Paste flatd's key").foregroundStyle(Ink.muted))
                    .font(AppFont.number(14)).foregroundStyle(Ink.primary)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textContentType(.oneTimeCode)
                    .focused($keyFocused)
                    .submitLabel(.done)
                    .onChange(of: model.key) { _, text in
                        // A whole pairing code pasted into the field: take what it says.
                        if text.contains("://") || text.hasPrefix("{") { model.take(text) }
                    }
                PasteButton(payloadType: String.self) { strings in
                    if let text = strings.first { Task { @MainActor in model.take(text) } }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)
                .tint(Ink.secondary)
            }
            .padding(.leading, 16).padding(.trailing, 10).frame(minHeight: 52)
            if DataScannerViewController.isSupported {
                SettingsDivider()
                Button { scanning = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "qrcode.viewfinder").font(.system(size: 16)).foregroundStyle(Ink.secondary)
                        Text("Scan flatd's QR code").font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
                }
                .buttonStyle(SettingsRowStyle())
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
                             text: String(localized: "Allow the camera for Arestia in iOS Settings, or paste the key instead."))
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
