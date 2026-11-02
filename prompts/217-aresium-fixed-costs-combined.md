# 217: Fixed costs: a fee taken together with the monthly charge

Status: merged 2026-11-02 (931 Aresium tests, one import test passed on a rerun alone; a follow-up for price steps after the check on the owner's export locally: one entry per subscription, no booking in two entries)
Branch: `codex/217-fixed-costs-combined` · Worktree: `../empire-ios-217-fixed-costs-combined` · Model: `gpt-6.1-sol`,
effort `high` · Simulator: `codex-217` (create it: iPhone 17, iOS 27.0)

## Goal

A real case, seen locally on the owner's own export after build 19 (nothing of it in this repo): a gym charges its
membership on the 1st of each month (with two months paused), and every six months its service fee is not a booking of
its own but **taken together with that month's membership in one larger booking**; when the membership began there was
one larger booking (the sign-up). Brief 216's detection gets it wrong twice: the membership shows as ended (the latest
month's booking has another amount, so the monthly series seems to stop a month early), and the six-monthly fee is not
found (its two bookings carry the membership inside them, and the sign-up booking makes the name "unclean" for brief
216's long-cadence rule). After this brief such a name shows the membership as running, monthly, and the fee as its own
half-yearly entry at the fee's amount only.

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Monthly average and fixed costs — data API" and "… on screen", briefs 208, 209, 216).
- `prompts/208-aresium-fixed-costs-data.md`, `prompts/216-aresium-fixed-costs-sharper.md`, `Model/FixedCosts.swift`,
  `AresiumTests/FixedCostsTests.swift`.

## Build

1. **A larger booking on a series' day carries it.** When a payment of the same name and direction falls on a monthly
   or quarterly series' usual day (brief 216's tolerance) in a period where the series has no payment, and its amount is
   larger than the series' amount, it counts as that period's payment of the series (for the gaps, the running/ended
   check and the next day due), and the difference is an **extra** of that booking.
2. **Extras can be fixed costs of their own.** The extras of one name and direction are series candidates like any
   payment (amounts within brief 208's tolerance, the cadences, brief 216's rules), so a fee taken every six months
   inside the membership's booking becomes a half-yearly entry whose amount is the fee alone. A booking whose extra is
   used this way is never counted twice: the membership counts its own amount, the fee only the difference.
3. **Only the series' own span is checked for cleanliness.** Brief 216's rule (a half-yearly or yearly series counts
   only when every other payment of the name in that direction is regular) looks only at payments between the long
   series' first and last payment; a sign-up booking before it, or a one-off after it, does not block it.
4. **Marks keep working.** A "Not fixed" mark on an entry keeps its id through this change where the entry stays the
   same (brief 208's anchor); say in the final message what happens to a mark on an entry whose rows change.

## Settled: do not re-open

- Brief 208's model, API and storage; brief 216's rules apart from item 3; brief 209's screens.

## Out of scope

- The screens, the tour, the engine.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=codex-217'
  -derivedDataPath build/DerivedData` passes, with tests (made-up data only) for: a gym charging the membership on the
  1st, with two months paused, a sign-up booking about four times the membership before it, and every six months one
  booking of membership plus fee (the membership running and monthly at its own amount, including the months of the
  combined bookings; the fee half-yearly at the difference; nothing counted twice in the monthly total); the same gym
  whose latest booking is a combined one (still running, next due a month later); a one-off booking of the same name
  after a yearly series (the yearly still found); brief 216's supermarket and restaurant cases unchanged; every existing
  fixed-cost test holding (or changed with a reason in a comment).
- `python3 scripts/strings.py check`: 0 problems.

## Final message

As in `AGENTS.md`: files changed, the exact test summary (count the "' passed on" and "' failed on" lines), what happens
to marks, anything doubtful. Never commit, push or merge: Claude does.
