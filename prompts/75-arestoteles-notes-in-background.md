# 75: Arestoteles: a note closes at once and is sent in the background; no lag when the vault arrives

Status: running
Branch: `codex/75-arestoteles-background` · Worktree: `../empire-ios-75-arestoteles-background` · Model: `gpt-6.1-sol`, effort `high`

## Goal

Patrik's first day with Arestoteles on his iPhone (build 1, 2026-11-01): "Notes lock me in the note creation screen
while waiting to be sent. Let's close the screen once Speichern is clicked and the sending happens in the background."
And: "I noticed slight lags initially." After this brief, Save in a note sheet (and Later in Discuss) closes the sheet
at once while the note goes to the server by itself, and the app's own work when a vault arrives or loads no longer
holds the main thread.

## Read first

- `AGENTS.md` and `CLAUDE.md` (always; "Arestoteles app" under Setup state)
- `Arestoteles/Arestoteles/Model/VaultStore.swift` (`addQuickNote`, `flushQuickNotes`, `send(_ note:)`, `refresh`,
  `loadFromDisk`, `accept`, `apply`, `updateSpotlight`, `context`/`isCurrent`), `Model/Persistence.swift`,
  `API/ArestotelesAPI.swift`, `Model/VaultIndex.swift` and the search types `apply` builds
- `Arestoteles/Arestoteles/Screens/Sheets.swift` (`QuickNoteSheet`'s Save, `DiscussSheet`'s Later),
  `Screens/Style.swift` (`StatusLine`), `ContentView.swift` (the notice)
- The tests in `Arestoteles/ArestotelesTests/` (`StoreTests` and friends)
- Note: the project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so code without an annotation runs on
  the main actor; work meant for elsewhere needs `nonisolated` / `@concurrent` or an actor of its own.

## Build

### Part A: Save closes the sheet; sending happens in the background

Today `addQuickNote` appends the note to the phone's queue, saves the queue to disk, then **awaits** the server
(commit, rebuild, push to GitHub) before the sheet may close; the sheet stays open with its text, so Patrik waits.

1. **The store queues and returns.** `VaultStore` gets a synchronous way to add a note (for example
   `queueQuickNote(_:about:kind:now:) -> QuickNoteOutcome` with `.empty` / `.queued`): validate as today, append, save
   the queue to disk (so nothing is lost if the app is closed right after), then start sending in a task the store owns
   (`flushQuickNotes`, still one at a time, in order, through `serially`). Remove or adapt the async `addQuickNote` so
   there is one path; keep the tests' ability to wait until sending settled (as `spotlightSettled` does).
2. **Both sheets close at once.** `QuickNoteSheet`'s Save and `DiscussSheet`'s Later call it and `dismiss()` right
   away when the outcome is not `.empty`. The sheet's "Saved on the phone. It goes to the Inbox once the server can be
   reached." line and its `waitingNow` state go (no longer reachable). The sheet's "Not sent yet" list stays.
3. **iOS gives it time.** While the queue is being sent, hold a background task (`UIApplication.shared
   .beginBackgroundTask(withName:expirationHandler:)`, ended when the flush ends or iOS expires it), so a note saved
   right before leaving the app still goes. Whatever is not sent goes when the app next refreshes (today's
   `refresh` → `flushQuickNotes`).
4. **What Patrik sees afterwards:**
   - Sent: nothing (as every other successful edit).
   - The tabs' `StatusLine` "N quick notes waiting to be sent" counts only notes that **already failed** to send at
     least once (offline or a server error), not one on its first try, so it does not flash up after every Save.
     Keep this state in the store (for example a set of ids tried and not sent), not in a view.
   - Refused by the server (422): as today, the notice "A quick note was not saved: …" and the note stays in "Not sent
     yet".
   - Offline: as today, the offline line plus the waiting line.
   - A logout while a note is on its way: as today (the context check); the queue goes with the logout.

### Part B: the lag when a vault loads or arrives

Measure first, then fix, then measure again. The moments:

1. **Launch with a saved vault:** `loadFromDisk` reads and decodes `vault.json` and calls `apply`.
2. **The first download** (no saved vault): `GET /vault` decoded, then `apply` (compare, build `VaultIndex`,
   `VaultSearch`, `TabSearch`, Spotlight, encode and write `vault.json`).
3. **The answer to an edit or a quick note:** `accept(result)` → `apply` with the whole new vault the server sends back.

Use a **made-up vault as large as the real one** (80 notes, about 0.32 MB of vault JSON, about 540 search passages,
29 or more positions): build it from the bundled samples (repeat and rename notes) in a test helper; never the real
vault. Time the main actor's share of each moment (a `ContinuousClock` measurement around the main-actor work, or
signposts read in a test), as an opt-in timing test like Aresium's `PickerTimingTests` (an environment variable turns
it on; it reports numbers, it does not fail on them).

Then move the heavy parts off the main actor: decoding (the API's and the file's), comparing the old and new vault,
building the index and search structures, and encoding plus writing `vault.json`. Only assigning the finished results
stays on the main actor, after an `isCurrent(context)` check, so a late result never replaces a newer vault, never
survives a logout, and the Spotlight order (`updateSpotlight`'s chain) holds. Keep the files' data protection and the
backup exclusion from brief 74.

## Settled: do not re-open

- The note is safe once it is in the queue on disk; closing the sheet then is right. No "Saved" toast or banner on
  success.
- Other edits (reword, edit a passage, confidence, …) keep waiting for the server's answer: they can conflict (409)
  and show its result. Only quick notes and Later marks change.
- No change to the API, the server, the login or what is stored.

## Out of scope

- The look of any screen (no new colours, components or texts beyond removing the one line above).
- `project.pbxproj`, `Shared/`, other apps, the Arestoteles server.

## API

None new. Quick notes: `POST /edits` with `{op: "quick_note", text, about?, kind?}` as today
(`~/Arestoteles/docs/API.md`).

## Done when

- `xcodebuild test -project Arestoteles/Arestoteles.xcodeproj -scheme Arestoteles` passes on your own simulator
  `codex-75`, with new tests for: queueing returns at once and the note is on disk before any network; sending
  continues after the caller is gone; the waiting count leaves out a note on its first try and includes it after a
  failure; a 422 keeps it aside with the notice; a logout during sending; a late vault never replaces a newer one or
  outlives a logout; the vault file still excluded from backup.
- The timing numbers for the three moments, before and after, in your final message (and the command to run them).
  Aim: none of the app's own main-actor work in these moments above about 16 ms (one frame) on the simulator; if
  something stays above, say what and why.
- Screenshots: the Positions tab right after Save (sheet closed), `build/75-after-save.png`, using the sample mode
  (`-sampleData`, `-openSheet quicknote`; type with a launch argument if one exists, else describe how you checked).

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines (tests run, failures), the timing table
(before / after), what is missing or doubtful, and any UI string removed or added.
