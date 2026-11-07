# 157: Arestemis app: the Preismonitor "Überall"

Status: done (bc1b602, 2026-11-04)
Branch: `claude/157-price-everywhere` · Worktree: `../empire-ios-157-price-everywhere` · **For a Claude agent** (design)

## Goal

Patrik (2026-11-03) wants a price monitor for one product that is not tied to a specific page: "…
Pick an item and it monitors multiple pages that either all have it or all could have it for either alerts or simply
monitors." His decisions on the plan (https://claude.ai/artifact/FBXeut5PmPNm3JqTeu38F1, sections 3, 4 and 6, with
phone sketches):
- **part of the Preismonitor:** "Ein Shop" (a link, as today) | "Überall" (a product in words);
- **"Überall" means the sites that carry this kind of product.** The user sees every site it checks in a list (his
  idea, "a screen that shows all sites it would check, also makes user suggestions easier"), switches off any they
  would never buy from, and can suggest a missing shop;
- **colour, size or variant go into one optional line in words**, no menu ("the search could just as well be a
  microphone, bike, helmet").

The server is live (the Arestemis repo, brief 154). The contract is in `~/Arestemis/docs/API.md` → "Price monitors
everywhere ("Überall")": `PriceSearch.mode/product/details/identity/sources_off`, `ProductIdentity`, `Offer`,
`PriceSite`, `ProductPreview`, `PriceOffers`, `POST /price/preview {product, details}`, `GET /hunts/{id}/offers`,
`PriceState` for this mode (`offers` count). Samples: `~/Arestemis/docs/samples/price-everywhere.json`,
`price-offers.json`, `product-preview.json`. Read only, never edit `~/Arestemis`.

## Read first

- `AGENTS.md`, `CLAUDE.md`:
  - the design rules (no `.shadow` around content, nothing moving over a pathless shadow, no material under shadow,
    mask or group; light and dark; one purple accent, no slogans);
  - Languages;
  - the Arestemis entry: price monitors (brief 137), the listing page and New search (brief 142), the tour (brief
    139), Contact & support in Settings.
- The Preismonitor's screens: `Model/PriceModels.swift`, `PriceSearchDraft`, `Screens/PriceSearchScreen.swift`,
  `Screens/MonitorPage.swift`, `PriceViews.swift`, `MonitorSwitchesCard`, `PricePreviewModel`.
- The plan's sketches (sections 3 and 4): the form with "Ein Shop | Überall", the monitor's page with the cheapest
  price, its curve and every shop, the "Wo gesucht wird" screen with switches and "Shop vorschlagen".

## Build

1. **Data:** the new fields and types, decoded leniently (absent `mode` = page; unknown site kinds and states kept);
   the preview, offers and sites calls; samples from the server's files (add them to the app's `Samples/` and
   `ArestemisTests/ServerSamples/`; keep the existing page monitors 9–11).
2. **The form:** a segmented "Ein Shop | Überall" at the top of the Preismonitor form ("One shop | Everywhere"):
   - "Ein Shop" is today's form, unchanged.
   - "Überall":
     - **Produkt** (words, e.g. "AirPods Max 2");
     - **Details (optional)** (one line, placeholder like "z. B. Farbe Mitternacht oder Blau");
     - once typing pauses, the preview: "Gefunden: Apple AirPods Max (2. Gen.) · in 11 Shops, ab 529 €" or the
       server's refusal;
     - then one quiet line "Sucht in 11 Shops · Ändern", which opens the sites screen;
     - What it should do (the same switches, Verlauf and Alarm, the alarm's limit prefilled a little under the
       cheapest price, as today);
     - How often (hourly or slower for this mode).
   - Saving sends the confirmed identity and `sources_off`.
3. **The sites screen ("Wo gesucht wird" / "Where it looks"):**
   - every `PriceSite` for this product, the ones that have it first, each with its name, a quiet state (has it /
     checking / doesn't have it / can't read it now) and a switch;
   - "Shop vorschlagen" / "Suggest a shop" at the end, which opens Settings' Contact & support form with the kind
     "Idea or wish" and the text started ("Shop vorschlagen: ") so the person types the shop's name. Nothing new on
     the server.
   - Reachable from the form and from the monitor's page.
4. **The card:** the cheapest price large with its shop ("529,00 € bei Otto"), "· N Shops" in the quiet line, the
   30-day line of the cheapest price while the history is on, "Checked …", and the read states as today.
5. **The monitor's page:**
   - the chart of the cheapest price (as today's chart);
   - below it the offers, cheapest first: shop, price, shipping when known, availability, each opening its URL;
   - the switches;
   - "Wo gesucht wird" with the count, opening the sites screen;
   - the alarms found.
6. **A price match** of this mode opens the cheapest offer's shop; its words name the shop ("… 449,00 € bei
   MediaMarkt (vorher …)").
7. **New search:** the Preismonitor card's line and example stay as brief 142 left them, unless "Überall" deserves
   the example now ("AirPods Max überall"); your call, keep one example.
8. **The tour (brief 139):** step 7's words about the Preismonitor may mention "in einem Shop oder überall" if it
   still reads in one line; otherwise leave it.
9. **Words:** English in code; `scripts/strings.py sync` (undo changes to other apps' catalogs; restore `"Could not
   load older listings."` if dropped), German with `fill`, `check` at 0 problems. German: du, plain, short; "Shop"
   and "Shops" are fine German here.
10. **Tests:**
    - decoding of every new type (unknown values);
    - the form's mode switch keeping each mode's draft;
    - the preview's states;
    - the sites screen's switches producing `sources_off`;
    - the suggest link opening the support form with its start text;
    - the card's and the page's words in both languages;
    - offers sorted cheapest first;
    - the old page mode unchanged.

## Out of scope

The server, TestFlight (Claude), automatic site picking for thing searches.

## Check before you report

- `xcodebuild test -scheme Arestemis` on your own simulator (`claude-157`, iOS 27.0; screenshots from the app
  installed on that simulator itself).
- Screenshots `build/157-*.png`, German and English, light and dark:
  - the form in "Überall" with the preview;
  - the sites screen with one shop switched off;
  - the card;
  - the monitor's page with the offers;
  - "Shop vorschlagen" opening the support form;
  - the form in "Ein Shop" (unchanged).

## Final message

Files changed; build and test summary lines; screenshots; strings added (English and German); anything doubtful.
