# 176: Arestemis app: "+ Versand unbekannt" where the cheapest price has no known shipping

Status: merged (d0ed172; 564 test cases passed on Claude's simulator, 40 screenshots reviewed)
Branch: `codex/176-shipping-unknown` · Worktree: `../empire-ios-176-shipping-unknown` · Model: `gpt-6.1-sol`, effort `xhigh`

## Goal

Today an offer whose shipping is unknown can never be the cheapest of a Preismonitor "Überall": the app shows "Total
unknown" in its row and never shows it on the card. Patrik decided (2026-11-05) that it is not counted as 0 € (furniture
delivery can be 50–150 €). Instead, an offer whose price alone is below the cheapest known total shows at the top
with **"+ Versand unbekannt"**, its alarm says so, and the chart keeps known totals only. The server (Arestemis brief
175) now sends what is needed; this brief shows it.

## Read first

- `AGENTS.md` and `CLAUDE.md` (always: the design rules at the top, "Languages", "Light mode", the Arestemis entry).
- The contract: `~/Arestemis/docs/API.md` → "Price monitors everywhere" and the brief
  `~/Arestemis/docs/briefs/175-price-shipping-coupons-aboutyou.md`, step 4. The server work runs at the same time in
  its own worktree; build from the contract below, not from its code.
- `Arestemis/Arestemis/Model/PriceModels.swift` (`Offer`, `PriceState`, `PriceChange`), `Model/PriceFulfillment.swift`
  (`Offer.selectedTotal`), `Model/PriceEverywhere.swift` (`EverywhereWords.cheapest`, `OfferList`),
  `Model/PricePresentation.swift` (the card, full and compact), `Screens/MonitorPage.swift`, `Screens/HuntsScreen.swift`,
  `Screens/PriceSearchScreen.swift` (`known`, the alarm price prefill), `Screens/MatchDetailScreen.swift` (`priceHero`),
  `Model/HuntsPresentation.swift`, the samples (`ArestemisSamples.swift`, `FulfillmentSample.swift`) and their tests.
- `prompts/157-…`, `prompts/164-…`, `prompts/166-…` and `prompts/168-…` for how these screens came about.

## Build

- **Decode** (all optional, older servers send none):
  - `Offer.totalFrom` from `total_from` (number or null);
  - `PriceState.shippingUnknown` from `shipping_unknown` (false when missing);
  - `PriceChange.shippingUnknown` from `shipping_unknown` (false when missing).
  Encode them back as the other fields are.
- **One rule for "the amount an offer is compared by"** next to `selectedTotal`, for example `Offer.comparable`.
  - It is `totalFrom` under the same guards as `selectedTotal`. With an older server (no `total_from`), it is
    `selectedTotal`.
  - The offer "ships with unknown shipping" when its `total` is nil and `totalFrom` is not.
  - No local sums: the app never adds shipping itself.
- **`EverywhereWords.cheapest`** uses that rule and also says whether the shipping is unknown. The New search form's
  known price (`PriceSearchScreen.known`) and the alarm prefill follow it: the found price shows "+ Versand
  unbekannt" under it when that is the case. The prefill starts a little under that price as today.
- **Offers list** (`OfferList`):
  - the row's amount is the total when known;
  - otherwise it is `totalFrom` with "+ Versand unbekannt" in the row's quiet style under the amount;
  - otherwise "Total unknown" as today.
  - The quiet line then does not repeat the price or "Shipping unknown".
  - `OfferList.selected` finds the card's offer by the same rule.
- **Card** (`PricePresentation`, full on the monitor's page and compact in the Hunts list): when
  `state.shippingUnknown`, "+ Versand unbekannt" sits in the card's quiet style beside or under the price, wherever
  the price is shown. Long German shop names and the large price must still fit at the smallest phone width.
- **Alarm** (`MatchDetailScreen.priceHero`, and the match row if it shows the price): when
  `priceChange.shippingUnknown`, "+ Versand unbekannt" in the muted style after the new price. The accessibility
  label says it too.
- **Chart:** unchanged (the server's history holds known totals only).
- **Samples:**
  - the Überall sample can show a cheapest offer with unknown shipping (a launch argument as the other sample
    switches do, for screenshots);
  - an unknown-shipping row among known ones;
  - an alarm match with `shipping_unknown`;
  - made-up shops and prices only.
- **Strings:** "+ shipping unknown" / "+ Versand unbekannt". Run `scripts/strings.py sync`, undo its changes to other
  apps' catalogs, and restore the Arestemis string "Could not load older listings." if it was dropped. Fill the
  German with `scripts/strings.py fill`, then `check` at 0 problems.

## Settled: do not re-open

- The words are "+ Versand unbekannt" / "+ shipping unknown", Patrik's (2026-11-05). Not "ab", not an icon, not a
  colour: the existing quiet text style. One purple accent, nothing new.
- Unknown shipping is never shown as 0 € and never summed in the app.
- The chart stays on known totals.

## Out of scope

The server (brief 175), the One-shop price mode, the Dinge (item) listings' shipping lines, other apps.

## API

From `~/Arestemis/docs/API.md` (brief 175, `CONTRACT ADDITION`):

- `Offer.total_from: number | null`: the lowest the total can be. It is the known total, or the item price when
  the offer ships and only its shipping is unknown, or null when the offer cannot be compared. Offers arrive ordered
  by it, nulls last. `total` keeps its meaning (known total or null).
- `PriceState.shipping_unknown: bool`, sent only when true on an Überall card: its `price` is an item price whose
  shipping is unknown.
- `PriceChange.shipping_unknown: bool`, default false: the alarm's new price has unknown shipping.

## Done when

- `xcodebuild test` passes on your own simulator (`xcrun simctl create codex-176 "iPhone 17"
  com.apple.CoreSimulator.SimRuntime.iOS-27-0`, never the iOS 27.1 runtime; your own `-derivedDataPath`). There are
  new tests for:
  - decoding with and without the fields;
  - the comparison rule with an old server;
  - `cheapest`, `OfferList.amount`, `line` and `selected` with unknown shipping;
  - the card and the alarm words in both languages.
- Screenshots in German and English, light and dark, in `build/176-*.png`:
  - the monitor page with an unknown-shipping cheapest (card and offers list);
  - the Hunts list card;
  - the New search form's found price;
  - an alarm detail.
  Wait for the screen to settle before each screenshot. Shut your simulator down when done; other sessions use the Mac.

## Final message

As in `AGENTS.md`:

- files changed;
- the exact build and test summary lines;
- the screenshot list;
- what is missing or doubtful.
