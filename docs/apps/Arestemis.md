# Arestemis (iPhone)

Searches that run on the server: flats, things for sale, price monitors, page watches, look hunts. The server and its briefs are in the private Arestemis repo (its `docs/API.md` is the contract). Decisions: `ares-empire/docs/ARESTEMIS-APP.md`. Rules for every app: `CLAUDE.md`. Owner decisions are tagged "(owner, date)"; when one changes, change its line (git keeps the old one).

## Decisions and rules in force

- The server decides which sites exist and what can be watched; the app keeps unknown sites and never ranks search
  results itself.
- New search asks only what's necessary; examples never fill in places or addresses (owner, 2026-11-02).
- Price monitor: recording history and the alarm are both optional, at least one is on, both can be changed at any
  time (owner, 2026-11-02).
- A watch's states never use an alarm colour; blocking-style states stay quiet.
- A listing reads like a listing, no long "why it fits"; "Open on <site>" is the main button; New search's kind marks
  are not in the accent colour (owner, 2026-11-03).
- Look hunts: `look` and `look_min` are always decoded and sent back, so editing keeps them; a vote never moves an
  entry between lists.
- The tour runs by itself once per account, never in sample mode, and never touches the account's data.
- Real portal photos never go on the Mac; sample photos are made up and Debug only.

## Open

- Comfort item 6 (Add place's keyboard key, the owner's list no. 18): the owner did not follow it, so explain it to him
  first and let him choose (the item in `docs/reviews/2026-10-30-swipe-and-comfort.md` has both options).
- No editor for look hunts yet.

## As built

### Arestemis app

