import SwiftUI
import UniformTypeIdentifiers

struct ImportButton: View {
    let store: ImportStore
    let sample: Bool
    let palette: Palette
    /// What the file picker offers: the server's CSV and XML, or phone mode's bank files (`PhoneImportTypes`).
    var types: [UTType] = [.commaSeparatedText, .xml]
    /// Done instead of opening the file picker (the tour, which picks no file into its made-up store).
    var instead: (() -> Void)? = nil
    @State private var pickingFiles = false

    var body: some View {
        Button {
            if sample { store.showSampleUnavailable() }
            else if let instead { instead() }
            else { pickingFiles = true }
        } label: {
            Group {
                if store.isBusy { ProgressView().tint(palette.secondary) }
                else { Image(systemName: "tray.and.arrow.up").font(.system(size: 17, weight: .medium)) }
            }
            .frame(width: 42, height: 42)
            .foregroundStyle(palette.secondary)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.line))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.isBusy ? "Importing statements" : "Import statements")
        .disabled(store.isBusy)
        .fileImporter(isPresented: $pickingFiles, allowedContentTypes: types, allowsMultipleSelection: true) { result in
            switch result {
            case let .success(urls):
                if !urls.isEmpty { Task { await store.receive(urls) } }
            case let .failure(error): store.show(error.localizedDescription, success: false)
            }
        }
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
