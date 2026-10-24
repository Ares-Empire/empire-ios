# E4b: a Settings screen in every app (replaces E4's placement; part 1 of E4 stays)

Patrik (2026-10-24, after E4 started): "I think each app should get a setting icon that opens settings plus the
necessary things an app needs ... making some for other users to read or so it feels legit might be good. So the
language switch in app thats being built rn will go into settings then. ... And each settings thing should get a
'support' or 'contact' entry so that a user could easily contact me."

E4 part 1 (how iOS 27 behaves) and the language entry's logic stay as briefed. What changes is **where** it sits: every
app gets one shared Settings screen, and the language entry is one row in it.

## The Settings screen (shared, `Shared/`)

- **Opened from a settings icon** (`gearshape`, a `GlassIconButton` or the app's own icon button, labelled) in each
  app's header, where the account actions are today; it replaces those (Arestoteles's header menu with Log out,
  Aresus's and Aresium's log-out spots, the Empire home's log-out icon). Arestemis's existing settings sheet becomes
  this screen, its own content kept as the app's section (below).
- A sheet (large detent), title "Settings" / "Einstellungen", a Done button, grouped rows on the black wall in the
  family look (glass sections, `SectionHeading`, row title 15, secondary 12–13; one accent at most). Sections, in order:
  1. **The app's own** (optional, a view-builder slot): Arestemis's current settings (its hunt facts etc.); nothing for
     the others today.
  2. **General / Allgemein:** Language (your entry); Notifications / Mitteilungen only in apps that send them
     (Arestemis, Aresus): opens the app's page in iOS Settings, where iOS keeps them.
  3. **Help / Hilfe:** "Contact & support" / "Kontakt & Support". Brief E5 builds the form (`Shared/Support/`) at the
     same time; you build the row and open a clearly marked stub sheet (`// E5: SupportSheet goes here`). The lead
     connects them when merging.
  4. **About / Über:** Privacy / Datenschutz and Imprint / Impressum (they open the pages below in the app's language),
     "Fonts & licences" / "Schriften & Lizenzen" (an in-app page with Space Grotesk and JetBrains Mono and their OFL
     texts from `Shared/Fonts/`; the OFL asks for the licence to travel with the fonts), and the version
     ("Version 1.0 (12)", `Text(verbatim:)` for the numbers).
  5. **Account / Konto:** the account's email (keep it from the login answer's `record.email` in `EmpireSession`;
     never logged; forgotten on logout) and Log out (as destructive as each app's log-out is now; same behaviour,
     including sample mode).
- **Links in one place** (`Shared/`, one constant each): privacy `https://www.ares-empire.de/datenschutz` (German) and
  `https://www.ares-empire.de/privacy` (English); imprint `https://www.ares-empire.de/impressum` and
  `https://www.ares-empire.de/imprint`. The pages are being written now (brief E6); they may 404 until the lead deploys
  them. Open them with the system's `openURL` (Shared must not use `UIApplication.shared`).
- **The login screen** (`Shared/Design/ProvinceLogin.swift`) gets one quiet footer line: "Privacy · Imprint" /
  "Datenschutz · Impressum", opening the same pages.
- No light/dark switch (the apps stay dark; Patrik decides later).

## Done when

As in E4, plus: screenshots of the Settings screen in every app (German and English), Arestemis with its own section,
and the login screen's footer. Update `~/empire-ios/CLAUDE.md` (a short "Settings" paragraph: where it is, its
sections, how an app adds its own section).
