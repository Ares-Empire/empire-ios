// Draws Arestia's mark (a marble flame with an ember core) until it has a bust of its own:
//   swift scripts/arestia-mark.swift <folder>   →  <folder>/AppIcon-1024.png (on black) and <folder>/mark.png (clear)
// Copy them into Arestia/Arestia/Assets.xcassets (AppIcon.appiconset, Mark.imageset).
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func outer(_ s: CGFloat, _ ox: CGFloat, _ oy: CGFloat) -> CGPath {
    let p = CGMutablePath()
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s / 100, y: oy + (100 - y) * s / 100) }
    p.move(to: pt(50, 95))
    p.addCurve(to: pt(19, 66), control1: pt(32, 95), control2: pt(19, 83))
    p.addCurve(to: pt(27, 37), control1: pt(19, 54), control2: pt(22, 45))
    p.addCurve(to: pt(33, 19), control1: pt(30, 31), control2: pt(32, 25))
    p.addCurve(to: pt(41, 39), control1: pt(37, 25), control2: pt(39, 33))
    p.addCurve(to: pt(57, 3), control1: pt(45, 25), control2: pt(54, 15))
    p.addCurve(to: pt(70, 30), control1: pt(61, 13), control2: pt(66, 21))
    p.addCurve(to: pt(81, 62), control1: pt(76, 40), control2: pt(81, 50))
    p.addCurve(to: pt(50, 95), control1: pt(81, 82), control2: pt(67, 95))
    p.closeSubpath()
    return p
}
func inner(_ s: CGFloat, _ ox: CGFloat, _ oy: CGFloat) -> CGPath {
    let p = CGMutablePath()
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s / 100, y: oy + (100 - y) * s / 100) }
    p.move(to: pt(50, 89))
    p.addCurve(to: pt(36, 72), control1: pt(41, 89), control2: pt(36, 82))
    p.addCurve(to: pt(52, 43), control1: pt(36, 61), control2: pt(47, 54))
    p.addCurve(to: pt(64, 71), control1: pt(57, 53), control2: pt(64, 61))
    p.addCurve(to: pt(50, 89), control1: pt(64, 82), control2: pt(58, 89))
    p.closeSubpath()
    return p
}
func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}
func draw(size: Int, background: Bool, scale: CGFloat, to path: String) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let S = CGFloat(size)
    if background {
        ctx.setFillColor(color(0x000000)); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
        // a faint warm glow under the flame
        let glow = CGGradient(colorsSpace: cs, colors: [color(0xD2602A, 0.20), color(0xD2602A, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: S/2, y: S*0.40), startRadius: 0, endCenter: CGPoint(x: S/2, y: S*0.40), endRadius: S*0.42, options: [])
    }
    let s = S * scale, ox = (S - s) / 2, oy = (S - s) / 2 + (background ? S * 0.02 : 0)
    let o = outer(s, ox, oy)
    // marble: light at the top-left, grey at the edges and the foot
    ctx.saveGState()
    ctx.addPath(o); ctx.clip()
    let marble = CGGradient(colorsSpace: cs, colors: [color(0xFBFAF7), color(0xE4E1DB), color(0xA9A49C)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(marble, start: CGPoint(x: ox + s*0.35, y: oy + s*0.95), end: CGPoint(x: ox + s*0.7, y: oy + s*0.05), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // soft shading on the right edge
    let shade = CGGradient(colorsSpace: cs, colors: [color(0x6E6A64, 0), color(0x6E6A64, 0.35)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(shade, start: CGPoint(x: ox + s*0.45, y: oy + s*0.5), end: CGPoint(x: ox + s*0.82, y: oy + s*0.5), options: [])
    ctx.restoreGState()
    // the ember core
    ctx.saveGState()
    ctx.addPath(inner(s, ox, oy)); ctx.clip()
    let ember = CGGradient(colorsSpace: cs, colors: [color(0xFFB27F), color(0xF0783A), color(0xB8481B)] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(ember, start: CGPoint(x: ox + s*0.5, y: oy + s*0.54), end: CGPoint(x: ox + s*0.5, y: oy + s*0.10), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
    // a hairline edge so it reads on the light wall
    ctx.addPath(o); ctx.setStrokeColor(color(0x5F5B55, background ? 0.0 : 0.35)); ctx.setLineWidth(max(1, S/256)); ctx.strokePath()
    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}
let out = CommandLine.arguments[1]
draw(size: 1024, background: true, scale: 0.58, to: out + "/AppIcon-1024.png")
draw(size: 384, background: false, scale: 0.94, to: out + "/mark.png")
print("ok")
