# App Store Connect: privacy answers, TestFlight test information, what is missing

**Written 2026-10-24** (brief E6). The facts behind every answer: `ares-empire/docs/PRIVACY.md` (what each service
stores, where, how long, who else gets it). The pages: `https://www.ares-empire.de/privacy` (English),
`/datenschutz` (German), `/imprint`, `/impressum`; they answer 404 until Patrik approved the text and the lead
filled the placeholders.

## In the projects (done)

- **Privacy manifests** `PrivacyInfo.xcprivacy` in each app folder and each widget folder (folder-synchronized, so
  they land in the bundle by themselves; `scripts/new-app-project.py` creates the baseline for a new app). No
  tracking, no tracking domains. Checked 2026-10-24 on Release builds for iPhone: every `.app` and `.appex` contains
  its manifest, and each binary imports only the required-reason APIs its manifest declares (2026-10-25, brief G1:
  `CA92.1` for the app's own language setting in every app, `1C8F.1` in both widgets, which read the app's language
  choice from their App Group; `nm` on Release builds of Aresus and Aresium):

  | Bundle | Collected (all linked to the account, App Functionality, no tracking) | Required-reason APIs |
  |---|---|---|
  | Ares Empire | Email Address, User ID, Customer Support | UserDefaults `CA92.1` (language), `1C8F.1` (App Group) |
  | Aresium | Email Address, User ID, Other Financial Info, Customer Support | UserDefaults `CA92.1` (theme, language), `1C8F.1` |
  | Aresium widget | none (reads the app's saved figures) | UserDefaults `1C8F.1` (the app's language) |
  | Arestemis | Email Address, User ID, Device ID, Search History, Other User Content, Customer Support | UserDefaults `CA92.1`, `1C8F.1` |
  | Aresus | Email Address, User ID, Device ID, Customer Support | UserDefaults `CA92.1`, `1C8F.1` |
  | Aresus widget | User ID (fetches with the shared login) | UserDefaults `1C8F.1` (the app's language) |
  | Arestoteles | Email Address, User ID, Other User Content, Customer Support | UserDefaults `CA92.1`, `1C8F.1` |

  To check again after a change (no file timestamps, boot time, disk space or keyboards are used today):
  `nm -u <App>.app/<App> | grep -E "NSUserDefaults|stat|getattrlist|mach_absolute_time|systemUptime|Volume.*Capacity|activeInputModes"`
  on a Release build, or Xcode → Organizer → an archive → *Generate Privacy Report*.
- **Encryption:** `ITSAppUsesNonExemptEncryption = NO` in each app's `Info.plist` (only HTTPS through Apple's
  frameworks), so uploads skip the export-compliance question.
- "Customer Support" is the *Contact & support* form (brief E5). If an app ships without it, drop that entry from its
  manifest and its form.

## App Privacy (App Store Connect → the app → App Privacy)

For every app: **"Do you or your third-party partners collect data from this app?" Yes.** For each data type below:
*linked to the user's identity:* **Yes**; *used for tracking:* **No**; *purposes:* **App Functionality** only.
**Privacy Policy URL:** `https://www.ares-empire.de/privacy` (a German localization, if added, gets `/datenschutz`).

