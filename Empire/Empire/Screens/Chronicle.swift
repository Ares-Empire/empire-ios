import SwiftUI
import UIKit

/// The chronicle, as the approved phone hub shows it: the desktop's log (ares-empire web/app/panels.jsx, GoldDust)
/// turned vertical. A bright golden line with dust rising off it and a glint gliding along it; each entry's bust sits
/// on the line inside a glowing golden ring; date · PROVINCE, then the text. Newest first. On the light wall the line
/// is antique gold drawn plainly (a glow that adds light vanishes on ivory), the dust amber, the coins parchment.
struct ChronicleList: View {
    let title: String
    let entries: [ChronicleEntry]
    let marks: [String: UIImage]       // by province slug; "empire" → the crest

    // Smaller than the website's phone layout (Patrik, 2026-10-24: the chronicle took too much room).
    private let lineX: CGFloat = 27     // the busts' centre on the line (LINE_Y on the desktop, transposed)
    private let coin: CGFloat = 38      // the website's 50
    private let column: CGFloat = 60    // the website's 78

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(AppFont.text(13, weight: .medium)).foregroundStyle(EmpireStyle.heading(dark: 0xC2C4BF))
            if entries.isEmpty {
                Text("No news yet.").font(AppFont.text(12)).foregroundStyle(EmpireStyle.ink2)
            } else {
                ZStack(alignment: .topLeading) {
                    GoldDustLine(lineX: lineX).frame(width: column).allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(Array(newestFirst.enumerated()), id: \.offset) { _, entry in
                            row(entry)
                        }
                    }
                }
            }
        }
    }

    private var newestFirst: [ChronicleEntry] { entries.sorted { $0.at > $1.at } }

    private func row(_ entry: ChronicleEntry) -> some View {
        HStack(alignment: .top, spacing: 0) {
            GoldCoin(image: image(for: entry))
                .frame(width: coin, height: coin)
                .padding(.leading, lineX - coin / 2)                     // centred on the line
                .frame(width: column, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                // mobile.css: the phone's meta line is quieter than the desktop's (grey project, no gold)
                HStack(spacing: 6) {
                    Text(entry.at).font(AppFont.number(8.5, weight: .regular)).foregroundStyle(EmpireStyle.quiet(dark: 0x858A8A))
                    Text(verbatim: "·").font(AppFont.text(10)).foregroundStyle(EmpireStyle.ink3)
                    Text((entry.project ?? "empire").uppercased()).font(AppFont.number(8.5, weight: .medium)).tracking(0.3)
                        .foregroundStyle(EmpireStyle.body(dark: 0xA7ABA7))
                }
                .frame(minHeight: 18)
                Text(entry.text).font(AppFont.text(11.5)).lineSpacing(3.5).foregroundStyle(EmpireStyle.body(dark: 0xAAAEAA))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func image(for entry: ChronicleEntry) -> UIImage? {
        let slug = entry.project ?? "empire"
        return slug == "empire" ? UIImage(named: "Crest") : (marks[slug] ?? UIImage(named: "Crest"))
    }
}

/// The marker (.log-bust): the bust in a glowing golden coin (light: a parchment coin in an antique gold ring).
private struct GoldCoin: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(light: Color(hex: 0xFFF8E8), dark: Color(hex: 0xFFE4A0, opacity: 0.22)),
                                                  Color(light: Color(hex: 0xE8DCC0), dark: Color(hex: 0x080705, opacity: 0.55))],
                                         center: .init(x: 0.5, y: 0.38), startRadius: 0, endRadius: 21))
            if let image {
                Image(uiImage: image).resizable().scaledToFit().padding(3)
                    .shadow(color: EmpireStyle.shadow(dark: 0.65), radius: 2, y: 2)
            }
            Circle().strokeBorder(Color(light: Color(hex: 0xB08435, opacity: 0.9), dark: Color(hex: 0xFFDE96, opacity: 0.75)),
                                  lineWidth: 1.5)
        }
        .clipShape(Circle())
        .shadow(color: Color(light: Color(hex: 0xC8963A, opacity: 0.35), dark: Color(hex: 0xFFCE70, opacity: 0.6)), radius: 6)
        .shadow(color: Color(light: Color(hex: 0x9A6B1F, opacity: 0.2), dark: Color(hex: 0xFFE8AA, opacity: 0.5)), radius: 2)
    }
}

/// The golden line with its glow, glint and rising dust (GoldDust in panels.jsx, vertical).
/// Reduce Motion: the line and a few still motes, no animation.
struct GoldDustLine: View {
    let lineX: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var dust = DustField()