**Arestemis app** (2026-10-24, build A1): `Arestemis/` (bundle id `de.ares-empire.arestemis`), the hunter for flats and, since
build 6 (briefs 113, 114, 2026-11-02), things for sale: several hunts, two tabs Suche (the Hunts list, each hunt's page, the
forms opened from a hunt) and Angebote (New | Searches since brief 133, below), on the Arestemis API (`~/Arestemis/docs/API.md`; samples in `Arestemis/Arestemis/Samples/`, copies of its `docs/samples/`).
Data in `API/` + `Model/` (one `ArestemisStore`, optimistic changes with rollback), screens in `Screens/` on
`Shared/Design`. Launch arguments (DEBUG): `-sampleData` (+ `-sampleNoHunt`, `-samplePaused`, `-sampleLoading`),
`-tab hunt|listings|search` (`search`: the first hunt's form), `-filter new|saved|applied|all`, `-openMatch <id>`, brief 114's
`-openHunt <id>`, `-openForm <id>`, `-openItemForm`, `-newItemForm`, `-newFlatForm`, `-newSearch` (New search's page),
`-sampleSlowed`, `-sampleNewerKind`; brief 133's `-listings new|searches`, `-openSearch <id>`, `-search <words>`;
`-openSheet settings|application|rejected|place|describe`, `-scrollBottom`, `-scrollTo size|rent|movein` (the thing form:
`where`); Settings →
Application (brief 61): `-openSettingsPage ownText|notes|aboutMe`, `-sampleOwnMode`, `-sampleNoTexts`. Push: the category and
the link routing are in `Model/Notifications.swift`; `Shared/Push` is wired in ContentView.

### Search (API version 2, 2026-10-24, the owner)

**Search (API version 2, 2026-10-24, the owner):** Flat or WG / Flat / WG, people moving in, max flatmates, size ranges
(flat, WG room), areas, cold and warm rent ranges, move-in and temporary offers, portals, extras; every field optional
except a place and a portal. "Describe it" is a line at the top that opens a sheet (`SearchDraft`, `SearchScreen`).

### Settings → Application

**Settings → Application** (brief 61, the owner 2026-10-31): after Notifications, one card of rows like General's: the
switch Write automatically (on = `ai`), the row it leads to (Your text, or Notes = `application_notes`, the Arestemis repo, `docs/briefs/62-arestemis-application-notes.md`) and
About you, each opening a page with one text field (`ApplicationPage`); one draft, saved when the sheet closes. **Sites come from the server** (brief 119, 2026-11-02): `Source` is open (`Model/Sites.swift`), a site the
app does not know is kept and shown by the server's name (`SourceStatus.name`, `Listing.source_name`, `GET /kinds`);
the forms' site switches come from `GET /kinds` for their kind (`SiteChoices`; today's lists when there is no answer),
a site with `ready: false` is greyed with "<site> is not set up yet.", and the thing form's "Include auctions" shows
only while a chosen site has `auctions`. An eBay auction shows its bid and time left (`DecodingTests`, `SitesTests`;
DEBUG `-sampleEbayNotReady`). **Delivery** (brief 129, 2026-11-02): `/kinds` says how a site's listings change hands
(`KindSource.delivery`: IKEA Preowned pickup, Vinted and mydealz shipping; absent or unknown = both); the thing form
greys a site its delivery cannot serve as one not set up and switches it off at once, also a saved search's and when
the sites arrive later, never on again by itself (`ItemSearchDraft.switchOffSitesThatCannotServe`); the one line under
the sites names what is not set up, then the delivery's reason in the server's words ("eBay is not set up yet.
mydealz and Vinted only ship."). Fonts & licences credits OpenStreetMap (`BundledLicence.townLocations`,
`Licences/town-locations-licence.txt`; the server looks up thing searches' towns on Nominatim). Sample hunts 4
(Bookcase, pickup, IKEA Preowned) and 5 (Denimwerk jeans, shipping, Vinted) with matches 33 and 34
(`DeliverySitesTests`; DEBUG `-sampleDelivery pickup|shipping|either`, chosen in the thing form as a tap would).

### Page watches

**Page watches** (brief 131, 2026-11-02; the Arestemis repo, `docs/briefs/130-arestemis-page-watches.md`, plan `Arestemis/docs/ARESTEMIS-ANYTHING.md` → Page watches):
a third kind, `watch` ("Watch a website" / "Webseite beobachten" since the server change described in the Arestemis repo, `docs/briefs/134-arestemis-price-monitor.md`, offered when `/kinds` lists it): an
optional name (first, since brief 135), an address, the change in the user's words, how often (15 min to daily,
default 1 h) (`Model/WatchModels.swift`,
`WatchSearchDraft`, `Screens/WatchSearchScreen.swift`, in the thing form's style; a pasted text keeps its first link,
`WatchAddress.fromField`). The server decides what can be watched: its refusals come as `400` with `field`
(`FieldRefusal`, `ArestemisStore.searchErrorField`) and show under that field. The card (`WatchLines`,
`WatchCardText`): the name (own, else the page's title, else the host), the host, what the page says now as its main
fact, "Checked … · Changed …"; while waiting, unreadable, failing or blocked one quiet line in muted ink (the server's
note; blocked adds that editing tries again), never an alarm colour. The words name a watch "Beobachtung"
(`HuntWords`); its third figure is Saved. A found change (`Listing.page`, source `"page"`): the summary as title,
"Now: …", Added and Removed lines (removed struck through), Open page; Save and Dismiss only. Push category
`ARESTEMIS_WATCH` ("Open page"). Sample hunts 6 (KALLAX, ok), 7 (AirPods on Geizhals, blocked), 8 (Mensa, ok) with
matches 35 and 36 (`at_start`); DEBUG `-openWatchForm`, `-newWatchForm` (`-watchURL <text>`, `-watchChange <text>`,
`-saveWatch`: the sample imitates the server's refusals), `-sampleWatchRead <read>` (hunt 7's state),
`-scrollToHunt <id>`. Tests: `WatchTests`. Screenshots: `build/131-*.png`.

### Angebote as "New | Searches"

**Angebote as "New | Searches"** (brief 133, the owner 2026-11-02, chosen from three drawn options: with several searches
the one list with a chip per search was "a little unorganized"; the chips are gone). The tab's header (`ListingsScreen`)
has the magnifying glass and a segmented switch **New | Searches** ("Neu" | "Suchen"); the part the user picks is
remembered across launches (`AppNavigation.choose`, `ListingsPartMemory`, key `arestemis.listingsPart`); a
notification's match opens over New and a hunt's page shows Searches without changing that choice. **New:** every
search's new listings (`loadMatches(.new)`), grouped under a heading per search (`NewListings.groups`: the search with
the newest finding first, newest first within it, by `found` then id; `NewGroupHeading`: the kind's mark, the name,
the hunt card's "● 3 NEW" and a chevron opening that search's listings at New; no headings while the account has one
search), the usual swipes, a group gone with its last new listing; only unread listings since brief 182 (`MatchFilter.seen`); then "Zuletzt angesehen" (brief 182) and "Filtered out" of every search. **Searches:**
one glass card per search in the Hunts tab's order, paused ones too (`SearchRow`, `SearchRowCard`): the kind's mark
and name, the new count, "2 saved · 1 applied" ("asked" for things, saved only for a watch, "Paused" first) in a quiet
line; a kind this build does not know shows its name only. A tap opens **one search's listings**
(`SearchListingsPage`, `ListingsRoute.hunt`): its name as the title, the magnifying glass for its own listings, New ·
Saved · Applied/Asked · All (a watch has no Applied, `MatchFilter.choices`; it opens at New while there are new ones,
else All, `MatchFilter.opening`), its own "Filtered out" (`RootSheet.rejected(hunt)`). A hunt's page's Listings and
figures open it over Searches (`AppNavigation.showSearch`); the Hunts tab's "All listings" opens the tab as it was.
The store keeps its lists per search and filter (`ArestemisStore.ListScope`, `list(_:hunt:)`, `matches(_:hunt:)`,
`rejected(hunt:)`; `selectedHuntID` is gone); deleting a hunt forgets them and the screens ask again. **The search over
listings** (`ListingSearchPage`, `ListingsRoute.find(hunt:)`; the server ranks, the Arestemis repo, `docs/briefs/132-arestemis-listing-search.md`, `GET /matches?q=`):
the place search's field on its glass card (`SearchBox`, shared with Add place), the keyboard up as it opens, the
hint "Type at least two letters. The best matches come first."; from two letters, 0.3 s after typing pauses, the
server's answer in its order (`ListingSearch`: a newer query cancels the older, the same words are not asked twice, at
most 100 characters, 50 results with "More listings match. Another word narrows it down." when there are more); each
row the usual card with its state (NEW too) and, over every search, the search's mark and name above it; tap, swipes
and long press as elsewhere; "Nothing found for “…”." / "Nichts gefunden für „…“."; a failure is a calm line with Try
again. Sample mode imitates the server's search simply (`SampleBackend.findMatches`; the app never ranks). Tests:
`ListingsTests`; the server's sample answer `ArestemisTests/ServerSamples/server-matches-search.json`. Screenshots:
`build/133-*.png`.

