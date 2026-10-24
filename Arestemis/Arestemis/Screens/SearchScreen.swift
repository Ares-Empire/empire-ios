import SwiftUI

/// The search as a form in glass cards: describe it (optional), what, where, rent and size, move-in, anything else,
/// portals; then save. Without a hunt the same form creates one (paused).
struct SearchScreen: View {
    let store: ArestemisStore
    @Bindable var navigation: AppNavigation
    /// Screenshots: a section to scroll to ("rent", "movein", "bottom").
    var scrollTarget: String? = nil

    @State private var draft = SearchDraft()
    @State private var baseline: Search?
    @State private var description = ""
    @State private var unclear: [String] = []
    @State private var district = ""
    @State private var confirmDelete = false
    @State private var savedNote = false

    private var isDirty: Bool { draft.search() != (baseline ?? SearchDraft().search()) }
    private var hasHunt: Bool { store.hunt != nil }

    var body: some View {
        NavigationStack {
          VStack(spacing: 0) {
            AppHeader(title: "Search")
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        describe
                        section("What") { kinds }
                        section("Where") { places }
                        section("Rent and size") { rentAndSize }.id("rent")
                        section("Move-in") { moveIn }.id("movein")
                        section("Anything else") { extra }
                        section("Portals") { portals }
                        save.padding(.top, Look.sectionGap)
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, Look.side).padding(.top, 4).padding(.bottom, 30)
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

    // MARK: 1 describe it

    private var describe: some View {
        VStack(alignment: .leading, spacing: Look.headingGap) {
            SectionHeading(text: "Describe it").padding(.leading, 4)
            VStack(alignment: .leading, spacing: 12) {
                TextArea(placeholder: "e.g. 2-room flat in Schwabing up to €1,000 warm from December",
                         text: $description, minHeight: 84)
                HStack(spacing: 12) {
                    Caption(text: store.parseError ?? "Optional. The fields below are what counts.")
                    Spacer(minLength: 8)
                    Button {
                        endTyping()
                        Task {
                            if let parsed = await store.parse(description) {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    draft.apply(parsed.search)
                                    unclear = parsed.unclear
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 7) {
                            if store.isParsing { ProgressView().controlSize(.small).tint(Ink.primary) }
                            Text(store.isParsing ? "Reading…" : "Fill in")
                        }
                    }
                    .buttonStyle(ProvinceButtonStyle(kind: .glass, height: 38))
                    .fixedSize()
                    .disabled(store.isParsing || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !unclear.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(unclear, id: \.self) { note in
                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                Image(systemName: "questionmark.circle").font(.system(size: 11, weight: .medium))
                                Text(note).fixedSize(horizontal: false, vertical: true)
                            }
                            .font(AppFont.text(12)).foregroundStyle(Ink.muted)
                        }
                    }
                }
            }
            .padding(14)
            .glassCard()
        }
        .padding(.top, 8)
    }

    // MARK: 2 what

    private var kinds: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(Kind.allCases) { kind in
                Button { withAnimation(.easeOut(duration: 0.15)) { draft.toggle(kind) } } label: {
                    Chip(text: kind.title, selected: draft.kinds.contains(kind))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(draft.kinds.contains(kind) ? .isSelected : [])
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: 3 where

    private var places: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(draft.places) { place in
                    Chip(text: place.name) { draft.places.removeAll { $0.id == place.id } }
                }
                Button { navigation.showsPlaceSearch = true } label: {
                    Chip(text: "Add place", symbol: "plus")
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 14)
            Hairline()
            VStack(alignment: .leading, spacing: 10) {
                CapsLabel(text: "Districts")
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(draft.districts, id: \.self) { name in
                        Chip(text: name) { draft.districts.removeAll { $0 == name } }
                    }
                    HStack(spacing: 6) {
                        TextField("", text: $district, prompt: Text("Add district").foregroundStyle(Ink.muted))
                            .font(AppFont.text(14)).foregroundStyle(Ink.primary)
                            .submitLabel(.done)
                            .onSubmit(addDistrict)
                            .frame(width: 118)
                        if !district.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button(action: addDistrict) {
                                Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Look.accent.color).frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add district")
                        }
                    }
                    .padding(.horizontal, 13).frame(minHeight: 34)
                    .overlay(Capsule().strokeBorder(Ink.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                Caption(text: "Words within the places, like Schwabing. None means the whole place.")
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

    // MARK: 4 rent and size

    private var rentAndSize: some View {
        FormCard {
            FormRow(label: "Max warm rent") {
                NumberField(value: $draft.rentMaxWarm, prefix: "€", label: "Max warm rent in euros")
            }
            Hairline()
            VStack(alignment: .leading, spacing: 10) {
                Text("Bigger flats may cost more").font(AppFont.text(13)).foregroundStyle(Ink.secondary)
                ForEach($draft.tiers) { $tier in
                    HStack(spacing: 8) {
                        Text("from").font(AppFont.text(13)).foregroundStyle(Ink.muted)
                        NumberField(value: $tier.sqmMin, suffix: "m²", placeholder: "m²", width: 82, label: "From square metres")
                        Text("up to").font(AppFont.text(13)).foregroundStyle(Ink.muted)
                        NumberField(value: $tier.rentMaxWarm, prefix: "€", placeholder: "€", width: 96, label: "Up to euros warm")
                        Spacer(minLength: 0)
                        Button { withAnimation { draft.tiers.removeAll { $0.id == tier.id } } } label: {
                            Image(systemName: "minus.circle").font(.system(size: 17)).foregroundStyle(Ink.muted)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove tier")
                    }
                }
                Button { withAnimation { draft.tiers.append(SearchDraft.Tier()) } } label: {
                    Label("Add tier", systemImage: "plus").font(AppFont.text(13, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(Ink.secondary)
                .frame(minHeight: 30)
            }
            .padding(.vertical, 12)
            if draft.asksFlatSize {
                Hairline()
                FormRow(label: "Min size (flat)") {
                    NumberField(value: $draft.sqmMin, suffix: "m²", label: "Minimum size of the flat in square metres")
                }
            }
            if draft.asksRoomSize {
                Hairline()
                FormRow(label: "Min room size") {
                    NumberField(value: $draft.roomSqmMin, suffix: "m²", label: "Minimum size of the room in square metres")
                }
            }
            if draft.asksRooms {
                Hairline()
                OptionalStepper(label: "Min rooms", value: $draft.roomsMin, range: 1...6, step: 0.5)
            }
            if draft.asksFlatmates {
                Hairline()
                OptionalStepper(label: "Max flatmates", value: flatmates, range: 0...8)
            }
        }
    }

    private var flatmates: Binding<Double?> {
        Binding(get: { draft.flatmatesMax.map(Double.init) }, set: { draft.flatmatesMax = $0.map { Int($0) } })
    }

    // MARK: 5 move-in

    private var moveIn: some View {
        FormCard {
            dateRow("From", date: $draft.moveInFrom)
            Hairline()
            dateRow("Until", date: $draft.moveInUntil)
            Hairline()
            VStack(alignment: .leading, spacing: 10) {
                CapsLabel(text: "Sublets")
                Picker("Sublets", selection: $draft.sublet) {
                    Text("No sublets").tag(Sublet.exclude)
                    Text("Include").tag(Sublet.include)
                    Text("Only").tag(Sublet.only)
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 12)
            Hairline()
            VStack(alignment: .leading, spacing: 10) {
                CapsLabel(text: "Furnished")
                Picker("Furnished", selection: $draft.furnished) {
                    Text("Any").tag(Furnished.any)
                    Text("Yes").tag(Furnished.yes)
                    Text("No").tag(Furnished.no)
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
                    .environment(\.locale, Locale(identifier: "en_GB"))      // "1 Dec 2026", like the rest of the app
                    .transition(.opacity)
            } else {
                Text("Any").font(AppFont.text(15)).foregroundStyle(Ink.muted)
            }
            Toggle(label, isOn: on).labelsHidden().tint(Look.accent.color)
        }
        .frame(minHeight: 50)
    }

    // MARK: 6 anything else

    private var extra: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextArea(placeholder: "e.g. balcony, not on the ground floor", text: $draft.extra, minHeight: 84, inWell: false)
                .glassCard()
            Caption(text: "Checked by the AI on every listing.").padding(.leading, 4)
        }
    }

    // MARK: 7 portals

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

    // MARK: 8 save

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
                Caption(text: "Changes apply from the next scan.")
            } else if !hasHunt {
                Caption(text: "The hunt starts paused. Start it on the Hunt tab.")
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
            Caption(text: "Type at least two letters. Places in Germany that the portals can search.")
                .padding(.horizontal, 4)
        } else if let error = search.error {
            CalmMessage(text: error)
        } else if search.results.isEmpty {
            if !search.isSearching { CalmMessage(text: "No place found.") }
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
