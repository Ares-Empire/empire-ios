import SwiftUI
import UniformTypeIdentifiers

struct ImportButton: View {
    let store: ImportStore
    let sample: Bool
    let palette: Palette
    @State private var pickingFiles = false

    var body: some View {
        Button {
            if sample { store.showSampleUnavailable() }
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
        .fileImporter(isPresented: $pickingFiles, allowedContentTypes: [.commaSeparatedText, .xml], allowsMultipleSelection: true) { result in
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

    var body: some View {
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
            HStack(spacing: 24) {
                if store.canRetry {
                    Button("Retry") { Task { await store.importPendingFiles() } }
                    Button("Discard") { store.discard() }
                } else {
                    Button("Dismiss") { store.dismiss() }
                }
            }.font(AppFont.text(13, weight: .bold)).tint(palette.ink)
        }
        .padding(14)
        .background(palette.card2, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.line))
        .padding(.horizontal, 18).padding(.bottom, 14)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
