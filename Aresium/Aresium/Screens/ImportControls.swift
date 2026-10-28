import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// What Import offers in phone mode (brief 31): the bank file as before, a receipt scanned with Apple's document
/// scanner (only where VisionKit says its camera is supported; the iOS 27 simulator says yes but cannot record, so its
/// scanner stops at once: "The scanner stopped. Try again.", seen 2026-10-27) or a receipt's photo.
struct ImportChoices {
    let chooseFile: () -> Void
    let scanReceipt: (() -> Void)?
    let choosePhoto: () -> Void
    /// Cash spent or received by hand (brief 33).
    let addCash: () -> Void

    init(chooseFile: @escaping () -> Void, scanReceipt: @escaping () -> Void, choosePhoto: @escaping () -> Void,
         addCash: @escaping () -> Void) {
        self.chooseFile = chooseFile
        self.scanReceipt = VNDocumentCameraViewController.isSupported ? scanReceipt : nil
        self.choosePhoto = choosePhoto
        self.addCash = addCash
    }

    /// The tour: every choice only answers its import step; nothing is picked, scanned, read or entered.
    static func tour(_ answer: @escaping () -> Void) -> ImportChoices {
        ImportChoices(chooseFile: answer, scanReceipt: answer, choosePhoto: answer, addCash: answer)
    }
}

/// Import as Apple's usual menu: Choose file, Scan receipt, Choose photo, Add cash, opened from `label` (the first
/// screen's main button, the dashboard's import button).
struct ImportMenu<Label: View>: View {
    let choices: ImportChoices
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            Button("Choose file", systemImage: "doc", action: choices.chooseFile)
            if let scan = choices.scanReceipt {
                Button("Scan receipt", systemImage: "doc.viewfinder", action: scan)
            }
            Button("Choose photo", systemImage: "photo", action: choices.choosePhoto)
            Button("Add cash", systemImage: "banknote", action: choices.addCash)
        } label: {
            label()
        }
        .menuStyle(.button)
    }
}

struct ImportButton: View {
    let store: ImportStore
    let sample: Bool
    let palette: Palette
    /// Phone mode and the tour: Import's menu (`ImportMenu`), whose owner picks and reads. Nil: server mode's button,
    /// which opens its own file picker for the server's CSV and XML.
    var choices: ImportChoices? = nil
    @State private var pickingFiles = false

    var body: some View {
        Group {
            if let choices {
                ImportMenu(choices: choices) { icon }
                    .buttonStyle(.plain)
                    .accessibilityLabel(store.isBusy ? Text("Importing statements") : Text("Import"))
            } else {
                Button {
                    if sample { store.showSampleUnavailable() }
                    else { pickingFiles = true }
                } label: { icon }
                .buttonStyle(.plain)
                .accessibilityLabel(store.isBusy ? "Importing statements" : "Import statements")
                .fileImporter(isPresented: $pickingFiles, allowedContentTypes: [.commaSeparatedText, .xml],
                              allowsMultipleSelection: true) { result in
                    switch result {
                    case let .success(urls):
                        if !urls.isEmpty { Task { await store.receive(urls) } }
                    case let .failure(error): store.show(error.localizedDescription, success: false)
                    }
                }
            }
        }
        .disabled(store.isBusy)
    }

    private var icon: some View {
        Group {
            if store.isBusy { ProgressView().tint(palette.secondary) }
            else { Image(systemName: "tray.and.arrow.up").font(.system(size: 17, weight: .medium)) }
        }
        .frame(width: 42, height: 42)
        .foregroundStyle(palette.secondary)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.line))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ImportFeedback: View {
    let store: ImportStore
    let palette: Palette

    var body: some View {
        Group {
            if let banner = store.banner { ImportToast(banner: banner, store: store, palette: palette) }
        }
    }
}

private struct ImportToast: View {
    let banner: ImportBanner
    let store: ImportStore
    let palette: Palette
    /// The content's own height: the result is never taller, and scrolls when the screen is shorter.
    @State private var height: CGFloat = 0

    private var asking: Bool {
        guard let share = banner.share else { return false }
        return share.shown == .asking || share.shown == .sending
    }

    var body: some View {
        ScrollView {
            content
                .padding(14)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .frame(maxHeight: height)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .background {
            // The website's toast (`.import-toast`): the second card colour over a blur, so the list under it never
            // shows through the words, and a soft shadow.
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14).fill(palette.card2)
            }
            .shadow(color: Ink.shadow, radius: 20, y: 12)
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.line))
        .padding(.horizontal, 18).padding(.bottom, 14)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: banner.success ? "checkmark.circle" : "exclamationmark.circle")
                    .foregroundStyle(banner.success ? palette.income : palette.expenseText)
                Text(banner.message).font(AppFont.text(13, weight: .semibold))
                    .foregroundStyle(palette.ink).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(banner.files.enumerated()), id: \.offset) { _, result in
                Text(result).font(AppFont.text(12)).foregroundStyle(palette.secondary)
            }
            if let share = banner.share {
                // Phone mode, an unknown bank's file just read with the confirmed layout: the offer to send its format.
                Rectangle().fill(palette.line).frame(height: 1).padding(.vertical, 2)
                BankFormatCardView(card: share, palette: palette) { store.close() }
            }
            // While the card asks, its Not now closes the result.
            if !asking {
                HStack(spacing: 24) {
                    if store.canRetry {
                        Button("Retry") { Task { await store.importPendingFiles() } }
                        Button("Discard") { store.discard() }
                    } else {
                        Button("Dismiss") { store.close() }
                    }
                }.font(AppFont.text(13, weight: .bold)).tint(palette.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
