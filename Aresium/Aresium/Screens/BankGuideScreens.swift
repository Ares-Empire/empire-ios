import SwiftUI
import UniformTypeIdentifiers

// "How do I get my file?" (brief 24): a search over the banks, then a bank's page with its steps on the website or in
// its app, which file to pick and why, what to know, how the file reaches Aresium, and Choose file. When the search finds
// no bank (brief 25), the list shows Another bank's general steps in place, under a note and "Tell us about your bank"
// (`BankRequestCard`); Another bank's own page ends with the same card. Built from Aresium's pieces: Settings' sections
// and rows, the first screen's numbered tiles (`DayTile`), `FormNote`, `FormButtonStyle`; ink only. The data and the
// search are `Model/BankGuide.swift`.

/// What the guide's Choose file does, given by whoever opens the guide; without it (the tour) there is no button.
struct GuideImport {
    /// What the file picker offers.
    let types: [UTType]
    /// The picked files (or why the picker failed); the owner imports them once the guide has closed (in phone mode the
    /// category picker follows the import while none is chosen, `ImportStore.asksForCategories`).
    let finished: (Result<[URL], Error>) -> Void
}

/// A quiet link to the guide: on the first screen, under an empty dashboard page, at the tour's import step.
struct GuideLink: View {
    /// The screen's second ink (Aresium's palette on the dashboard, `Ink` in sheets).
    var tint: Color = Ink.secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text("How do I get my file?").font(AppFont.text(13.5, weight: .semibold))
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
            }
            .foregroundStyle(tint)
            .frame(minHeight: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The guide as a sheet of its own (the first screen, an empty dashboard, the tour): the bank list with Done.
struct BankGuideSheet: View {
    var importing: GuideImport?
    /// Where "Tell us about your bank" sends the name; nil in the tour.
    var outbox: BankOutbox?
    @Environment(\.dismiss) private var dismiss
    #if DEBUG
    /// Screenshots: `-openGuide <bank id>` opens that bank's page at once (`-openGuide list`: the list).
    @State private var shown: String? = LaunchArguments.value("-openGuide").flatMap { $0 == "list" ? nil : $0 }
    #endif

    var body: some View {
        NavigationStack {
            BankGuideList(importing: importing, outbox: outbox)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { dismiss() } label: { Text("Done", tableName: "Shared") }
                    }
                }
                #if DEBUG
                .navigationDestination(item: $shown) { id in
                    if let guide = try? BankGuide.bundled(), let bank = guide.bank(id) {
                        BankGuidePage(bank: bank, guide: guide, importing: importing, outbox: outbox)
                    }
                }
                #endif
        }
        .tint(Ink.primary)
        .presentationBackground(Ink.background)
        .tourCard()
    }
}

/// The banks: a line on what this is, the search field ("Your bank"), the matching banks, Another bank last. When the
/// search finds none: the note, Tell us about your bank, and Another bank's steps in place, with Choose file. The
/// sheet's root, or pushed in Settings → Help.
struct BankGuideList: View {
    var importing: GuideImport?
    var outbox: BankOutbox?
    @State private var guide: BankGuide? = try? BankGuide.bundled()
    #if DEBUG
    @State private var query = LaunchArguments.value("-guideSearch") ?? ""
    #else
    @State private var query = ""
    #endif
    /// Website or app for Another bank's steps in the no-match state (nil: its usual place).
    @State private var otherKind: BankGuide.PlaceKind?

    var body: some View {
        let results = guide?.results(query)
        // The search found no bank: Another bank's steps show in place.
        let unknown: BankGuide.Bank? = if case let .unknown(other) = results { other } else { nil }
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        FormNote(text: String(localized: "Find your bank: step by step, how to get a file of your payments out of it."))
                            .padding(.top, 16)
                        searchField.padding(.top, 14)
                        if let guide {
                            if let unknown {
                                noMatch(unknown, guide: guide)
                            } else if case let .banks(found) = results {
                                let banks = found.filter { !$0.isOther }
                                VStack(spacing: 0) {
                                    ForEach(Array(banks.enumerated()), id: \.element.id) { index, bank in
                                        if index > 0 { SettingsDivider() }
                                        row(bank, guide: guide)
                                    }
                                }
                                .glassCard()
                                .padding(.top, 14)
                                ForEach(found.filter(\.isOther)) { other in
                                    VStack(spacing: 0) { row(other, guide: guide) }
                                        .glassCard()
                                        .padding(.top, 22)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                #if DEBUG
                .task {
                    // Screenshots: `-scrollToEnd` shows the end of the no-match state.
                    guard LaunchArguments.current.contains("-scrollToEnd") else { return }
                    try? await Task.sleep(for: .milliseconds(400))
                    proxy.scrollTo(BankGuideSteps.end, anchor: .bottom)
                }
                #endif
            }
            if unknown != nil, let importing { ChooseFileBar(importing: importing) }
        }
        .background { Ink.background.ignoresSafeArea() }
        .navigationTitle(Text("File from your bank"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// No bank matches: the note with Tell us about your bank (the name is what was typed), then Another bank's steps.
    private func noMatch(_ other: BankGuide.Bank, guide: BankGuide) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            BankRequestCard(lead: Text("We don't know this bank yet. The general steps below may help."),
                            outbox: outbox, prefill: query)
                .padding(.top, 14)
            BankGuideSteps(bank: other, guide: guide,
                           kind: Binding(get: { otherKind ?? other.firstPlace }, set: { otherKind = $0 }))
        }
    }

    /// The search: a field in a glass card, like the category picker's own-name row.
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundStyle(Ink.muted)
                .accessibilityHidden(true)
            TextField("", text: $query, prompt: Text("Your bank").foregroundStyle(Ink.muted))
                .font(AppFont.text(15)).foregroundStyle(Ink.primary)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel(Text("Your bank"))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(Ink.muted)
                        .frame(minWidth: 32, minHeight: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear"))
            }
        }
        .padding(.horizontal, 16).frame(minHeight: 52)
        .glassCard()
    }

