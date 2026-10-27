import SwiftUI
import UIKit

/// The look the province apps share (Arestemis, Aresus, and the ones after them): the Aresium/Arestoteles wall, glass
/// cards and type (aresium/web/public/index.html `html[data-theme="dark"]` and `html[data-theme="light"]`), with one
/// accent colour per app instead of their red. Patrik, 2026-10-24: each app may have its own accent so the apps can be
/// told apart, but only as an accent ("I don't want to see completely green apps"); red is the special mode.
/// Every colour here is a light/dark pair, so a screen built from them follows the app's appearance by itself
/// (Settings → Appearance, `Appearance`). Aresium and the Empire app keep their own styles (Palette, EmpireStyle).

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    /// One colour for each appearance; the screen picks as it draws, so it follows a switch at once. Nonisolated:
    /// SwiftUI may resolve a colour off the main thread (it draws some animations on a render thread), where a
    /// main-actor closure stops the app (seen with the tour's veil, 2026-10-27).
    nonisolated init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { @Sendable traits in UIColor(traits.userInterfaceStyle == .dark ? dark : light) })
    }
}

/// An app's accent: the colour of its key control, highlights and the faint light on its wall. On the light wall
/// the accent is a deeper shade of the same colour, so text and marks in it read as well as on the dark one (at
/// least 4.5:1 on `Ink.background`).
struct AppAccent: Sendable {
    let color: Color        // controls, selected tab, highlights
    let deep: Color         // the wall's light and the glass edge tint
    /// Words and marks on a fill of `color` (a main button): dark on the bright dark-mode accent, white on the deeper
    /// light-mode one.
    static let onColor = Color(light: .white, dark: Color(hex: 0x141617))

    /// Arestemis: moonlight violet (Artemis wears a crescent moon).
    static let arestemis = AppAccent(color: Color(light: Color(hex: 0x6A4FE0), dark: Color(hex: 0xA996FF)),
                                     deep: Color(hex: 0x6A4FE0))
    /// Aresus: lightning blue (Zeus); keeps green and red free for status words.
    static let aresus = AppAccent(color: Color(light: Color(hex: 0x2A62E0), dark: Color(hex: 0x6AA8FF)),
                                  deep: Color(hex: 0x2F6BEA))
    /// Arestoteles: Aegean teal.
    static let arestoteles = AppAccent(color: Color(light: Color(hex: 0x12746B), dark: Color(hex: 0x5ECBBE)),
                                       deep: Color(hex: 0x1E8C82))
}

/// Ink and surfaces of the wall, light and dark (`html[data-theme="light"]` / `"dark"` in Aresium's styles). One
/// change from the website: the light `muted` is darker than its #88919F, which is too faint for 11–12 pt text on
/// the phone (3.9:1 now, as the dark one's 4.2:1).
enum Ink {
    static let background = Color(light: Color(hex: 0xECEDF2), dark: Color(hex: 0x050507))           // --bg
    static let primary = Color(light: Color(hex: 0x0A0C12), dark: Color(hex: 0xF6F7FB))              // --ink
    static let secondary = Color(light: Color(hex: 0x525A69), dark: Color(hex: 0xB3B9C6))            // --ink-2
    static let muted = Color(light: Color(hex: 0x6E7685), dark: Color(hex: 0x6B7280))                // --ink-3
    static let line = Color(light: Color(hex: 0x0F1428, opacity: 0.10), dark: .white.opacity(0.08)) // --line-soft
    static let grid = Color(light: Color(hex: 0x0F1428, opacity: 0.07), dark: .white.opacity(0.05)) // --grid
    static let card = Color(light: .white.opacity(0.74), dark: Color(hex: 0x0F1015, opacity: 0.55)) // --card
    static let card2 = Color(light: Color(hex: 0xF7F8FB, opacity: 0.82),                              // --card-2
                             dark: Color(hex: 0x1A1C23, opacity: 0.62))
    /// A row or button while it is pressed (--hover).
    static let press = Color(light: Color(hex: 0x0F1428, opacity: 0.045), dark: .white.opacity(0.05))
    /// An input's fill and edge (the login's fields, quiet outlined buttons).
    static let field = Color(light: .white.opacity(0.62), dark: .white.opacity(0.04))
    static let edge = Color(light: Color(hex: 0x0F1428, opacity: 0.13), dark: .white.opacity(0.12))
    /// The shadow under a card or a floating mark (--shadow): black on the dark wall, a soft blue-grey on the light one.
    static let shadow = Color(light: Color(hex: 0x0F1628, opacity: 0.16), dark: .black.opacity(0.55))
    static let cardRadius: CGFloat = 16                 // --r-card
    static let rowRadius: CGFloat = 11                  // --r-row
}

