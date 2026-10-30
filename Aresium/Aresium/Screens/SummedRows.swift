import SwiftUI

// Adding up names in a category's list (brief 53; the choices and the grouping in `Model/PaymentSums.swift`): the summed
// row with its payments below it while open, the category's icon in the header, and the switches on the name's page and
// in Settings. The rows' own swipe and long press are in `PaymentList.swift`.

/// The symbols of adding up: the category's icon is a stack of tiles, as the summed row's mark (on and off differ by the
/// button's fill: the filled symbol reads as a jar); the swipe's and the long press's actions show what they do to the
/// rows (fold them into one, unfold them), so they never look like "All"'s stack beside them.
enum SumSymbol {
    static let category = "square.stack"
    static let addUp = "rectangle.compress.vertical"
    static let separate = "rectangle.expand.vertical"
}

/// How a summed row opens and closes, and how rows fold into one or come apart: the system's spring, without bounce, so
/// the rows around it glide to their places. Reduce Motion: no movement (the change shows at once).
enum SumMotion {
    static func animation(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        #if DEBUG
        // Screenshots of the motion itself: `-sumsSlow <seconds>` stretches it.
        if let seconds = LaunchArguments.value("-sumsSlow").flatMap(Double.init) {
            return .spring(duration: seconds, bounce: 0)
        }
        #endif
        return .spring(duration: 0.38, bounce: 0)
    }
}

/// A summed row in a category's list and, while it is open, its payments below it, each the usual row (tap, long press,
/// swipe "All"), on a card that holds them together. Opening and closing let the card grow and shrink while the rows
/// below glide (the card clips its payments to its height as it grows, so nothing lies over the rows below meanwhile).
struct SummedPaymentGroup: View {
    let sum: SummedPayments
    let store: DashboardStore
    let palette: Palette
    @Bindable var menu: PaymentRowMenu
    var shortcuts = true
    /// Separate: the name's payments single again in this category (`PaymentSums`).
    let separate: () -> Void
    let allFrom: (DashboardRoute) -> Void
    /// Screenshots only: the summed row shown so far left, as halfway through a swipe.
    var shownAt: CGFloat? = nil
    let open: (Transaction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isOpen: Bool { menu.openSums.contains(sum.key) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(spacing: 0) {
            SummedPaymentRow(sum: sum, store: store, palette: palette, menu: menu, shortcuts: shortcuts, isOpen: isOpen,
                             toggle: toggle, separate: separate, allFrom: allFrom, shownAt: shownAt)
            if isOpen {
                // A hairline between the sum and its payments, as the start screen sets the Cash row apart.
                Rectangle().fill(palette.line).frame(height: 1).padding(.horizontal, 12)
                    .transition(.opacity).accessibilityHidden(true)
                ForEach(sum.rows) { row in
                    PaymentRow(row: row, store: store, palette: palette, menu: menu, shortcuts: shortcuts,
                               allFrom: allFrom, open: open)
                }
                .transition(.opacity)
            }
        }
        // Always there, shown only while open: so the card's own height animates with the group's, rounded corners and
        // edge included, rather than appearing at its full height behind the clipping.
        .background { shape.fill(palette.card).overlay(shape.stroke(palette.line)).opacity(isOpen ? 1 : 0) }
        // Clips the payments to the card's height while it opens or closes; sideways the rows still slide off freely.
        .mask { Rectangle().padding(.horizontal, -1000) }
    }

    private func toggle() {
        withAnimation(SumMotion.animation(reduceMotion: reduceMotion)) {
            if isOpen { menu.openSums.remove(sum.key) } else { menu.openSums.insert(sum.key) }
        }
    }
}

/// The summed row: a stack of tiles with the count where a payment shows its day, the name as its newest payment shows
/// it, the days, and the net sum in the list's colours. A tap opens or closes its payments below it; the swipe offers
/// Separate and All, the long press the same.
struct SummedPaymentRow: View {
    let sum: SummedPayments
    let store: DashboardStore
    let palette: Palette
    @Bindable var menu: PaymentRowMenu
    var shortcuts = true
    let isOpen: Bool
    let toggle: () -> Void
    let separate: () -> Void
    let allFrom: (DashboardRoute) -> Void
    var shownAt: CGFloat? = nil