    /// A bank: its name and where the file can be had (website, app or both).
    private func row(_ bank: BankGuide.Bank, guide: BankGuide) -> some View {
        NavigationLink {
            BankGuidePage(bank: bank, guide: guide, importing: importing, outbox: outbox)
        } label: {
            SettingsRow(title: bank.title(), subtitle: bank.isOther ? String(localized: "Its usual steps")
                                                                    : Self.where(bank))
        }
        .buttonStyle(SettingsRowStyle())
    }

    private static func `where`(_ bank: BankGuide.Bank) -> String {
        switch bank.placesWithSteps {
        case [.website, .app]: String(localized: "Website and app")
        case [.app]: String(localized: "In the app")
        default: String(localized: "On the website")
        }
    }
}

/// A bank's page: its steps (`BankGuideSteps`), for Another bank "Your bank is missing?" at the end, and Choose file at
/// the bottom.
struct BankGuidePage: View {
    let bank: BankGuide.Bank
    let guide: BankGuide
    var importing: GuideImport?
    var outbox: BankOutbox?
    @State private var kind: BankGuide.PlaceKind

    init(bank: BankGuide.Bank, guide: BankGuide, importing: GuideImport?, outbox: BankOutbox?) {
        self.bank = bank
        self.guide = guide
        self.importing = importing
        self.outbox = outbox
        var kind = bank.firstPlace
        #if DEBUG
        // Screenshots: `-guidePlace app|website`.
        if let place = LaunchArguments.value("-guidePlace").flatMap(BankGuide.PlaceKind.init(rawValue:)),
           bank.place(place).hasSteps { kind = place }
        #endif
        _kind = State(initialValue: kind)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        BankGuideSteps(bank: bank, guide: guide, kind: $kind, marksEnd: !bank.isOther)
                        if bank.isOther {
                            BankRequestCard(lead: Text("Your bank is missing? Tell us which one."), outbox: outbox)
                                .padding(.top, 26)
                                .id(BankGuideSteps.end)
                        }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                #if DEBUG
                .task {
                    // Screenshots: `-scrollToEnd` shows the end of the page.
                    guard LaunchArguments.current.contains("-scrollToEnd") else { return }
                    try? await Task.sleep(for: .milliseconds(400))
                    proxy.scrollTo(BankGuideSteps.end, anchor: .bottom)
                }
                #endif
            }
            if let importing { ChooseFileBar(importing: importing) }
        }
        .background { Ink.background.ignoresSafeArea() }
        .navigationTitle(Text(verbatim: bank.title()))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A bank's steps, as sections of a scroll view: Website / App (only the places with steps; for the other one line),
/// the numbered steps, which file and why, what to know, how the file gets to Aresium. Its page and the list's no-match
/// state show it.
struct BankGuideSteps: View {
    let bank: BankGuide.Bank
    let guide: BankGuide
    @Binding var kind: BankGuide.PlaceKind
    /// The last section carries `end` (screenshots scroll to it); off when something follows it.
    var marksEnd = true
    /// The ways opened beyond the usual one.
    @State private var opened: Set<BankGuide.Way.Key> = []

