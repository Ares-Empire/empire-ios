import SwiftUI

/// A glass card holding form rows, with the app's inner padding.
struct FormCard<Content: View>: View {
    var accent = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(accent: accent ? Look.accent : nil)
    }
}

/// One row of a form card: a label on the left, the control on the right.
struct FormRow<Control: View>: View {
    let label: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                .lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            control
        }
        .frame(minHeight: 50)
    }
}

/// A small caption under a card or a row ("Checked by the AI on every listing.").
struct Caption: View {
    let text: String
    var body: some View {
        Text(text).font(AppFont.text(12)).foregroundStyle(Ink.muted).lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The euro sign beside an amount: before it in English, after it in German ("€400", "400 €").
enum Euro {
    static var prefix: String? { AppLanguage.current == .german ? nil : "€" }
    static var suffix: String? { AppLanguage.current == .german ? "€" : nil }
}

/// A whole number in a quiet well, with "€" before or "m²" after; empty = no limit ("Any").
struct NumberField: View {
    @Binding var value: Double?
    var prefix: String? = nil
    var suffix: String? = nil
    var placeholder = String(localized: "Any")
    var width: CGFloat = 104
    var label: String
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        // The unit sits right beside the number; the whole well takes the tap.
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Spacer(minLength: 0)
            if let prefix, !text.isEmpty { unit(prefix) }
            TextField("", text: $text, prompt: Text(placeholder).font(AppFont.text(15)).foregroundStyle(Ink.muted))
                .font(AppFont.number(15, weight: .medium))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Ink.primary)
                .fixedSize()
                .focused($focused)
                .accessibilityLabel(label)
            if let suffix, !text.isEmpty { unit(suffix) }
        }
        .padding(.horizontal, 12)
        .frame(width: width, height: 38)
        .background(Look.well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(focused ? Look.accent.color.opacity(0.6) : Look.wellEdge))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear { text = Self.format(value) }
        .onChange(of: text) { _, new in
            let digits = new.filter(\.isNumber)
            if digits != new { text = digits; return }
            let parsed = Double(digits)
            if parsed != value { value = parsed }
        }
        .onChange(of: value) { _, new in
            if Double(text) != new { text = Self.format(new) }
        }
    }

    private func unit(_ text: String) -> some View {
        Text(text).font(AppFont.text(14)).foregroundStyle(Ink.muted)
    }

    private static func format(_ value: Double?) -> String {
        value.map { String(Int($0.rounded())) } ?? ""
    }
}

/// A native stepper whose lowest step is "Any" (no limit): stepping down from the minimum clears the value.
struct OptionalStepper: View {
    let label: String
    @Binding var value: Double?
    let range: ClosedRange<Double>
    var step: Double = 1

    var body: some View {
        Stepper {
            HStack {
                Text(label).font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary).lineLimit(1)
                Spacer(minLength: 8)
                Text(value.map { Format.number($0) } ?? String(localized: "Any"))
                    .font(value == nil ? AppFont.text(15) : AppFont.number(15, weight: .medium))
                    .foregroundStyle(value == nil ? Ink.muted : Ink.primary)
                    .contentTransition(.numericText())
                    .padding(.trailing, 6)
            }
        } onIncrement: {
            withAnimation(.snappy) { value = value.map { min($0 + step, range.upperBound) } ?? range.lowerBound }
        } onDecrement: {
            guard let current = value else { return }
            withAnimation(.snappy) { value = current - step < range.lowerBound ? nil : current - step }
        }
        .frame(minHeight: 50)
        .accessibilityValue(value.map { Format.number($0) } ?? String(localized: "Any"))
    }
}

/// A native stepper over a required count ("1 person", "2 people").
struct CountStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let text: (Int) -> String

    var body: some View {
        Stepper(value: $value.animation(.snappy), in: range) {
            HStack {
                Text(label).font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary).lineLimit(1)
                Spacer(minLength: 8)
                Text(text(value)).font(AppFont.text(15)).foregroundStyle(Ink.primary)
                    .contentTransition(.numericText())
                    .padding(.trailing, 6)
            }
        }
        .frame(minHeight: 50)
        .accessibilityValue(text(value))
    }
}

