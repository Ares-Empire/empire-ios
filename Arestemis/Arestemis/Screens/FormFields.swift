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

/// A whole number in a quiet well, with "€" before or "m²" after; empty = no limit ("Any").
struct NumberField: View {
    @Binding var value: Double?
    var prefix: String? = nil
    var suffix: String? = nil
    var placeholder = "Any"
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
                Text(value.map(Format.number) ?? "Any")
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
        .accessibilityValue(value.map(Format.number) ?? "Any")
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
            NumberField(value: $range.min, prefix: prefix, suffix: suffix, placeholder: "min", width: 92,
                        label: "\(label), at least, in \(unitName)")
            Text("–").font(AppFont.text(14)).foregroundStyle(Ink.muted).accessibilityHidden(true)
            NumberField(value: $range.max, prefix: prefix, suffix: suffix, placeholder: "max", width: 92,
                        label: "\(label), at most, in \(unitName)")
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
