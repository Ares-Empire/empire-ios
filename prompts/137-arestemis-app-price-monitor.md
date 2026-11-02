# 137: Arestemis app: the Preismonitor, and examples in the watch form

Status: draft (starts after brief 135 is merged)
Branch: `claude/137-arestemis-price-monitor` · Worktree: `../empire-ios-137-arestemis-price` · **For a Claude agent**
(screens and their data part)

## Goal

Patrik (2026-11-02), on the sketch at https://claude.ai/artifact/X2rxw1Vj9JotohSQaw2g8E (section 3; its HTML is
`/private/tmp/claude-501/-Users-pab/b05f4a4e-2a00-4096-a226-f11e802b21a2/scratchpad/arestemis-next-round.html`):
the commonest page watch, "this product in this shop", becomes its own kind, the **Preismonitor**, and it "should have
the time change graph / data … like a toggle when creating the search if data should be collected and if it should
have an alarm (both choosable but one needs to be chosen) and changeable anytime in the app."

The server is live (brief 134): kind `price`, `PriceSearch` (`url`, `history`, `alarm {below, back_in_stock}`,
`every`), `HuntCard.price` (`PriceState`), `POST /price/preview`, `GET /hunts/{id}/prices?days=30|90|365`,
`Listing.price_change`, push category `ARESTEMIS_PRICE`. After this brief the app makes, shows, charts and edits
monitors; the watch form gets its example chips.

## Read first

- `AGENTS.md`, `CLAUDE.md` (design rules, Languages, the Arestemis app entry: watches, Neue Suche from brief 135)
- `~/Arestemis/docs/API.md` → the price kind (`PriceSearch` … `Prices`, the preview and prices routes, the
  `/kinds` order), and `docs/samples/` (`overview.json`, `prices.json`, `matches.json`, `kinds.json`): copy them into
  `ArestemisTests/ServerSamples/` and the app's samples
- The sketch's section 3 and its three mockups (the form with the two switches, the card with the 30-day line, the
  watch form's chips): follow them, in the app's components
- The watch screens to follow and share with (`Model/WatchModels.swift`, `WatchSearchDraft`,
  `Screens/WatchSearchScreen.swift`, `WatchLines`), Neue Suche (brief 135), `Model/Notifications.swift`
- Aresium's charts (`Aresium/Aresium/Screens/Components.swift`, Swift Charts) for how the Empire draws a line

## Build

1. **Data:** `HuntKind.price`, `PriceSearch`, `PriceState` (with `reader` decoded leniently: brief 136 adds
   `"plain" | "browser" | "browser_exit"`), `PriceChange`, `PricePreview`, `Prices`; the API calls; the store; push
   category `ARESTEMIS_PRICE` opening the match; samples with a monitor on history and alarm, one history-only, a
   price match.
2. **Neue Suche:** the Preismonitor card (sketch section 1): "Ein Produkt in einem Shop: der Preisverlauf, und
   Bescheid, wenn es günstiger oder wieder lieferbar ist." Examples "Preis unter … €", "Wieder lieferbar".
3. **The form** (the sketch's mockup): Produkt (the link; a pasted text keeps its first link, as the watch form), and
   under it, once the link looks complete and typing pauses, the server's preview: "Gefunden: NINTENDO Switch 2 ·
   483,99 € · lieferbar" or the server's refusal in its words (one preview at a time, never more than one every 5
   seconds, as the server allows). **Was er tun soll:** two switches, Verlauf aufzeichnen ("Preis und Lieferbarkeit als
   Kurve") and Alarm ("Push, wenn es so weit ist"); Alarm opens its two conditions (Preis unter [ ] €, prefilled a little
   under the found price; wieder lieferbar); Save is off while both are off, with one quiet line "Mindestens eins von
   beiden." Wie oft (as the watch form; default 1 h). Name (placeholder: the found product's name).
4. **Changeable any time** (Patrik): on the monitor's page the two switches and the alarm's conditions are right there,
   saved as they change (`PUT` with the whole search; turning both off is refused with the line above), not only
   through Edit.
5. **The card** (Suche and Angebote → Suchen): the product, the host, the price large (the app's numbers face), the
   availability word, with history a small 30-day line under it (the price's line, a faint line at the alarm's limit
   when there is one, the newest point marked), "Alarm unter 450 €" or "Nur Verlauf" in the quiet line; the read states
   as watches show them.
6. **The monitor's page:** the chart large with 30 · 90 · 365 days (Swift Charts; low and high named under it; points as
   steps, since a price holds until it changes; out-of-stock stretches visibly so, not by colour alone), the switches
   (4), the alarms found (matches), Open in shop.
7. **A price match** (row, page, push): "Nintendo Switch 2: 449,00 € (vorher 483,99 €)" or "… ist wieder lieferbar",
   old and new price, Open in shop; Save and Dismiss as for watches.
8. **The watch form's examples** (sketch section 3, third mockup): chips over "Sag mir, wenn": "eine neue Version
   erscheint", "ein neuer Eintrag dazukommt", "sich ein Datum ändert", "eigene Beschreibung"; a chip fills the sentence
   for the user to sharpen.
9. **Words:** English in code; `scripts/strings.py sync` (undo changes to other apps' catalogs; restore
   `"Could not load older listings."` if dropped), German with `fill`, `check` at 0 problems.
10. **Tests:** decoding (each new type, unknown availability and reader), the preview's pacing and states, the
    switches' rule (at least one) in the form and on the page, the alarm's prefill, the card's lines per state, the
    chart's points and steps, the match's words in both languages, the push category, the watch chips.

## Settled: do not re-open

- History and alarm as two switches, at least one on, changeable on the monitor's page. The server reads prices; the
  app never parses a shop page.

## Out of scope

- The server, the tour (brief 139), TestFlight (Claude).

## Check before you report

- `xcodebuild test -scheme Arestemis` on your own simulator (`claude-137`; boot it first; screenshots from the app
  installed on that simulator itself, as `xcodebuild test` runs on clones).
- Screenshots `build/137-*.png`, each looked at yourself: Neue Suche with four cards; the form with the preview and
  both switches (and with one off; with both off and the line); the card on Suche (history and alarm; history only);
  the monitor's page with the chart (30 and 365 days); a price match; the watch form's chips; German and English, light
  and dark.

## Final message

Files changed; build and test summary lines; screenshots; strings added (English and German); anything doubtful.
