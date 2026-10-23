# 07: Widgets show the calendar month, with a note when nothing is imported yet

Status: draft
Branch: `codex/07-widget-month` · Worktree: `../empire-ios-07-widget-month` · Model: `gpt-6.1-sol`, effort `high`

## Goal

Patrik asked for "the month that I'm in". Today the widgets show the newest month that has transactions, so on
1 November, before the first November import, they still show October. Decided 2026-10-24 (council finding D2,
`docs/reviews/2026-10-23-pre-testflight.md`): the widgets always show the **calendar month**; when the data has no
transactions in it yet, they say so.

## Read first

- `AGENTS.md`, `CLAUDE.md`; `AresiumShared/WidgetSnapshot.swift`, `AresiumShared/WidgetViews.swift`,
  `AresiumWidget/WidgetProviders.swift`, `AresiumTests/WidgetTests.swift`.

## Build

1. A small pure function (shared, testable with an injected date and calendar) that decides, for a snapshot and
   "now", whether the snapshot's month is the calendar month.
2. **When it is:** unchanged.
3. **When it is not** (the calendar month is newer than the snapshot's month): both widgets show the calendar
   month's label (e.g. "November 2026") and, instead of numbers and the line, the note "Nothing imported for
   November yet" plus "last data 30 Oct" (the snapshot's newest transaction date, formatted as today's "up to …").
   No amounts, no zeros: €0 would look like real data.
4. The timeline already refreshes at the start of the next month; make sure the entry for the new month renders the
   note without the app having run.
5. Tests: same month → normal; next month → note with both labels; a snapshot from two months ago → still the note
   with the right "last data"; year change (December → January).
6. Screenshots via the existing test rendering: `build/07-medium-note.png`, `build/07-small-note.png`.

## Settled: do not re-open

- The calendar month comes from the device clock; this is display logic, no money is calculated.
- The app's own screens keep "Current = newest month with data" (unchanged); this brief is widgets only.

## Out of scope

- Server changes, the app's screens, anything else in the widgets.

## Done when

- `xcodebuild test` passes on your own simulator, existing 95 tests too; the screenshots exist.

## Final message

As in `AGENTS.md`.
