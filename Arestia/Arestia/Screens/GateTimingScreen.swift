#if DEBUG && ARESTIA_GATE
import SwiftUI

struct GateTimingSection: View {
    var body: some View {
        SettingsSection(String(localized: "Gate build")) {
            NavigationLink {
                GateTimingScreen()
            } label: {
                SettingsRow(title: String(localized: "Gate timing log"))
            }
            .buttonStyle(SettingsRowStyle())
        }
    }
}

private struct GateTimingScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var lines: [String] = []
    @State private var hasError = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if hasError {
                    Text("The gate timing log is unavailable.")
                } else if lines.isEmpty {
                    Text("No timing entries yet.")
                }
                ForEach(lines, id: \.self) { line in
                    Text(verbatim: line.replacingOccurrences(of: "\t", with: "  "))
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Ink.primary)
            .padding(16)
        }
        .background { SettingsWall(accent: .arestia) }
        .navigationTitle("Gate timing log")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scenePhase) { reload() }
        .refreshable { reload() }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !lines.isEmpty, let file = GateTimingLog.file {
                    ShareLink(item: file)
                    Button("Clear log", systemImage: "trash", role: .destructive, action: clear)
                }
            }
        }
    }

    private func reload() {
        do {
            lines = try GateTimingLog.newestFirst()
            hasError = false
        } catch {
            hasError = true
        }
    }

    private func clear() {
        do {
            try GateTimingLog.clear()
            reload()
        } catch {
            hasError = true
        }
    }
}
#endif