/// Status words: green for running, red for a problem, grey for off; the same green as the hub's CONQUERED. Deeper
/// on the light wall, as the accents.
enum StatusTone: Sendable {
    case active, issue, inactive, accent

    static let activeColor = Color(light: Color(hex: 0x12784A), dark: Color(hex: 0x6FCF9B))
    static let issueColor = Color(light: Color(hex: 0xD11F35), dark: Color(hex: 0xFF5D6C))

    func color(_ accent: AppAccent) -> Color {
        switch self {
        case .active: Self.activeColor
        case .issue: Self.issueColor
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

/// The wall with the app's accent as a faint light from the top and the far corner (Aresium's walls, `--glow1` /
/// `--glow2`, in the accent colour; on the light wall about a third as strong, as Aresium's).
struct ProvinceWall: View {
    let accent: AppAccent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let light = scheme == .light
        ZStack {
            Ink.background
            Glow(color: accent.deep.opacity(light ? 0.11 : 0.30), center: UnitPoint(x: 0.5, y: -0.12),
                 radius: CGSize(width: 0.72, height: 0.52))
            Glow(color: accent.deep.opacity(light ? 0.05 : 0.16), center: UnitPoint(x: 0.9, y: 1.2),
                 radius: CGSize(width: 0.58, height: 0.5))
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
/// (`--glass-edge` and `--spec` of Aresium's light and dark themes, the edge tinted with the accent instead of red).
/// On the light wall the card is nearly white with a strong white edge and a soft shadow; on the dark one it is
/// smoked glass with a faint edge.
struct GlassCard: ViewModifier {
    var accent: AppAccent? = nil
    var radius: CGFloat = Ink.cardRadius
    var raised = false            // a little lighter, for the one card that matters most on a screen
    var edge: Color? = nil        // one colour in place of the bright edge (Aresus's issue box: a faint red)
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let light = scheme == .light
        let tint = accent?.deep ?? .white
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(raised ? Ink.card2 : Ink.card)
                    shape.fill(RadialGradient(colors: [.white.opacity(light ? 0.6 : 0.07), .clear], center: .topLeading,
                                              startRadius: 0, endRadius: 220))
                }
            }
            .overlay {
                if let edge {
                    shape.strokeBorder(edge, lineWidth: 1)
                } else {
                    glassEdge(shape, light: light, tint: tint)
                }
            }
            .shadow(color: Ink.shadow, radius: light ? 18 : 22, y: light ? 10 : 14)
    }

    /// The bright edge that fades: white from the top left, the accent's tint lower down.
    private func glassEdge(_ shape: RoundedRectangle, light: Bool, tint: Color) -> some View {
        shape.strokeBorder(LinearGradient(stops: light ? [
            .init(color: .white.opacity(0.95), location: 0),
            .init(color: .white.opacity(0.4), location: 0.35),
            .init(color: accent == nil ? .white.opacity(0.3) : tint.opacity(0.14), location: 0.74),
            .init(color: .white.opacity(0.3), location: 1)
        ] : [
            .init(color: .white.opacity(0.22), location: 0),
            .init(color: .white.opacity(0.04), location: 0.30),
            .init(color: accent == nil ? .white.opacity(0.03) : (accent?.color ?? .white).opacity(0.10), location: 0.68),
            .init(color: .white.opacity(0.03), location: 1)
        ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
    }
}

extension View {
    func glassCard(accent: AppAccent? = nil, radius: CGFloat = Ink.cardRadius, raised: Bool = false,
                   edge: Color? = nil) -> some View {
        modifier(GlassCard(accent: accent, radius: radius, raised: raised, edge: edge))
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

/// The big wordmark across the full width that ends an app's main screen (Aresium's band, without its special mode):
/// the letters spread edge to edge, by default white fading into the wall. A space is a wider slot, so two words
/// read apart (the hub's "ARES EMPIRE" band does the same).
struct WordmarkBand: View {
    let word: String
    let width: CGFloat
    var fill = AnyShapeStyle(LinearGradient(stops: [.init(color: Ink.primary, location: 0),
                                                    .init(color: Color(hex: 0x7F7F7F, opacity: 0.18), location: 1.16)],
                                            startPoint: .top, endPoint: .bottom))

    /// The letters' size for a word across a width.
    static func letterSize(of word: String, width: CGFloat) -> CGFloat {
        min(220, max(48, width / CGFloat(max(word.count, 1)) * 1.08))
    }

    /// How tall the band is (a screen that places things around it, as Aresium's lock screen).
    static func height(of word: String, width: CGFloat) -> CGFloat { letterSize(of: word, width: width) * 0.74 }

    var body: some View {
        let letters = Array(word.uppercased())
        let size = Self.letterSize(of: word, width: width)
        Rectangle().fill(fill)
            .frame(width: width, height: Self.height(of: word, width: width))
            .mask {
                Canvas { context, canvasSize in
                    let glyphs = letters.map {
                        context.resolve(Text(String($0)).font(.custom(AppFont.textName, fixedSize: size).weight(.bold))
                            .tracking(-size * 0.015))
                    }
                    let proposal = CGSize(width: canvasSize.width, height: .infinity)
                    let widths = zip(letters, glyphs).map { $0 == " " ? size * 0.5 : $1.measure(in: proposal).width }
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

/// The main screen's scroll view, ending with the app's wordmark: the rule for every app (Patrik, 2026-10-24). Use it
/// in place of the screen's `ScrollView`. The band scrolls with the content and is never fixed on screen. Below
/// content shorter than the screen the gap grows to the scroll view's bottom edge, so the band starts just below it
/// and shows only when you scroll down; longer content is followed by the band (`WordmarkEnd` spacing).
/// Scroll modifiers (`.refreshable`, `.scrollIndicators`, …) go on it as on a `ScrollView`; inside a
/// `ScrollViewReader`, `proxy.scrollToWordmark()` scrolls the band into view.
struct WordmarkScrollView<Content: View, Band: View>: View {
    private let content: Content
    private let band: (CGFloat) -> Band
    /// The scroll view's width, and the height from the content's top to its bottom edge under the bars (0 until measured).
    @State private var visible = CGSize.zero

    /// A band of the app's own (Aresium's, with its special mode); it gets the full width.
    init(@ViewBuilder content: () -> Content, @ViewBuilder band: @escaping (CGFloat) -> Band) {
        self.content = content()
        self.band = band
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    content.fixedSize(horizontal: false, vertical: true)   // only the gap grows, never the content
                    Spacer(minLength: WordmarkEnd.above)
                }
                .frame(minHeight: visible.height, alignment: .top)
                band(visible.width)
                    .padding(.bottom, WordmarkEnd.below)
                    .opacity(visible == .zero ? 0 : 1)      // never seen in the first frame, before the measure
                    .id(WordmarkEnd.id)
            }
        }
        .onScrollGeometryChange(for: CGSize.self) { geometry in
            // The container is the part between the bars; the content runs on under the bottom bars to the edge.
            CGSize(width: geometry.containerSize.width, height: geometry.containerSize.height + geometry.contentInsets.bottom)
        } action: { _, size in
            visible = size
        }
    }
}

extension WordmarkScrollView where Band == WordmarkBand {
    /// The usual band: the app's name, white fading into the wall.
    init(word: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) { width in WordmarkBand(word: word, width: width) }
    }
}

/// The band's place at the end of a `WordmarkScrollView`.
enum WordmarkEnd {
    static let above: CGFloat = 44          // the least gap between the content and the band
    static let below: CGFloat = 10          // between the band and the bottom bars, scrolled to the end
    fileprivate static let id = "wordmark-end"
}

extension ScrollViewProxy {
    /// Scrolls a `WordmarkScrollView` to its end, the band at the bottom (for the screenshots' launch arguments).
    func scrollToWordmark() { scrollTo(WordmarkEnd.id, anchor: .bottom) }
}
