import SwiftUI

/// Arestia's own section at the top of Settings: the flat service it is paired with (its state, the address it was last
/// reached at, and its identity to compare with what `flatd pair` shows), a new code of the same flat, and Forget this
/// flat, the one way to another flat (one flat per install, docs/ARESTIA-APP.md). There is no account section: Arestia
/// has none.
struct ConnectionSection: View {
    let store: FlatStore
    let session: FlatSession
    @State private var connecting = false
    @State private var confirmsForget = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSection(String(localized: "Flat service")) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "flatd")
                            .font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                        if let address = pairing?.baseURL {
                            Text(verbatim: address.host().map { host in address.port.map { "\(host):\($0)" } ?? host } ?? "")
                                .font(AppFont.number(12)).foregroundStyle(Ink.muted)
                        }
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 6) {
                        LiveDot(live: store.link == .live)
                        Text(verbatim: status).font(AppFont.text(14)).foregroundStyle(Ink.secondary)
                    }
                }
                .frame(minHeight: 58).padding(.horizontal, 16)
                .accessibilityElement(children: .combine)
                if let pairing {
                    SettingsDivider()
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Identity").font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                            Text("The same as under flatd's QR code")
                                .font(AppFont.text(12)).foregroundStyle(Ink.muted)
                        }
                        Spacer(minLength: 12)
                        Text(verbatim: pairing.pin.short).font(AppFont.number(13)).foregroundStyle(Ink.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 58).padding(.horizontal, 16)
                    .accessibilityElement(children: .combine)
                }
                SettingsDivider()
                Button { connecting = true } label: {
                    SettingsRow(title: String(localized: "Pair again"),
                                subtitle: String(localized: "A new code from the same flatd"))
                }
                .buttonStyle(SettingsRowStyle())
                SettingsDivider()
                Button { confirmsForget = true } label: {
                    SettingsRow(title: String(localized: "Forget this flat"), trailing: .none,
                                tint: FormButtonStyle.dangerInk)
                }
                .buttonStyle(SettingsRowStyle())
                .disabled(session.isForgetting)
                .confirmationDialog(Text("Forget this flat?"), isPresented: $confirmsForget,
                                    titleVisibility: .visible) {
                    Button(role: .destructive) {
                        Task {
                            let forgotten = await session.forget()
                            dismiss()
                            if !forgotten {
                                store.offer = UndoOffer(message: String(localized: "Arestia couldn't forget the flat. Try again."))
                            }
                        }
                    } label: { Text("Forget") }
                    Button(role: .cancel) {} label: { Text("Cancel") }
                } message: {
                    Text("Arestia forgets the pairing and everything it knows of this flat. The Control Center controls and Shortcuts do nothing until you pair again, and a blind or fan chosen in them is chosen again. Another flat can be paired only after this.")
                }
            }
            FormNote(text: String(localized: "Arestia talks only to the flatd with this identity, encrypted. The pairing stays on this iPhone, in the Keychain; Shortcuts and the Control Center controls use it too."))
        }
        .sheet(isPresented: $connecting) {
            ConnectScreen(store: store, closable: true)
        }
    }

    /// Read on every pass: the address follows flatd (the store's state changes whenever that happens).
    private var pairing: FlatdPairing? { store.connection.pairing }

    private var status: String {
        switch store.link {
        case .live: String(localized: "Connected")
        case .connecting: store.hasSnapshot ? String(localized: "Reconnecting…") : String(localized: "Connecting")
        case .offline: String(localized: "Not reachable")
        case .refused: String(localized: "Key refused")
        case .notSetUp: String(localized: "Not connected")
        }
    }
}

/// Settings → 3D flat: always daylight, or the sun where it really is now (time of day and season (owner, 2026-11-19):
/// "Real time of day but also accurately depending on season and stuff. But with a setting toggle to always day").
struct FlatViewSection: View {
    @AppStorage(PageScript.alwaysDaylightKey) private var alwaysDaylight = false

    var body: some View {
        SettingsSection(String(localized: "3D flat")) {
            Toggle(isOn: $alwaysDaylight) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Always daylight").font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                    Text("Otherwise the sun stands where it really is now.")
                        .font(AppFont.text(12)).foregroundStyle(Ink.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: 58).padding(.horizontal, 16)
        }
    }
}
