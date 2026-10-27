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
  | Ares Empire | Email Address, Name, User ID, Device ID, Customer Support | UserDefaults `CA92.1` (language), `1C8F.1` (App Group) |
  | Aresium | Email Address, Name, User ID, Customer Support | UserDefaults `CA92.1` (theme, language), `1C8F.1`; File timestamp `C617.1` (moving an older per-account store over, brief 22) |
  | Aresium widget | none (reads the app's saved figures) | UserDefaults `1C8F.1` (the app's language) |
  | Arestemis | Email Address, Name, User ID, Device ID, Search History, Other User Content, Customer Support | UserDefaults `CA92.1`, `1C8F.1` |
  | Aresus | Email Address, Name, User ID, Device ID, Customer Support | UserDefaults `CA92.1`, `1C8F.1` |
  | Aresus widget | User ID (fetches with the shared login) | UserDefaults `1C8F.1` (the app's language) |
  | Arestoteles | Email Address, Name, User ID, Other User Content, Customer Support | UserDefaults `CA92.1`, `1C8F.1` |

  To check again after a change (no boot time, disk space or keyboards are used today; file timestamps only in Aresium):
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
| Ares Empire | Contact Info → Email Address, Name · Identifiers → User ID, Device ID · User Content → Customer Support |
| Aresium | Contact Info → Email Address, Name · Identifiers → User ID · User Content → Customer Support (all optional: only who signs in, or writes to support) |
| Arestemis | Contact Info → Email Address, Name · Identifiers → User ID, Device ID · Search History · User Content → Other User Content, Customer Support |
| Aresus | Contact Info → Email Address, Name · Identifiers → User ID, Device ID · User Content → Customer Support |
| Arestoteles | Contact Info → Email Address, Name · Identifiers → User ID · User Content → Other User Content, Customer Support |

Why these and not others:

- **User ID:** the Empire account id, carried by the login token on every request. **Device ID:** the APNs device
  token the push service keeps per account (only the apps with notifications).
- **Search History (Arestemis):** the hunt's search is stored on the server. **Other User Content:** Arestemis's
  "About you", own application text and match states; Arestoteles's edits and quick notes.
- **Name:** optional when an account is created in an app (Create account on the login screen, 2026-10-25); the
  account server keeps it, Patrik sees it when approving.
- **Not collected:** location
  (Arestemis's places are where to search, not where the phone is; IP addresses are not used for location),
  diagnostics (no crash or analytics SDK), contacts, photos, purchases, browsing history.
- **Aresium needs no account** (Patrik, 2026-10-27, brief 22): it opens without a login; Email Address, Name and User
  ID come only from someone who signs in (Settings → Ares account, only for an Aresium server of one's own) or, Email
  and Name, from Contact & support without a login (the account server's `contact` collection). The data types stay
  ticked, since the app can send them; they are still linked (an email address identifies its owner).
- **Aresium's camera and photos: nothing collected** (brief 31, 2026-10-27). Import → Scan receipt uses the camera
  through Apple's document scanner (`NSCameraUsageDescription`: "The camera scans your receipts. The photo stays on
  this iPhone and is not kept."); Choose photo uses Apple's photo picker, which needs no access to the photo library.
  The receipt is read on the iPhone (Vision), only the read lines are kept in the phone's store, never the image, and
  nothing is sent. So Photos or Videos stays unticked, and the privacy manifest is unchanged (no new required-reason
  API).
- **Aresium and Financial Info: not collected** (changed 2026-10-27). Everyone but Patrik uses phone mode: their bank
  files, payments and categories stay on their iPhone and are never sent (Apple: data processed only on the device
  is not "collected"). Server mode is only Patrik's own account (the owner list), his own data on his own server, so
  no user's financial info is collected. If server mode is ever given to someone else, tick Financial Info → Other
  Financial Info again (and the manifest).
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
| Review notes | "Every Ares Empire app needs an approved Ares account; accounts are created in any of the apps (Create account on the login screen) or on www.ares-empire.de and approved by the developer; Settings → Account deletes the account. The demo account is approved and has access to this app. Push notifications go through the developer's own push service." (+ the app's line below) |

Beta App Description (English; German in brackets for a German localization):

- **Ares Empire:** "The Ares Empire hub on the iPhone: your provinces on the ring with their live status, the
  chronicle, and each province's app one tap away." (*Der Ares-Empire-Hub auf dem iPhone: deine Provinzen im Ring mit
  ihrem aktuellen Stand, die Chronik und die App jeder Provinz mit einem Tipp.*)
- **Aresium:** "Personal finances from bank and PayPal exports: spending by month and category, receipts read on the
  iPhone, import from the share sheet, home-screen widgets." (*Persönliche Finanzen aus Bank- und PayPal-Exporten:
  Ausgaben nach Monat und Kategorie, Belege auf dem iPhone gelesen, Import über das Teilen-Menü, Widgets für den
  Home-Bildschirm.*)

**Aresium's Test Information differs** (brief 22, 2026-10-27): *Sign-in required* **No**, no demo account. Review
notes: "Aresium needs no account: it keeps your bank data on this iPhone and sorts it there; nothing about your money
is sent anywhere. To try it: choose a few categories, then import the attached made-up bank file
(Files → Aresium-Sample.csv, or share it to Aresium). Import → Scan receipt (or Choose photo) reads a shop receipt on
the iPhone; the photo is not kept. Settings → Lock turns on Face ID or a code of Aresium's own. Settings → Ares account
is only for the developer's own server and is not needed." Attach a made-up bank file to the
review notes (App Store Connect takes an attachment): the richest is the nine-month VR Bank file the DEBUG phone sample
builds (`PhoneSample.vrBankCSV` in `Aresium/Aresium/Model/PhoneSample.swift`, made-up shops and amounts), saved once
as `Aresium-Sample.csv`; the engine's small made-up fixtures in `Aresium/AresiumTests/Engine/` (`vrbank.csv`,
`dkb.csv`) work too. Never a real export.
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

Only needed once an app goes to other people (App Store or external testers): builds for Patrik alone use internal
testing, which Apple does not review (Patrik, 2026-10-25). Never the existing test account (Claude's own).

1. Sign up at `https://www.ares-empire.de/signup` with an extra address on Patrik's domain that forwards to him
   (Patrik, 2026-10-25: e.g. `review@REDACTED-DOMAIN`; his own address is his own account).
   Password from a generator, kept only in the Keychain item `empire-review-account` and in App Store Connect.
2. Confirm the email, then approve the account (Empire app → Approvals, or the PocketBase admin UI). In the admin UI
   set `services` to `empire` plus the app under review (`arestemis`, `aresus`); nothing else.
3. Give it something to show: Arestemis a paused hunt with a broad search started once, so matches exist (as with the
   test account on 2026-10-24); the Empire app's ring fills from its services.
4. Enter user name and password under *Sign-in required*. Keep the account while builds are reviewed; remove its
   services when no review is pending.

**Arestoteles and Aresus** hold only Patrik's own data and let in only their owner (`EMPIRE_ALLOWED_USERS` in each
server, 2026-10-25), so a demo account gets 403 there. **Aresus** (and Aresync) stay Patrik's own tools and never go to
others (Patrik, 2026-10-25): internal TestFlight only. Arestoteles likewise for now. **Aresium** needs no demo account
any more (above): everyone but Patrik uses it without one, on their iPhone; its server mode stays the owner's.

## Missing before the App Store

1. **Delete your account inside each app** (App Review Guideline 5.1.1(v)): Aresium needs no account at all since
   2026-10-27 (brief 22), which 5.1.1(v) asks of apps without account-based features; signing in there is optional
   and the deletion below is offered once signed in. Built 2026-10-25 (brief F2): Settings →
   Account → *Delete Ares account* (password, confirmation, `DELETE …/users/records/<id>`, logged out everywhere) and
   *Leave <app>*; the servers' deletions run from the account server (brief F1, `ares-empire/docs/ACCOUNTS.md`). The
   privacy policy says so (live 2026-10-25). Optional: the same on the website (a page on the hub); the policy also
   names deletion by email.
2. **Arestemis and the portals' terms** (Guideline 5.2.2: an app may show a third-party service's content only when
   that service's terms allow it). Arestemis reads WG-Gesucht, Kleinanzeigen and Immowelt without permission
   (`Arestemis/CLAUDE.md`: "scraping is against their terms") and shows their text and photos. Fine for private
   TestFlight use; a public App Store release needs permission or a different source. **[Patrik]**
3. **Support URL** (required on the App Store page): `https://www.ares-empire.de/kontakt` (the contact form, live
   since 2026-10-25; English `/contact`).
4. **EU trader status** (App Store Connect → Business, required for EU distribution under the Digital Services Act):
   **[Patrik]** declares himself a non-trader (private, non-commercial), or a trader, whose address and phone number
   Apple then shows on the App Store.
5. **The pages online:** done 2026-10-25 (`/datenschutz`, `/privacy`, `/impressum`, `/imprint`; Settings opens them).
   When an app opens to people besides Patrik, its section goes into the policy first (`ares-empire/docs/PRIVACY.md`).
6. Per app on the App Store page: age rating questionnaire, category, screenshots, copyright line; for Arestemis and
   Aresus the time-sensitive notification entitlement is justified by "a new flat listing / a service is down".