    var body: some View {
        let light = scheme == .light
        if reduceMotion {
            Canvas { context, size in draw(in: &context, size: size, time: 0, animate: false, light: light) }
        } else {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    draw(in: &context, size: size, time: timeline.date.timeIntervalSinceReferenceDate, animate: true,
                         light: light)
                }
            }
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval, animate: Bool, light: Bool) {
        let length = size.height
        let line = Path { p in p.move(to: CGPoint(x: lineX, y: 0)); p.addLine(to: CGPoint(x: lineX, y: length)) }
        let gradient = light ? Gradient(stops: [
            .init(color: Color(hex: 0xA87A2A, opacity: 0), location: 0), .init(color: Color(hex: 0xA87A2A, opacity: 0.9), location: 0.04),
            .init(color: Color(hex: 0xC99B47), location: 0.5), .init(color: Color(hex: 0xA87A2A, opacity: 0.9), location: 0.96),
            .init(color: Color(hex: 0xA87A2A, opacity: 0), location: 1)
        ]) : Gradient(stops: [
            .init(color: Color(hex: 0xFFCE6E, opacity: 0), location: 0), .init(color: Color(hex: 0xFFD680, opacity: 0.9), location: 0.04),
            .init(color: Color(hex: 0xFFF4CE), location: 0.5), .init(color: Color(hex: 0xFFD680, opacity: 0.9), location: 0.96),
            .init(color: Color(hex: 0xFFCE6E, opacity: 0), location: 1)])
        let shading = GraphicsContext.Shading.linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: length))
        context.blendMode = light ? .normal : .plusLighter
        for (alpha, width) in light ? [(0.10, 10.0), (0.28, 3.4), (1.0, 1.3)]       // a soft halo → the gold core
                                    : [(0.22, 10.0), (0.55, 3.4), (1.0, 1.3)] {     // layered glow → bright core
            var layer = context
            layer.opacity = alpha
            layer.stroke(line, with: shading, style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        guard animate else {
            for i in 0..<12 {
                let y = (Double(i) + 0.5) / 12 * length
                context.fill(Path(ellipseIn: CGRect(x: lineX + 6 + Double(i % 3) * 5, y: y, width: 2.2, height: 2.2)),
                             with: .color(light ? Color(hex: 0xB0823A, opacity: 0.45) : Color(hex: 0xFFE096, opacity: 0.5)))
            }
            return
        }
        // a small glint gliding along the line, squashed so it stays within the line's body
        let glintY = ((time * 0.054).truncatingRemainder(dividingBy: 1.5) - 0.25) * length
        let glint = CGRect(x: lineX - 16 * 0.32, y: glintY - 16, width: 32 * 0.32, height: 32)
        context.fill(Path(ellipseIn: glint), with: .radialGradient(
            Gradient(colors: light ? [Color(hex: 0xFFF6DC, opacity: 0.95), Color(hex: 0xE8C77A, opacity: 0.3), .clear]
                                   : [Color(hex: 0xFFFFF6, opacity: 0.95), Color(hex: 0xFFF0C8, opacity: 0.3), .clear]),
            center: CGPoint(x: glint.midX, y: glint.midY), startRadius: 0, endRadius: 16))
        // dust: emitted along the line, drifting outward (rightward, the desktop's "up") and fading
        dust.step(length: length, time: time)
        for p in dust.particles {
            let a = p.life * p.life
            let r = max(0.2, p.size * a)
            let color = light
                ? Color(.sRGB, red: (176 - p.warm * 20) / 255, green: (126 - p.warm * 22) / 255, blue: (48 + p.warm * 20) / 255,
                        opacity: a * 0.8)                                       // amber dust on ivory
                : Color(.sRGB, red: 1, green: (212 - p.warm * 36) / 255, blue: (120 + p.warm * 70) / 255, opacity: a * 0.95)
            context.fill(Path(ellipseIn: CGRect(x: lineX + p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
        }
    }
}

/// The dust particles, advanced once per frame (60 fps assumed, as the desktop's requestAnimationFrame loop).
/// Deliberately not observable: it is advanced while the Canvas draws, and observing it would redraw in a loop.
final class DustField {
    struct Particle { var x, y, vx, vy, life, size, warm: Double }
    private(set) var particles: [Particle] = []
    private var lastTime: TimeInterval = 0

    func step(length: Double, time: TimeInterval) {
        let frames = lastTime == 0 ? 1 : min(4, Int(((time - lastTime) * 60).rounded()))
        lastTime = time
        guard frames > 0 else { return }
        for _ in 0..<frames {
            let emit = max(1, Int((length / 320).rounded()))
            for _ in 0..<emit {
                particles.append(Particle(x: Double.random(in: -1.4...1.4), y: Double.random(in: 0...length),
                                          vx: -(0.2 + Double.random(in: 0...0.8)), vy: Double.random(in: -0.15...0.15),
                                          life: 1, size: 0.6 + Double.random(in: 0...1.9), warm: Double.random(in: 0...1)))
            }
            for i in particles.indices.reversed() {
                particles[i].x -= particles[i].vx      // drift away from the line (to the right)
                particles[i].y += particles[i].vy
                particles[i].vx -= 0.0016
                particles[i].vy *= 0.992
                particles[i].life -= 0.011
                if particles[i].life <= 0 { particles.remove(at: i) }
            }
        }
    }
}
