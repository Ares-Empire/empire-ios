# Aresium (iPhone)

Aresium on the iPhone: phone mode (everyone's data on their own iPhone, no account) and the owner's server mode (in the
code, unused since 2026-10-31). The engine is aresium's TypeScript (`aresium/src/engine`), bundled by
`scripts/aresium-engine.sh`. Plan and decisions for other people: `ares-empire/docs/ARESIUM-FOR-OTHERS.md`. Rules for every app: `CLAUDE.md`. Owner decisions are tagged "(owner, date)"; when one changes, change its line (git keeps the old one).

Read this page, then only the topic file for your task.

## Topics

| Topic | File | Covers |
|---|---|---|
| Phone mode, storage and the engine | `docs/apps/aresium/storage-and-engine.md` | the two modes, the store and its schema versions, moving over, the bundled engine and local places, Settings' and the picker's timings, targets and Info.plist, Fonts & licences, the phone-mode launch arguments |
| Names, shops and search | `docs/apps/aresium/names-and-search.md` | payment names and own names, shop identities, one bank name per shop, renaming and a name's page, "All from <name>", name search, a day's page |
| Categories and sorting | `docs/apps/aresium/categories-and-sorting.md` | counting as it happened, category names/rename/removal, category sides, Save in Add asks, quick sort, New category where a category is chosen |
| Selecting several payments | `docs/apps/aresium/selecting-several.md` | the selection data API, selecting on screen, renaming several, selecting by sliding |
| Money paid back | `docs/apps/aresium/money-paid-back.md` | linking a payment in to the expense it pays back, the amounts, the lists, several at once, whether it comes off the totals |
| Monthly average and fixed costs | `docs/apps/aresium/average-and-fixed-costs.md` | the average line under Overview's total, fixed and regular payments, Not fixed |
| Dashboard, lists and the graph | `docs/apps/aresium/dashboard-and-graph.md` | adding up names in a list, which month Current shows, the payment page, comfort on the dashboard, the graph and the header, reading a graph, the graph moving away |
| Lock, widget and messages | `docs/apps/aresium/lock-widget-messages.md` | the widget snapshot, the lock, local messages and their settings, notification taps |
| First run, import, bank guide, tour, files from outside | `docs/apps/aresium/first-run-and-import.md` | the first screen, Start tour, an unknown bank's file, My bank is missing, How do I get my file?, the tour, files from outside and dropped files |
| Receipts and cash | `docs/apps/aresium/receipts-and-cash.md` | receipts read from a photo, correcting receipts, cash entries, comfort in the windows |

## Decisions and rules in force

- No account: Aresium opens in phone mode without a login. Phone-mode data stays on the iPhone (imports, categories,
  storage); other people's bank data never reaches the server; the owner's own aresium.de data stays on the server
  (owner, 2026-10-25 and 2026-10-27). It offers no sign-in (owner,
  2026-11-02). Server mode stays in the code, unused since 2026-10-31 (`APP_SERVER_MODE_USERS` is empty).
- The data belongs to the iPhone, not to a login: logout, Leave and deleting the account never touch it; only Delete
  Aresium data or the lock's "Forgot the code?" removes it, together with sums, message settings and history and the
  bank outbox.
- It never registers a push device: messages are local only (`UNUserNotificationCenter`, alert and sound, no badge).
- A SwiftData model change always adds the next schema version, never edits one in place; every older export keeps
  restoring.
- The bank's original fields stay as they came: sorting, learning and receipt matching use them, and stored learning
  and rename rules stay keyed by merchant (display grouping may use a shop identity or an own name).
- The engine bundle is never edited by hand and its patterns are never copied into Swift; a new engine layout field
  needs a Swift twin, or saving drops it.
- Counting as it happened: every payment counts once, in the direction it went; no netting, no Refunds row; the only
  exceptions are cash covered by receipts and money paid back (owner, 2026-11-01).
- A category's side decides only where it is offered, never where its money counts; menus stay short (owner,
  2026-11-01).
- Money paid back is linked only by hand, nothing is matched automatically; it stays optional and quiet: no prompts
  after an import, no badges, no offers anywhere else (owner, 2026-11-02). Euros only for now. Taking it off the
  totals is on by default (owner, 2026-11-18).
- Renaming opens with a single tap; the row swipe goes left only, with no direction setting; rows get no double tap,
  which would delay every tap (owner, 2026-10-30).
- The quick sort never changes an already sorted payment and never asks the shop question; its cards are "names",
  never "payees" or "Absender".
- Adding up names changes only how a list shows: totals, the export and the engine never change, and the choice is
  kept outside the export.
- The tour is never offered by itself; it explains everything coherently, so it is updated when a feature changes what the app does (owner,
  2026-10-31); its veil stays light (owner, 2026-10-27). Its made-up data never shows outside it, and it never opens
  the person's store, changes settings, sets a lock, schedules a message, asks iOS anything or sends anything.
- Import opens the file picker at once; in phone mode the category picker is offered after an import adds payments,
  only while no categories have been chosen (owner, 2026-10-27).
- Import texts use plain words, never "CSV" or format names, and the bank guide names no sources (owner, 2026-10-27);
  the fallback column picker shows the file's own headers, and the guide may quote the bank's own labels.
- Info.plist document types exclude `.txt`, so Aresium isn't offered for every text file; ZIP, XLSX and XLS are
  declared since the engine reads them (build 25).
- A receipt's total and card-or-cash choice are never learned; cash entries never join bank payments and never teach
  a category. A receipt image is never written and is released after reading; only the read rows and confirmed
  values are kept.
- Bundled data's memory budget (Claude's decision, 2026-11-01): under 25 MB may stay loaded for the app's lifetime;
  25–60 MB must unload after sorting and keep at most 5 MB; above 60 MB is not allowed. Server mode never loads the
  local places list.
- Security: the store uses complete file protection. The lock code is a salted PBKDF2-SHA256 hash (310,000 rounds) in
  Aresium's own Keychain group, named explicitly, `AfterFirstUnlockThisDeviceOnly`; wrong codes cause growing waits
  that survive a restart, and a clock set back never shortens one; a Keychain lock left from a deleted install is
  removed; the lock is optional and off by default; when on, it takes effect at launch and after more than 10 seconds in the
  background; "Forgot the code?" deletes the data.
- While the lock is on: widgets show only "Locked" and no numbers are kept; while the app is locked, shared files wait unread; messages hide
  amounts and day counts; turning the lock on clears delivered messages. Message progress stores no amounts.
- Sharing a bank's format is offered only for a confirmed layout that passes `shareableLayout`, and sends only the layout, bank name, app version and language, without a token; a
  name that looks like personal data (IBAN, email, date, amount, long number) is not sent, and the server checks
  again. Bank requests go without a token.
- Copies of shared files are removed once read; leftovers are cleared at the next launch.

## Open

- Money paid back in currencies other than the euro.
- The local places file at `aresium.de/osm/local-places-de.places.bin.gz`: hosting it was left as a deployment step on
  2026-11-01; check whether it was done.
