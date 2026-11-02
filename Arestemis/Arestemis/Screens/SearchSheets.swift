import SwiftUI

/// "Describe it": a sentence in, the fields of a search of this kind filled in (`POST /search/parse`). Nothing is saved
/// here; the form shows what was filled and the user saves it. Closes by itself when everything was clear, else lists
/// what was not.
struct DescribeSheet: View {
    let store: ArestemisStore
    let kind: SearchKind
    @Binding var text: String
    let fill: (HuntParseResult) -> Void
    @State private var unclear: [String] = []
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var placeholder: String {
        switch kind {
        case .flat: String(localized: "e.g. WG or flat in Munich for two, up to €1,400 warm, from December, furnished")
        // A watch's form has no "Describe it": its description is the user's own words already.
        case .item, .watch: String(localized: "e.g. a Herman Miller Aeron up to €450, pickup near Garching or shipped")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextArea(placeholder: placeholder, text: $text, minHeight: 130, inWell: false)
                        .focused($focused)
                        .glassCard()
                    Caption(text: store.parseError ?? String(localized: "The fields are filled in automatically. Check them, then save."))
                        .padding(.horizontal, 4)
                    if !unclear.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            CapsLabel(text: String(localized: "Filled in, except"))
                            ForEach(unclear, id: \.self) { note in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Image(systemName: "questionmark.circle").font(.system(size: 12, weight: .medium))
                                    Text(note).fixedSize(horizontal: false, vertical: true)
                                }
                                .font(AppFont.text(13)).foregroundStyle(Ink.secondary)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()
                    }
                    Button {
                        if unclear.isEmpty { read() } else { dismiss() }
                    } label: {
                        HStack(spacing: 8) {
                            if store.isParsing { ProgressView().controlSize(.small).tint(Look.onAccent) }
                            Text(store.isParsing ? "Reading…" : unclear.isEmpty ? "Fill in" : "Done")
                        }
                    }
                    .buttonStyle(.accent)
                    .disabled(store.isParsing || (unclear.isEmpty && isEmpty))
                    .padding(.top, 6)
                }
                .padding(.horizontal, Look.side).padding(.top, 8).padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .provinceWall()
            .navigationTitle("Describe it")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(Ink.primary) }
            }
        }
        .onAppear { if text.isEmpty { focused = true } }
        .onChange(of: text) { _, _ in unclear = [] }
    }

    private func read() {
        endTyping()
        Task {
            guard let parsed = await store.parse(text: text, kind: kind.huntKind) else { return }
            fill(parsed)
            let left = switch parsed {
            case .flat(let flat): flat.unclear
            case .item(let item): item.unclear
            }
            if left.isEmpty {
                dismiss()
            } else {
                withAnimation(.easeOut(duration: 0.2)) { unclear = left }
            }
        }
    }
}

/// Finding a place as you type; each suggestion shows its region and the portals that cover it.
struct PlaceSearchSheet: View {
    let store: ArestemisStore
    let chosen: [Place]
    var initialQuery = ""
    let pick: (Place) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private var search: PlaceSearch { store.places }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Look.rowGap) {
                    SearchBox(text: $text, prompt: String(localized: "Town or city"), busy: search.isSearching,
                              capitalization: .words, submit: .done, focused: $focused)

                    results
                }
                .padding(.horizontal, Look.side).padding(.top, 8).padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .provinceWall()
            .navigationTitle("Add place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(Ink.primary) }
            }
        }
        .onChange(of: text) { _, new in search.update(new) }
        .onAppear {
            search.reset()
            text = initialQuery
            if initialQuery.isEmpty { focused = true } else { search.update(initialQuery) }
        }
    }

    @ViewBuilder private var results: some View {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.count < 2 {
            Caption(text: String(localized: "Type at least two letters. Places in Germany that the portals can search."))
                .padding(.horizontal, 4)
        } else if let error = search.error {
            CalmMessage(text: error)
        } else if search.results.isEmpty {
            if !search.isSearching { CalmMessage(text: String(localized: "No place found.")) }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(search.results.enumerated()), id: \.element.id) { index, place in
                    if index > 0 { Hairline().padding(.leading, 16) }
                    let isChosen = chosen.contains { $0.id == place.id }
                    Button {
                        pick(place)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline, spacing: 7) {
                                    Text(place.name).font(AppFont.text(15, weight: .semibold)).foregroundStyle(Ink.primary)
                                    if let region = place.region {
                                        Text(region).font(AppFont.text(13)).foregroundStyle(Ink.secondary)
                                    }
                                }
                                Text(place.sources.map(store.siteNames.name).joined(separator: " · "))
                                    .font(AppFont.text(11)).foregroundStyle(Ink.muted)
                            }
                            Spacer(minLength: 8)
                            if isChosen {
                                Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Look.accent.color)
                            }
                        }
                        .padding(.horizontal, 16).frame(minHeight: 58)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isChosen)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(isChosen ? .isSelected : [])
                }
            }
            .glassCard()
        }
    }
}

/// A search field on its glass card: the magnifying glass, the field, a small spinner while the server is asked and,
/// where `clears`, the clear button once something is typed. Place search and the search over listings.
struct SearchBox: View {
    @Binding var text: String
    let prompt: String
    var busy = false
    var capitalization: TextInputAutocapitalization = .never
    var submit: SubmitLabel = .search
    var clears = false
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium)).foregroundStyle(Ink.muted)
                .accessibilityHidden(true)
            TextField(text: $text, prompt: Text(verbatim: prompt).foregroundStyle(Ink.muted)) { Text(verbatim: prompt) }
                .font(AppFont.text(16)).foregroundStyle(Ink.primary)
                .textInputAutocapitalization(capitalization).autocorrectionDisabled()
                .submitLabel(submit)
                .onSubmit { focused.wrappedValue = false }
                .focused(focused)
            if busy { ProgressView().controlSize(.small).tint(Ink.muted) }
            if clears && !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(Ink.muted)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, -12)
                .accessibilityLabel("Clear text")
            }
        }
        .padding(.horizontal, 14).frame(height: 48)
        .glassCard(radius: 14)
    }
}
