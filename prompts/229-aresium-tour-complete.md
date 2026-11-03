# 229: The Aresium tour covers everything again

Status: merged 2026-11-03, build 22 (833 tests on Claude's run): step 4 of 23, the average and fixed costs; tour groceries no longer fixed.
Branch: `codex/229-tour-complete` · Worktree: `../empire-ios-229-tour-complete` · Model: `gpt-6.1-sol`, effort `high` ·
Simulator: `codex-229` (create it as `AGENTS.md` says)

## Goal

Aresium's tour (`Aresium/Aresium/Model/TourModel.swift`, `TourData`, the tour screens; 22 steps) shows every feature
up to build 18, but not the newest: the monthly average and the fixed costs under Overview's total (briefs 208, 209,
216, 217; build 19). External testers start with the tour, so it should show it. After this brief the tour has a step
for it, and nothing else Aresium can do is missing from the tour.

## Read first

`AGENTS.md`, `CLAUDE.md` (Aresium sections: the tour, "Monthly average and fixed costs"), briefs 59, 203, 206 and 209
here (how earlier tour steps were added), the tour's model, data, screens and `TourTests`.

## Build

1. **A step for the average and fixed costs**, right after Overview: the ring on the line under the total
   ("Ø … im Monat · davon … fix"), one or two short sentences in the tour's voice in English and German (for example:
   what a month costs on average and how much of it is fixed; a tap shows rent, subscriptions and insurance and when
   each is due). Next opens the fixed costs page if that is how earlier steps show a page, else stays.
2. **The tour's made-up data** shows believable fixed costs: rent, two or three subscriptions, an insurance. Today it
   also lists two REWE payments and one dm payment as fixed: change the made-up groceries so they are not regular
   enough to look fixed (do not change the detection).
3. **Check the rest:** go through every Aresium feature named in `CLAUDE.md`'s build list from build 14 on and the
   changelog in `~/ares-empire/EMPIRE.md`, and list in the final message anything the tour does not show. Add a step
   only for the fixed costs; the rest is the owner's choice.

## Settled

- The tour's existing card, ring and motion only; no new look. Readable code in the existing style.
- `scripts/strings.py check` 0 problems; every new word in both languages.

## Done when

`xcodebuild test` passes on `codex-229` with `TourTests` covering the new step. Screenshots of the new step in German and
English, light and dark: `build/229-step-{de,en}-{light,dark}.png`.

## Final message

As in `AGENTS.md`, plus the list from point 3.
