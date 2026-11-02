# 135: Arestemis app: a "Neue Suche" screen, a name in every form, renaming in place

Status: running (Claude agent, 2026-11-02)
Branch: `claude/135-arestemis-new-search` · Worktree: `../empire-ios-135-arestemis-new-search` · **For a Claude agent**
(screens and their data part)

## Goal

Patrik (2026-11-02), on the sketch at https://claude.ai/artifact/X2rxw1Vj9JotohSQaw2g8E (sections 1 and 2; open it):

- "The new search type selection menu is not pretty": "+" opens iOS's plain action sheet. After this brief it opens a
  **screen of its own**, "Neue Suche": one card per kind with what it does in one sentence and two or three examples
  that open the form already filled.
- "Make searches nameable and renameable": today only the watch form has a name field, and renaming hides in the "…"
  menu. After this brief **every form has one Name field** (its grey placeholder is the automatic name; nothing else
  explains it: Patrik found the sketch's first version showed "the same field 3 times"), and **renaming happens in
  place**: tap the name at the top of a search's page and it becomes that field, as Aresium renames a payment. A long
  press on a search's card offers Umbenennen (the same in-place field), Pausieren, Löschen.

The kinds' names change on the server (brief 134, running at the same time): **Wohnung, Dinge, Preismonitor,
Webseite beobachten**. The app shows `/kinds`' names as today; the Preismonitor's own form and card come in brief 137,
so this brief shows a kind's card only when this build can open its form.

## Read first

- `AGENTS.md`, `CLAUDE.md` (design rules, Languages, the Arestemis app entry: the forms, the Hunts list, the hunt page,
  Angebote's Searches)
- The sketch (above), sections 1 and 2, and its mockups: follow them, in the app's existing components
- `Screens/HuntsScreen.swift` (today's `confirmationDialog`), `Model/AppNavigation.swift` (`asksSearchKind`,
  `startNewSearch`), `Screens/HuntPage.swift` (the "…" menu's Rename alert), `Screens/HuntCards.swift`,
  `Screens/ListingRows.swift` (Searches cards), `Screens/FlatSearchScreen.swift`, `Screens/ItemSearchScreen.swift`,
  `Screens/WatchSearchScreen.swift` (its Name field), `Model/SearchDraft.swift`, `Model/ItemSearchDraft.swift`,
  `Model/WatchSearchDraft.swift`, `Model/HuntsPresentation.swift` (`HuntName`, `HuntWords`)
- Aresium's in-place rename (`Aresium/Aresium/Screens/` → the payment page's `nameEditor`, `PenButton`) for the feel
- `~/Arestemis/docs/API.md` → `POST /hunts` and `PUT /hunts/{id}` (`name`: absent kept, `""`/null cleared, 60
  characters), `/kinds`

## Build

1. **"Neue Suche"** (a sheet at full height, or pushed; your call, it must feel like part of the app): the title, one
   line "Was soll Arestemis für dich finden?", then one card per kind this build can open, in `/kinds`' order, with
   the kind's mark (the marks the Hunts list uses), `/kinds`' name, one sentence and example chips:
   - Wohnung: "Neue Angebote von WG-Gesucht, Kleinanzeigen, Immowelt und ImmoScout24, Minuten nachdem sie online
     sind." Examples: "2 Zimmer bis 1.100 € warm", "WG-Zimmer".
   - Dinge: "Gebraucht und günstig: Kleinanzeigen, eBay, Vinted, IKEA Preowned und mehr, mit Preisgrenze und Abholung
     in der Nähe." Examples: "Kallax bis 40 €", "Rennrad Größe 56".
   - Webseite beobachten: "Eine Seite, die du kennst: neue Version, neue Stelle, Tickets, der Speiseplan." Examples:
     "Neue Version", "Neue Stelle", "Speiseplan".
   - (Preismonitor in brief 137.)
   A tap on a card opens its empty form; a tap on an example opens the form filled (the flat example: flat, 2 rooms,
   warm rent up to 1,100 €; the thing examples: the words and the price; the watch examples: the "Tell me when"
   sentence, e.g. "eine neue Version erscheint"); places and addresses stay for the user. English copies of every
   sentence and example (English in code, German in the catalog).
2. **The Name field** at the top of the flat and thing forms, as the watch form has it: one field, its placeholder the
   name the search gets when it stays empty (today's automatic name, live as the form changes), 60 characters. Sent as
   `name` on save; an edited search keeps or clears its name as the contract says.
3. **Renaming in place** on a search's page: the name at the top is the button; a tap turns it into a field in the
   same font and place, all selected, keyboard up; Return or tapping away saves (`PUT` with `name` only changes the
   name), Escape/Cancel restores; empty means "the automatic name again". The "…" menu's Rename alert goes.
4. **Long press** on a search's card in the Suche tab and in Angebote → Suchen: Umbenennen (opens the page with the
   name field active), Pausieren/Starten, Löschen (asks first, as today).
5. **Words:** English in code; `scripts/strings.py sync` (undo its changes to other apps' catalogs; restore
   `"Could not load older listings."` if it drops it), German with `fill`, `check` at 0 problems.
6. **Tests:** the cards come from `/kinds` (an unknown kind and a kind this build cannot open are left out); each example
   fills its form as listed; the placeholder follows the form; name sent, kept, cleared; renaming in place (save,
   cancel, empty); the long-press actions; the words in both languages.

## Settled: do not re-open

- One name field, nothing else about it; renaming where the name stands. Kinds and their names from `/kinds`.

## Out of scope

- The server, the Preismonitor's screens (137), the tour (137), TestFlight (Claude).

## Check before you report

- `xcodebuild test -scheme Arestemis` on your own simulator (`claude-135`; boot it first; screenshots from the app
  installed on that simulator itself, as `xcodebuild test` runs on clones).
- Screenshots `build/135-*.png`, each looked at yourself: Neue Suche (English and German, light and dark), a filled
  example form, the Name field in the flat and thing forms, renaming in place on a search's page, the long-press menu.

## Final message

Files changed; build and test summary lines; screenshots; strings added (English and German); anything doubtful.
