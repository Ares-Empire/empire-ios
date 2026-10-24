import SwiftUI

/// The look the province apps share (Arestemis, Aresus, and the ones after them): the Aresium/Arestoteles dark wall,
/// glass cards and type (aresium/web/public/app/styles.css, Arestoteles/web/app/styles.css `[data-theme="dark"]`), with one
/// accent colour per app instead of their red. Patrik, 2026-10-24: each app may have its own accent so the apps can be
/// told apart, but only as an accent ("I don't want to see completely green apps"); red is the special mode.
/// Aresium and the Empire app keep their own styles (Palette, EmpireStyle).

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// An app's accent: the colour of its key control, highlights and the faint light on its wall.
struct AppAccent: Sendable {
    let color: Color        // controls, selected tab, highlights
    let deep: Color         // the wall's light and the glass edge tint

    /// Arestemis: moonlight violet (Artemis wears a crescent moon).
    static let arestemis = AppAccent(color: Color(hex: 0xA996FF), deep: Color(hex: 0x6A4FE0))
    /// Aresus: lightning blue (Zeus); keeps green and red free for status words.
    static let aresus = AppAccent(color: Color(hex: 0x6AA8FF), deep: Color(hex: 0x2F6BEA))
    /// Arestoteles: Aegean teal.
    static let arestoteles = AppAccent(color: Color(hex: 0x5ECBBE), deep: Color(hex: 0x1E8C82))
}

/// Ink and surfaces of the dark wall (`[data-theme="dark"]` in the Aresium/Arestoteles styles).
enum Ink {
    static let background = Color(hex: 0x050507)        // --bg
    static let primary = Color(hex: 0xF6F7FB)           // --ink
    static let secondary = Color(hex: 0xB3B9C6)         // --ink-2
    static let muted = Color(hex: 0x6B7280)             // --ink-3
    static let line = Color.white.opacity(0.08)         // --line-soft
    static let grid = Color.white.opacity(0.05)         // --grid
    static let card = Color(hex: 0x0F1015, opacity: 0.55)   // --card
    static let card2 = Color(hex: 0x1A1C23, opacity: 0.62)  // --card-2
    static let cardRadius: CGFloat = 16                 // --r-card
    static let rowRadius: CGFloat = 11                  // --r-row
}

/// Status words: green for running, red for a problem, grey for off; the same green as the hub's CONQUERED.
enum StatusTone: Sendable {
    case active, issue, inactive, accent

    func color(_ accent: AppAccent) -> Color {
        switch self {
        case .active: Color(hex: 0x6FCF9B)
        case .issue: Color(hex: 0xFF5D6C)
        case .inactive: Ink.muted
        case .accent: accent.color
        }
    }
}

/// A short status word in tracked capitals (the hub's ring-tab status).
struct StatusLabel: View {
    let text: String
    let tone: StatusTone
    var accent: AppAccent = .aresus
    var size: CGFloat = 10

    var body: some View {
        Text(text.uppercased()).font(AppFont.text(size, weight: .semibold)).tracking(size * 0.2)
            .foregroundStyle(tone.color(accent)).lineLimit(1)
    }
}

/// A small section heading ("OCTOBER 2026" on Aresium's start screen).
struct SectionHeading: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(AppFont.text(11, weight: .semibold)).tracking(1.3)
            .foregroundStyle(Ink.muted).accessibilityAddTraits(.isHeader)
    }
}

/// The black wall with the app's accent as a faint light from the top and the far corner (Aresium's dark wall,
/// `--glow1` / `--glow2`, in the accent colour).
struct ProvinceWall: View {
    let accent: AppAccent

