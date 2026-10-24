import SwiftUI
import UIKit

/// The hub's orbital circle, ported from ares-empire/web/app/ring.jsx (the desktop's own wheel, which the approved
/// phone hub reuses): a wheel laid flat and seen from the front. The province at the front is sharp and centred; its
/// neighbours fall away to the sides, smaller, paler and blurred; the far side is out of sight. Swipe to revolve, tap a
/// neighbour to bring it round, tap the front one to open it. Short rings (fewer than six places) keep their tabs as
/// close as six would be and stop at both ends.
struct EmpireRing: View {
    struct Item: Identifiable, Equatable {
        let id: String
        let name: String
        let status: String          // CONQUERED, …, or "COMING SOON"
        let isAdd: Bool
    }

    let items: [Item]
    let marks: [String: UIImage]
    let onOpen: (Item) -> Void
    var onFront: (Item?) -> Void = { _ in }

    @State private var rotation: Double = 0          // degrees
    @State private var dragStart: Double?
    @State private var dragDistance: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let sensitivity = 0.34                   // degrees of revolve per point dragged (SENS)
    private let visible = 104.0                      // beyond this many degrees from the front, a tab is hidden

    private var count: Int { max(items.count, 1) }
    private var isShort: Bool { count < 6 }
    private var step: Double { 360 / Double(max(count, 6)) }
    private func clamp(_ r: Double) -> Double { isShort ? min(0, max(-Double(count - 1) * step, r)) : r }
    private func norm180(_ d: Double) -> Double { ((d + 180).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) - 180 }

    private var frontIndex: Int {
        (0..<items.count).min { abs(norm180(Double($0) * step + rotation)) < abs(norm180(Double($1) * step + rotation)) } ?? 0
    }

    var body: some View {
        GeometryReader { geometry in
            let spread = min(geometry.size.width * 0.42, 560)                  // SPREAD_X
            let rise = max(28, min(geometry.size.height * 0.18, 52))           // RISE_Y
            ZStack {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let phi = norm180(Double(index) * step + rotation)
                    let r = phi * .pi / 180
                    let off = min(abs(phi) / visible, 1)
                    let hidden = abs(phi) > visible
                    RingTab(item: item, mark: marks[item.id], isFront: index == frontIndex)
                        .scaleEffect(1 - 0.42 * off)
                        .blur(radius: off * 3.2)
                        .opacity(hidden ? 0 : 1 - 0.84 * off)
                        .offset(x: sin(r) * spread, y: -(1 - cos(r)) * rise)
                        .zIndex((cos(r) + 1) * 50)
                        .allowsHitTesting(!hidden)
                        .onTapGesture { tap(index) }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(item.isAdd ? item.name : "\(item.name), \(item.status)")
                        .accessibilityAddTraits(index == frontIndex ? [.isButton, .isSelected] : .isButton)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .position(x: geometry.size.width / 2, y: geometry.size.height * 0.6)   // --front-y: 60%
            .contentShape(Rectangle())
            .gesture(drag)
        }
        .onAppear { report() }
        .onChange(of: frontIndex) { _, _ in report() }
        .accessibilityAdjustableAction { direction in
            stepBy(direction == .increment ? -1 : 1)
        }
    }

    /// A sideways pan only, so a vertical swipe that starts on the ring still scrolls the page.
    private var drag: HorizontalPan {
        HorizontalPan(
            onChanged: { dx in
                if dragStart == nil { dragStart = rotation }
                dragDistance = max(dragDistance, abs(dx))
                rotation = clamp((dragStart ?? rotation) + dx * sensitivity)
            },
            onEnded: {
                dragStart = nil
                settle(clamp((rotation / step).rounded() * step))
                DispatchQueue.main.async { dragDistance = 0 }
            })
    }

    private func tap(_ index: Int) {
        guard dragDistance <= 6 else { return }           // it was a revolve, not a tap
        if index != frontIndex {
            settle(clamp(rotation + norm180(-Double(index) * step - rotation)))
        } else {
            onOpen(items[index])
        }
    }

    private func stepBy(_ n: Int) {
        settle(clamp(((rotation / step).rounded() + Double(n)) * step))
    }

    private func settle(_ target: Double) {
        if reduceMotion { rotation = target }
        else { withAnimation(.timingCurve(0.22, 0.7, 0.2, 1, duration: 0.5)) { rotation = target } }
    }

    private func report() {
        let item = items.indices.contains(frontIndex) ? items[frontIndex] : nil
        onFront(item?.isAdd == true ? nil : item)
    }
}

/// UIKit's pan, allowed to begin only when the finger moves more sideways than up or down (CSS `touch-action: pan-y`).
struct HorizontalPan: UIGestureRecognizerRepresentable {
    var onChanged: (CGFloat) -> Void
    var onEnded: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .changed: onChanged(recognizer.translation(in: recognizer.view).x)
        case .ended, .cancelled, .failed: onEnded()
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}

/// One province tab (.ring-tab): neutral glass, mark on the left, the GOLD NAME over the status word.
private struct RingTab: View {
    let item: EmpireRing.Item
    let mark: UIImage?
    let isFront: Bool

    var body: some View {
        HStack(spacing: 13) {
            if item.isAdd {
                Text("+").font(AppFont.text(26, weight: .light)).foregroundStyle(Color(hex: 0xD6D6D0))
                    .frame(width: 46, height: 46)
                    .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.18), style: .init(lineWidth: 1, dash: [4, 3])))
                    .frame(width: 50, height: 50)
                Text(item.name).font(AppFont.text(13)).tracking(0.5).foregroundStyle(Color(hex: 0xD0D1CC))
            } else {
                ProvinceMarkView(name: item.name, image: mark, size: 50)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name.uppercased()).font(AppFont.text(15, weight: .bold)).tracking(1.5)
                        .lineLimit(1).goldFill(EmpireStyle.goldName)
                        .shadow(color: .black.opacity(0.55), radius: 1, y: 1)
                    Text(item.status).font(AppFont.text(9.5, weight: .semibold)).tracking(2.1)
                        .foregroundStyle(EmpireStyle.statusColor(item.status))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(width: 236, height: 82)
        .background(tabBackground)
        .overlay(tabEdge)
        .shadow(color: .black.opacity(0.9), radius: isFront ? 30 : 22, y: isFront ? 18 : 14)
    }

    @ViewBuilder private var tabBackground: some View {
        let shape = RoundedRectangle(cornerRadius: EmpireStyle.cardRadius, style: .continuous)
        if item.isAdd {
            shape.fill(.white.opacity(0.015))
        } else {
            ZStack {
                shape.fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                shape.fill(Color(hex: isFront ? 0x1A1B21 : 0x101015, opacity: 0.64))
                shape.fill(RadialGradient(colors: [.white.opacity(0.07), .clear], center: .topLeading, startRadius: 0, endRadius: 140))
            }
        }
    }

    @ViewBuilder private var tabEdge: some View {
        let shape = RoundedRectangle(cornerRadius: EmpireStyle.cardRadius, style: .continuous)
        if item.isAdd {
            shape.strokeBorder(.white.opacity(isFront ? 0.34 : 0.18), style: .init(lineWidth: 1, dash: [5, 4]))
        } else {
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(isFront ? 0.26 : 0.22), .white.opacity(0.04),
                                                       .white.opacity(0.03), .white.opacity(isFront ? 0.12 : 0.10)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
    }
}
