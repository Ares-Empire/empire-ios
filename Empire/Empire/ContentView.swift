import SwiftUI

/// Placeholder until the throne room screens land (the approved phone hub, ares-empire web/app/mobile.jsx).
/// It already uses the shared Empire login: logged in once in any Empire app means logged in here.
struct ContentView: View {
    @State private var session = EmpireSession(app: .empire, installDefaults: EmpireShared.defaults)

    var body: some View {
        VStack(spacing: 14) {
            Text("THE EMPIRE").font(AppFont.text(14, weight: .bold)).tracking(5).foregroundStyle(Color.accentColor)
            if session.isRestoring {
                ProgressView()
            } else if session.isSignedIn {
                Text("Signed in").font(AppFont.text(15))
            } else {
                Text(session.error ?? "Not signed in").font(AppFont.text(13)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .task { await session.restore() }
    }
}
