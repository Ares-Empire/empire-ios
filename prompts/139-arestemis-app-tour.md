# 139: Arestemis app: a tour of eight steps

Status: draft (starts after brief 137 is merged, and after Aresium brief 206 is on main: it changes only the select step's line in `TourModel.swift` and its `TourTests` expectation; branch 139 from main after that)
Branch: `claude/139-arestemis-tour` · Worktree: `../empire-ios-139-arestemis-tour` · **For a Claude agent**

## Goal

Patrik (2026-11-02): "it's not actually clear what Seite beobachten is for, it's quite generic. We should add a tour to
Arestemis (like Aresium has) that explains it." He approved eight steps (the sketch at
https://claude.ai/artifact/X2rxw1Vj9JotohSQaw2g8E, section 6; its HTML is
`/private/tmp/claude-501/-Users-pab/b05f4a4e-2a00-4096-a226-f11e802b21a2/scratchpad/arestemis-next-round.html`). After
this brief the tour shows once after the first login, can be started again from Settings, runs on sample data so it
never touches real searches, and rings the part of the screen each step is about, as Aresium's does.

## Read first

- `AGENTS.md`, `CLAUDE.md` (design rules, Languages, the Arestemis app entry: Hunts, New search, Angebote, watches,
  Preismonitor)
- **Aresium's tour, the model:** `Aresium/Aresium/Model/TourModel.swift`, `Aresium/Aresium/Screens/TourScreens.swift`,
  its steps' anchors and cards, how it runs on its own sample store and ends, `TourTests`. Where its pieces are not
  Aresium-specific (the ring around an anchor, the card with step count, Weiter/Überspringen), **move them into
  `Shared/` and use them from both apps** rather than copying (EMPIRE.md → "How we build apps"); Aresium's tour must
  behave exactly as before (its tests pass, its screenshots unchanged).
- The sketch's section 6 (the eight steps and the mockup of step 3)

## The steps (German as on Patrik's phone; English in code)

1. **Arestemis sucht für dich.** It reads the sites every few minutes, checks each new listing against your search and
   sends a push.
2. **Neue Suche.** The four kinds, one example each (Wohnung, Dinge, Preismonitor, Webseite beobachten).
3. **Eine Suche.** Suche läuft, Pausieren, the new count; tap for its page. (The sketch's mockup.)
4. **Angebote → Neu.** Everything new, grouped by search. Swipe right to keep, left to dismiss.
5. **Angebote → Suchen.** Each search's listings, and the magnifying glass for all of them.
6. **Ein Angebot.** Why it fits; for flats the application text.
7. **Preismonitor und Webseite beobachten.** What each can do: a price falls or a product is back (with its curve);
   something new appears on a page (a version, a job, the menu). Two lines, concrete, from the sketch's section 3.
8. **Aussortiert.** What the check turned down, so a search that is too strict shows.

Each step's words: one or two short sentences, "du", no slogans, in the app's terms (Suche, Angebote, Preismonitor,
Beobachtung). Write them yourself from the steps above; Claude reads them before merging.

## Build

1. The tour on sample data (the app's sample backend, as screenshots use it), never the account's real searches.
2. Shown once after the first successful login of an account on this iPhone (remembered per account), never over a
   push being opened or a sheet; Settings → Tour starts it again.
3. Each step rings its anchor on the real screen it names and shows the card; Weiter, Überspringen, and the step count
   ("3 / 8").
4. Words: English in code; `scripts/strings.py sync` (undo changes to other apps' catalogs; restore `"Could not load
   older listings."` if dropped), German with `fill`, `check` at 0 problems.
5. Tests: the order of steps and their anchors, once per account, Settings starting it again, never touching real data,
   Aresium's tour unchanged.

## Out of scope

- The server, TestFlight (Claude).

## Check before you report

- `xcodebuild test` for **Arestemis and Aresium** on your own simulator (`claude-139`; boot it first; screenshots from
  apps installed on that simulator itself).
- Screenshots `build/139-step{1..8}-{de,en}-{light,dark}.png` and Aresium's tour before/after (unchanged), each looked
  at yourself.

## Final message

Files changed (and what moved to `Shared/`); build and test summary lines for both apps; screenshots; the eight steps'
words in English and German; anything doubtful.
