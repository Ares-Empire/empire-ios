# 25: The first screen, a lighter tour with the lock and contact, and "my bank is missing"

Status: open (2026-10-27)
Repo: empire-ios · Worktree: `../empire-ios-25-first-screen` (branch `claude/25-first-screen`) · Built by: a Claude
agent (flow, data and the look)

## Goal

Patrik tried the tour and the guide (2026-10-27) and asked for:
1. **The tour's background is far too dark**: the dimmed app must stay clearly visible so people understand what they
   are looking at. Today `TourScreens.swift` lays `Ink.background.opacity(0.74)`. Make the app readable under the veil
   (about a third of that darkness, tuned by eye in light and dark), keep the highlighted control clearly set apart (the
   ring, the control at full strength), and keep the card readable on top.
2. **The first opening** shows a clear empty state, not steps and not sample data: something like "No data yet", one
   or two calm sentences on what Aresium does and that everything stays on this iPhone, and two buttons: **Start
   tour** and **Import data** (the main one). Quiet links under them: "How do I get my file?" and "Restore from an
   export". Choosing categories is no separate step any more: Import data opens the category picker first while none
   is chosen (as the import button does today), then the file picker. After the tour (finished or ended early), this
   screen comes back as long as the person has no data; the made-up data is never shown outside the tour.
3. **The tour also shows the lock and contact**: two more steps in the tour's Settings: the Lock row ("Protect
   Aresium with Face ID or a code of your own.") and Contact & support ("Questions, ideas, problems? Write to us
   here."). The tour's Settings shows those rows next to Categories; in the tour they only point and go on (tapping
   them changes nothing real: no lock is set, nothing is sent). New order: welcome, income, overview, graph, category,
   payment, switch, categories, lock, contact, import, done (12).
4. **"My bank is missing"** in the bank guide: when the search finds no bank, show the "Another bank" steps with a
   note at the top: "We don't know this bank yet. The general steps below may help." and a button **Tell us about
   your bank** that sends the typed name (editable, prefilled with the search text) to Patrik, in two taps: the name
   is already there, Send. The "Another bank" page itself has the same button at its end ("Your bank is missing? Tell
   us which one."). Sent → "Thank you. We'll look at adding it." Offline or a server error: kept and sent by itself
   later, through the **same outbox** as the bank formats (`BankFormatShare`/`BankFormatOutbox`, brief 23): generalise
   it to carry both kinds rather than copying it; the same tries, the same handling of 400 and 429; deleted with
   Aresium's data. A name that looks like personal data (the server's and `shareableLayout`'s rules: IBAN, email,
   date, amount, long digits) is refused in the app with a plain line. No account, no token.
   The request (built by brief 26 at the same time; deployed by Claude later):
   `POST https://auth.ares-empire.de/api/collections/bank_requests/records`, JSON `{"bank": "…", "app_version":
   "1.0 (12)", "language": "de"}`, header `Accept-Language`, no token; answers 200 (the record), 400 (`message` in the
   request's language, `data.bank.code` e.g. `personal_data`), 429 (rate limited, 5 an hour per address).

## Read first

`AGENTS.md`, `CLAUDE.md` ("Aresium phone mode": the first run, the tour, the guide, the unknown file and sending a
format; Languages; Light mode; the design rules). The code: `Screens/PhoneScreens.swift` (`PhoneFirstRun`),
`Screens/TourScreens.swift`, `Model/TourModel.swift`, `Model/TourData.swift`, `Screens/BankGuideScreens.swift`,
`Model/BankGuide.swift`, `Model/BankFormatShare.swift`, `Screens/FileCheckSend.swift`, `ContentView.swift`,
`Shared/Design/SettingsScreen.swift`, `Model/AppLock.swift`/`Screens/LockSettings.swift` (only to point at them).

## Settled: do not re-open

- No account; no data leaves the phone except what the person sends on purpose (a format, a bank's name, a contact
  message). The tour never touches the person's store, lock or contact.
- Contact & support without a login stays as brief 22 built it (email required so Patrik can answer, name optional).

## Done when

- `xcodebuild test` for Aresium passes (`-parallel-testing-enabled NO`) on **your own simulator** (create one, delete
  it at the end; never the booted "iPhone 17" 56D5D752…, Patrik uses it), with tests for: the first screen without
  data and its return after the tour, Import data opening the picker first, the 12 tour steps (the lock and contact
  steps change nothing real), the guide's no-match state, the bank request (body, outbox kinds, offline, 400, 429,
  a personal-looking name refused), deleting Aresium's data removing waiting requests.
- `scripts/strings.py check` 0 problems (German "du", plain), every changed screen looked at in German.
- Screenshots `build/25-*.png`: the first screen, each changed tour step (show the lighter veil), the guide's no-match
  state and the sent state, light and dark, English and German, one at the largest text size; contact sheet
  `build/25-sheet.png`. No real data (there are no real payments on this Mac and you must not look for any).
- `CLAUDE.md` updated (the first screen, the tour's steps, the bank request). Final message: files, test counts,
  screenshots, anything doubtful. Never commit, push, merge or deploy; never touch the server, any database or other
  repos.
