# empire-ios — notes for Claude Code

Read `README.md` first, then the decision record in the ares-empire repo
(`docs/IPHONE-APPS.md`) and the login plan (`docs/ACCOUNTS.md`).

- Native SwiftUI only — no web views wrapping the websites.
- Each app uses its service's existing JSON API; if the API lacks something, change the
  service (its own repo), don't work around it in the app.
- Log in via the Empire account system, never a service's own password.
- Design language: the Ares Empire "crown language" in `ares-empire/EMPIRE.md`
  (near-black, polished gold accent, Space Grotesk / JetBrains Mono).
- Append a line to the Chronicle in `ares-empire/EMPIRE.md` after meaningful work.