/// A label and two number wells, "min – max"; either may stay empty (no limit on that side).
struct RangeRow: View {
    let label: String
    @Binding var range: SearchDraft.Range
    var prefix: String? = nil
    var suffix: String? = nil
    /// The unit for VoiceOver ("euros", "square metres").
    let unitName: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                .lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: 6)
            NumberField(value: $range.min, prefix: prefix, suffix: suffix, placeholder: String(localized: "min"), width: 92,
                        label: String(localized: "\(label), at least, in \(unitName)"))
            Text("–").font(AppFont.text(14)).foregroundStyle(Ink.muted).accessibilityHidden(true)
            NumberField(value: $range.max, prefix: prefix, suffix: suffix, placeholder: String(localized: "max"), width: 92,
                        label: String(localized: "\(label), at most, in \(unitName)"))
        }
        .frame(minHeight: 54)
    }
}

/// A text area in a quiet well (the search's "Describe it" and extras, the application texts).
struct TextArea: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 96
    var font: Font = AppFont.text(15)
    /// In a quiet well (inside a card with other controls), or bare (the glass card itself is the field).
    var inWell = true

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Ink.muted), axis: .vertical)
            .font(font).foregroundStyle(Ink.primary).lineSpacing(3)
            .lineLimit(3...)
            .padding(inWell ? 12 : 16)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background(inWell ? Look.well : .clear, in: RoundedRectangle(cornerRadius: Ink.rowRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Ink.rowRadius, style: .continuous)
                .strokeBorder(inWell ? Look.wellEdge : .clear))
    }
}

// MARK: - pieces both search forms share

/// A titled part of a search form: the heading, its card, and the lines saying what is wrong there (`problems`).
struct FormSection<Content: View>: View {
    let title: String
    var problems: [String] = []
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Look.headingGap) {
            SectionHeading(text: title).padding(.leading, 4)
            content
            ForEach(problems, id: \.self) { ProblemLine(text: $0).padding(.leading, 4) }
        }
        .padding(.top, Look.sectionGap)
    }
}

/// What is wrong with a field, under it: a small amber mark and the sentence (as a match's warnings).
struct ProblemLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "exclamationmark.circle").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Look.amber)
            Text(text).font(AppFont.text(12)).foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Describe it": the line at the top of a search form that opens the sheet where a sentence fills the fields in.
struct DescribeLine: View {
    let action: () -> Void

    var body: some View {
        Button {
            endTyping()
            action()
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
}

/// The chosen places as chips (× removes one) and a chip that opens the place search.
struct PlaceChips: View {
    let places: [Place]
    var canAdd = true
    let remove: (Place) -> Void
    let add: () -> Void

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(places) { place in
                Chip(text: place.name) { remove(place) }
            }
            if canAdd {
                Button(action: add) {
                    Chip(text: places.isEmpty ? String(localized: "Choose a city") : String(localized: "Add city"), symbol: "plus")
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Words as chips (× removes one) and a dashed chip to type a new one in (the flat form's areas, the thing form's
/// words to leave out).
struct WordChips: View {
    let words: [String]
    let placeholder: String
    let remove: (String) -> Void
    /// Adds the typed word; false keeps it in the field (empty or there already).
    let add: (String) -> Bool
    @State private var text = ""

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(words, id: \.self) { word in
                Chip(text: word) { remove(word) }
            }
            HStack(spacing: 6) {
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Ink.muted))
                    .font(AppFont.text(14)).foregroundStyle(Ink.primary)
                    .submitLabel(.done)
                    .onSubmit(addTyped)
                    .frame(width: 104)
                if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: addTyped) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Look.accent.color).frame(width: 22, height: 22)
                            .padding(11).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(placeholder)
                    .padding(-11)
                }
            }
            .padding(.horizontal, 13).frame(minHeight: 34)
            .overlay(Capsule().strokeBorder(Ink.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
    }

    private func addTyped() {
        if add(text) { text = "" }
    }
}

/// One switch per site, in the server's order (`SiteChoices`), with the site's note from the server ("Blocked since
/// 14:02"). A site that is not set up, or cannot serve the thing form's delivery (brief 129), is greyed and cannot be
/// switched on (one that is on can still be switched off); one line under the card says why. `extra` follows under
/// them (the thing form's "Include auctions", a card of its own, so it does not read as another site).
struct PortalToggles<Extra: View>: View {
    let choices: SiteChoices
    @Binding var chosen: Set<Source>
    let statuses: [SourceStatus]
    @ViewBuilder let extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FormCard {
                ForEach(Array(choices.sites.enumerated()), id: \.element.id) { index, site in
                    if index > 0 { Hairline() }
                    row(site)
                }
            }
            if let line = choices.line() { Caption(text: line).padding(.leading, 4) }
            extra
        }
    }

