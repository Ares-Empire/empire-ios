import SwiftUI

/// New search (brief 135, Patrik 2026-11-02, from the sketch's section 1): pushed on the Hunts tab by New search, in the
/// app's own pieces. The question, then one glass card per kind this build can open, in `/kinds`' order
/// (`NewSearchCard.cards`): the kind's mark (as on the Hunts list) and the server's name for it, what it does in one
/// sentence, and its examples as chips. A tap on the card opens the kind's form (empty, or as the user left it); a tap on
/// an example opens it filled in (`SearchExample`). No tab bar, as in the forms it leads to.
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
                    ForEach(NewSearchCard.cards(offered: store.kinds)) { card in
                        NewSearchKindCard(card: card) { example in
                            navigation.openNewForm(card.kind, example: example)
                        }
                    }
                }
            }
            .padding(.horizontal, Look.side).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .provinceWall()
        .navigationTitle("New search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { await store.loadKinds() }               // the kinds as the server offers them now
    }
}

/// One kind on New search: a glass card that opens its form, with the examples laid over its lower part as buttons of
/// their own (a hidden copy keeps their room inside the card's button, as `HuntListCard` keeps its Start / Pause's).
private struct NewSearchKindCard: View {
    let card: NewSearchCard
    /// nil: the empty form; an example: the form filled in.
    let open: (SearchExample?) -> Void

    var body: some View {
        Button { open(nil) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    HuntTitle(kind: card.kind, title: card.name, size: 17)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Ink.muted)
                }
                Text(card.line).font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                examples.hidden().accessibilityHidden(true).padding(.top, 14)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous))
        }
        .buttonStyle(CardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the form")
        .overlay(alignment: .bottomLeading) {
            examples.padding([.horizontal, .bottom], 18)
        }
        .glassCard(raised: true)
    }

    /// The kind's examples as chips, each opening the form filled in; at least 44 pt tall to the touch.
    private var examples: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(card.examples) { example in
                Button { open(example) } label: {
                    Chip(text: example.title())
                        .padding(.vertical, 5).contentShape(Rectangle()).padding(.vertical, -5)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the form filled in")
            }
        }
    }
}