    var body: some View {
        ZStack {
            Ink.background
            Glow(color: accent.deep.opacity(0.30), center: UnitPoint(x: 0.5, y: -0.12), radius: CGSize(width: 0.72, height: 0.52))
            Glow(color: accent.deep.opacity(0.16), center: UnitPoint(x: 0.9, y: 1.2), radius: CGSize(width: 0.58, height: 0.5))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// A CSS-style radial gradient with separate horizontal and vertical radii.
    private struct Glow: View {
        let color: Color
        let center: UnitPoint
        let radius: CGSize

        var body: some View {
            Canvas { context, size in
                context.translateBy(x: size.width * center.x, y: size.height * center.y)
                context.scaleBy(x: size.width * radius.width, y: size.height * radius.height)
                context.fill(Path(CGRect(x: -10, y: -10, width: 20, height: 20)), with: .radialGradient(
                    Gradient(stops: [.init(color: color, location: 0), .init(color: .clear, location: 0.6)]),
                    center: .zero, startRadius: 0, endRadius: 1))
            }
            .allowsHitTesting(false)
        }
    }
}

/// Glass surface: blurred translucent card, a soft highlight from the top left, and a bright edge that fades
/// (Arestoteles `--glass-edge` and `--spec`, the edge tinted with the accent instead of red).
struct GlassCard: ViewModifier {
    var accent: AppAccent? = nil
    var radius: CGFloat = Ink.cardRadius
    var raised = false            // a little lighter, for the one card that matters most on a screen

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                    shape.fill(raised ? Ink.card2 : Ink.card)
                    shape.fill(RadialGradient(colors: [.white.opacity(0.07), .clear], center: .topLeading,
                                              startRadius: 0, endRadius: 220))
                }
            }
            .overlay {
                shape.strokeBorder(LinearGradient(stops: [
                    .init(color: .white.opacity(0.22), location: 0),
                    .init(color: .white.opacity(0.04), location: 0.30),
                    .init(color: (accent?.color ?? .white).opacity(accent == nil ? 0.03 : 0.10), location: 0.68),
                    .init(color: .white.opacity(0.03), location: 1)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.55), radius: 22, y: 14)
    }
}

extension View {
    func glassCard(accent: AppAccent? = nil, radius: CGFloat = Ink.cardRadius, raised: Bool = false) -> some View {
        modifier(GlassCard(accent: accent, radius: radius, raised: raised))
    }
}

/// A square glass icon button (Aresium's header buttons).
struct GlassIconButton: View {
    let symbol: String
    let label: String
    var tint: Color = Ink.secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(Ink.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Ink.line))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The big wordmark across the full width that ends a province app's main screen (Aresium's band, without its
/// special mode): the letters spread edge to edge, white fading into the wall.
struct WordmarkBand: View {
    let word: String
    let width: CGFloat

    var body: some View {
        let letters = Array(word.uppercased())
        let size = min(220, max(48, width / CGFloat(max(letters.count, 1)) * 1.08))
        LinearGradient(stops: [.init(color: Ink.primary, location: 0),
                               .init(color: Color(hex: 0x7F7F7F, opacity: 0.18), location: 1.16)],
                       startPoint: .top, endPoint: .bottom)
            .frame(width: width, height: size * 0.74)
            .mask {
                Canvas { context, canvasSize in
                    let glyphs = letters.map {
                        context.resolve(Text(String($0)).font(.custom(AppFont.textName, fixedSize: size).weight(.bold))
                            .tracking(-size * 0.015))
                    }
                    let proposal = CGSize(width: canvasSize.width, height: .infinity)
                    let widths = glyphs.map { $0.measure(in: proposal).width }
                    let gap = (canvasSize.width - 8 - widths.reduce(0, +)) / CGFloat(max(glyphs.count - 1, 1))
                    var x: CGFloat = 4
                    for (index, glyph) in glyphs.enumerated() {
                        context.draw(glyph, at: CGPoint(x: x, y: canvasSize.height - glyph.firstBaseline(in: proposal)),
                                     anchor: .topLeading)
                        x += widths[index] + gap
                    }
                }
            }
            .opacity(0.9)
            .accessibilityHidden(true)
    }
}
