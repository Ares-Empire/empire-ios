import SwiftUI

/// The search as a form in glass cards, in the order one thinks of it: what, where, size, rent, move-in, portals,
/// extras; then save. Every field is optional on its own (empty = any) except a place and a portal. "Describe it" (a
/// line at the top) opens a sheet where a sentence fills the fields in. Without a hunt the same form creates one (paused).
struct SearchScreen: View {
    let store: ArestemisStore
    @Bindable var navigation: AppNavigation
    /// Screenshots: a section to scroll to ("size", "rent", "movein", "bottom").
    var scrollTarget: String? = nil

    @State private var draft = SearchDraft()
    @State private var baseline: Search?
    @State private var description = ""
    @State private var district = ""
    @State private var confirmDelete = false
    @State private var savedNote = false

    private var isDirty: Bool { draft.search() != (baseline ?? SearchDraft().search()) }
    private var hasHunt: Bool { store.hunt != nil }

    var body: some View {
        NavigationStack {
          VStack(spacing: 0) {
            AppHeader(title: String(localized: "Search"))
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        describeLine
                        section(String(localized: "What")) { what }
                        section(String(localized: "Where")) { places }
                        section(String(localized: "Size")) { size }.id("size")
                        section(String(localized: "Rent")) { rent }.id("rent")
                        section(String(localized: "Move-in")) { moveIn }.id("movein")
                        section(String(localized: "Portals")) { portals }
                        section(String(localized: "Extras")) { extra }
                        save.padding(.top, Look.sectionGap)
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, Look.side).padding(.top, 4).padding(.bottom, 30)
                    .animation(.easeOut(duration: 0.2), value: draft.type)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .edgeFade(top: 14)
                .onAppear {
                    if let scrollTarget { DispatchQueue.main.async { reader.scrollTo(scrollTarget, anchor: .top) } }
                }
            }
          }
            .provinceWall()
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { endTyping() }
                }
            }
            .sheet(isPresented: $navigation.showsPlaceSearch) {
                PlaceSearchSheet(store: store, chosen: draft.places, initialQuery: navigation.placeQuery) { place in
                    draft.add(place)
                }
                .presentationDetents([.large])
                .presentationBackground(Ink.background)
            }
            .sheet(isPresented: $navigation.showsDescribe) {
                DescribeSheet(store: store, text: $description) { parsed in
                    withAnimation(.easeOut(duration: 0.25)) { draft.apply(parsed) }
                }
                .presentationDetents([.large])
                .presentationBackground(Ink.background)
            }
            .confirmationDialog("Delete the search?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete search", role: .destructive) {
                    Task { if await store.deleteSearch() { sync(force: true) } }
                }
            } message: {
                Text("The hunt stops and its listings are deleted.")
            }
        }
        .onAppear { sync(force: false) }
        .onChange(of: store.hunt?.search) { _, _ in sync(force: false) }
        .onChange(of: store.hunt?.id) { _, _ in sync(force: false) }
    }

    /// Takes the saved search into the form, unless the form holds unsaved changes (`force` overrides).
    private func sync(force: Bool) {
        guard force || !isDirty else { return }
        baseline = store.hunt?.search
        draft = baseline.map { SearchDraft($0) } ?? SearchDraft()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Look.headingGap) {
            SectionHeading(text: title).padding(.leading, 4)
            content()
        }
        .padding(.top, Look.sectionGap)
    }

    // MARK: describe it (a line; the sheet does the work)

    private var describeLine: some View {
        Button {
            endTyping()
            navigation.showsDescribe = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Look.accent.color)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Describe it").font(AppFont.text(15, weight: .semibold)).foregroundStyle(Ink.primary)
                    Text("Say what you look for; the fields fill in.").font(AppFont.text(12)).foregroundStyle(Ink.muted)
                        .lineLimit(1).minimumScaleFactor(0.9)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.muted)
            }
            .padding(.horizontal, 16).frame(minHeight: 60)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    // MARK: what

    private var what: some View {
        FormCard {
            Picker("Type", selection: $draft.type) {
                Text("Flat or WG").tag(SearchDraft.OfferType.any)
                Text("Flat").tag(SearchDraft.OfferType.flat)
                Text("WG").tag(SearchDraft.OfferType.wg)
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 12)
            Hairline()
            CountStepper(label: String(localized: "Moving in"), value: $draft.people, range: SearchDraft.people) { count in
                String(localized: "\(count) people")
            }
            if draft.asksWG {
                Hairline()
                OptionalStepper(label: String(localized: "Max flatmates"), value: flatmates, range: 0...8)
            }
        }
    }

    private var flatmates: Binding<Double?> {
        Binding(get: { draft.flatmatesMax.map(Double.init) }, set: { draft.flatmatesMax = $0.map { Int($0) } })
    }

    // MARK: where

    private var places: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(draft.places) { place in
                    Chip(text: place.name) { draft.places.removeAll { $0.id == place.id } }
                }
                Button { navigation.showsPlaceSearch = true } label: {
                    Chip(text: draft.places.isEmpty ? String(localized: "Choose a city") : String(localized: "Add city"), symbol: "plus")
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 14)
            Hairline()
            VStack(alignment: .leading, spacing: 10) {
                CapsLabel(text: String(localized: "Areas"))
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(draft.districts, id: \.self) { name in
                        Chip(text: name) { draft.districts.removeAll { $0 == name } }
                    }
                    HStack(spacing: 6) {
                        TextField("", text: $district, prompt: Text("Add area").foregroundStyle(Ink.muted))
                            .font(AppFont.text(14)).foregroundStyle(Ink.primary)
                            .submitLabel(.done)
                            .onSubmit(addDistrict)
                            .frame(width: 104)
                        if !district.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button(action: addDistrict) {
                                Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Look.accent.color).frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add area")
                        }
                    }
                    .padding(.horizontal, 13).frame(minHeight: 34)
                    .overlay(Capsule().strokeBorder(Ink.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                Caption(text: String(localized: "Optional, like Schwabing. None means the whole city."))
            }
            .padding(.vertical, 14)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func addDistrict() {
        if draft.addDistrict(district) { district = "" }
    }

    // MARK: size

    private var size: some View {
        VStack(alignment: .leading, spacing: 8) {
            FormCard {
                if draft.asksFlat {
                    RangeRow(label: String(localized: "Flat"), range: $draft.flatSize, suffix: "m²", unitName: String(localized: "square metres"))
                }
                if draft.asksFlat && draft.asksWG { Hairline() }
                if draft.asksWG {
                    RangeRow(label: String(localized: "WG room"), range: $draft.roomSize, suffix: "m²", unitName: String(localized: "square metres"))
                }
                if draft.asksFlat {
                    Hairline()
                    OptionalStepper(label: String(localized: "Min rooms"), value: $draft.roomsMin, range: 1...6, step: 0.5)
                }
            }
            Caption(text: draft.asksFlat && draft.asksWG
                    ? String(localized: "In m². A flat by its whole size, a WG by your room.")
                    : String(localized: "In m²."))
                .padding(.leading, 4)
        }
    }

    // MARK: rent

    private var rent: some View {
        VStack(alignment: .leading, spacing: 8) {
            FormCard {
                RangeRow(label: String(localized: "Cold"), range: $draft.coldRent, prefix: euro.prefix, suffix: euro.suffix, unitName: String(localized: "euros"))
                Hairline()
                RangeRow(label: String(localized: "Warm"), range: $draft.warmRent, prefix: euro.prefix, suffix: euro.suffix, unitName: String(localized: "euros"))
            }
            Caption(text: String(localized: "Per month, as listed. Warm includes the utilities.")).padding(.leading, 4)
        }
    }

    /// "€" before the amount in English, after it in German ("€400", "400 €").
    private var euro: (prefix: String?, suffix: String?) { AppLanguage.current == .german ? (nil, "€") : ("€", nil) }

    // MARK: move-in

    private var moveIn: some View {
        FormCard {
            dateRow(String(localized: "From"), date: $draft.moveInFrom)
            Hairline()
            dateRow(String(localized: "Until"), date: $draft.moveInUntil)
            Hairline()
            VStack(alignment: .leading, spacing: 10) {
                CapsLabel(text: String(localized: "Temporary offers"))
                Picker("Temporary offers", selection: $draft.sublet) {
                    Text("No").tag(Sublet.exclude)
                    Text("Also").tag(Sublet.include)
                    Text("Only").tag(Sublet.only)
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 12)
        }
    }

    /// A move-in bound: a toggle turns it on; then a compact date picker.
    private func dateRow(_ label: String, date: Binding<Date?>) -> some View {
        let on = Binding(get: { date.wrappedValue != nil }, set: { isOn in
            withAnimation(.easeOut(duration: 0.2)) {
                date.wrappedValue = isOn ? (draft.moveInFrom ?? Calendar.app.startOfDay(for: .now)) : nil
            }
        })
        return HStack(spacing: 10) {
            Text(label).font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
            Spacer(minLength: 6)
            if let value = date.wrappedValue {
                DatePicker(label, selection: Binding(get: { value }, set: { date.wrappedValue = $0 }),
                           displayedComponents: .date)
                    .datePickerStyle(.compact).labelsHidden()
                    .environment(\.locale, AppLanguage.current.locale)      // "1 Dec 2026" / "1. Dez. 2026", like the rest of the app
                    .transition(.opacity)
            } else {
                Text("Any").font(AppFont.text(15)).foregroundStyle(Ink.muted)
            }
            Toggle(label, isOn: on).labelsHidden().tint(Look.accent.color)
        }
        .frame(minHeight: 50)
    }

    // MARK: portals

    private var portals: some View {
        FormCard {
            ForEach(Array(Source.allCases.enumerated()), id: \.element) { index, source in
                if index > 0 { Hairline() }
                let status = store.overview?.sources.first { $0.source == source }
                Toggle(isOn: Binding(get: { draft.sources.contains(source) }, set: { on in
                    if on { draft.sources.insert(source) } else { draft.sources.remove(source) }
                })) {
                    HStack(spacing: 10) {
                        Text(status?.name ?? source.name).font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                        if let note = status?.note {
                            Text(note).font(AppFont.text(12)).foregroundStyle(Ink.muted).lineLimit(1)
                        }
                    }
                }
                .tint(Look.accent.color)
                .frame(minHeight: 50)
            }
        }
    }

    // MARK: extras

    private var extra: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextArea(placeholder: String(localized: "e.g. furnished, balcony, not on the ground floor"), text: $draft.extra, minHeight: 84,
                     inWell: false)
                .glassCard()
            Caption(text: String(localized: "Optional. The AI checks every listing against it.")).padding(.leading, 4)
        }
    }

    // MARK: save

    private var save: some View {
        VStack(spacing: 12) {
            Button {
                endTyping()
                let creating = !hasHunt
                Task {
                    guard await store.saveSearch(draft.search()) else { return }
                    sync(force: true)
                    if creating {
                        navigation.tab = .hunt
                    } else {
                        withAnimation { savedNote = true }
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { savedNote = false }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if store.isSavingSearch { ProgressView().controlSize(.small).tint(Look.onAccent) }
                    if savedNote { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)) }
                    Text(savedNote ? "Saved" : hasHunt ? "Save search" : "Create search")
                }
            }
            .buttonStyle(.accent)
            .disabled(!draft.isValid || (hasHunt && !isDirty) || store.isSavingSearch)

            if let error = store.searchError {
                Caption(text: error).multilineTextAlignment(.center)
            } else if let hint = draft.hint {
                Caption(text: hint).multilineTextAlignment(.center)
            } else if store.hunt?.active == true && isDirty {
                Caption(text: String(localized: "Changes apply from the next scan."))
            } else if !hasHunt {
                Caption(text: String(localized: "The hunt starts paused. Start it on the Hunt tab."))
            }

            if hasHunt {
                Button("Delete search", role: .destructive) { confirmDelete = true }
                    .buttonStyle(.destructiveQuiet)
                    .disabled(store.isSavingSearch)
                    .padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// "Describe it": a sentence in, the fields filled in (`POST /search/parse`). Nothing is saved here; the form shows
/// what was filled and the user saves it. Closes by itself when everything was clear, else lists what was not.
struct DescribeSheet: View {
    let store: ArestemisStore
    @Binding var text: String
    let fill: (PartialSearch) -> Void
    @State private var unclear: [String] = []
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextArea(placeholder: String(localized: "e.g. WG or flat in Munich for two, up to €1,400 warm, from December, furnished"),
                             text: $text, minHeight: 130, inWell: false)
                        .focused($focused)
                        .glassCard()
                    Caption(text: store.parseError ?? String(localized: "The AI fills in the fields from it. Check them, then save."))
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
            guard let parsed = await store.parse(text) else { return }
            fill(parsed.search)
            if parsed.unclear.isEmpty {
                dismiss()
            } else {
                withAnimation(.easeOut(duration: 0.2)) { unclear = parsed.unclear }
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
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium)).foregroundStyle(Ink.muted)
                        TextField("", text: $text, prompt: Text("Town or city").foregroundStyle(Ink.muted))
                            .font(AppFont.text(16)).foregroundStyle(Ink.primary)
                            .textInputAutocapitalization(.words).autocorrectionDisabled()
                            .submitLabel(.search)
                            .focused($focused)
                        if search.isSearching { ProgressView().controlSize(.small).tint(Ink.muted) }
                    }
                    .padding(.horizontal, 14).frame(height: 48)
                    .glassCard(radius: 14)

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
                                Text(place.sources.map(\.name).joined(separator: " · "))
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
