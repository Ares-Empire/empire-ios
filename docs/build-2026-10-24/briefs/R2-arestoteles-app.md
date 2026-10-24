# R2: the Arestoteles iPhone app (data, flows, structure; the look comes after, by the lead)

Read `COMMON.md` (same folder) first; its rules hold: only your worktree, commit on your branch but never push or
merge, no SSH, no secrets. Worktree: `~/wt/empire-ios-arestoteles` (branch `arestoteles-app`). Simulator: your own
clone of the "iPhone 17" (iOS 27.0) device named `agent-arestoteles` (`xcrun simctl create agent-arestoteles
com.apple.CoreSimulator.SimDeviceType.iPhone-17 com.apple.CoreSimulator.SimRuntime.iOS-27-0`); never use the booted
"iPhone 17". Build output in the worktree's `build/`.

## Why

Arestoteles becomes the iPhone app for Patrik's Weltbild vault (topics, positions, mechanisms, events, questions).
Read, in this order:
1. `~/ares-empire/docs/ARESTOTELES-APP.md` (the decisions; do not re-open them),
2. the API contract `~/wt/Arestoteles-app/docs/API.md` and its samples `~/wt/Arestoteles-app/docs/samples/*.json`
   (a parallel agent builds that server now; the contract is fixed: build against it, never guess fields),
3. this repo's `CLAUDE.md` (all of it: setup, one login for all apps, **Languages**, launch-argument conventions),
   `AGENTS.md` → rules, `README.md`,
4. the Arestemis app as the pattern to follow for structure: `Arestemis/Arestemis/` (`API/`, `Model/`, `Screens/`,
   `Samples/`, `ContentView.swift`, DEBUG launch arguments, sample mode, tests in `ArestemisTests/`).

**The look is not your job** (Patrik's rule: design stays with the lead). Build every screen as clean structure on
`Shared/Design` components (`ProvinceWall`, glass cards, `AppFont`, `Ink`), with the data, states and actions right;
the lead styles it afterwards. Spend your effort on the data layer, the flows and the tests.

## Build

1. **Project:** `python3 scripts/new-app-project.py Arestoteles de.ares-empire.arestoteles "Arestoteles"`; add
   `EmpireAppIdentity.arestoteles` (service `arestoteles`) and `AppAccent.arestoteles = AppAccent(color: Color(hex:
   0x5ECBBE), deep: Color(hex: 0x1E8C82))` ("Aegean teal"; the lead may tune it); the bust asset from
   `~/wt/Arestoteles-app/web/brand/aristotle-bust.png` (an image set named `Bust`, like Arestemis); URL scheme
   `arestoteles`. Login screen and loading as in Arestemis (`ProvinceLogin`, `ProvinceLoading`). Samples: copies of
   the three JSON files in `Arestoteles/Samples/`.
2. **Data layer** (`API/`, `Model/`, unit-tested): Codable models for the contract (snake_case); the API client on
   `Shared/API/HTTP.swift` (Empire token; `ETag`/`If-None-Match` → 304); one `VaultStore`: loads the last vault from
   disk first (Application Support; the app works offline), refreshes on launch, on foreground and pull-to-refresh,
   keeps lookups (notes by id, positions by id, backlinks, topics, mechanisms, events by year, questions, actors).
   **Edits:** one method per op of the contract, each sends `POST /edits` and swaps in the returned vault; `409`
   shows "changed elsewhere" and reloads, `422` shows the server's message, `pushed: false` shows that it will reach
   the laptops later. **Quick notes** also work offline: a small persisted queue, sent when the server is reachable.
   Free editing loads `GET /notes/{id}/source` and sends `edit_note` with its `version`.
3. **Text:** the contract's inline Markdown → `AttributedString` (`AttributedString(markdown:)`, inline only);
   `arestoteles://note/<id>#<anchor>` links open that note (scrolled to the heading when there is one); web links open
   Safari. One link parser for taps, deep links and Spotlight.
4. **Screens (structure):** four tabs: **Positions** (the groups of `vault.positions`; a position card: text, draft
   mark, evidence count; tap → the position page: the text, its history, the evidence notes with their summaries, the
   actions), **Topics** (the topic overviews with summary → note page), **Library** (Mechanisms with how many notes use
   each; Events as a timeline by `from` with a region filter and "what followed" from `led_to`; Questions; Actors),
   **Search** (on device: titles, summaries, text, glossary English and German; titles rank first; a type filter).
   **Note page:** title, type and confidence, summary box, the blocks (positions as cards, callouts with Adopt and
   Dismiss for `claude` ones, embeds shown inline, section links), backlinks at the end, and a toolbar: Brief (topic
   overviews: the `brief` object as a sheet), Edit (the free editor), Discuss, Confidence. **Position actions:**
   Confirm (drafts), Reword, Change my view (asks why), Drop (asks why), Add a position (on a topic overview and on
   Positions, with evidence picked from the notes). A **+ button** for quick notes, reachable from every tab.
5. **Discuss:** builds a prompt for Claude Code on the vault ("Weltbild vault, repo carlsenares/opinions: read
   CLAUDE.md first. Let's discuss <the position or note, with its path> …" plus an optional question Patrik types),
   copies it and opens `https://claude.ai/code` (the lead checks on the phone whether the Claude app opens and how
   to start a session there; keep the target URL in one constant).
6. **Spotlight:** index every note (title, summary, type) with Core Spotlight after each refresh; tapping a result
   opens the note through the link parser. Remove the index on logout.
7. **Languages:** UI text as `CLAUDE.md` → Languages says (English in code, `String(localized:)` where text is a
   `String`); run `scripts/strings.py sync`. Leave the German to the lead.
8. **DEBUG launch arguments** (`-sampleData` uses the bundled samples, edits answered from `edit-result.json` or a
   `409`/`422` with `-sampleEditConflict` / `-sampleEditInvalid`): `-tab positions|topics|library|search`,
   `-openNote <id>`, `-openPosition <id>`, `-openSheet brief|edit|quicknote|discuss`, `-sampleOffline`. Document them in
   `CLAUDE.md` → Setup state (a short "Arestoteles app" entry like the others).

## Out of scope

The visual design, a widget (needs a new target; the lead adds it), push, Siri, App Intents, the server.

## Done when

- `xcodebuild test` passes on your simulator (scheme `Arestoteles`), with tests for decoding all three samples, the
  store (cache first, refresh, 304, offline), every edit op incl. 409/422/pushed false, the quick-note queue, search
  ranking, link parsing (ids with spaces and apostrophes, anchors), the Discuss prompt, Spotlight item building.
- Every screen and sheet above opens with `-sampleData` and shows the sample's data; save screenshots of each to
  `build/r2-<screen>.png` and list them in your final message.
- `scripts/strings.py sync` ran; `scripts/strings.py check` may list German as missing (the lead adds it), nothing else.

Final message as `COMMON.md` says.