    private func row(_ site: KindSource) -> some View {
        let open = choices.isOpen(site)
        let note = open ? statuses.first { $0.source == site.source }?.note : nil
        return Toggle(isOn: Binding(get: { chosen.contains(site.source) }, set: { on in
            if on { chosen.insert(site.source) } else { chosen.remove(site.source) }
        })) {
            HStack(spacing: 10) {
                Text(verbatim: site.name).font(AppFont.text(15, weight: .medium))
                    .foregroundStyle(open ? Ink.primary : Ink.muted)
                if let note {
                    Text(note).font(AppFont.text(12)).foregroundStyle(Ink.muted).lineLimit(1)
                }
            }
        }
        .tint(Look.accent.color)
        .disabled(!choices.canSwitch(site, chosen: chosen))
        .frame(minHeight: 50)
    }
}

extension PortalToggles where Extra == EmptyView {
    init(choices: SiteChoices, chosen: Binding<Set<Source>>, statuses: [SourceStatus]) {
        self.init(choices: choices, chosen: chosen, statuses: statuses) { EmptyView() }
    }
}

/// "Extras": the free text every listing is checked against, in a glass card, with its caption.
struct ExtrasField: View {
    let placeholder: String
    @Binding var text: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextArea(placeholder: placeholder, text: $text, minHeight: 84, inWell: false)
                .glassCard()
            Caption(text: caption).padding(.leading, 4)
        }
    }
}

/// The bottom of a search form: Save (or Create), the line under it, and Delete for a search that exists; in a watch's
/// form the words name a watch (`words`).
struct SearchSaveArea: View {
    var words = HuntWords(nil)
    let creating: Bool
    let canSave: Bool
    let saving: Bool
    /// The server's refusal, else what is still missing, else a note on what saving does.
    let line: String?
    let save: () -> Void
    let delete: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Button(action: save) {
                HStack(spacing: 8) {
                    if saving { ProgressView().controlSize(.small).tint(Look.onAccent) }
                    Text(creating ? words.create : words.save)
                }
            }
            .buttonStyle(.accent)
            .disabled(!canSave || saving)

            if let line { Caption(text: line).multilineTextAlignment(.center) }

            if let delete {
                Button(words.delete, role: .destructive, action: delete)
                    .buttonStyle(.destructiveQuiet)
                    .disabled(saving)
                    .padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Look.sectionGap)
    }
}

extension View {
    /// A search form pushed on the Hunts tab: its title in the bar, Save at the top while there is something to save
    /// (comfort item 3), the keyboard's Done, no tab bar.
    func searchFormChrome(title: String, showsSave: Bool, saving: Bool, save: @escaping () -> Void) -> some View {
        self
            .provinceWall()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                if showsSave {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: save) {
                            HStack(spacing: 6) {
                                if saving { ProgressView().controlSize(.small).tint(Look.accent.color) }
                                // The app's accent, so it reads as the action it is (grey read as switched off).
                                Text("Save").font(AppFont.text(16, weight: .semibold)).foregroundStyle(Look.accent.color)
                            }
                        }
                        .disabled(saving)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { endTyping() }
                }
            }
    }
}
