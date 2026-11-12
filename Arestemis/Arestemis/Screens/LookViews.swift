import SwiftUI

/// A look hunt on screen (brief 268, on the server's brief 267): the judge's verdict on a finding's page, and Patrik's
/// thumbs that teach it, there and on each filtered-out listing of the hunt. Words in `Model/LookPresentation.swift`.

/// A finding's look on its page, under the price, title and site, as the page's other verdict line (`PriceVerdictLine`):
/// "Look 8/10" small and strong in the accent with the thumbs at the right of that row, where the thumb reaches them, then
/// the judge's reason in the app's language in quiet ink, always whole, and what it could tell of the coat ("Long · Men's
/// cut · Real fur") in muted ink.
struct LookLine: View {
    let verdict: LookVerdict
    let vote: Vote?
    var isSaving = false
    let choose: (Vote) -> Void

    var body: some View {
        let reason = verdict.reason().trimmingCharacters(in: .whitespacesAndNewlines)
        let facts = verdict.facts()
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Text(verbatim: verdict.scoreLabel())
                    .font(AppFont.text(15, weight: .semibold)).foregroundStyle(Look.accent.color)
                    .lineLimit(1)
                    // One element for VoiceOver: the score, the reason and the facts, then the two thumbs.
                    .accessibilityLabel(Text(verbatim: verdict.spoken()))
                Spacer(minLength: 8)
                LookVoteButtons(vote: vote, isSaving: isSaving, choose: choose)
                    .padding(.trailing, -3) // the circle's edge on the page's margin; its 44 pt target reaches past it
            }
            if !reason.isEmpty {
                Text(verbatim: reason).font(AppFont.text(14)).foregroundStyle(Ink.secondary)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            if let facts {
                Text(verbatim: facts).font(AppFont.text(12.5)).foregroundStyle(Ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 7)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Thumbs up ("Good find") and thumbs down ("Not it"): a listing as the look hunt wants it, or not. The chosen one filled
/// in the accent on a faint accent circle (as a chosen chip), the other an outline in muted ink on glass; a tap on the
/// chosen one takes the vote back (`ArestemisStore.setVote`). Each answers a tap with a light tap felt and has a 44 pt
/// target; `.compact` is the filtered-out rows' smaller pair.
struct LookVoteButtons: View {
    enum Size { case regular, compact }

    let vote: Vote?
    var isSaving = false
    var size: Size = .regular
    let choose: (Vote) -> Void
    /// Counts the taps, for the light tap felt with each.
    @State private var taps = 0

    private var diameter: CGFloat { size == .regular ? 36 : 32 }

    var body: some View {
        HStack(spacing: size == .regular ? 4 : 0) {
            button(.up)
            button(.down)
        }
        .disabled(isSaving)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }

    private func button(_ choice: Vote) -> some View {
        let chosen = vote == choice
        return Button {
            taps += 1
            choose(choice)
        } label: {
            Image(systemName: choice.symbol(filled: chosen))
                .font(.system(size: size == .regular ? 15 : 13.5, weight: .medium))
                .foregroundStyle(chosen ? Look.accent.color : Ink.muted)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(chosen ? Look.accent.color.opacity(0.14) : Look.buttonFill))
                .overlay(Circle().strokeBorder(chosen ? Look.accent.color.opacity(0.6) : Ink.edge))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(VotePress())
        .accessibilityLabel(Text(choice == .up ? "Good find" : "Not it"))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

private extension Vote {
    func symbol(filled: Bool) -> String {
        let name = self == .up ? "hand.thumbsup" : "hand.thumbsdown"
        return filled ? name + ".fill" : name
    }
}

/// Pressed, a thumb dims a little, as the app's other buttons do; a vote being sent does not grey it (it already shows
/// the new vote).
private struct VotePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