### New search, names, renaming in place

**New search, names, renaming in place** (brief 135, the owner 2026-11-02 on the sketch: the kind menu "is not pretty";
searches nameable and renameable, "only what's necessary"). **New search** (`Screens/NewSearchScreen.swift`, model
`Model/NewSearch.swift`): New search (the list's button, the empty states) pushes a page on the Hunts tab
(`HuntRoute.newSearch`, no tab bar): "What should Arestemis find for you?" / "Was soll Arestemis für dich finden?",
then one glass card per kind this build can open, in `/kinds`' order with `/kinds`' names (`NewSearchCard.cards`;
the kinds are Flat / Wohnung, Things / Dinge, Price monitor / Preismonitor, Watch a website / Webseite beobachten
since the server change described in the Arestemis repo, `docs/briefs/134-arestemis-price-monitor.md`; `price` has its card since brief 137, a kind of a newer server none; without an answer this
build's four with its own names, `SearchKind.choiceTitle`): the Hunts list's mark and the name, a chevron, one
sentence (`SearchKind.pitch`), the examples as chips (`SearchExample`, laid over the card's button as
`HuntListCard`'s Start / Pause is). A tap on the card opens the kind's form (empty, or the kept draft); an example
opens it filled in (`.form(kind, hunt: nil, example:)`): flat, at least 2 rooms, up to €1,100 warm; a WG room;
"Kallax" up to €40; "Road bike" / "Rennrad" with "Frame size 56" / "Rahmengröße 56" in Extras; the watch's "Tell me
when" sentence ("a new version comes out" / "eine neue Version erscheint", …). Places and addresses stay the user's.
Saving replaces the form and New search with the hunt's page (`showCreated`). **One Name field, first in every form**
(`NameField`): its grey placeholder is the automatic name, following the form (`HuntText.automaticTitle`: a flat's
kinds, a thing's words, a watch's page title or host; "Optional" while there is none), nothing else explains it; 60
characters, sent as `name` (`sentName`: kept, changed, or null to clear). The drafts carry the name, so a kept draft's
baseline is the saved hunt as a draft (`KeptDraft`, one generic `KeptSearchDraft` for the three kinds; a rename
elsewhere drops the kept edits). **Renaming in place** (`HuntPage`, `NameEdit`, as Aresium's payment page): the name
on the hunt's card is a button with a small pen (`PenButton`); a tap, the pen, the `…` menu's Rename or a card's long
press turns it into a field in the same font and place (the mark stays, a well reaching into the margin), the name
selected, the keyboard up; the bar shows Cancel (ink) and Save (the accent, muted while unchanged). Return, Save, a
tap anywhere else on the page or a scroll save a changed name (`PATCH /hunts/{id}` with the name alone, so the server
does not start the search again as a `PUT` would; nothing is sent when unchanged), Cancel leaves it (Escape on a hardware keyboard through Cancel's `.keyboardShortcut(.cancelAction)`;
not checked: XCTest's `typeKey` reached no key of the field, Return neither); empty is the automatic name again. While it is open the rest of the
page takes no taps (a tap there ends it). The Rename alert is gone. **A search card's long press** (`huntCardMenu`,
the Hunts list and Listings → Searches): Rename (the search's page on the Hunts tab, its field open,
`AppNavigation.rename`), Pause or Start, Delete (asks first, as on the page). A hunt this build cannot read offers
Delete only (`HuntPageActions.rename`: its page shows no name to edit). DEBUG `-newSearch`,
`-newExample <example>` (`twoRooms`, `kallax`, `everywhere` (brief 157; `priceBelow` before), `newVersion` since brief 142),
`-renameHunt <id>` (`-renameText <text>`). Tests: `NewSearchTests`. Real touches (a temporary UI test in
`Aresus/AresusUITests` driving Arestemis, deleted): the long press's menu on both tabs and in German, Pause and Start
from it, Rename opening the field with the keyboard, a tap elsewhere saving, Cancel restoring, the clear button
showing the automatic name, Return and Save saving, Delete asking first; the examples filling their forms. Found then
and left (Shared): a glass card lifted by a long press from a scroll view (these cards, and brief 49's match cards)
shows a coarse band along its lower edge in the preview on the simulator; cards in a `List` (Searches) do not. Screenshots:
`build/135-*.png`.

### Price monitors

**Price monitors** (brief 137, the owner 2026-11-02 on the sketch's section 3: the commonest page watch, "this product in
this shop", as a kind of its own that "should have the time change graph / data … like a toggle when creating the
search if data should be collected and if it should have an alarm (both choosable but one needs to be chosen) and
changeable anytime in the app"; the Arestemis repo, `docs/briefs/134-arestemis-price-monitor.md`, `~/Arestemis/docs/API.md` → Price monitors): a fourth kind, `price`
("Price monitor" / "Preismonitor"; `Model/PriceModels.swift`: `PriceSearch` (`url`, `history`, `alarm {below,
back_in_stock}`, `every`), `PriceState` on `HuntCard.price`, `PriceChange` on `Listing.price_change`, `PricePreview`,
`Prices`; read leniently: an unknown availability reads unknown, an unknown reader is kept (`PageReader`, on
`PageState` too since the server change described in the Arestemis repo, `docs/briefs/136-arestemis-browser-reader.md`), a product state that cannot be read leaves the card without it). New
search's card: "One product in one shop: its price history, and a word when it gets cheaper or is back in stock." /
"Ein Produkt in einem Shop: der Preisverlauf, und Bescheid, wenn es günstiger oder wieder lieferbar ist.", examples
"Price under € …" / "Preis unter … €" (the alarm on, its limit filled once the price is found) and "Back in stock" /
"Wieder lieferbar". **The form** (`Screens/PriceSearchScreen.swift`, `PriceSearchDraft`): Name (grey: the product
found, else the host), Product (the link; a pasted text keeps its first link) with the server's preview under it once
the link looks complete (a host with a dot and a path or query) and typing pauses (`PricePreviewModel`: one at a time,
never sooner than 5 s after the last, only the newest link, an answer for an older link dropped, a 429 waits its turn
quietly; "Found: NINTENDO Switch 2 · €483.99 · in stock" / "Gefunden: … · 483,99 € · lieferbar" in quiet type, the
server's refusal as a problem line), What it should do (`MonitorSwitchesCard`: Record the history "Price and
availability as a curve" / Verlauf aufzeichnen "Preis und Lieferbarkeit als Kurve", Alarm "A push when it happens" /
"Push, wenn es so weit ist"; the alarm opens Price under [ € ] (empty: no price condition) and Back in stock under it,
a little in; switched on without a condition, both come on with the limit a little under the price found,
`PriceLimit`: about 5 % under, rounded down to 1, 5, 10 or 50 €, 483.99 → 450; Save is off while both switches are off,
with one quiet line "At least one of the two." / "Mindestens eins von beiden.", an alarm without a condition says the
server's "Say when the alarm should ring."), How often (`ReadIntervalCard`, the watch form's, shared now). **The card**
(`PriceLines`, `PriceCardText`): the name (own, else the product, else the host), "host · Alarm under €450" or "· History
only" / "Nur Verlauf" (`PriceWords.mode`; under an own name the product first), the price large in the numbers' face
with the availability's word, the small 30-day line while the history is on (`PriceChartView(compact: true)`, loaded
per card and again after each new read, `ArestemisStore.loadPrices`, `MonitorRead`), "Checked …"; the read states as a
watch's (one quiet line instead of the price; blocked reads Stopped and adds "Saving it again tries again."; the
reader's note only on the page). **The page** (`Screens/MonitorPage.swift`, `MonitorSections`; Open in shop in
Listings' place beside Edit): Price history over 30 · 90 · 365 days (Swift Charts drawn as Aresium's `SeriesChart`: the
accent line 2.6 pt with round ends over a fainter area, as steps, `.stepEnd`, since a price holds until it changes; a
stretch out of stock dashed in muted ink over a faint band, with its key "- - - Out of stock"; the alarm's limit a
faint dashed rule; the newest point marked; "Lowest €449.00 · Highest €483.99" / "Tiefstpreis … · Höchstpreis …" from
the server; `PriceChart`), What it should do (the form's card, saved as it changes: `MonitorSwitches` refuses turning
off the last switch with the line, holds an alarm without a condition on the page until it has one, saves the limit
1 s after typing pauses; `ArestemisStore.saveMonitor`: shown at once, `PUT` with the whole search and the name as it is,
changes made meanwhile sent once it answers (the newest only), a refusal puts back what the server confirmed last with
a notice "Not saved. …"), Alarms (the newest three, while it has an alarm or found some; no figures). **An alarm**
(`Listing.price_change`, source `"page"`; `Match.isPriceChange`, `kind(of:)` asks it before a watch's change): its row
"Nintendo Switch 2: €449.00 (was €483.99)" / "… 449,00 € (vorher 483,99 €)" or "… is back in stock" / "… ist wieder
lieferbar" (`PriceWords.alarm`, the app's words from the change), the shop and when; its page the new price big with
"was €483.99" (or "back in stock") beside it, the product, the shop and when, Open in shop; Save and Dismiss only. Push
category `ARESTEMIS_PRICE` ("Open in shop" / "Im Shop öffnen"). **The watch form's examples** (`WatchChange`): chips
over "Tell me when": "a new version comes out", "a new entry appears", "a date changes", "own description" / "eine neue
Version erscheint", "ein neuer Eintrag dazukommt", "sich ein Datum ändert", "eigene Beschreibung"; a chip fills the
sentence and puts the cursor in it, the one tapped last shows chosen; "own description" empties an example's sentence
and keeps one's own words. The placeholder is now "3.4.0 is out, not a release candidate" and the caption "Pages behind
a login, or that need clicks (such as appointment bookings), can't be watched." (page reading improved on the server;
the Arestemis repo, `docs/briefs/136-arestemis-browser-reader.md`). Sample monitors 9 (Nintendo Switch 2 on MediaMarkt, history and alarm under €450 or back in stock,
a year of history in `Resources/prices-9.json` with two stretches out of stock; moved out of `Samples/` by brief 245 because the shipping tour reads it, so a fresh copy of the server's samples puts it there, not in `Samples/`), 10 ("Headphones", history only, `prices-10.json`) and 11 (LEGO Titanic, alarm when back in stock, no history, out of stock), with
alarms 39 (under the limit, new) and 37 (back in stock, saved) in `price-matches.json`; the server's own samples in
`ArestemisTests/ServerSamples/` (`server-prices.json` new). DEBUG `-openPriceForm`, `-newPriceForm` (`-priceURL
<text>`, `-priceSwitches both|history|alarm|none`, `-pricePreview reading|refused|failed`), `-newExample
priceBelow|backInStock`, `-openHunt <id>` with `-priceDays 30|90|365`, `-scrollTo history|switches|bottom` and
`-monitorLine refused|hold`. Tests: `PriceMonitorTests`. Screenshots: `build/137-*.png`.

### Price monitors everywhere ("Überall")

**Price monitors everywhere ("Überall")** (brief 157, the owner 2026-11-03: a price monitor for one product across shops, not on
one page; plan sections 3 and 4 with sketches; the server's brief 154,
`~/Arestemis/docs/API.md` → Price monitors everywhere). Part of the Preismonitor: `PriceSearch.mode` `page` | `everywhere`
(absent = page; a mode this build does not know makes the hunt unsupported, "Needs a newer app"; a page monitor is sent
as before, its four fields), `url` now optional, `product`, `details`, `identity` (`ProductIdentity`), `sources_off`;
`Offer`, `PriceSite` (kind and state kept when unknown), `ProductPreview`, `PriceOffers`, `PriceState.offers`
(`Model/PriceModels.swift`); `POST /price/preview {product, details}` (timeout 150 s: the server reads each comparison
site twice a minute apart) and `GET /hunts/{id}/offers` (`ArestemisStore.productPreview`, `loadOffers`, as the history:
again after each new read). **The form** (`PriceSearchScreen`): a segmented "One shop | Everywhere" / "Ein Shop |
Überall" at the top; a new form opens on Everywhere; each mode keeps its fields while the other shows
(`PriceSearchDraft.mode`, only the shown mode's fields compare and are sent; a kept draft without a mode is a page's).
Everywhere: Product (placeholder "z. B. AirPods Max 2"), the preview under it once typing pauses (1 s; the link's pacing
made generic, `PacedPreview` in `Model/PricePreviewModel.swift`, `ProductPreviewModel`): "Gefunden: <name>" over "in 2
Shops, ab 215,00 €" (sellers among its offers, the cheapest) or the server's refusal as a problem line; Details
(optional) ("z. B. Farbe Mitternacht oder Blau"); the quiet line "Sucht in 10 Shops · Ändern" (the sites on), opening
"Where it looks"; the switches; How often hourly or slower ("Shops prüfen"). Saving needs the product found for the
words as they are (`identity`/`identityWords`, `isConfirmed`; "Erst muss das Produkt gefunden werden."); a saved
monitor's own words take its saved product again without asking the server. **"Where it looks" / "Wo gesucht wird"**
(`Screens/PriceSitesScreen.swift`): the sites, those that have it first (`PriceSites.ordered`), each with a quiet state
("hat es", "wird geprüft", "gerade nicht lesbar", "hat es nicht") and a switch making `sources_off` (the last one on
stays, "Mindestens eine Seite bleibt an."); "Shop vorschlagen" at the end opens the shared contact form as "Idea or
wish" with "Shop vorschlagen: " started (`SupportSheet(kind:text:)`, Shared: the start alone is nothing written).
From the form it edits the draft; from the page it saves at once (`MonitorSitesPage`, `saveMonitor`). **The card**: the
product as the name, "Überall · 6 Shops · Alarm unter 220 €…", the cheapest price large with "bei Amazon · lieferbar"
beside it (`PriceCardText.shop`), its own words while it looks ("Shops werden durchsucht…") or finds none. **The page**:
"Günstigster Preis" (the same chart), "Shops" (`OffersCard`: one row per shop, its cheapest, shop and price,
availability, shipping and "über idealo" in the quiet line, each opening its link; five, then "+ N weitere Shops"),
the switches, "Wo gesucht wird · 9 Shops", the alarms; Open in shop opens the cheapest offer. **An alarm** names the
shop ("… 449,00 € bei MediaMarkt (vorher …)", `ArestemisStore.alarmShop(of:)` by the hunt's mode; the server's push
title does not). New search's example is "AirPods Max überall" (`SearchExample.everywhere`). Sample hunt 12 (the
server's `price-everywhere.json`, its offers `Samples/price-offers.json` with more shops, `prices-12.json`, alarm 42),
the preview imitated from `product-preview.json`. DEBUG `-priceMode page|everywhere`, `-priceProduct`, `-priceDetails`,
`-sitesOff <id,id>`, `-priceSites` (the form's sites once known), `-openHunt 12` with `-openSites` or `-scrollTo
offers`, `-suggestShop`. Tests: `PriceEverywhereTests`, Shared's in `EmpireTests/SupportTests`. Screenshots:
`build/157-*.png`.

### The tour

**The tour** (brief 139, the owner 2026-11-02: "it's not actually clear what Seite beobachten is for … add a tour to
Arestemis (like Aresium has)"; eight steps from the sketch's section 6; `Model/Tour.swift`, `Screens/TourScreens.swift`
on the shared pieces, below): the real tabs (`MainTabs`) on a world of its own, `TourWorld`: its own data in the app's
language (`Model/TourData.swift`, as Aresium's `TourData`; the main session's review: the English contract samples
showed in the German tour) served by `SampleBackend` in memory (no longer DEBUG-only; it takes a `SampleContent`, the
contract's files for `-sampleData` and the tests, `SampleContent.contract`, or the tour's; `ArestemisStore.isSample`
is honoured in Release for it), its own store, a session that never logs in, its own `AppNavigation` whose remembered
part lives in the defaults suite `de.ares-empire.arestemis.tour` (emptied when it starts and ends). **The tour's
data** (`TourData.content(now:language:)`): four searches, one of each kind (a flat or WG room in Munich or Garching;
Herman Miller Aeron; the watch "Schnitzel at the Mensa" / "Schnitzel in der Mensa" on the Mensa's menu; the Nintendo
Switch 2 at MediaMarkt with its alarm), the flat's new listing (step 6) and its two filtered-out ones (step 8), three
chairs, the menu's change and the console's alarm, the kinds' names; its words in the String Catalog (names stay
names, money and dates by the app; listing titles read like listings in each language), built as the server's JSON
and read through the app's decoders, times around `now`; the console's history is the contract's `prices-9.json`
(numbers only) moved to now; a made-up application text in the app's language, signed "Alex". The account's store,
login, drafts and defaults are never touched (`TourTests`). Settings behind the gear stays the account's own.

### When

**When:** by itself once per account on this iPhone (`TourOffer`, key `arestemis.tourShown.<account id>`, set when it
starts) 0.8 s after the account's main screen first shows, never in sample mode and never while a notification or link
is opened, a sheet is up or a page is pushed (then the next launch tries again); Settings → Help → Tour of Arestemis
("With sample searches") at any time (`TourRunner`, owned by `ContentView`), in place of the account's tabs without a
fade (a scroll issued while the tabs faded in was lost at times). A notification, a link or logging out ends it first.

### The steps

**The steps** (`TourStep`, `TourSpot`; each rings its part of the real screen, Next gets that screen ready again): 1
Arestemis searches for you (the Hunts list, no ring), 2 New search (its page, the first kind's card), 3 A
search (the first search's card), 4 Listings → New (the newest listing's row, whose swipe works), 5 Listings → Searches
(the magnifying glass), 6 A listing (a flat's page, its facts card since brief 142), 7 Price monitor and Watch a website (the watch's and
the monitor's cards that stand together, one ring; a line each, led by the kind's name), 8 Filtered out (the flat
search's listings at New, its Filtered out row; a tap opens the sheet, without the card, which covered its
reasons at the sheet's height; closing it brings the card back). **The card**: "3 / 8",
Skip, the step's title over one or two sentences, Next (Done at the last) in the accent; the ring in the accent; the
card's glass without its blur (`glassCard(blur: false)`, the wall's colour in its place): the searches' pulse moves
under the card, and a blur there was taken again every frame with a group pass (`scripts/offscreens`, step 3: about 1
group and 4 mask/group passes per frame with it, none without, as the app without the tour). The
card sits on each tab's NavigationStack (it stays put while pages are pushed, under the undo bar) and every page of the
stack keeps its room (`tourCardRoom`, `TourModel.cardRoom`: a stack's inset does not reach its pages); a scroll view
shows the ringed part within its safe area (`TourGuide.cardRoomInSafeArea`), again once its height settles. **A
listing's page fades under its bar** (brief 139's review: scrolled, the title ran on under the back button): iOS's own
top edge effect hidden (`scrollEdgeEffectHidden`, it showed a blurred copy of the content no wall covers) and the
wall's fade from the screen's top (`edgeFade(top:bottom:underBar:)`: the scroll view's drawn area stops at its frame
there, so the wall covers above it by itself). DEBUG `-sampleData -tour <1–8>`. Tests: `TourTests`. Screenshots:
`build/139-step{1..8}-{de,en}-{light,dark}.png`.

### A listing reads like a listing; New search guides

**A listing reads like a listing; New search guides** (brief 142, the owner 2026-11-03 after builds 12–13: the long "why
it fits" was not needed, "it fits because of the filter"; the colourful Bewerbung button hid Open; New search was "lots
of concentrated reading"). **The listing page** (`MatchDetailScreen`, `Model/ListingPage.swift`, facts in
`Formatting.swift`/`ItemFormatting.swift`): the price, title and site, then one card of facts in a portal's way, every
fact the search asks about always there with a muted "–" when the listing does not state it (VoiceOver "not stated";
a flat: warm and cold rent, size or room size, rooms, flatmates for a WG room, move-in, until, furnished, location,
kind, posted; a thing: condition, delivery, distance while pickup counts, seller, place, posted), and the AI's
`warnings` under "To check" / "Zu prüfen"; "Why it fits" is gone from the page (`reason` stays in the data and on
Filtered out). The description in full; when `Listing.description_partial` (the Arestemis repo, brief 141) is true, "Only
a preview. The whole text is on Immowelt." / "Nur ein Auszug. Den ganzen Text zeigt Immowelt.", which opens the
listing. **Open on <site>** is the main button in the accent; "Application text" / "Bewerbungstext" a quiet one with
a document symbol under it (also the push's action and the sheet's title). **New search**: one card per kind with
its mark large in a calm tile (not the accent: four accent marks on a page without a main action), the name strong, one
short line in muted ink ("Neue Wohnungen und WG-Zimmer, sobald sie online sind." …, no site lists), one example chip
after "z. B." (one list card, a 2×2 grid and accent tiles were tried and dropped: `build/142-variants/`). Sample
`Samples/immowelt-match.json` (match 27, a preview). Tests: `ListingPageTests`, `NewSearchTests`, `TourTests`.
Screenshots: `build/142-*.png`.

### Asking prices

**Asking prices** (brief 256, the owner 2026-11-05; the Arestemis repo's brief 254, `~/Arestemis/docs/API.md` → Thing
asking-price records): the server keeps the asking prices of a Dinge search's fitting listings, within its limits, for
30 days (`GET /hunts/{id}/price-record` → `ItemPriceSummary`), and a match may carry `price_verdict`
(`ItemPriceVerdict`: cheap, expensive, unusually cheap); every text comes in both languages (`LocalizedText`), the app
picks its own (`Model/ItemPriceModels.swift`, words in `Model/ItemPricePresentation.swift`, screens in
`Screens/ItemPriceViews.swift`). Read leniently: a verdict that is missing, malformed or of an unknown kind is none; a
404 or a failure shows nothing (`ArestemisStore.loadPriceRecord`, with the page, again after a newer scan or a changed
search, `PriceRecordRead`). **A search's page** ends, under Latest so the listings stay where they were, with "ASKING
PRICES · Last 30 days" / "ANGEBOTSPREISE · Letzte 30 Tage": one glass card with the server's `display` one fact per
line (split at " · "; a number keeps its word, `PriceText.keepingNumbersTogether`), then while two or more sites have
offers one row per site (its usual range, or its count below 8 offers), the server's note under the card as fine
print; no offers yet: one quiet line "Noch keine Preise. Sie kommen mit den ersten passenden Angeboten.". **A row**
(`MatchRow`, things only): under the price a small label, text only like the row's other labels, mark + the server's
label: ↓ Günstig in the accent, ↑ Teuer in ink, (!) Ungewöhnlich günstig – genau prüfen (`exclamationmark.circle`) in the warnings' amber. **A
listing's page**: under the price, title and site, the server's line with its label in that tone and the rest quiet
(`PriceVerdictLine`; the note stays with the search's card, Claude's review). No verdict, nothing. Sample mode (`PriceRecordSample`): hunt 2 rich (23 offers,
€400–450, Kleinanzeigen and eBay), 31 cheap, 30 expensive, an invented 43 at €95 unusually cheap; hunt 5 few; hunt 4
none. DEBUG `-sampleNoPrices` (as a server from before it), `-openHunt <id> -scrollTo prices`. Tests:
`AskingPricesTests`, `ServerSamplesTests` (the server's four `item-price-*` samples). Screenshots:
`build/256-*.png`.

### Look hunts and votes

**Look hunts and votes** (brief 268, 2026-11-12; the Arestemis repo's brief 267, `~/Arestemis/docs/API.md` → "brief
267"): a Dinge search may carry `look` (Claude judges the listing's photos against it) and `look_min`; the app has no
editor for them yet but always decodes and sends both, so editing such a search keeps them (the server also keeps
them when an older app omits them). A finding with `Match.look` (`LookVerdict`: score, length, cut, fur, reasons;
unknown values read as unknown) shows under the price, title and site "Look 8/10" in the accent with thumbs up /
down at the row's right (`LookLine`, `LookVoteButtons` in `Screens/LookViews.swift`; SF Symbols, filled in the accent
when chosen, 44 pt, "Good find" / "Guter Fund", "Not it" / "Nicht das"), the reason in the app's language whole, and
"Long · Men's cut · Real fur" muted. Filtered out of a look hunt: the listing's photo beside the words, "Look 4/10:"
a little stronger, compact thumbs at the card's foot. A tap on the chosen thumb takes the vote back; votes are
optimistic with rollback (`ArestemisStore.setVote`, `POST /matches/{id}/vote`, `POST /rejected/{id}/vote` with
`{"vote": "up" | "down" | null}`) and never move an entry between lists. **Photos** (every listing page): a swipeable
gallery from `Listing.photo_urls` (up to four; else `image_url`; `ListingGallery`), a look hunt's 4:5 and other
things square showing the whole photo on a mat, a flat's 16:10 filled; row thumbnails use the first photo. Sample:
hunt 5 is a fur coat look hunt with made-up coat drawings under `sample://` (`Samples/look-*.jpg`, Debug only,
`debug_only` in `scripts/release-resources.json`); never real portal photos on the Mac. DEBUG `-sampleData
-sampleLook -openMatch 34` (`-sampleLookVote up|down|none`), `-openSearch 5 -openSheet rejected`. Tests:
`LookVotesTests`, `LookPresentationTests`. Screenshots: `build/268-design-*.png`.
