import SwiftUI

/// The thing form's search words (brief 149, the plan's sketch: "Hermès Krawatte ×", "Ferragamo Krawatte ×"): the words
/// as chips in the accent's tint, each with its ×, and after them a field that takes the rest of the line, as Mail's
/// address field does. Return, the field's + or a comma adds the typed word as a chip, and the keyboard stays for the
/// next; leaving the field adds it too. Five at most: then the field goes (the form's quiet line says why). A word that
/// repeats a chip, or is too short, stays in the field (`ItemSearchDraft.typed`), and the form says why. A tap anywhere
/// on the card but a chip's × puts the cursor in the field. The rules are the draft's (`ItemSearchDraft`, `SearchWords`).
struct SearchWordsField: View {
    @Binding var draft: ItemSearchDraft
    var focus: FocusState<Bool>.Binding
    /// Set when Return or + found a word that cannot be added, so its line shows while the field is still in use.
    @Binding var triedAdding: Bool
    /// The field's own text, set back to the draft's typed word whenever that differs (a comma made a chip, Return
    /// added one): a binding's setter that changes what was typed does not reach the field on screen (seen with real
    /// typing: "Ferragamo tie," stayed and the next letters came as "Ferragamo tie,he"), a change made here does, as in
    /// `NameField` and `NumberField`.
    @State private var text = ""

    /// The field's least width after chips: its placeholder fits ("Noch ein Suchbegriff"), else it takes a line.
    private static let fieldWidth: CGFloat = 176

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8, lastFills: draft.takesWords ? Self.fieldWidth : nil) {
            ForEach(Array(draft.words.enumerated()), id: \.element) { index, word in
                Chip(text: word, selected: true) { draft.removeWord(at: index) }
                    .transition(.opacity)
            }
            if draft.takesWords { field }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { if draft.takesWords { focus.wrappedValue = true } }
    }

    private var field: some View {
        HStack(spacing: 6) {
            TextField("", text: $text,
                      prompt: (draft.words.isEmpty ? Text("e.g. Herman Miller Aeron") : Text("Another search word"))
                          .foregroundStyle(Ink.muted))
                .font(AppFont.text(16, weight: .medium)).foregroundStyle(Ink.primary)
                .autocorrectionDisabled()
                .focused(focus)
                .onSubmit(submit)
                .accessibilityLabel(draft.words.isEmpty ? Text("What you look for") : Text("Another search word"))
            if draft.typed == .adds {
                Button(action: add) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Look.accent.color).frame(width: 22, height: 22)
                        .padding(11).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Add search word"))
                .padding(-11)                       // a 44 pt button in the 22 pt of the field's line
            }
        }
        .frame(minHeight: 34)
        .onAppear { text = draft.typedWord }
        .onChange(of: text) { _, _ in
            takeText()
        }
        // A typed word set from outside (a kept draft, the screenshots' arguments) shows in the field; one the field
        // itself passed on is there already, and the field may be letters ahead of it.
        .onChange(of: draft.typedWord) { old, new in
            if text == old && text != new { text = new }
        }
        // Leaving the field adds what is typed as a chip, when it can be one.
        .onChange(of: focus.wrappedValue) { was, now in
            guard was, !now else { return }
            takeText()
            withAnimation(.easeOut(duration: 0.2)) { if draft.addTypedWord() { text = "" } }
        }
    }

    /// Passes what the field shows to the draft (a comma makes a chip, `ItemSearchDraft.type`) and shows what the draft
    /// keeps typed. It reads the field's text as it is now: with fast typing the changes arrive late and one after the
    /// other, so an older one would bring back letters already made a chip.
    private func takeText() {
        guard text != draft.typedWord else { return }
        triedAdding = false
        draft.type(text)
        if draft.typedWord != text { text = draft.typedWord }
    }

    /// Return: the typed word becomes a chip and the keyboard stays for the next one; on an empty field Return ends
    /// typing.
    private func submit() {
        takeText()
        guard draft.typed != .empty else { return }
        add()
        DispatchQueue.main.async { if draft.takesWords { focus.wrappedValue = true } }
    }

    /// Return or the +: what the field shows becomes a chip, or stays with its line saying why.
    private func add() {
        takeText()
        withAnimation(.easeOut(duration: 0.2)) {
            if draft.addTypedWord() { text = "" } else { triedAdding = true }
        }
    }
}
