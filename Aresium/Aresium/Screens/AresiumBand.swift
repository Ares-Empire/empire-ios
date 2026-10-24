import SwiftUI

/// Shared by the real band and the overlay so the last entering frame lands exactly in place.
struct AresiumWord: View {
    let palette: Palette
    let width: CGFloat

    var body: some View {
        let size = min(252, max(64, width * 0.154))
        let height = size * 0.72
        palette.wordGradient(width: width, height: height)
            .frame(width: width, height: height)
            .mask {
                Canvas { context, canvasSize in
                    let letters = "ARESIUM".map {
                        context.resolve(Text(String($0))
                            .font(.custom(AppFont.textName, fixedSize: size).weight(.bold))
                            .tracking(-size * 0.015))
                    }
                    let proposal = CGSize(width: canvasSize.width, height: .infinity)
                    let widths = letters.map { $0.measure(in: proposal).width }
                    let gap = (canvasSize.width - 8 - widths.reduce(0, +)) / 6
                    var x: CGFloat = 4
                    for (index, letter) in letters.enumerated() {
                        // Place capital glyphs on the band baseline without Text's descent/leading.
                        context.draw(letter, at: CGPoint(x: x, y: canvasSize.height - letter.firstBaseline(in: proposal)),
                                     anchor: .topLeading)
                        x += widths[index] + gap
                    }
                }
            }
            .opacity(0.92)
            .accessibilityHidden(true)
    }
}

/// The ARESIUM band that ends the screens' scroll content (`WordmarkScrollView`), so it shows only when you scroll down.
/// Tapping it enters or leaves the special mode; it hands over where the word is on screen, so the intro's word lands
/// exactly on it (or lifts off from it).
struct AresiumBand: View {
    let palette: Palette
    let width: CGFloat
    let hidden: Bool
    let action: (_ wordFrame: CGRect) -> Void       // in the global (screen) coordinate space
    @State private var wordFrame = CGRect.zero      // read only on a tap, so scrolling does not redraw the band

    var body: some View {
        Button { action(wordFrame) } label: {
            AresiumWord(palette: palette, width: width)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { wordFrame = $0 }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(hidden ? 0 : 1)
        .accessibilityLabel(palette.red ? "Exit Aresium mode" : "Enter Aresium mode")
        .accessibilityHidden(hidden)
    }
}

struct AresiumIntro: View {
    let transition: ThemeState.Transition
    let landing: CGFloat            // from the screen's bottom edge to the band word's bottom, where the word lands
    var pausedProgress: Double?

    var body: some View {
        Group {
            if let pausedProgress {
                frame(at: pausedProgress)
            } else {
                // A linear clock lets the shared sampler preserve the website's exact offsets
                // and per-segment cubic Beziers, including the impact curve's overshoot.
                Color.clear.keyframeAnimator(initialValue: 0.0, repeating: false) { _, progress in
                    frame(at: progress)
                } keyframes: { _ in
                    LinearKeyframe(1.0, duration: IntroTimeline.duration)
                }
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }

    nonisolated private func frame(at progress: Double) -> some View {
        GeometryReader { geometry in
            let pose = IntroTimeline.frame(at: progress, entering: transition.entering)
            let target = Palette(theme: transition.target)
            ZStack(alignment: .bottom) {
                Wall(palette: target).opacity(IntroTimeline.backgroundOpacity(at: progress))
                // The website overlay uses the translucent white word in either direction.
                // Reuse the red band's gradient so entering ends on the identical real word.
                AresiumWord(palette: Palette(theme: .red), width: geometry.size.width)
                    .scaleEffect(pose.scale)
                    .rotationEffect(.degrees(pose.rotation))
                    .offset(x: pose.x, y: geometry.size.height * pose.y / 100)
                    .opacity(pose.opacity)
                    .padding(.bottom, landing)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
    }
}
