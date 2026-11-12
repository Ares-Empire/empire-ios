# 268: Arestemis app: look score and 👍/👎 votes

Status: draft
Branch: `codex/268-arestemis-look-votes` · Worktree: `../empire-ios-268-look-votes` · Model: `gpt-6.1-sol`, effort
`high` (models, API client, store and tests in known code; the workhorse is enough and the weekly allowance has to
last until 11-17). The look of the new controls is Claude's (a Claude Opus design agent after this build).

## Goal

Patrik's men's fur coat hunt is judged by Claude from the photos (server brief 267, "look"). He teaches it with
👍/👎. After this, the app keeps a search's look when it is edited, shows the look score and reason on a finding,
and sends his votes on findings and on filtered-out listings of a look hunt.

## Read first

- `AGENTS.md` and `CLAUDE.md` (always)
- The server contract: `~/Arestemis-267-look-check/docs/API.md` (the server worktree), the parts marked "brief 267" (read only; the branch is
  `codex/267-look-check` until it merges, the fields are final)
- `Arestemis/Arestemis/Model/ItemModels.swift` (`ItemSearch`), `Model/ArestemisModels.swift` (`Match`, `Rejected`),
  `API/ArestemisAPI.swift`, `Model/ArestemisStore.swift` (`setState`, the reject action), `Screens/MatchDetailScreen.swift`,
  `Screens/MatchRow.swift`, `Screens/ListingRows.swift`, the filtered-out list (`GET /rejected`)

## Build

1. **Keep the look on edit.** `ItemSearch` gains `look: String = ""` and `lookMin: Int = 6` (`look_min`), decoded
   when present (a server or search from before them has none) and always sent back, so editing a look hunt in the
   app never wipes them. No editor field for them in this brief.
2. **Models.** `LookVerdict` (`score` Int, `length`, `cut`, `fur` as enums with an unknown fallback, `reason`,
   `reasonDE` = `reason_de`); `Match.look: LookVerdict?`, `Match.vote: Vote?`; `Rejected.vote: Vote?`. `Vote` is
   `up`/`down`; absent or null = no vote. Decoding never fails on a value it does not know.
3. **API.** `vote(_ vote: Vote?, match id: Int) async throws -> Match` → `POST /matches/{id}/vote` with
   `{"vote": "up" | "down" | null}`; `vote(_ vote: Vote?, rejected id: Int) async throws` → `POST /rejected/{id}/vote`
   (returns `{id, vote}`). Mock transport answers in the existing test style.
4. **Store.** `setVote(_:for match:)` and `setVote(_:forRejected:)`: optimistic update of the stored match/entry, roll
   back and show the existing error banner on failure; tapping the active vote again clears it (sends null).
5. **Structure only (Claude styles it afterwards):** on the match detail screen of an item finding with `look`, a
   line with "Look n/10" and the German or English reason (the app's language), and two buttons 👍/👎 bound to the
   store; the same two buttons on each filtered-out entry of a hunt whose search has a non-empty `look`. Use plain
   existing components (no new colours, no shadows); accessibility labels "Good find" / "Not it" (strings in the
   String Catalog; leave the German to Claude, list the keys you added).
6. **Samples and tests.** Add made-up samples (a match with `look` and `vote`, a rejected entry with `vote`) and unit
   tests: decoding with and without the fields, encoding `ItemSearch` keeps `look`/`look_min`, the two requests'
   paths and bodies, optimistic update and rollback, clearing by tapping the active vote.

## Settled: do not re-open

- Votes only teach the server's future judgments; the app does not move a voted entry between lists.
- 👍/👎 show only where the server can use them (item findings with a look; filtered-out entries of look hunts).

## Out of scope

The visual design of the controls (Claude, next), editing `look` in the app, reference photo upload, any server change.

## API

From `~/Arestemis-267-look-check/docs/API.md` (brief 267): `ItemSearch.look`, `ItemSearch.look_min`, `Match.look` (`LookVerdict`),
`Match.vote`, `Rejected.vote`, `POST /matches/{id}/vote`, `POST /rejected/{id}/vote`.

## Done when

- `bash scripts/test-unit.sh Arestemis` passes, with the new tests (Claude runs xcodebuild/simulator checks if your
  environment cannot).
- The match detail sample with a look shows the score line and the two buttons on the simulator; screenshot to
  `build/268-match-detail.png`.

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, strings added, what is missing or doubtful.
