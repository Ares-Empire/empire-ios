import SwiftUI

/// "Where it looks" ("Wo gesucht wird", brief 157, the plan's section 4: Patrik's idea, "a screen that shows all sites it
/// would check, also makes user suggestions easier"): every site an everywhere monitor checks for its product, the ones
/// that have it first (`PriceSites.ordered`), each with its name, a quiet word for its state and a switch; turning off
/// the last one is refused with a line. "Suggest a shop" at the end opens Settings' Contact & support form as an idea or
/// wish with its text started ("Suggest a shop: "), so the person types the shop's name (nothing new on the server).
/// Pushed from the form (its draft's sites switched off) and from the monitor's page (saved as they change).
struct PriceSitesScreen: View {
    /// The product, for the line over the sites.
    let product: String?
    /// The sites, in the server's order; nil while they load.
    let sites: [PriceSite]?
    /// The ids switched off.
    @Binding var off: [String]
    let store: ArestemisStore
    var delivery: Delivery = .shipping

    @State private var line: String?
    /// Counts the refusals, so a switch turned off against the rule is drawn on again.
    @State private var refusals = 0
    @State private var suggesting = false
    @State private var launchDone = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Caption(text: EverywhereWords.sitesIntro(product: product))
                    .padding(.horizontal, 4).padding(.top, 10)
                if let sites {
                    VStack(alignment: .leading, spacing: 8) {
                        FormCard {
                            ForEach(Array(PriceSites.ordered(sites).enumerated()), id: \.element.id) { index, site in
                                if index > 0 { Hairline() }
                                row(site, all: sites)
                            }
                        }
                        .id(refusals)
                        if let line { Caption(text: line).padding(.leading, 4) }
                    }
                    .padding(.top, 14)
                } else {
                    ProgressView().controlSize(.small).tint(Ink.muted).frame(maxWidth: .infinity, minHeight: 120)
                }
                Button { suggesting = true } label: {
                    Text("Suggest a shop").font(AppFont.text(15, weight: .semibold)).foregroundStyle(Look.accent.color)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassCard()
                .padding(.top, Look.sectionGap)
            }
            .padding(.horizontal, Look.side).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .provinceWall()
        .navigationTitle(Text("Where it looks"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $suggesting) {
            let start = PriceSites.suggestion()
            SupportSheet(session: store.session, accent: Look.accent, sample: store.isSample, kind: start.kind,
                         text: start.text)
        }
        .onAppear(perform: debugLaunch)
    }

    /// A site's name with one small line under it, "Price comparison · has it" for idealo, billiger.de and Geizhals
    /// ("Preisvergleich · hat es"), else the state alone, so every row keeps the same height; and its switch.
    private func row(_ site: PriceSite, all: [PriceSite]) -> some View {
        Toggle(isOn: Binding(get: { !off.contains(site.id) && site.serves(delivery) }, set: { on in switchSite(site.id, on: on, all: all) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: site.name).font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                if let detail = PriceSites.detail(site, delivery: delivery) {
                    Text(verbatim: detail).font(AppFont.text(12)).foregroundStyle(Ink.muted)
                }
            }
        }
        .disabled(!site.serves(delivery))
        .opacity(site.serves(delivery) ? 1 : 0.45)
        .toggleStyle(EmpireSwitchStyle(accent: Look.accent))
        .frame(minHeight: 56)
    }

    private func switchSite(_ id: String, on: Bool, all: [PriceSite]) {
        guard let changed = PriceSites.switched(id, on: on, off: off, sites: all, delivery: delivery) else {
            line = PriceSites.lastSiteLine()
            refusals += 1
            return
        }
        line = nil
        if changed != off { off = changed }
    }

    /// Screenshots (sample mode, DEBUG): `-suggestShop` opens the contact form as "Suggest a shop" does.
    private func debugLaunch() {
        #if DEBUG
        guard store.isSample, !launchDone else { return }
        launchDone = true
        if LaunchArguments.current.contains("-suggestShop") {
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                suggesting = true
            }
        }
        #endif
    }
}
