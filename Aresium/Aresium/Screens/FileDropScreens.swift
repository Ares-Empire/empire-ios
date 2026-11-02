import SwiftUI
import UniformTypeIdentifiers

// Dropping files on the main screen (brief 204): the drop target and what shows while files hover. The logic (which
// items, their copies, when the target is on) is `FileDrop`; the files then go the way a shared file goes.

extension View {
    /// The main screen as a drop target for files (brief 204): while files the import takes hover, `DropHover` over it;
    /// letting go hands their copies to `dropped`.
    func fileDrops(enabled: Bool, palette: Palette, dropped: @escaping ([URL], Int) -> Void) -> some View {
        modifier(FileDropArea(enabled: enabled, palette: palette, dropped: dropped))
    }
}

private struct FileDropArea: ViewModifier {
    let enabled: Bool
    let palette: Palette
    let dropped: ([URL], Int) -> Void
    /// What hovers that the import takes; nil while nothing does.
    @State private var hovering: FileDrop.Hover?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if let hovering, enabled { DropHover(hover: hovering, palette: palette).transition(.opacity) }
            }
            .onDrop(of: [.item], delegate: ProviderDropTarget(enabled: enabled, type: FileDrop.importType,
                                                          copy: { FileDrop.copyTaken($0, done: $1) }, hovering: $hovering,
                                                          reduceMotion: reduceMotion, dropped: dropped))
    }
}

/// While files the import takes hover over the main screen: the app's own wall in place of the screen (a veil let the
/// first screen's button and the dashboard's cards show through as grey ghosts behind the words, brief 204) and, a little
/// above the middle, the first screen's mark in its thin circle with what letting go does. Ink only, nothing new.
struct DropHover: View {
    let hover: FileDrop.Hover
    let palette: Palette

    var body: some View {
        ZStack {
            Wall(palette: palette)
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(palette.card2)
                    Circle().strokeBorder(palette.line, lineWidth: 1)
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 22, weight: .medium))
                        .foregroundStyle(palette.secondary)
                }
                .frame(width: 64, height: 64)
                Text("Let go to import").font(AppFont.text(21, weight: .bold)).foregroundStyle(palette.ink)
                    .multilineTextAlignment(.center).padding(.top, 22)
                line.font(AppFont.text(14)).foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center).lineLimit(2).truncationMode(.middle)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 60)
            .accessibilityElement(children: .combine)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// The file's name when one names itself, else how many.
    private var line: Text {
        if let name = hover.name { Text(verbatim: name) } else { Text("\(hover.count) files") }
    }
}

/// VoiceOver's drop point for the main screen's drop target, on an element that is always there (the header's title,
/// the first screen's heading): with a file picked up by VoiceOver's Drag, its Drop action says it imports. Only the
/// marked element changes when it goes on or off, never the screen around it.
struct FileDropPoint: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on {
            content.accessibilityDropPoint(.center, description: Text("Import files"))
        } else {
            content
        }
    }
}
