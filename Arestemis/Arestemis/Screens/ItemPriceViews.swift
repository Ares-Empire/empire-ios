import SwiftUI

/// Asking prices on screen (brief 256): the section on a thing search's page, a listing's verdict on its row and on its
/// page. Words in `PriceRecordCard` and `PriceVerdictWords`; the server's sentences in the app's language.

/// "ASKING PRICES · LAST 30 DAYS" over one quiet glass card: the server's facts one per line (how many fitting listings,
/// what they usually ask, the cheapest of the last 7 days, the weekly trend, as the server has them), then, while two or
/// more sites have offers, one row per site with its usual range (or its count, below 8 offers). The server's note under
/// the card as fine print: asking prices of fitting listings within the search's limits, no fees, not sale prices.
/// While the record is empty one quiet line under the heading instead of the card.
struct PriceRecordSection: View {
    let card: PriceRecordCard

    var body: some View {
        VStack(alignment: .leading, spacing: Look.headingGap) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SectionHeading(text: card.title)
                Spacer(minLength: 8)
                Text(card.period).font(AppFont.text(11.5)).foregroundStyle(Ink.muted).lineLimit(1)
            }
            .padding(.horizontal, 4)
            if let empty = card.empty {
                Text(empty).font(AppFont.text(13)).foregroundStyle(Ink.muted).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(card.lines.enumerated()), id: \.offset) { _, line in
                            Text(line).font(AppFont.text(14)).foregroundStyle(Ink.primary).lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !card.sites.isEmpty {
                        Hairline().padding(.vertical, 14)
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(card.sites) { site in siteRow(site) }
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
                if let note = card.note {
                    Text(note).font(AppFont.text(11)).foregroundStyle(Ink.muted).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4).padding(.top, -2)
                }
            }
        }
        .padding(.top, Look.sectionGap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: card.spoken))
    }

    /// A site's name, then its usual range in the numbers' face and its count in muted ink; under the name when the
    /// row is too narrow (large text).
    private func siteRow(_ site: PriceRecordCard.Site) -> some View {
        let figures = HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let range = site.range {
                Text(verbatim: range).font(AppFont.number(13.5, weight: .medium)).foregroundStyle(Ink.primary)
                Text(verbatim: "·").font(AppFont.text(12.5)).foregroundStyle(Ink.muted)
            }
            Text(verbatim: site.count).font(AppFont.text(12.5)).foregroundStyle(Ink.muted)
        }
        .lineLimit(1)
        let name = Text(verbatim: site.name).font(AppFont.text(13.5, weight: .medium)).foregroundStyle(Ink.secondary)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                name.lineLimit(1)
                Spacer(minLength: 10)
                figures.fixedSize()
            }
            VStack(alignment: .leading, spacing: 2) {
                name
                figures
            }
        }
    }
}

/// A listing's verdict on its row, under the price: a small mark and the server's label in the verdict's tone, text
/// only as the row's other labels are. Cheap in the accent, expensive in neutral ink, unusually cheap in the warnings'
/// amber (it means "check", not an alarm).
struct PriceVerdictLabel: View {
    let words: PriceVerdictWords

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: words.symbol).font(.system(size: 10, weight: .bold))
            Text(words.label).font(AppFont.text(12, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(words.tone.color)
        .accessibilityElement(children: .combine)
    }
}

/// A listing's verdict on its page, under the price, title and site: the mark and the server's line ("Cheap: usually
/// €400–€450 asked within your search limits"), its label in the verdict's tone and the rest in quiet ink, the note under
/// it in small muted type.
struct PriceVerdictLine: View {
    let words: PriceVerdictWords

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: words.symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(words.tone.color)
            VStack(alignment: .leading, spacing: 6) {
                Text(line).font(AppFont.text(14)).foregroundStyle(Ink.secondary)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                if !words.note.isEmpty {
                    Text(words.note).font(AppFont.text(11.5)).foregroundStyle(Ink.muted).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var line: AttributedString {
        guard let lead = words.lead else { return AttributedString(words.line) }
        var label = AttributedString(lead)
        label.font = AppFont.text(14, weight: .semibold)
        label.foregroundColor = words.tone == .neutral ? Ink.primary : words.tone.color
        return label + AttributedString(words.rest)
    }
}

extension PriceVerdictWords.Tone {
    var color: Color {
        switch self {
        case .accent: Look.accent.color
        case .neutral: Ink.secondary
        case .caution: Look.amber
        }
    }
}
