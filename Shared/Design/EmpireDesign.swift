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
extension EnvironmentValues {
    /// Cheaper drawing for a share extension, which iOS ends at 220 MB on an iPhone 17 (Aresus's, 2026-11-03: killed at
    /// 240 MB in the folder picker). SwiftUI draws a `Canvas` and a `drawingGroup` into Metal layers of their own, as big
    /// as the view and kept two or three times over, so the wall's two glows cost a whole screen each and a glass card as
    /// much as its height (a long list in one card, many screens). With this set, the wall draws its glows as gradients
    /// and `GlassCard` leaves out its drawn inner shading and its blur (the wall's colour in its place). The apps keep
    /// the full look; only `AresusShare` sets it.
    @Entry var plainDrawing = false
}

struct ProvinceWall: View {
    let accent: AppAccent
    @Environment(\.colorScheme) private var scheme
    @Environment(\.plainDrawing) private var plain

    var body: some View {
        let light = scheme == .light
        ZStack {
            Ink.background
            glow(accent.deep.opacity(light ? 0.11 : 0.30), center: UnitPoint(x: 0.5, y: -0.12),
                 radius: CGSize(width: 0.72, height: 0.52))
            glow(accent.deep.opacity(light ? 0.05 : 0.16), center: UnitPoint(x: 0.9, y: 1.2),
                 radius: CGSize(width: 0.58, height: 0.5))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    @ViewBuilder private func glow(_ color: Color, center: UnitPoint, radius: CGSize) -> some View {
        if plain { PlainGlow(color: color, center: center, radius: radius) }
        else { Glow(color: color, center: center, radius: radius) }
    }

    /// The same glow as a gradient on a rectangle the size of its ellipse, drawn with the rest of the screen instead of
    /// in a layer of its own (`plainDrawing`).
    private struct PlainGlow: View {
        let color: Color
        let center: UnitPoint
        let radius: CGSize

        var body: some View {
            GeometryReader { box in
                let size = CGSize(width: box.size.width * radius.width * 2, height: box.size.height * radius.height * 2)
                Rectangle()
                    .fill(EllipticalGradient(stops: [.init(color: color, location: 0), .init(color: .clear, location: 0.6)],
                                             center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5))
                    .frame(width: size.width, height: size.height)
                    .position(x: box.size.width * center.x, y: box.size.height * center.y)
            }
            .allowsHitTesting(false)
        }
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
///
/// Nothing of the card is drawn offscreen while something on it moves (brief 87). Under `.shadow`, SwiftUI gives every
/// layer below it a shadow of its own without a path, and Core Animation draws that shadow from the layer's pixels in an
/// offscreen pass, again in every frame in which anything over it changes. With the hunt's dot pulsing (`StatusDot`),
/// one of those passes came out on Patrik's iPhone (iOS 27.0.1) as a black rectangle the size of the pulse's shadow.
/// So the card is drawn in the old order, from the bottom up, without such shadows:
/// 1. the blur, its shadow part of its style (no pass), as dark as the blur's and the fill's together outside the card
///    (`CardShadow.outside`); the blur is never inside a shadow, mask or group (brief 67);
/// 2. a still image (`drawingGroup`, drawn once) clipped to the outline: the fill over its shadow, which shows through
///    the see-through fill as the card's depth, and the highlight's shadow alone;
/// 3. the highlight, its shadow outside the card part of its style;
/// 4. the content, with no shadow (it used to have one: a 22 pt shadow under every word and chip, never meant);
/// 5. the edge, its shadow part of its style.
/// The still image stays within the card: a `List` row cuts off what its content draws past the row (Arestemis's
/// listings). Measured on the simulator (`scripts/offscreens/`, the hunt pulsing): about 45 shadow, mask and group
/// passes per frame before, none after.
struct GlassCard: ViewModifier {
    var accent: AppAccent? = nil
    var radius: CGFloat = Ink.cardRadius
    var raised = false            // a little lighter, for the one card that matters most on a screen
    var edge: Color? = nil        // one colour in place of the bright edge (Aresus's issue box: a faint red)
    /// false: the wall's colour in place of the blur, for a card that lies over something moving (Arestemis's tour card
    /// over a pulsing search, brief 139): a blur there is taken again in every frame, with a group pass.
    var blur = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.self) private var environment
    @Environment(\.plainDrawing) private var plain

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let light = scheme == .light
        let tint = accent?.deep ?? .white
        let fill = raised ? Ink.card2 : Ink.card
        let shadow = CardShadow(light: light)
        let highlight = { (color: Color) in
            RadialGradient(colors: [color.opacity(light ? 0.6 : 0.07), .clear], center: .topLeading,
                           startRadius: 0, endRadius: 220)
        }
        content
            .background {
                if plain { shape.fill(highlight(.white)) } else { shape.fill(highlight(.white).shadow(shadow.drop)) }
            }
            .background {
                if plain {
                    shape.fill(fill)
                } else {
                    ZStack {
                        shape.fill(fill)
                            .shadow(color: Ink.shadow, radius: shadow.radius, y: shadow.y)
                        // The highlight's shadow alone: the highlight in the shadow's colour, moved and blurred as one.
                        shape.fill(highlight(Ink.shadow))
                            .offset(y: shadow.y)
                            .blur(radius: shadow.radius)
                    }
                    .clipShape(shape)
                    .drawingGroup()
                }
            }
            .overlay {
                if let edge {
                    if plain { shape.strokeBorder(edge, lineWidth: 1) } else { shape.strokeBorder(edge.shadow(shadow.drop), lineWidth: 1) }
                } else {
                    glassEdge(shape, light: light, tint: tint, shadow: shadow)
                }
            }
            .background {
                if plain {
                    shape.fill(Ink.background)
                } else if blur {
                    shape.fill(Material.ultraThinMaterial.shadow(shadow.outside(under: fill, in: environment)))
                } else {
                    shape.fill(Ink.background.shadow(shadow.outside(under: fill, in: environment)))
                }
            }
    }

    /// The bright edge that fades: white from the top left, the accent's tint lower down.
    private func glassEdge(_ shape: RoundedRectangle, light: Bool, tint: Color, shadow: CardShadow) -> some View {
        let gradient = LinearGradient(stops: light ? [
            .init(color: .white.opacity(0.95), location: 0),
            .init(color: .white.opacity(0.4), location: 0.35),
            .init(color: accent == nil ? .white.opacity(0.3) : tint.opacity(0.14), location: 0.74),
            .init(color: .white.opacity(0.3), location: 1)
        ] : [
            .init(color: .white.opacity(0.22), location: 0),
            .init(color: .white.opacity(0.04), location: 0.30),
            .init(color: accent == nil ? .white.opacity(0.03) : (accent?.color ?? .white).opacity(0.10), location: 0.68),
            .init(color: .white.opacity(0.03), location: 1)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
        return Group {
            if plain { shape.strokeBorder(gradient, lineWidth: 1) } else { shape.strokeBorder(gradient.shadow(shadow.drop), lineWidth: 1) }
        }
    }
}

/// The glass card's shadow: softer and shorter on the light wall.
private struct CardShadow {
    let radius: CGFloat
    let y: CGFloat

    init(light: Bool) {
        radius = light ? 18 : 22
        y = light ? 10 : 14
    }

    /// The shadow as part of a shape's style (the highlight, the edge).
    var drop: ShadowStyle { .drop(color: Ink.shadow, radius: radius, y: y) }

    /// The shadow outside the card. The blur (opaque) and the see-through fill used to cast this same shadow onto the
    /// same place, one over the other; one shadow as dark as the two together where they are whole stands in for both.
    /// Where they fade it is off by at most a quarter of the two opacities multiplied (half a percent on the light wall,
    /// five on the dark one, which is nearly black there).
    func outside(under fill: Color, in environment: EnvironmentValues) -> ShadowStyle {
        var color = Ink.shadow.resolve(in: environment)
        let fillOpacity = fill.resolve(in: environment).opacity
        color.opacity *= 1 + fillOpacity * (1 - color.opacity)   // 1 − (1 − s)(1 − s·fill)
        return .drop(color: Color(color), radius: radius, y: y)
    }
}

extension View {
    func glassCard(accent: AppAccent? = nil, radius: CGFloat = Ink.cardRadius, raised: Bool = false,
                   edge: Color? = nil, blur: Bool = true) -> some View {
        modifier(GlassCard(accent: accent, radius: radius, raised: raised, edge: edge, blur: blur))
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
