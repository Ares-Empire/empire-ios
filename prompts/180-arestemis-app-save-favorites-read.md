# 180: Arestemis app: Überall saves at once, Favoriten with a star, a listing is read when opened

Status: draft
Branch: `claude/180-save-favorites-read` · Worktree: `../empire-ios-180-save` · Builder: Claude agent (design)

## Goal

Patrik's test of builds 18–19 on 2026-11-05:

1. **Überall saves at once.** He typed "AirPods Max 2" with the details "Mitternacht oder Navy"; the preview searched,
   then failed, and the form would not let him save ("Erst muss das Produkt gefunden werden."), holding him on the
   screen. Patrik: "allow the user to save it asap and then send a msg if not found". The server (Arestemis brief 179,
   deployed) now finds the product in the background and notifies only when nothing fits.
2. **Favoriten.** "Let's change 'Gespeichert' → Favoriten and add a little star to each findings page so it's easy to
   favorite them."
3. **Read when opened.** "The 'neu' only goes away after scrolling all the way down, can we do it so it's when opening
   it?" Today the app hides a listing's dot only in memory 0.4 s after its page opens (`ArestemisStore.markSeen`); the
   server's "● 3 NEU" counts stay and the dots return after a restart. The server now stores `seen`.

## Read first

- `AGENTS.md` and `CLAUDE.md` (always: design rules, "Languages", "Light mode", the Arestemis entry, above all
  "Price monitors everywhere", "Angebote as New | Searches" and the listing page), `~/ares-empire/EMPIRE.md` → design.
- The contract: `~/Arestemis/docs/briefs/179-save-at-once-ai-order-read.md` and `~/Arestemis/docs/API.md` (search for
  "brief 179": `Match.seen`, `POST /matches/{id}/seen`, `Counts.new`, `GET /matches?seen=`, `identity: null` on save,
  `PriceState.product_state` and `refusal`, the `arestemis://hunt/<id>` push); the new server samples
  `~/Arestemis/docs/samples/price-everywhere-finding.json` and `price-everywhere-not-found.json` (copy them into
  `ArestemisTests/ServerSamples/` and decode them in `ServerSamplesTests`, as brief 178 did).
- `Screens/PriceSearchScreen.swift` (`isConfirmed`, the save gate, `productChoices`), `Screens/DidYouMeanChips.swift`,
  `Model/PriceModels.swift`, `Model/PricePresentation.swift`, `Screens/MonitorPage.swift`, `Screens/HuntCards.swift`,
  `Screens/MatchDetailScreen.swift` (the toolbar's state menu, `.task` with `markSeen`), `Screens/MatchRow.swift`
  (`MatchRowActions`, the dot), `Model/ArestemisStore.swift` (`seen`, `showsNewDot`, `setState`, counts),
  `Model/AppNavigation.swift` (`MatchFilter`, `ArestemisLink` use), `Model/Notifications.swift` (`ArestemisLink`),
  `ContentView.swift` (link and push routing), `Model/HuntsPresentation.swift`, `Localizable.xcstrings`, the samples
  and the tests next to them.

## Build

### 1. Überall saves at once

- Saving no longer waits for the preview: with a preview confirmed for the words as they are, send its `identity` as
  today; otherwise send `identity: null`. The "Erst muss das Produkt gefunden werden." gate goes. The preview stays as
  the quick hint while typing ("Gefunden: …", a refusal with its chips), it just never blocks Save.
- Decode `PriceState.product_state` (`finding` | `found` | `not_found`; missing = found; unknown kept as found) and
  `refusal` (the `ProductRefusal` the app already reads from a refused preview).
- **The card and the monitor's page while `finding`:** the product words as the name and one quiet line in place of
  the price, "Sucht das Produkt …" / "Looking for the product…" (the card's existing quiet look; no spinner, no
  accent). **When `not_found`:** the refusal sentence as that quiet line, and on the monitor's page the existing
  "Meintest du …" chips from `refusal.suggestions` plus the Dinge route (`item_search`) as in the form; a chip opens the
  monitor's form with those words in Product (a preview runs as usual; saving restarts the search). No alarm colour.
- `found`: exactly as today.

### 2. Links to a search

- `ArestemisLink` gains a hunt form: `arestemis://hunt/<id>` opens that search's page on the Suche tab (the monitor's
  page for a monitor). A notification with that URL (the server's "Kein passendes Produkt …" push, category
  `ARESTEMIS_PRICE`) routes the same way, its "Open in shop" action does nothing extra for it. Unknown ids show the
  page's normal "not found"/loading behaviour; never a crash.

### 3. Favoriten

- Everywhere the state `saved` is shown, its word becomes **Favoriten** / **Favorites** (filters, the hunt's figures,
  Searches' quiet lines "2 Favoriten · 1 beworben", empty states, VoiceOver), and the action **Favorit** / **Favorite**
  (menus, swipes, the long press) with the `star` symbol instead of `bookmark` (`star.fill` where it shows the state).
  The API state stays `saved`; only words and symbols change. Check German lengths in every place (a label that wraps
  gets a shorter word, not a smaller font).
- **The listing's page** gets a star in its top bar beside the state menu: `star` while the listing is new,
  `star.fill` (in the accent) while it is a favourite; a tap toggles `saved` ↔ `new` (`setState`, optimistic as today,
  with the light haptic other state changes use). Applied and dismissed listings show no star (they are dealt with;
  the state menu still offers everything). VoiceOver: "Favorit" / "Kein Favorit mehr" as the action.

### 4. Read when opened

- Decode `Match.seen` (missing = false). Opening a listing's page marks it read at once: the store sets it locally and
  calls `POST /matches/{id}/seen` (once per listing; a failure keeps it read locally and is retried at the next opening;
  no message). Remove the 0.4 s in-memory `markSeen` and the `seen` set: the dot follows `state == .new && !seen`.
- The "● N NEU" counts come from the server's `counts.new` (now unread new listings); after opening a listing, the
  card's and the group heading's count drop at once (adjust locally, then the next overview confirms).
- **The New part keeps a read listing until it is favourited, applied or dismissed, without its dot** (like read mail
  in an inbox; Claude's recommendation, Patrik may still choose that read listings leave "Neu": keep the list's query
  in one place, so that is a one-line change to `seen=false`).

## Settled: do not re-open

- Save never waits for the preview; the server finds the product.
- "Favoriten" is only words and a star; the API state stays `saved`.
- Read = opened; it is stored on the server.
- No new component styles: the quiet card line, the existing chips, the toolbar's existing button look.

## Out of scope

- The server; the notification-tap crash Patrik reported (not found yet; separate); Dinge and flat forms.

## Done when

- `xcodebuild test` passes on your own simulator (commands in `AGENTS.md`), with new tests for: saving with and without
  an identity; decoding `product_state`/`refusal`/`seen` (present, missing, unknown); the finding and not-found card
  lines and the page's chips; `arestemis://hunt/<id>` from a link and from a notification; the star toggling
  new ↔ saved and hidden for applied/dismissed; opening a listing sending `seen` once and dropping the counts;
  the words in both languages.
- `scripts/strings.py check` says 0 problems.
- Screenshots in `build/180-*.png`, light and dark, German and English, at the smallest phone width: the Überall card
  and page while finding and not found (with chips), a listing page with the star off and on, Angebote → Neu with a
  read and an unread listing, a hunt's figures with "Favoriten".

## Final message

Files changed, the exact build and test summary lines, the screenshot paths, new DEBUG arguments, what is missing or
doubtful.
