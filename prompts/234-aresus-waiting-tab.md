# 234: Aresus app: the "Waiting on you" tab (the board's asks on Patrik's phone)

Status: running 2026-11-06
Branch: `codex/234-waiting-tab` · Worktree: `../empire-ios-234-waiting-tab` · Model: `gpt-6.1-sol`, effort `high`

## Goal

Claude sessions on Patrik's machines ask him things (merge this fix now? turn this on?), and the questions got buried at
the end of long replies. The board (aresus server, brief 232, live) keeps every question in one list; this brief puts
that list in the Aresus app as a third tab: every open question with its answers as buttons, one tap answers; an
action is marked Done; anything can be set aside as not needed; and the session that asked can be opened in Claude.
Work for other sessions never shows here, only one quiet line counting work that no session has picked up. You build
the data, the flows and the screen's structure; Claude styles the screen afterwards.

## Read first

- `AGENTS.md` and `CLAUDE.md` (always; "Languages", "Light mode", "Settings", the Aresus app and Aresync drops entries
  under "Setup state", "Push").
- **The contract, settled:** `~/aresus/docs/API.md` → "Board (version 1, 2026-11-06)" (read only). The app uses
  `GET /board/waiting`, `POST /board/items/{id}/answer`, `POST /board/items/{id}/done`, `POST /board/items/{id}/drop`,
  with the app's Empire token like every Aresus route. Sample answer: `~/aresus/docs/samples/board-waiting.json`.
- The app: `Aresus/Aresus/Screens/AresusTabs.swift` (the tabs), `Model/AresusNavigation.swift` (links, `visibleParts`),
  `Model/AresusStore.swift` (refresh by parts, errors, sample mode), `Model/AresusSamples.swift`,
  `AresusShared/AresusAPI.swift` and `API/AresusAPI+Details.swift` (requests), `Screens/SyncScreen.swift` and
  `AresusDrops/DropsStore.swift` + `Screens/DropsSection.swift` (the newest feature, the pattern for a list with
  actions and a swipe), `Shared/Design/UndoBar.swift`, `Shared/Design/RowSwipe.swift`, `Shared/Design/EmpireDesign.swift`.

## Build

1. **Models** (`Aresus/Aresus/Model/Board.swift`): `BoardItem`, `BoardWaiting`, `BoardUnowned` decoding the contract
   leniently as the app's other models do (an unknown `state` or `kind` keeps the item out of the lists, never fails
   the whole answer). Pure helpers with `language:` for the words below (age, due date in `AppLanguage.locale`).
2. **API** (`Aresus/Aresus/API/AresusAPI+Board.swift`): the four calls. Errors as the app's others: 401 logs out
   everywhere, 403 closes the app as elsewhere, `404` = the item is gone (drop it from the list), `409` = it changed
   elsewhere (refresh, one quiet line "Already answered elsewhere." / leave German to Claude).
3. **Store** (`Model/BoardStore.swift`, owned beside `AresusStore`, refreshed with the tab like the other parts: a new
   `AresusStore.Part` or the store's own `refresh(olderThan:)`, every minute while the tab is visible and on
   foreground). **Answering waits for an undo:** a tap on an answer (or Done, or Not needed) takes the card out of the
   list at once and shows the shared undo bar ("Answered: Ship it" / "Done" / "Set aside", with Undo); the request is
   sent when the bar goes away, at once when the app leaves the foreground, and never when Undo was tapped. A failed
   send puts the card back with one quiet line on it ("Not sent. Try again.") and its buttons working again.
4. **The tab** (`Screens/BoardScreen.swift`): third tab after Aresync, title "For you", SF Symbol `tray`, badge = the
   number of open asks (none at 0). The page: header in the Aresync tab's way with the gear; the heading "Waiting on
   you"; one card per open ask in the server's order:
   - the question (`text`) as the card's title; `why` under it in muted ink; a quiet line: topic · how long it has
     waited ("aresium · 2 days") and the due date when there is one ("due Fri 7 Nov"), the due date in the status
     red when it is today or past;
   - the answers: each option a button (the first in the accent, the others plain); an ask without options (an
     action) has **Done** instead; every card has a quiet **Own answer…** (opens a sheet with one multi-line field,
     1–1000 characters, Send) and **Not needed** (`drop`); the card's long press offers Not needed and Ask in Claude
     too;
   - **Ask in Claude** (quiet, with `arrow.up.forward.app`) when `session` is set: opens
     `https://claude.ai/code/<session>` with iOS's `openURL` (outside the app, so the Claude app takes it if
     installed).
   - Then "Answered" (the `answered` list, newest first): one quiet row each, the question and "→ <answer>", with
     "waiting for the session" under it; no actions.
   - Then, when `unowned.count > 0`, one quiet line: "3 open items have no session · aresium, arestoteles". No tap.
   - Empty: "Nothing waits on you." centred in muted ink (the other lists' empty style).
5. **Link and push:** `aresus://board` opens the tab (`AresusLink.board`; tests in `AresusRoutingTests`). The daily
   push carries it.
6. **Sample mode:** `Aresus/Aresus/Samples/board-waiting.json` = a copy of the server's sample; answers in sample mode
   only pretend (as drops do). DEBUG launch arguments: `-tab board`, `-sampleBoardEmpty`, `-sampleBoardManyAsks` (eight
   asks, long text, for scrolling), `-openOwnAnswer <id>`, `-sampleBoardFailed` (the next send fails).
7. **Tests** (`AresusTests/BoardTests.swift`): decoding the sample and lenient decoding; the words in English and German
   (`language: .german`); the store: answer, done, drop, undo cancels, leaving the foreground sends at once, a failed
   send puts the card back, 404 and 409; the badge count; the link.

## Settled: do not re-open

- A third tab, "For you", not a section in the Aresus tab: the watchtower tab is about the server; this is Patrik's
  own list, and the badge must be visible from anywhere in the app.
- Only asks and the unowned count show; work items never do (Patrik, 2026-11-06: work goes to sessions, not to him).
- Answers wait for the undo bar before they are sent: the server has no way to take an answer back.
- Ask in Claude opens outside the app (iOS's `openURL`), not the in-app browser: the Claude app should take the link.
- The screen's look is Claude's: build it as plain structure on the shared pieces (`GlassCard`, `Ink`, the app's
  accent, the existing fonts), no new decoration; Claude restyles it after review.

## Out of scope

- The widget, the server, `project.pbxproj` (folder-synchronized groups pick up new files), German translations
  (list the new strings in your final message; Claude writes the German).

## API

`~/aresus/docs/API.md` → Board: `GET /board/waiting` → `Waiting`; `POST /board/items/{id}/answer` `{"answer"}` →
`Item`; `POST /board/items/{id}/done` → `Item`; `POST /board/items/{id}/drop` → `Item`. Base URL and auth as every
Aresus call (`AresusAPI`). Nothing else.

## Done when

- `xcodebuild test -scheme Aresus` passes on your own simulator (`codex-234`), with the new tests above.
- The tab shows the sample on the simulator: `build/234-board.png` (`-sampleData -tab board`), `build/234-empty.png`
  (`-sampleBoardEmpty`), `build/234-own-answer.png` (`-openOwnAnswer 1`), in light and dark.

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the new strings, what is missing or doubtful.