    var body: some View {
        Button(action: toggle) {
            SummedRowLabel(sum: sum, palette: palette)
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: SumWording.spoken(sum)))
        .accessibilityHint(isOpen ? Text("Hides its payments") : Text("Shows its payments"))
        .accessibilityAddTraits(.isButton)
        .contextMenu { if shortcuts { items } }
        .rowSwipe(swipes, id: sum.id, open: $menu.openRow, shownAt: shownAt)
    }

    private var route: DashboardRoute? { store.nameRoute(for: sum.newest) }

    private var swipes: [RowSwipeAction] {
        guard shortcuts else { return [] }
        var actions = [RowSwipeAction.separate(separate)]
        if let route { actions.append(.all(route, name: sum.title, open: allFrom)) }
        return actions
    }

    /// Separate and "All with this name": what the swipe offers (`DashboardStore.rowActions(for:)`).
    @ViewBuilder private var items: some View {
        ForEach(store.rowActions(for: .summed(sum)), id: \.self) { action in
            switch action {
            case .separate:
                Button(SumWording.separate(), systemImage: SumSymbol.separate, action: separate)
            case .allFromName:
                Button("All with this name", systemImage: "rectangle.stack") { if let route { allFrom(route) } }
            default:
                EmptyView()
            }
        }
    }
}

/// The summed row as drawn (a payment row's layout, `PaymentRowLabel`).
struct SummedRowLabel: View {
    let sum: SummedPayments
    let palette: Palette

    var body: some View {
        HStack(spacing: 12) {
            StackTile(palette: palette) {
                Text(verbatim: SumWording.count(sum.count)).lineLimit(1).minimumScaleFactor(0.5)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: sum.title).font(AppFont.text(14.5, weight: .semibold)).lineLimit(1)
                Text(verbatim: SumWording.days(from: sum.firstDay, to: sum.lastDay)).font(AppFont.text(12.5))
                    .foregroundStyle(palette.muted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: Money.transaction(sum.total)).font(AppFont.number(14))
                .foregroundStyle(sum.cents < 0 ? palette.expenseText : palette.income).fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 11).contentShape(Rectangle())
    }
}

/// The summed row's mark: the day's tile (`DayTile`) with a second tile peeking out above it, a small stack, and the
/// count in it ("10×").
struct StackTile<Label: View>: View {
    let palette: Palette
    @ViewBuilder let label: Label

    var body: some View {
        DayTile(palette: palette) { label }
            .background(alignment: .top) {
                // Only the part above the front tile shows (the tiles are translucent).
                let shape = RoundedRectangle(cornerRadius: 8)
                shape.fill(palette.card2).overlay(shape.stroke(palette.line))
                    .frame(width: 28, height: 16)
                    .offset(y: -4)
                    .mask(alignment: .top) { Rectangle().frame(height: 4.5).offset(y: -4) }
            }
            .accessibilityHidden(true)
    }
}

/// The category's icon in the header of its payments (brief 53, Patrik: "a little icon at the top of each that shows if
/// its summed up or not"): the header's button (`IconButton`), a stack of tiles; on, it is filled (the second ink, the
/// wall's colour on it), off as the other header buttons, so the two differ in light, dark and red. A tap adds up every
/// name there, or none.
struct SumCategoryButton: View {
    let on: Bool
    let palette: Palette
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        Button(action: action) {
            Image(systemName: SumSymbol.category).font(.system(size: 17, weight: .medium))
                .frame(width: 42, height: 42)
                .foregroundStyle(on ? palette.background : palette.secondary)
                .background(on ? palette.secondary : palette.card, in: shape)
                .overlay(shape.stroke(on ? Color.clear : palette.line))
                .minimumTapArea()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Add up same names"))
        .accessibilityValue(on ? Text("On") : Text("Off"))
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier("sumCategory")
    }
}

/// The name's page's switch (brief 53): this name added up in every category's list, on a card under the totals.
struct NameSumSwitch: View {
    let key: String
    let sums: PaymentSums
    let palette: Palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Toggle(isOn: Binding(get: { sums.choices.sumsName(key) }, set: { on in
            withAnimation(SumMotion.animation(reduceMotion: reduceMotion)) { sums.setName(key, sums: on) }
        })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add up in every category").font(AppFont.text(14.5, weight: .semibold)).foregroundStyle(palette.ink)
                Text("One row with the sum per month").font(AppFont.text(12.5))
                    .foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(EmpireSwitchStyle())
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(palette.card, in: shape)
        .overlay(shape.stroke(palette.line))
    }
}
