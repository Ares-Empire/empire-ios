import SwiftUI

/// A flat hunt's search as a form in glass cards, in the order one thinks of it: what, where, size, rent, move-in,
/// portals, extras; then save. Every field is optional on its own (empty = any) except a place and a portal. "Describe
/// it" (a line at the top) opens a sheet where a sentence fills the fields in. Pushed on the Hunts tab for one hunt
/// (Edit search), or empty for a new one (New search → Flat or room), which it creates paused. Unsaved edits are kept
/// per hunt (`KeptSearchDraft`).
struct FlatSearchScreen: View {
    let store: ArestemisStore
    @Bindable var navigation: AppNavigation
    /// The hunt whose search this is; nil for a new one.
    let huntID: Int?

    @State private var draft = SearchDraft()
    @State private var baseline: Search?
    @State private var description = ""
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    private var hunt: Hunt? { huntID.flatMap { store.card($0)?.hunt } }
    private var creating: Bool { huntID == nil }
    private var isDirty: Bool { draft.search() != (baseline ?? SearchDraft().search()) }
    private var canSave: Bool { draft.isValid && (creating || isDirty) }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DescribeLine { navigation.showsDescribe = true }
                    FormSection(title: String(localized: "What")) { what }
                    FormSection(title: String(localized: "Where")) { places }
                    FormSection(title: String(localized: "Size")) { size }.id("size")
                    FormSection(title: String(localized: "Rent")) { rent }.id("rent")
                    FormSection(title: String(localized: "Move-in")) { moveIn }.id("movein")
                    FormSection(title: String(localized: "Portals")) {
                        PortalToggles(sources: Source.allCases, chosen: $draft.sources, statuses: store.overview?.sources ?? [])
                    }
                    FormSection(title: String(localized: "Extras")) {
                        ExtrasField(placeholder: String(localized: "e.g. furnished, balcony, not on the ground floor"),
                                    text: $draft.extra, caption: String(localized: "Optional. Every listing is checked against it."))
                    }
                    SearchSaveArea(creating: creating, canSave: canSave, saving: store.isSavingSearch, line: saveLine,
                                   save: saveSearch, delete: creating ? nil : { confirmDelete = true })
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, Look.side).padding(.top, 4).padding(.bottom, 30)
                .animation(.easeOut(duration: 0.2), value: draft.type)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                guard let target = navigation.formScroll else { return }
                navigation.formScroll = nil
                DispatchQueue.main.async { reader.scrollTo(target, anchor: target == "bottom" ? .bottom : .top) }
            }
        }
        .searchFormChrome(title: creating ? String(localized: "New search") : String(localized: "Edit search"),
                          showsSave: canSave, saving: store.isSavingSearch, save: saveSearch)
        .sheet(isPresented: $navigation.showsPlaceSearch) {
            PlaceSearchSheet(store: store, chosen: draft.places, initialQuery: navigation.placeQuery) { place in
                draft.add(place)
            }
            .presentationDetents([.large])
            .presentationBackground(Ink.background)
        }
        .sheet(isPresented: $navigation.showsDescribe) {
            DescribeSheet(store: store, kind: .flat, text: $description) { parsed in
                guard case .flat(let flat) = parsed else { return }
                withAnimation(.easeOut(duration: 0.25)) { draft.apply(flat.search) }
            }
            .presentationDetents([.large])
            .presentationBackground(Ink.background)
        }
        .confirmationDialog("Delete the search?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete search", role: .destructive, action: deleteSearch)
        } message: {
            Text("The hunt stops and its listings are deleted.")
        }
        .onAppear { sync() }
        .onChange(of: hunt?.search.flat) { _, _ in sync() }
        .onChange(of: draft) { _, new in store.keepFlatSearchDraft(new, baseline: baseline, huntID: huntID) }
    }

    /// The hunt's search as saved, with the edits kept for it while that search is still current.
    private func sync() {
        baseline = hunt?.search.flat
        draft = store.flatSearchDraft(huntID: huntID)
    }

    /// Under Save: the server's refusal, what is still missing, or what saving does.
    private var saveLine: String? {
        if let error = store.searchError { return error }
        if let hint = draft.hint { return hint }
        if creating { return String(localized: "The search starts paused.") }
        if hunt?.active == true && isDirty { return String(localized: "Changes apply from the next scan.") }
        return nil
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
            PlaceChips(places: draft.places, remove: { place in draft.places.removeAll { $0.id == place.id } },
                       add: { navigation.showsPlaceSearch = true })
                .padding(.vertical, 14)
            Hairline()
            VStack(alignment: .leading, spacing: 10) {
                CapsLabel(text: String(localized: "Areas"))
                WordChips(words: draft.districts, placeholder: String(localized: "Add area"),
                          remove: { name in draft.districts.removeAll { $0 == name } },
                          add: { draft.addDistrict($0) })
                Caption(text: String(localized: "Optional, like Schwabing. None means the whole city."))
            }
            .padding(.vertical, 14)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
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
                RangeRow(label: String(localized: "Cold"), range: $draft.coldRent, prefix: Euro.prefix, suffix: Euro.suffix, unitName: String(localized: "euros"))
                Hairline()
                RangeRow(label: String(localized: "Warm"), range: $draft.warmRent, prefix: Euro.prefix, suffix: Euro.suffix, unitName: String(localized: "euros"))
            }
            Caption(text: String(localized: "Per month, as listed. Warm includes the utilities.")).padding(.leading, 4)
        }
    }

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

    // MARK: save and delete

    private func saveSearch() {
        endTyping()
        Task {
            guard let saved = await store.saveHunt(id: huntID, kind: .flat, name: hunt?.name, search: .flat(draft.search()))
            else { return }
            if creating { navigation.showCreated(saved.id) } else { dismiss() }
        }
    }

    private func deleteSearch() {
        guard let huntID else { return }
        navigation.leaveDeleted()
        Task { await store.deleteHunt(id: huntID) }
    }
}
