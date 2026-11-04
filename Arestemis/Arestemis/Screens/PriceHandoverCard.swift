import SwiftUI

/// The Things form's place chips and radius choices, used for Everywhere's handover.
struct PriceHandoverCard: View {
    @Binding var delivery: Delivery
    @Binding var places: [Place]
    @Binding var radiusKm: Double
    let add: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Handover", selection: $delivery) {
                Text("Shipping").tag(Delivery.shipping)
                Text("Pickup").tag(Delivery.pickup)
                Text("Either").tag(Delivery.either)
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 12)
            if delivery != .shipping {
                Hairline()
                PlaceChips(places: places, canAdd: places.count < ItemSearchDraft.maxPlaces,
                           remove: { place in places.removeAll { $0.id == place.id } }, add: add)
                    .padding(.vertical, 14)
                Hairline()
                Stepper {
                    HStack {
                        Text("Radius").font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                        Spacer(minLength: 8)
                        Text(verbatim: Format.number(radiusKm) + " km")
                            .font(AppFont.number(15, weight: .medium)).foregroundStyle(Ink.primary)
                            .contentTransition(.numericText()).padding(.trailing, 6)
                    }
                } onIncrement: {
                    withAnimation(.snappy) { radiusKm = RadiusSteps.up(from: radiusKm) }
                } onDecrement: {
                    withAnimation(.snappy) { radiusKm = RadiusSteps.down(from: radiusKm) }
                }
                .frame(minHeight: 50)
                .accessibilityValue(Format.number(radiusKm) + " km")
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
