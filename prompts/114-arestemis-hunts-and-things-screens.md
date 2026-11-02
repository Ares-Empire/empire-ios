# 114: Arestemis app: the Hunts list, the thing search and the thing cards (screens)

Status: merged 2026-11-02 (empire-ios 03d4503, 149 tests; designed by a Claude agent, Claude fixed the auction and shipping texts and kept Patrik's Settings wording under "Flat applications"). Uploaded as Arestemis build 6.
Branch: `claude/114-arestemis-screens` · Worktree: `../empire-ios-114-arestemis-screens` · **For a Claude agent**
(design work stays with Claude: `CLAUDE.md` → Workflow)

## Goal

Arestemis now holds several hunts of two kinds, flats and things for sale (plan:
`~/Arestemis/docs/ARESTEMIS-ANYTHING.md`; the data side is merged, brief 113). Its screens still show one flat hunt.
After this brief the app shows **every hunt**, lets Patrik **add a thing hunt** with its own form, and shows **a thing's
matches** with the facts that matter for buying (price and VB, condition, shipping or pickup with distance, seller).
Flats look and work as today wherever they appear. This build goes to Patrik's iPhone through TestFlight.

## Read first

- `AGENTS.md` (its rules apply to you as to Codex: stay in the worktree, never commit or push, install nothing, keep
  logic out of views and tested) and `CLAUDE.md` (all of the design rules: crown language, light and dark from the
  shared colour pairs, **no pathless shadows over anything that moves** (brief 87) and **no material under shadow,
  mask or group** (brief 67), Languages (English in code, German in the catalog, `scripts/strings.py`), Settings, the
  Arestemis app entry under Setup state, `WordmarkScrollView` ending the first tab)
- `~/ares-empire/EMPIRE.md` → "The crown language"; memory of Patrik's taste: gold only as an accent, no slogans, one
  accent colour per app (Arestemis: moonlight violet), plain and classy; the existing Arestemis screens are the bar
- The data you build on: `Arestemis/Arestemis/Model/` (`ArestemisModels.swift`, `ItemModels.swift`,
  `ArestemisStore.swift` (its `// brief 114 replaces` parts are yours to replace), `SearchDraft.swift`,
  `ItemSearchDraft.swift`, `KeptSearchDraft.swift`, `Formatting.swift`, `ItemFormatting.swift`, `AppNavigation.swift`,
  `Notifications.swift`, `ArestemisSamples.swift`), the samples in `Samples/`, and the contract in
  the Arestemis repo, `docs/briefs/112-arestemis-several-hunts.md` → "The contract"
- Today's screens: `Arestemis/Arestemis/Screens/` (`HuntScreen`, `ListingsScreen`, `MatchRow`, `MatchDetailScreen`,
  `SearchScreen`, `SettingsSheet`, `FormFields`, `Style`) and `ContentView.swift`

## Build (Claude's design choices, settled here; refine details, not the structure)

