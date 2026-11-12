import SwiftUI

/// Plain controls for brief 268; the visual design follows separately.
struct LookVoteButtons: View {
    let vote: Vote?
    let isSaving: Bool
    let choose: (Vote) -> Void

    var body: some View {
        HStack(spacing: 16) {
            button(.up, symbol: "👍", label: "Good find")
            button(.down, symbol: "👎", label: "Not it")
        }
        .disabled(isSaving)
    }

    private func button(_ choice: Vote, symbol: String, label: LocalizedStringKey) -> some View {
        Button { choose(choice) } label: {
            HStack(spacing: 4) {
                Text(verbatim: symbol)
                if vote == choice { Image(systemName: "checkmark") }
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Ink.primary)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(vote == choice ? .isSelected : [])
    }
}
