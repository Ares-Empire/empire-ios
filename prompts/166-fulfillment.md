# 166: Arestemis: delivery and pickup in Everywhere

Status: running (round2step4)
Branch: `codex/166-fulfillment` · Worktree: `../empire-ios-166-fulfillment` · Model: `gpt-6.1-sol`, effort `xhigh`

## Goal

Patrik wants the same plain handover choice for Everywhere as Things: “Übergabe”, “Versand” / “Abholung” / “Beides”. The form gains places/radius for pickup. The monitor compares known delivered/pickup totals and clearly shows where a pickup offer is available.

Patrik explicitly assigns screens to Codex for this round, overriding the usual design delegation. Build from existing components; Claude reviews screenshots and owns TestFlight.

## Read first

AGENTS.md, CLAUDE.md top design/Languages/Light mode/Arestemis entry, README and docs/DEVELOPMENT; prompt164; read-only `~/Arestemis/docs/API.md` fulfillment CONTRACT ADDITION and samples from165. Existing PriceModels/PriceSearchDraft/PricePreviewModel/API/price presentation, PriceSearchScreen/PriceSitesScreen/OffersCard/price chart, ItemSearchScreen and its Delivery/Place/radius components. The API is given; use only the documented fields.

## Build and settled design

- Extend Everywhere PriceSearch/draft/request models with delivery/places/radius exactly as the server documents; defaults shipping/[]/20. Existing Everywhere drafts/hunts decode safely; new clients always send their explicit selection, including shipping; page-mode encoding/validation remains its old shape. No build-number/project-file/shared-design edits.
- Under Details and before the history/alarm choices, add the existing Things handover section: heading “Handover” / “Übergabe”, segmented Shipping / Pickup / Either with existing German Versand/Abholung/Beides. Reuse its place search, chips and radius choices when pickup/either; max5places. A saved change retains all other product/name/details/site/alarm choices. Shipping hides/preserves place draft for switching back. Full save validates place/radius; product identity can still confirm while the place is being chosen.
- Send selection to product preview as documented. Changing handover/place updates displayed offer selection without stale answers or confirming a different product; reuse existing paced preview. Suggestions/Things route from164 retain original query/details and remain intact. No local site/product inference.
- Preserve Claude’s reviewed polish (b215465, mergedc3a9ea7): the Things route uses the accent, and comparison label/state share one quiet “Price comparison · has it” / “Preisvergleich · hat es” line. Where it looks retains that label and state. Use optional server delivery capability to disable/grey incompatible sites exactly as the Things form does; no added paragraph or decoration. Keep a single quiet detail line per row; disabled capability wording replaces/joins the state instead of adding a third/fourth line. Preserve sources_off while changing handover; one compatible enabled site must remain. Unknown future values decode safely.
- Offer rows use the server's selected total; keep raw product price and known shipping/fee available in the quiet line. Unknown shipping: short “Shipping unknown” / “Versandkosten unbekannt”, never free. Pickup: store name/city, distance when provided, and “In store” / “Im Einrichtungshaus” or Click & Collect, with a known fee included in total. Unknown costs/stock don't appear as an eligible cheapest total. Keep grouping from existing listing rows; no new card system.
- Everywhere card/monitor/chart titles reflect a total price, using PriceState already computed by the server. Show the cheapest shop/store and chosen handover succinctly, with no long explanation. Stock, last-check/error states and page-monitor layout remain. Open in shop opens the chosen offer. Do not compute a different cheapest than the server; unknown totals remain unknown. Handle old payloads without these optional fields leniently and visibly rather than assuming missing shipping is zero.
- Keep all logic/formatting out of views, tests for decoding/defaults/page encoding/draft preservation/places validation/preview staleness/capabilities/total-vs-raw price/pickup fee/unknown shipping/selection/state and curve labels. Synthetic business names/locations/data only.
- Add DEBUG sample states for shipping, pickup with a place/radius, either, a total-reordered monitor with pickup and shipping offers, and an unknown-shipping quote. Screens should exercise the same UI/model paths, with complete sample contract fields.

## API and scope

Server165's documented PriceSearch/PreviewBody fields and Offer/OfferStore/PriceSite fulfillment additions; existing place search and hunt endpoints. No guessed fields/routes. No private site-reading implementation or findings in this public repo. No used switch/list yet, new source readers, login/token changes, TestFlight or build bump.

## Done when

Own iPhone17 simulator iOS27.0 only. `xcodebuild test -project Arestemis/Arestemis.xcodeproj -scheme Arestemis -destination id=<own> -derivedDataPath build/DerivedData` passes. Strings sync; undo other apps' catalogs; restore “Could not load older listings.” if dropped; fill German; check0. Screens of every changed screen/state in English/German×light/dark, including form shipping/pickup/either, place selection/radius, disabled site, totals/pickup monitor and unknown cost; `build/166-*.png`. Wait for navigation/preview to settle before screenshots and inspect them. Shut down/delete your own simulator. No commit/push/merge. Final report exact test summary, strings, screenshot manifest, changed files and doubts.
