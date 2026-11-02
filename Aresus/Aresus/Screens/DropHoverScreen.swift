import SwiftUI

/// While files hover over the Aresync tab (brief 100; letting go opens the send sheet with them, brief 94): the tab's
/// wall in place of the screen (a veil let the cards show through as grey ghosts in Aresium's, brief 204), one thin line
/// of the accent round the screen's edge, following its corners, and a little above the middle a laptop with an arrow
/// in a thin circle over what letting go does and what is held (`DropHoverWords`). Nothing moves; it fades in and out
/// (`ProviderDropTarget`). Over the tab's content only, so the tab bar stays.
struct DropHoverScreen: View {
    let hover: ProviderFiles.Hover

    var body: some View {
        ZStack {
            ProvinceWall(accent: .aresus)
            ConcentricRectangle(corners: .concentric(minimum: .fixed(28)), isUniform: true)
                .stroke(AppAccent.aresus.color.opacity(0.75), lineWidth: 1.5)
                .padding(7)
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(Ink.card2)
                    Circle().strokeBorder(Ink.line, lineWidth: 1)
                    Image(systemName: "laptopcomputer.and.arrow.down").font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Ink.secondary)
                }
                .frame(width: 64, height: 64)
                Text(DropHoverWords.title()).font(AppFont.text(19, weight: .bold)).foregroundStyle(Ink.primary)
                    .multilineTextAlignment(.center).padding(.top, 22)
                Text(verbatim: DropHoverWords.line(hover)).font(AppFont.text(14)).foregroundStyle(Ink.secondary)
                    .lineLimit(1).truncationMode(.middle).padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 60)
            .accessibilityElement(children: .combine)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