    static let end = "guide-page-end"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if bank.placesWithSteps.count > 1 {
                Picker(selection: $kind) {
                    Text("Website").tag(BankGuide.PlaceKind.website)
                    Text("App").tag(BankGuide.PlaceKind.app)
                } label: { Text("Where") }
                .pickerStyle(.segmented)
                .padding(.top, 16)
            } else if let line = bank.otherPlaceLine() {
                FormNote(text: line).padding(.top, 16)
            }
            SettingsSection(kind == .website ? String(localized: "On the website") : String(localized: "In the bank's app")) {
                let steps = bank.place(kind).steps()
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    if index > 0 { SettingsDivider().padding(.leading, 48) }
                    NumberedStep(number: index + 1, text: step)
                }
            }
            if bank.mayDiffer(kind) {
                FormNote(text: String(localized: "At your bank a button may be called a little differently."))
                    .padding(.top, 10)
            }
            SettingsSection(String(localized: "Which file")) { fileType }
            if !bank.limits().isEmpty {
                SettingsSection(String(localized: "Good to know")) {
                    Text(verbatim: bank.limits()).font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 14)
                }
            }
            SettingsSection(String(localized: "How the file gets to Aresium")) { ways }
                .id(marksEnd ? Self.end : "guide-ways")
        }
    }

    /// The label(s) to pick as quiet chips, the why in one line under them.
    private var fileType: some View {
        VStack(alignment: .leading, spacing: 10) {
            let labels = bank.fileType.pick()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { chips(labels) }
                VStack(alignment: .leading, spacing: 8) { chips(labels) }
            }
            Text(verbatim: bank.fileType.why()).font(AppFont.text(13.5)).foregroundStyle(Ink.secondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private func chips(_ labels: [String]) -> some View {
        ForEach(labels, id: \.self) { label in
            Text(verbatim: label).font(AppFont.text(13.5, weight: .semibold)).foregroundStyle(Ink.primary)
                .lineLimit(1)
                .padding(.horizontal, 11).frame(minHeight: 32)
                .background(Ink.field, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Ink.line))
                .fixedSize()
        }
    }

    /// The usual way open, the others as rows that open in place.
    private var ways: some View {
        let keys = bank.ways(for: kind)
        return ForEach(Array(keys.enumerated()), id: \.element) { index, key in
            if index > 0 { SettingsDivider() }
            if let way = guide.ways[key] {
                WayBlock(title: Self.title(of: key), way: way, open: index == 0 || opened.contains(key)) {
                    if opened.contains(key) { opened.remove(key) } else { opened.insert(key) }
                }
            }
        }
    }

    private static func title(of key: BankGuide.Way.Key) -> String {
        switch key {
        case .safari: String(localized: "From Safari")
        case .share: String(localized: "From the bank's app")
        case .computer: String(localized: "From a computer")
        case .unzip: String(localized: "A ZIP file")
        case .desktopSite: String(localized: "No export on the iPhone?")
        case .numbers: String(localized: "An Excel file")
        }
    }
}

/// Choose file at the bottom of a page: the file picker, as Import data; the picked files go to the guide's owner.
private struct ChooseFileBar: View {
    let importing: GuideImport
    @State private var picksFiles = false

    var body: some View {
        Button { picksFiles = true } label: {
            Text("Choose file")
        }
        .buttonStyle(FormButtonStyle(accent: nil))
        .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 10)
        .fileImporter(isPresented: $picksFiles, allowedContentTypes: importing.types,
                      allowsMultipleSelection: true) { result in
            if case let .success(urls) = result, urls.isEmpty { return }
            importing.finished(result)
        }
    }
}

/// One numbered step: its number in a day tile (`DayTile`'s metrics, in `Ink`, which the
/// sheets use), the sentence beside it.
private struct NumberedStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            tile
            Text(verbatim: text).font(AppFont.text(14.5, weight: .medium)).foregroundStyle(Ink.primary).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 9)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var tile: some View {
        Text(verbatim: String(number)).font(AppFont.number(15)).foregroundStyle(Ink.secondary)
            .frame(width: 38, height: 38)
            .background(Ink.card2, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Ink.line))
    }
}

/// A way the file gets to Aresium: its title, and when open its three lines and the "or" line; a closed one is a row
/// that opens in place.
private struct WayBlock: View {
    let title: String
    let way: BankGuide.Way
    let open: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Text(verbatim: title).font(AppFont.text(14.5, weight: .semibold)).foregroundStyle(Ink.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Ink.muted).accessibilityHidden(true)
                }
                .frame(minHeight: 48).padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(SettingsRowStyle())
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(open ? Text("Open") : Text("Closed"))
            if open {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(way.steps().enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(verbatim: String(index + 1)).font(AppFont.number(12.5)).foregroundStyle(Ink.muted)
                                .frame(minWidth: 14, alignment: .leading)
                            Text(verbatim: step).font(AppFont.text(13.5)).foregroundStyle(Ink.secondary).lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if let also = way.also() {
                        Text(verbatim: also).font(AppFont.text(12.5)).foregroundStyle(Ink.muted).lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.bottom, 14)
            }
        }
    }
}
