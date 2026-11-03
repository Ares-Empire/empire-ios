import SwiftUI
import UIKit

/// The application text for a match, to copy into the portal (Arestemis never sends it). Mode label, the text, then
/// "Copy and open listing", "Copy", and in AI mode "Write again". After copying, "Mark as applied".
struct ApplicationSheet: View {
    let matchID: Int
    let store: ArestemisStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var copied = false
    @State private var justCopied = false

    private var state: ArestemisStore.ApplicationState { store.application(matchID) }
    private var match: Match? { store.match(matchID) }

    var body: some View {
        NavigationStack {
          VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let application = state.application {
                        CapsLabel(text: application.mode == .ai ? String(localized: "Written automatically") : String(localized: "Your text"), size: 11)
                            .padding(.leading, 4)
                        Text(application.text).font(AppFont.text(15)).foregroundStyle(Ink.primary).lineSpacing(5)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard()
                            .opacity(state.isLoading ? 0.35 : 1)
                            .overlay { if state.isLoading { ProgressView().tint(Ink.secondary) } }
                            .animation(.easeOut(duration: 0.2), value: state.isLoading)
                            .padding(.top, Look.headingGap)
                        if let error = state.error {
                            Text(error).font(AppFont.text(12)).foregroundStyle(Ink.muted).padding(.top, 10).padding(.leading, 4)
                        }
                    } else if let error = state.error {
                        CalmMessage(text: error, action: (String(localized: "Try again"), { Task { await store.loadApplication(for: matchID) } }))
                    } else {
                        CalmMessage(text: String(localized: "Writing the application…"), loading: true)
                    }
                }
                .padding(.horizontal, Look.side).padding(.top, 8).padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .edgeFade(bottom: state.application == nil ? 0 : 22)
            if let application = state.application { buttons(application) }
          }
            .provinceWall()
            .navigationTitle("Application text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task { await store.loadApplication(for: matchID) }
        .sensoryFeedback(.success, trigger: justCopied) { _, now in now }
    }

    private func buttons(_ application: Application) -> some View {
        VStack(spacing: 10) {
            Button("Copy and open listing") {
                copy(application)
                if let url = match?.listing.portalURL { openURL(url) }
            }
            .buttonStyle(.accent)
            .disabled(state.isLoading)
            HStack(spacing: 10) {
                Button { copy(application) } label: {
                    Label(justCopied ? "Copied" : "Copy", systemImage: justCopied ? "checkmark" : "doc.on.doc")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.glassy)
                .disabled(state.isLoading)
                if application.mode == .ai {
                    Button { Task { await store.loadApplication(for: matchID, regenerate: true) } } label: {
                        Label(state.isLoading ? "Writing…" : "Write again", systemImage: "arrow.clockwise")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.glassy)
                    .disabled(state.isLoading)
                }
            }
            if copied, let match {
                if match.state == .applied {
                    Label("Marked as applied", systemImage: "checkmark")
                        .font(AppFont.text(13, weight: .medium)).foregroundStyle(Ink.muted).frame(minHeight: 36)
                } else {
                    Button("Mark as applied") { Task { await store.setState(.applied, for: matchID) } }
                        .buttonStyle(.quiet)
                        .disabled(store.changingState.contains(matchID))
                }
            }
        }
        .padding(.horizontal, Look.side).padding(.top, 4).padding(.bottom, 6)
        .animation(.easeOut(duration: 0.2), value: copied)
    }

    private func copy(_ application: Application) {
        UIPasteboard.general.string = application.text
        copied = true
        justCopied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            justCopied = false
        }
    }
}
