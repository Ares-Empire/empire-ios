import SwiftUI

/// A listing's photos at the top of its page (brief 268): one photo per page, swiped sideways and settling one at a time,
/// with a small gap between photos while they move and rounded corners as the cards have; dots under them while there is
/// more than one. The frame comes from the listing (`PhotoFrame`): a look hunt's tall, another thing's square, both
/// showing the whole photo on a quiet mat; a flat's wide and filled. VoiceOver reads "Photos, 2 of 4" and swipes up or
/// down to the next.
struct ListingGallery: View {
    let photos: [URL]
    let frame: PhotoFrame
    @State private var page: Int? = 0

    private var current: Int { min(max(page ?? 0, 0), photos.count - 1) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous) }

    var body: some View {
        VStack(spacing: 12) {
            // The frame sets the size; the photos fill it, each a page of its own.
            Color.clear.aspectRatio(frame.aspect, contentMode: .fit)
                .overlay {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(photos.indices, id: \.self) { index in
                                // As wide as the gallery, as high as its frame (the page's own scroll view is the
                                // container on the other axis, so not relative to that).
                                ListingPhoto(url: photos[index], radius: Ink.cardRadius, whole: frame.showsWholePhoto)
                                    .containerRelativeFrame(.horizontal)
                                    .frame(maxHeight: .infinity)
                                    .clipShape(shape)
                                    .id(index)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
                    .scrollPosition(id: $page)
                    .scrollIndicators(.hidden)
                    .scrollDisabled(photos.count < 2)
                }
            if photos.count > 1 {
                PageDots(count: photos.count, current: current)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(photos.count < 2)
        .accessibilityLabel(Text("Photos"))
        .accessibilityValue(Text("\(current + 1) of \(photos.count)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: show(current + 1)
            case .decrement: show(current - 1)
            @unknown default: break
            }
        }
    }

    private func show(_ index: Int) {
        guard photos.indices.contains(index) else { return }
        withAnimation(.easeOut(duration: 0.3)) { page = index }
    }
}

/// Which photo shows: a small dot per photo, the shown one in ink, the others faint.
private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Circle().fill(index == current ? Ink.secondary : Ink.edge)
                    .frame(width: 6, height: 6)
            }
        }
        .animation(.easeOut(duration: 0.2), value: current)
        .accessibilityHidden(true)
    }
}

/// A listing's photo on a quiet tile, which is all that shows while it loads; a faint photo mark when it cannot be
/// loaded. `whole` shows the whole photo on the tile (a thing's page); otherwise it fills the frame (rows, a flat's page),
/// cut by the caller's shape.
struct ListingPhoto: View {
    let url: URL
    var radius: CGFloat = Ink.rowRadius
    var whole = false

    var body: some View {
        Rectangle().fill(Ink.card2)
            .overlay { content }
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Ink.line))
            .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        #if DEBUG
        if url.scheme == SamplePhotoScheme.name {
            // Sample mode: a bundled made-up photo, never fetched.
            if let image = SamplePhotos.image(url) { picture(Image(uiImage: image)) } else { failed }
        } else {
            remote
        }
        #else
        remote
        #endif
    }

    private var remote: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
            switch phase {
            case .success(let image): picture(image)
            case .failure: failed
            default: Color.clear
            }
        }
    }

    @ViewBuilder private func picture(_ image: Image) -> some View {
        if whole {
            image.resizable().scaledToFit()
        } else {
            image.resizable().scaledToFill()
        }
    }

    private var failed: some View {
        Image(systemName: "photo").font(.system(size: 17, weight: .regular)).foregroundStyle(Ink.muted.opacity(0.7))
    }
}

#if DEBUG
/// Sample mode's photos: made-up pictures in `Samples/` (Debug builds only), named by `sample://<file>`.
enum SamplePhotos {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(_ url: URL) -> UIImage? {
        guard url.scheme == SamplePhotoScheme.name, let name = url.host(), !name.isEmpty else { return nil }
        if let image = cache.object(forKey: name as NSString) { return image }
        guard let file = Bundle.main.url(forResource: name, withExtension: nil),
              let image = UIImage(contentsOfFile: file.path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}
#endif