| App | Data types to tick (App Store Connect's names) |
|---|---|
| Ares Empire | Contact Info → Email Address · Identifiers → User ID · User Content → Customer Support |
| Aresium | Contact Info → Email Address · Financial Info → Other Financial Info · Identifiers → User ID · User Content → Customer Support |
| Arestemis | Contact Info → Email Address · Identifiers → User ID, Device ID · Search History · User Content → Other User Content, Customer Support |
| Aresus | Contact Info → Email Address · Identifiers → User ID, Device ID · User Content → Customer Support |
| Arestoteles | Contact Info → Email Address · Identifiers → User ID · User Content → Other User Content, Customer Support |

Why these and not others:

- **User ID:** the Empire account id, carried by the login token on every request. **Device ID:** the APNs device
  token the push service keeps per account (only the apps with notifications).
- **Search History (Arestemis):** the hunt's search is stored on the server. **Other User Content:** Arestemis's
  "About you", own application text and match states; Arestoteles's edits and quick notes.
- **Not collected:** Name (the apps never ask; the account's name field is empty unless set through the API), location
  (Arestemis's places are where to search, not where the phone is; IP addresses are not used for location),
  diagnostics (no crash or analytics SDK), contacts, photos, purchases, browsing history.
- **Groq** (Arestemis's AI check) is a processor working for the app's function; its data is already covered by the
  types above.
- **[Patrik to decide] Arestoteles and "Sensitive Info":** the vault holds political views, which Apple counts as
  sensitive. While only Patrik uses the app (internal TestFlight), the form is not needed; before anyone else gets it,
  tick *Sensitive Info* as well, or keep the app private.

## TestFlight → Test Information

Fill once per app (the same for every build); *What to Test* is written per build. Needed for **external** testers;
internal testers (App Store Connect users, up to 100) need no Beta App Review.

| Field | Value |
|---|---|
| Feedback Email | `REDACTED-EMAIL` |
| Privacy Policy URL | `https://www.ares-empire.de/privacy` |
| Marketing URL | empty (the hub needs a login), or `https://www.ares-empire.de` |
| Contact (Beta App Review) | Patrik Breeck, `REDACTED-EMAIL`, phone: **[Patrik]** (entered in App Store Connect only, never here) |
| Sign-in required | **Yes**: the demo login below |
| Review notes | "Every Ares Empire app needs an approved Ares Empire account; accounts are created on www.ares-empire.de and approved by the developer. The demo account is approved and has access to this app. Push notifications go through the developer's own push service." (+ the app's line below) |

Beta App Description (English; German in brackets for a German localization):

- **Ares Empire:** "The Ares Empire hub on the iPhone: your provinces on the ring with their live status, the
  chronicle, and each province's app one tap away." (*Der Ares-Empire-Hub auf dem iPhone: deine Provinzen im Ring mit
  ihrem aktuellen Stand, die Chronik und die App jeder Provinz mit einem Tipp.*)
- **Aresium:** "Personal finances from bank and PayPal exports: spending by month and category, import from the share
  sheet, home-screen widgets." (*Persönliche Finanzen aus Bank- und PayPal-Exporten: Ausgaben nach Monat und
  Kategorie, Import über das Teilen-Menü, Widgets für den Home-Bildschirm.*)
- **Arestemis:** "Flat hunting: set a search, start the hunt, and get every new listing from WG-Gesucht,
  Kleinanzeigen and Immowelt that an AI checked against your whole search, with an application text ready to copy."
  (*Wohnungssuche: Suche festlegen, Jagd starten und jedes neue Angebot von WG-Gesucht, Kleinanzeigen und Immowelt
  bekommen, das eine KI gegen deine ganze Suche geprüft hat, mit einem Bewerbungstext zum Kopieren.*)
- **Aresus:** "The status of the Ares Empire's services and the sync runs of its computers, with widgets and a
  notification when something breaks." (*Der Zustand der Dienste von Ares Empire und die Sync-Läufe seiner Rechner,
  mit Widgets und einer Mitteilung, wenn etwas ausfällt.*)
- **Arestoteles:** "A reader and editor for a personal knowledge vault: positions, topics, mechanisms and events,
  searchable in English and German." (*Lesen und Bearbeiten einer persönlichen Wissenssammlung: Positionen, Themen,
  Mechanismen und Ereignisse, durchsuchbar auf Deutsch und Englisch.*)

### The demo login (the lead makes it)

Never the existing test account: it has the `arestoteles` service, which opens Patrik's own vault.

1. Sign up at `https://www.ares-empire.de/signup` with a mailbox the lead can read (**[Patrik]**: which address).
   Password from a generator, kept only in the Keychain item `empire-review-account` and in App Store Connect.
2. Confirm the email, then approve the account (Empire app → Approvals, or the PocketBase admin UI). In the admin UI
   set `services` to `empire` plus the app under review (`arestemis`, `aresus`); nothing else.
3. Give it something to show: Arestemis a paused hunt with a broad search started once, so matches exist (as with the
   test account on 2026-10-24); the Empire app's ring fills from its services.
4. Enter user name and password under *Sign-in required*. Keep the account while builds are reviewed; remove its
   services when no review is pending.

**Aresium and Arestoteles** show only Patrik's own data (Aresium lets in only `EMPIRE_ALLOWED_USERS`), so a demo
account would see nothing (Aresium answers 403). Keep both on internal TestFlight, or give them a demo mode on the
server before external testing. **Aresus** would show a reviewer the real server's state (service names, machine
names, commit subjects): **[Patrik]** whether that is acceptable, else internal only as well.

## Missing before the App Store

1. **Delete your account inside each app** (App Review Guideline 5.1.1(v): apps that let people create an account
   must let them start its deletion in the app; the apps link to sign-up). Suggested: Settings → Account → *Delete
   account* (Shared, next to Log out from brief E4b), confirm, unregister push, then
   `DELETE https://auth.ares-empire.de/api/collections/users/records/<id>` with the token (the account rules already
   allow it for non-admins), then log out everywhere. The servers must follow: Arestemis deletes the account's hunts,
   settings and matches, the push service its devices (today they stay; see PRIVACY.md → Open 1). The same on the
   website (a page on the hub).
2. **Arestemis and the portals' terms** (Guideline 5.2.2: an app may show a third-party service's content only when
   that service's terms allow it). Arestemis reads WG-Gesucht, Kleinanzeigen and Immowelt without permission
   (`Arestemis/CLAUDE.md`: "scraping is against their terms") and shows their text and photos. Fine for private
   TestFlight use; a public App Store release needs permission or a different source. **[Patrik]**
3. **Support URL** (required on the App Store page): a public page, e.g. a short `/support` on the hub naming
   `REDACTED-EMAIL` and the in-app form, or the imprint.
4. **EU trader status** (App Store Connect → Business, required for EU distribution under the Digital Services Act):
   **[Patrik]** declares himself a non-trader (private, non-commercial), or a trader, whose address and phone number
   Apple then shows on the App Store.
5. **The pages online:** Patrik approves the text, the lead fills `[ADDRESS]` and every `[lead to confirm]`
   (`ares-empire/docs/PRIVACY.md`), and the Settings links (brief E4b) then open them.
6. Per app on the App Store page: age rating questionnaire, category, screenshots, copyright line; for Arestemis and
   Aresus the time-sensitive notification entitlement is justified by "a new flat listing / a service is down".
