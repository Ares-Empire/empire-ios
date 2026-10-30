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
        .minimumTapArea()                   // drawn at 42 pt like the header's buttons, taps over 44 pt
    }
}

struct ImportFeedback: View {
    let store: ImportStore
    let palette: Palette
    /// The messages' offer after the first import (brief 46), in the result's place once the result has gone; nil while
    /// it does not show (`ReminderOffer.shows`).
    var offer: ReminderOfferChoice? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            // One toast per result: a new result starts unmoved (`BottomToast`'s swipe).
            if let banner = store.banner {
                ImportToast(banner: banner, store: store, palette: palette).id(banner.id)
            } else if let offer {
                // Not now, also as a swipe down, as the send card's.
                BottomToast(palette: palette, closesBySwipe: { true }, close: offer.notNow) {
                    ReminderOfferCard(offer: offer, palette: palette)
                }
                .id("reminder-offer")
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        // The offer comes by itself after the result: it rises into place rather than appearing at once.
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.35), value: offer != nil)
    }
}

private struct ImportToast: View {
    let banner: ImportBanner
    let store: ImportStore
    let palette: Palette

    private var asking: Bool {
        guard let share = banner.share else { return false }
        return share.shown == .asking || share.shown == .sending
    }

    var body: some View {
        // Swipe down to put it away, as a notification (brief 41); only where Dismiss (or Not now) would. A newer result
        // is never closed by this one's swipe.
        BottomToast(palette: palette, closesBySwipe: { store.closesBySwipe }, close: { [id = banner.id] in
            if store.banner?.id == id { store.close() }
        }) {
            content
        }
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
            // The words stay as drawn; each takes taps over 44 pt (brief 41).
            if !asking {
                HStack(spacing: 24) {
                    if store.canRetry {
                        Button { Task { await store.importPendingFiles() } } label: { Text("Retry").minimumTapArea() }
                        Button { store.discard() } label: { Text("Discard").minimumTapArea() }
                    } else {
                        Button { store.close() } label: { Text("Dismiss").minimumTapArea() }
                    }
                }.font(AppFont.text(13, weight: .bold)).tint(palette.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The card at the bottom of the app (the website's `.import-toast`): the import's result, and the messages' offer in
/// its place (brief 46). The second card colour over a blur, so the list under it never shows through the words, and a
/// soft shadow; never taller than its content, and it scrolls when the screen is shorter. A swipe down puts it away as
/// a notification (brief 41) while `closesBySwipe` allows it and it does not scroll (there the drag belongs to the
/// scrolling); VoiceOver's escape does the same.
struct BottomToast<Content: View>: View {
    let palette: Palette
    /// Whether a swipe may close it now (read as the swipe ends, so a state that changed meanwhile counts).
    let closesBySwipe: () -> Bool
    let close: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The content's own height: the card is never taller, and scrolls when the screen is shorter.
    @State private var height: CGFloat = 0
    /// The height it is shown at (less than `height` when it scrolls).
    @State private var shownHeight: CGFloat = 0
    /// How far the finger has moved it; back to 0 by itself when the drag ends or is cancelled.
    @GestureState private var dragging: CGFloat = 0
    /// Where it is after the finger let go: sliding off, or back into place.
    #if DEBUG
    /// Screenshots: `-sampleBannerDrag <points>` shows it moved down as a swipe moves it.
    @State private var released = CGFloat(Double(LaunchArguments.value("-sampleBannerDrag") ?? "") ?? 0)
    #else
    @State private var released: CGFloat = 0
    #endif

    var body: some View {
        ScrollView {
            content()
                .padding(14)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .frame(maxHeight: height)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14).fill(palette.card2)
            }
            .shadow(color: Ink.shadow, radius: 20, y: 12)
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.line))
        .padding(.horizontal, 18).padding(.bottom, 14)
        .offset(y: dragging + released)
        .gesture(swipeAway, isEnabled: closesBySwipe() && height <= shownHeight + 1)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityAction(.escape) { if closesBySwipe() { close() } }
    }

    /// The swipe: the card follows the finger down (upwards only a little, as a sheet does); let go far or fast enough
    /// it slides off and closes, else it goes back. With Reduce Motion it closes without sliding off.
    private var swipeAway: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragging) { value, state, _ in state = Self.follow(value.translation.height) }
            .onEnded { value in
                // The finger's offset ends here (`dragging` is 0 again); `released` takes over from where it is.
                released = Self.follow(value.translation.height)
                let closes = value.translation.height > 44 || value.predictedEndTranslation.height > 140
                guard closes, closesBySwipe() else {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { released = 0 }
                    return
                }
                if reduceMotion {
                    close()
                    return
                }
                withAnimation(.easeOut(duration: 0.2)) {
                    released = shownHeight + 60          // below the screen's edge, shadow and all
                } completion: {
                    close()
                }
            }
    }

    /// Down follows the finger; up gives only a little.
    private static func follow(_ translation: CGFloat) -> CGFloat { translation > 0 ? translation : translation / 6 }
}

/// The offer's state and answers, from the owner of the messages (ContentView).
struct ReminderOfferChoice {
    /// How often the reminder would come (the line names it).
    let interval: MessageInterval
    let turnOn: () -> Void
    let notNow: () -> Void
}

/// The one-time offer after the first import (brief 46), in the result's card and place: the question, the line on the
/// reminder and the month review, Turn on and Not now, laid out as the send card's ("Help Aresium learn your bank").
struct ReminderOfferCard: View {
    let offer: ReminderOfferChoice
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: "bell").foregroundStyle(palette.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Remind you to import new statements?").font(AppFont.text(14.5, weight: .semibold))
                        .foregroundStyle(palette.ink).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: MessageWording.offerLine(offer.interval)).font(AppFont.text(12.5))
                        .foregroundStyle(palette.secondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    turnOn.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    notNow
                }
                VStack(alignment: .leading, spacing: 10) {
                    turnOn
                    notNow
                }
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var turnOn: some View {
        Button(action: offer.turnOn) { Text("Turn on") }
            .buttonStyle(FormButtonStyle(accent: nil))
    }

    /// A quiet word, taking taps over 44 pt (brief 41), as the send card's Not now.
    private var notNow: some View {
        Button(action: offer.notNow) { Text("Not now").minimumTapArea() }
            .buttonStyle(.plain)
            .font(AppFont.text(13, weight: .bold)).foregroundStyle(palette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}
