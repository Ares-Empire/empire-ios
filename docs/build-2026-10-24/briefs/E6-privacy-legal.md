# E6: privacy policy, imprint, and what Apple needs from each app

Read `E-COMMON.md` first. Worktrees: `~/wt/ares-empire-legal` (branch `legal`: the inventory, the pages) and
`~/wt/empire-ios-legal` (branch `legal`: the apps' privacy manifests and settings). You may read every Ares repo in
`~` (`aresium`, `Arestemis`, `aresus`, `aresync`, `Arestoteles`, `ares-empire`, `empire-ios`, …) to learn what data
they handle; change only your two worktrees. No SSH.

## Why

Patrik (2026-10-24) wants the apps to "feel legit" for other users and asked: "should we do things like Impressum,
privacy page etc?" The lead's answer: yes, before anyone besides Patrik uses an app. A privacy policy is needed under
the GDPR as soon as the apps handle other people's data, and Apple asks for its link in App Store Connect (TestFlight for
outside testers, and the App Store). An imprint (Impressum) is the safe choice in Germany for apps offered to the
public. You draft; Patrik approves the text before anything goes online; the lead deploys.

## 1. The inventory (`ares-empire/docs/PRIVACY.md`)

From the code and docs (not guesses), per service and app: which personal data it handles (account email and name,
login tokens, IP addresses in logs, push device tokens and language, Aresium's transactions, Arestemis's search
profile including the facts the AI may use such as gender and age, Aresus's machine reports, the Arestoteles vault,
support messages from brief E5), where it is stored, for how long, who else receives it (Resend for email, Groq for
Arestemis's AI checks, Apple for push, Telegram while it is still used, GitHub for the vault repository, the host),
and the legal basis. Facts the lead gives you: the server is a netcup VPS in Germany; DNS at Hetzner; email through
Resend (`smtp.resend.com`); the iPhone apps contain no analytics, ads or tracking. Mark anything you could not confirm
from the code with **[lead to confirm]**.

## 2. The pages (German and English)

- **Datenschutzerklärung / Privacy policy** from the inventory: plain language ("du" in German, like the apps), every
  item GDPR Art. 13 needs (controller, data, purposes, legal bases, recipients, transfers outside the EU and their
  safeguards, retention, rights incl. the complaint to the supervisory authority for Bavaria, BayLDA), no tracking.
- **Impressum / Imprint** (§ 5 DDG): Patrik Breeck, the address as the placeholder `[ADDRESS]` (Patrik decides which
  address), contact: the owner's email (the owner file, see ares-empire `docs/PRIVACY.md`).
- Served by the hub **without login** at `https://www.ares-empire.de/datenschutz`, `/privacy`, `/impressum`,
  `/imprint` (find how the hub serves pages: `webauth/server.py` and its open paths, `web/`), in the hub's look,
  each with a link to the other language. These are an exception to "websites stay English" (legal pages in Germany are
  in German). Tests for the open paths if the hub has them (`python3 -m unittest webauth/test_server.py`).

## 3. What Apple needs, per app (`empire-ios`)

- A privacy manifest `PrivacyInfo.xcprivacy` for each app and each widget extension: no tracking, no tracking
  domains, the collected data types (what Apple's categories call them, linked to the user, for app functionality),
  and the required-reason APIs the code really uses (search for `UserDefaults`, file timestamps, disk space, boot time)
  with their reason codes. Make sure each file is in its target's resources (folder-synchronized groups; check the
  built `.app`).
- `ITSAppUsesNonExemptEncryption = NO` for each app (only HTTPS), so uploads skip the export question.
- `empire-ios/docs/APP-STORE.md`: per app, the answers for App Store Connect's "App Privacy" form, and the TestFlight
  "Test Information" (beta description, feedback email, privacy policy link, the note that a demo login is needed and
  how the lead makes one), plus what is still missing before the App Store (deleting your account inside the app,
  which Apple asks of apps with accounts; anything else you find).

## Done when

- The builds of all five apps pass with the manifests (each `.app` contains them); the hub's tests pass.
- Final message: the open **[lead to confirm]** points, the questions only Patrik can answer, the deploy steps for the
  pages. Never put a real address or other personal data into the files; the placeholder stays.
