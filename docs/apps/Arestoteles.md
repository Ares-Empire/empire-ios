# Arestoteles (iPhone)

The owner's Weltbild on the phone: positions, topics, library; read, search, note, discuss. Decisions: `ares-empire/docs/ARESTOTELES-APP.md`. Rules for every app: `CLAUDE.md`. Owner decisions are tagged "(owner, date)"; when one changes, change its line (git keeps the old one).

## Decisions and rules in force

- Lookups: position cards are one line; a position page offers Discuss, Edit and Note; nothing can be changed or
  dropped on the phone (owner, 2026-10-24).
- A note is saved and the sheet closes at once; sending happens in the background (owner, 2026-11-01).
- `-sampleVaultFile` with real notes is DEBUG only and never committed. The saved vault is used only for the saved
  login's account; files and Spotlight are forgotten on logout; a late answer never outlives a logout.

## Open

- On the phone: the Discuss hand-off (`DiscussPrompt.target`, `https://claude.ai/code`: does the Claude app open, and
  how to start a session there with the copied prompt).
- `showcase/` shows the old bust until `scripts/showcase.py` runs again.
- A widget with a position, to revisit (needs a widget target).

## As built

### Arestoteles app

**Arestoteles app** (2026-10-24, build R2): `Arestoteles/` (bundle id `de.ares-empire.arestoteles`, URL scheme
`arestoteles`), the owner's Weltbild vault on the Arestoteles API (`Arestoteles/docs/API.md`, decisions
`ares-empire/docs/ARESTOTELES-APP.md`; samples in `Arestoteles/Arestoteles/Samples/`, copies of its `docs/samples/`).
Data in `API/` + `Model/`: one `VaultStore` (the last vault from Application Support first, only for the account of
the saved login, then `GET /vault` with `If-None-Match`; one method per edit op, sent one at a time; quick notes kept
on the device until sent; forgets files and Spotlight on logout), `VaultIndex` (lookups), `VaultSearch`, `NoteLink`
(the one parser for links in notes, deep links and Spotlight), `DiscussPrompt` (target URL in one constant),
`Spotlight`. Screens in `Screens/` are structure on `Shared/Design`, not styled yet. Launch arguments (DEBUG):
`-sampleData` (edits answered with `edit-result.json`; `-sampleEditConflict` 409, `-sampleEditInvalid` 422,
`-samplePushLater` pushed false, `-sampleOffline` the sample as the saved vault and no server),
`-sampleSlowSearch` (the server's search answers after 3 s), `-tab positions|topics|library|search`,
`-library mechanisms|events|questions|actors`, `-search <query>`, `-tabSearch <query>` (in the field of the tab
`-tab` opens), `-openBestMatch <n>` (taps the n-th best match), `-openNote <id>[#<heading>]`, `-openPosition <id>`,
`-openSheet brief|edit|quicknote|discuss|discussions|reword|change|drop|add|evidence`, `-scrollToEnd` (Positions), and `-sampleVaultFile <path>` (a
vault saved from the server instead of the made-up sample, to look at real notes; DEBUG only, never committed).

### For lookups (owner, 2026-10-24)

**For lookups (owner, 2026-10-24):** position cards show the position's `title` (the bold part) cut to one line of
thought (`Lookup.cardLine`); a position page offers Discuss (now, or "later" onto the vault's to-discuss list), Edit
(wording) and Note (into the Inbox, about the position); no change/drop on the phone. Long notes open with their
sections closed (`NoteBody`), with Figures & dates, Sources and Terms (`LookupPanel`), search shows sentences first,
and pressing a paragraph or list item edits just that passage (the server's block `lines`).

### Search (2026-10-24, build E2)

**Search (2026-10-24, build E2):** Positions, Topics and Library each have a search field over their own items
(`TabSearch`, `VaultSearch`'s matching; the Library shows every kind while a query is typed). The Search tab puts the
server's best matches (`GET /search`, by words and meaning; `BestMatches`: asked once typing pauses, a newer query
cancels the older, 5 s timeout, nothing shown on failure) above the device's results; sample mode answers every
query with `Samples/search.json`.

### Notes go in the background

**Notes go in the background** (brief 75, the owner's first day on the phone, 2026-11-01: "notes lock me in the note
creation screen while waiting to be sent"): Save in a note sheet and Later in Discuss call
`VaultStore.queueQuickNote` (synchronous: the note is written to `quick-notes.json` first) and close at once; the
store's own task sends the queue in order, holding an iOS background grant (`QuickNoteBackgroundTask`) so a note saved
just before leaving the app still goes; what is left goes with the next refresh. Success is silent; the tabs'
"N quick notes waiting" counts only notes that already failed once (`failedQuickNotes`), so it never flashes after a
Save; a 422 shows the notice and keeps the note under "Not sent yet". **The vault off the main thread** (same brief;
the owner: "slight lags initially"): decoding (`ArestotelesAPI.decode`, `@concurrent`), comparing, building
`VaultIndex`/`VaultSearch`/`TabSearch` and reading/writing `vault.json` run on `VaultWorker` (one serial queue, so a
logout's delete always follows an accepted save); the main actor only assigns the results after its context and
`vaultRevision` checks, so a late answer never replaces a newer vault or outlives a logout. Measured on the simulator
with a made-up vault as large as the real one (80 notes, 305 KB, 540 passages): the main actor's share went from about
90 ms to under 0.4 ms at a launch from the saved vault, the first download and an edit's answer
(`TEST_RUNNER_VAULT_TIMINGS=1` with `-only-testing:ArestotelesTests/VaultTimingTests`). The saved vault is now read
after the first frame, so while it is read (`VaultStore.isLoadingSaved`) ContentView shows the plain
`LaunchBackground`, iOS's launch screen, not the loading screen (Claude, checked by recording launches: no flash, the
launch as long as before). DEBUG: `-quickNoteText <text>` fills the open note sheet, `-saveQuickNote` then saves.

### A queue write that fails is reported

**A queue write that fails is reported** (brief 243): a delete writes first and keeps the note on failure; a sent or
refused note changes memory at once and the disk catches up (retried on the next save, flush and foreground); the
failure shows as the notice and as a line in the quick-note sheet (`VaultStore.quickNoteQueueProblem`). One replay
window stays: a note the server accepted is sent again if the app is killed before the write succeeds (exactly once
would need the server to take a note id). DEBUG `-failQueueWrites` (sample: one waiting note, every queue write fails).