1. **Two tabs: Hunts and Listings** ("Suche" / "Angebote", the words the app already uses). The Filter tab goes: a
   hunt's search opens from the hunt. `AppTab` and the launch arguments follow (`-tab hunt|listings`; keep `-tab
   search` working as "open the first hunt's search").
2. **Hunts tab** (the first tab, ends with the wordmark):
   - One card per hunt, oldest first, built from today's hunt card (the same glass card, status line with the pulse
     while it runs, "PAUSED" otherwise), made compact: a small kind mark (a house for a flat, a tag for a thing; SF
     symbols, muted ink), the hunt's display name (`name`, else the formatting's name), its summary line (one or two
     lines), the new count when there are new matches, and Start / Pause as today's button, smaller. A hunt of a kind
     this build does not know shows its name and "Needs a newer app" / "Braucht eine neuere App-Version", nothing else.
     A `slowed` hunt shows one quiet line: "Checked less often right now" / "Wird gerade seltener geprüft".
   - Under the cards a quiet full-width button "New search" / "Neue Suche" that asks which kind (Apple's
     confirmation dialog: "Flat or room" / "Wohnung oder Zimmer", "Something to buy" / "Etwas kaufen") and opens that
     kind's form, empty.
   - Then today's Portals card (every site, as today) and Latest (today's three newest across all hunts).
   - **A hunt's page** (tap a card; pushed): today's big hunt card for that hunt with Start/Pause, its figures (New /
     Today / Applied for flats, New / Today / Asked ("Angefragt") for things), and three actions: Edit search
     ("Suche bearbeiten", pushes the kind's form), Listings ("Angebote", switches to the Listings tab with this hunt
     chosen), and a `…` menu with Rename (Apple's name alert, 60 characters, empty clears) and Delete (Apple's
     destructive confirmation; the hunt and its matches go). Then this hunt's latest matches.
   - With no hunt yet: today's empty state, with New search.
3. **The flat form** is today's `SearchScreen`, now opened for one hunt (new or existing) instead of being a tab; its
   Save and Delete act on that hunt; its kept draft is per hunt (brief 113's `KeptSearchDraft`).
4. **The thing form** (new, built from the same `FormFields` pieces, same look and order of habit as the flat form):
   "Describe it" line at the top (as the flat form; `kind: item`), then sections:
   - **What** ("Was"): the search words (one field, required; placeholder "e.g. Herman Miller Aeron"), and Leave out
     ("Ausschließen": words as chips with an add field, like today's district chips).
   - **Price** ("Preis"): min and max (€), and "VB up to … over" ("VB bis … darüber", €; filled with 10 % of the maximum
     until touched, brief 113's draft) with a one-line caption: "Negotiable listings a little over your maximum still
     show." / "Verhandelbare Angebote etwas über deinem Maximum zeigen sich trotzdem."
   - **Condition** ("Zustand"): at least New · Like new · Good · OK · Any (a menu or segmented chips), and a switch
     "Defective is fine too" / "Defekt ist auch okay".
   - **Where** ("Wo"): Pickup · Shipping · Either (segmented), then, unless Shipping, the places (today's place search
     sheet, up to 5) and the radius (km, a stepper or slider with 5/10/20/50/100/200; default 20).
   - **Seller** ("Verkäufer"): Private only / Any.
   - **Extras** (today's extras text area, its caption adapted: "Anything else: size, colour, with box …").
   - **Sites** ("Portale"): Kleinanzeigen (the only one now; the chips as the flat form's portals).
   - Save at the top as the flat form (comfort item 3), validation lines from the draft under their fields.
5. **Listings tab:** a row of hunt chips at the top ("All" / "Alle" and one per hunt, horizontally scrolling, the
   app's `Chip`), then today's New / Saved / Applied / All picker ("Asked" when only things are chosen, else "Applied").
   - **A thing's row** (`MatchRow` for `listing.item`): the price as the big figure (formatting's price line: "80 € VB",
     "Zu verschenken"), the title, and one facts line: condition · shipping or pickup with distance · place. A VB over
     the maximum shows "VB, 30 € over" quietly beside the price; a match found when the hunt started shows the small
     line "Online at start" / "Schon online beim Start". No application action.
   - **A thing's page** (`MatchDetailScreen`): the big price, the title, the facts grid (Condition with the site's word,
     Shipping or Pickup only, Shipping cost "from 6.19 €", Distance, Seller, Place, Posted), why it fits and the
     warnings (as today), the description, "Open on Kleinanzeigen". No Application button.
   - Flats' rows and pages exactly as today.
6. **Settings:** the application pages sit under a heading "Flats" / "Wohnungen" (they only apply to flats).
7. **Push:** a thing's notification uses the `ARESTEMIS_ITEM` category (brief 113); tapping opens its page as today.
8. **Words:** English in code; then `scripts/strings.py sync`, the German with `scripts/strings.py fill`, and
   `scripts/strings.py check` at 0 problems. German style: du, plain and short; a label that wraps gets a shorter word.
9. **Samples and launch arguments:** the sample data (brief 113: two flat hunts and a thing hunt) drives every
   screenshot; add what you need to reach each screen (`-openHunt <id>`, `-openItemForm`, `-newSearch`, `-sampleHunt
   <id>` for the chips) and list them in your final message.
10. **Tests:** any logic you add (the kind dialog's choices, which actions a hunt page offers, the chip filter, the
    Applied/Asked word) goes into `Model/` with unit tests; existing tests stay green.

## Check before you report

- `xcodebuild test -scheme Arestemis` on your own simulator (`claude-114`, commands in `AGENTS.md`).
- **Screenshots** in `build/114-*.png`, English and German, light and dark, of: the Hunts tab (three hunts, one
  running, one paused, one thing), a hunt's page (flat and thing), the kind dialog, the thing form (top and bottom), the
  Listings tab with the chips (All and the thing hunt chosen), a thing's row and page (VB over, at start, shipped,
  free), the flat screens unchanged, Settings with the Flats heading. Look at every one yourself; fix what wraps, clips
  or crowds.
- `scripts/offscreens/offscreens.sh` on the Hunts tab while a hunt runs (the pulse): a steady frame lists no shadow,
  mask or group passes.

## Settled: do not re-open

- Two tabs; the form opens from a hunt. The thing form's sections and order above. No application for things.
- The data side (brief 113) is the API: change it only where a screen truly needs it, and then with a test.

## Out of scope

- The server, eBay and other sites, TestFlight (Claude uploads), the Empire app.

## Final message

Files changed; the exact build and test summary lines; the screenshots' list; the launch arguments added; the strings
added (English and German); anything you would design differently with more time.
