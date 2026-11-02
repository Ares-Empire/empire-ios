# 216: Fixed costs: fewer false finds

Status: running
Branch: `codex/216-fixed-costs-sharper` (from `claude/209-fixed-costs-screens`, which holds briefs 208 and 209) ·
Worktree: `../empire-ios-216-fixed-costs-sharper` · Model: `gpt-6.1-sol`, effort `high` · Simulator: `codex-216`
(create it: iPhone 17, iOS 27.0)

## Goal

Brief 208's detection (`Model/FixedCosts.swift`) finds the real fixed costs, but also things that are not. On the
screens' made-up sample (brief 209) a supermarket and a bouldering hall visited about once a month show as monthly fixed
costs, and two restaurant visits about six months apart show as a half-yearly one. Claude ran the detection on Patrik's
own export, locally (nothing of it in this brief): the subscriptions, the transit ticket, a membership and the ended
rent were right, but a supermarket came out as a **yearly** fixed cost (two similar purchases a year apart among dozens
of others), and a gym as half-yearly from two payments. Testers will judge the page by its first rows: make the finds
trustworthy, keeping every real one.

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Monthly average and fixed costs — data API", brief 208, and "… on screen", brief 209).
- `prompts/208-aresium-fixed-costs-data.md`, `Model/FixedCosts.swift`, `AresiumTests/FixedCostsTests.swift`,
  `Model/FixedCostPage.swift` (brief 209's words), `Model/PhoneSample.swift` (`-sampleFixedCosts`).

## Build

1. **Long cadences need a clean name.** A half-yearly or yearly series counts only when every other payment of the
   same name in that direction belongs to a regular series too (a gym's monthly fee beside its half-yearly one is
   fine; a supermarket's or restaurant's other visits are not). Two payments stay enough for half-yearly and yearly.
2. **Monthly and quarterly need a steady day.** At least three quarters of a series' payments fall within 5 days of its
   usual day of the month, counting across the month's end (the 30th, the 31st and the 2nd are close; a payment moved
   to the next working day stays close). A name with many other payments at other amounts (a shop visited often) gets
   no monthly series from a few look-alike visits unless the day holds.
3. **The rows' "next" day in the past:** when the next day due lies before today (an import that is a while old), the
   row says when it was last paid instead (brief 209's `FixedCostWording.last`), never a "next" in the past. Today comes
   from the dashboard's clock (testable), not from the reference day.
4. **The sample** (`-sampleFixedCosts`) shows exactly what a person would call fixed: adjust the made-up data only if a
   rule above makes one of its intended entries disappear, and say which.

## Settled: do not re-open

- Brief 208's model, API, marks, schema 8 and brief 209's screens. Only the detection's rules and the "next/last" choice
  change.

## Out of scope

- The screens' look, the tour, the engine.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=codex-216'
  -derivedDataPath build/DerivedData` passes, with tests (made-up data only) for: a supermarket with two near-identical
  purchases a year apart among many others (no yearly entry); a restaurant visited twice six months apart among other
  visits (no half-yearly entry); a gym's monthly fee plus a half-yearly fee (both found); an insurance paid once a year
  and nothing else from it (found); a shop visited about monthly at similar amounts but on scattered days (none); a rent
  whose day moves by up to three days and once to the next working day (still monthly); a payment on the 30th, 31st or
  1st (still monthly); a "next" day in the past shows "last"; every existing fixed-cost test still holding (or changed
  with a reason in a comment).
- `python3 scripts/strings.py check`: 0 problems.

## Final message

As in `AGENTS.md`: files changed, the exact test summary (count the "' passed on" and "' failed on" lines), what the
sample shows now, anything doubtful. Never commit, push or merge: Claude does.
