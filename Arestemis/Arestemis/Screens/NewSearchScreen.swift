import SwiftUI

/// New search (brief 135, Patrik 2026-11-02, from the sketch's section 1; brief 142, 2026-11-03: "lots of concentrated
/// reading because all text is in the same colour, small symbols and the screen is not really guiding"): pushed on the
/// Hunts tab by New search, in the app's own pieces. The question, then one glass card per kind this build can open, in
/// `/kinds`' order (`NewSearchCard.cards`), each read in one order: the kind's mark large in a calm tile, the server's
/// name for it strong, what it does in one quiet line, and its example as a quiet chip after "e.g.". A tap on the card
/// opens the kind's form (empty, or as the user left it); a tap on the example opens it filled in (`SearchExample`). No
/// tab bar, as in the forms it leads to. Chosen from three drawn on the simulator (`build/142-variants/`): one list card
/// and a grid of four tiles with the examples under them read less at a glance in German. The tiles stay calm, ink on
/// the card's field, not the accent: four violet marks would spread the one accent over a page that has no main action.
struct NewSearchScreen: View {
    let store: ArestemisStore
    let navigation: AppNavigation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("What should Arestemis find for you?")
                    .font(AppFont.text(20, weight: .semibold)).foregroundStyle(Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 4).padding(.top, 10).padding(.bottom, 18)
                VStack(spacing: Look.rowGap) {
                    let cards = NewSearchCard.cards(offered: store.kinds)
                    ForEach(cards) { card in
                        NewSearchKindCard(card: card) { example in
                            navigation.openNewForm(card.kind, example: example)
                        }
                        .tourAnchor(card.id == cards.first?.id ? .kindCard : nil)
                    }
                }
            }
            .padding(.horizontal, Look.side).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .tourScrollsToTarget()
        .tourSpotlight()
        .provinceWall()
        .navigationTitle("New search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { await store.loadKinds() }               // the kinds as the server offers them now
    }
}

/// One kind on New search: a glass card that opens its form, the kind's mark in a tile, its name and line beside it, the
/// example laid over its lower part as a button of its own (a hidden copy keeps its room inside the card's button, as
/// `HuntListCard` keeps its Start / Pause's).
private struct NewSearchKindCard: View {
    let card: NewSearchCard
    /// nil: the empty form; an example: the form filled in.
    let open: (SearchExample?) -> Void

    private static let tile: CGFloat = 44
    private static let gap: CGFloat = 14
    private static let inset: CGFloat = 16

    var body: some View {
        Button { open(nil) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: Self.gap) {
                    KindTile(kind: card.kind, size: Self.tile)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(card.name).font(AppFont.text(17, weight: .semibold)).foregroundStyle(Ink.primary)
                        Text(card.line).font(AppFont.text(13.5)).foregroundStyle(Ink.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Ink.muted)
                }
                if !card.examples.isEmpty {
                    examples.hidden().accessibilityHidden(true)
                        .padding(.top, 12).padding(.leading, Self.tile + Self.gap)
                }
            }
            .padding(Self.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous))
        }
        .buttonStyle(CardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the form")
        .overlay(alignment: .bottomLeading) {
            if !card.examples.isEmpty {
                examples.padding(.leading, Self.inset + Self.tile + Self.gap).padding([.trailing, .bottom], Self.inset)
            }
        }
        .glassCard(raised: true)
    }

    /// "e.g." and the kind's example in a quiet capsule: tappable, but under the card's own words. At least 44 pt tall to
    /// the touch.
    private var examples: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            Text("e.g.").font(AppFont.text(12.5)).foregroundStyle(Ink.muted).frame(minHeight: 32)
                .accessibilityHidden(true)
            ForEach(card.examples) { example in
                Button { open(example) } label: {
                    Text(example.title()).font(AppFont.text(13, weight: .medium)).foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 12).frame(minHeight: 32)
                        .background(Ink.field, in: Capsule())
                        .overlay(Capsule().strokeBorder(Ink.line.opacity(1.6)))
                        .padding(.vertical, 6).contentShape(Rectangle()).padding(.vertical, -6)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the form filled in")
            }
        }
    }
}

/// A kind's mark, large, in a calm tile: ink on the card's field with a hairline.
private struct KindTile: View {
    let kind: SearchKind
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        Image(systemName: kind.symbol).font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(Ink.primary)
            .frame(width: size, height: size)
            .background(Ink.field, in: shape)
            .overlay(shape.strokeBorder(Ink.line))
            .accessibilityHidden(true)
    }
}
