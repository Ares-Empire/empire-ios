# 168: Arestemis: also used in Everywhere

Status: root reviewed; full simulator suite and localization passed; 104 screenshots ready for Claude
Branch: `codex/168-used` · Worktree: `../empire-ios-168-used` · Model: `gpt-6.1-sol`, effort `xhigh`

## Goal and read first

Patrik wants “Auch gebraucht”: an Everywhere form switch and a separate “Gebraucht” list on the monitor page. The
server finds used listings for the same product and handover; a price alarm may notify below its limit. The app
presents those ordinary listings without mixing them into the new-goods shop prices or curve.

Read AGENTS.md; CLAUDE.md design/Languages/Light mode/Arestemis; README/docs/DEVELOPMENT; prompts164/166 Results;
read-only `~/Arestemis/docs/API.md` committed167 contract/samples. Existing PriceSearch/draft/monitor/form, normal
listing rows/detail/actions/filters/pagination, Store/session fences and fake/sample backend. The API is given; no
invented fields or local portal inference.

## Build, settled design

- Everywhere PriceSearch/draft gains include_usedBool defaultfalse, explicit in new requests, lenient missing on old
  hunts/drafts. Page wire encoding remains fourfields and ignores it. All edits preserve original
  words/identity/handover/places/radius/sources/alarm/history/every/name. Toggling used does not reset the confirmed
  product or trigger a product-identity HTTP preview; used lookup begins on save/start. Saved state/dirty checks and
  refresh match server.
- One calm existing switch card under Handover and before What it should do: “Also used” / “Auch gebraucht”. No
  paragraph, decoration, new colour or user-visible implementation. Only Everywhere. Preserve166handover
  and164compact comparison label/Things route.
- Where it looks continues to configure the existing new-goods sites. While include_usedtrue make that count
  unambiguous, with short “New goods · %lld sites” / “Neuware · %lld Seiten” in the form; on the monitor's row use
  the same meaning within available space. Source rows/capability rules remain server-based. Do not count/invent
  used portals in this number or add a second source picker.
- Add a separate MonitorSection “Used” / “Gebraucht” on the Everywhere monitor page below the shops section and
  before settings. Load GET/hunts/{id}/used, using ordinary listing rows and detail/actions, not shop quote
  rows/cards. Show the newest5 inline and “Show all” if more; the opened existing-style listing page supports
  next-page before cursor and state filtering New/Saved/All (use existing wording/components). No duplicate
  notification switches or alarm explanation; monitor alarm remains its existing control. Display normal
  condition/price-kind/shipping/distance facts as the current item rows do, including auction bids as bids, never as
  purchase totals.
- Section enabled with include_usedtrue even empty, with one plain empty/loading/retry state. When turned off,
  retain access to previously saved/known used matches (server still serves them), show section when it has records;
  don't suggest a hunt still runs. No extra hunt in the hunt list or new tab. Counts, parent routing and
  matches/actions come from server. Both saved and dismissed actions update the inline/full/global lists using
  shared match identity. Tapping push/detail uses normal item screen with parent monitor route.
- Backend/store calls follow existing account/refresh/cancellation fences; stale answers after signout/delete/hunt
  edits cannot repopulate. Pagination deduplicates by match.id, obeys more and before, keeps existing values on
  retry, resets on current hunt/filter/account. Simultaneous state changes and pages must not restore an old match
  state. Do not locally choose which listing is used or whether to notify; server owns matching/price policy.
- Use the general short German “Im Geschäft” for the existing In store method; it applies to every store. Update its
  existing translation/tests and include the normal offer screen in screenshot QA.
- The form’s preview amount must honor current sourcesOff: filter the server-ordered quotes before selecting its
  first eligible total. Never recompute costs or invent a preview request field for exclusions; the shared raw
  preview remains public. Pin switching off the initially cheapest source.
- Prepare the existing offer rows for step6 last-good retention without a new API field: when the returned PriceSite
  for an offer has state unreadable, mark that retained row “Last confirmed” / “Zuletzt bestätigt” with its actual
  Offer.checked time when available. Do not show an invented fresh check time or hide the total. Use existing source
  state and checked fields; no per-site findings. Include a retained-offer screenshot and formatting test.
- Keep new-goods offer prices/selectedTotal/curve unchanged. Used API returns normal MatchPage; listing.item drives
  detail type even though public hunt_id points at a price monitor. Price push matches still open their price-change
  detail normally. Existing flat/item/page hunts remain.

## Claude review fixes to fold in (questions.md, 2026-11-04)

Claude reviewed166and requested these while this brief already touches the monitor page. When the chosen shop/store
+ handover + stock line does not fit comfortably beside the big price, put that whole line below the price
(ViewThatFits or equivalent existing layout); do not squeeze it into three narrow lines. Preserve compact card
behavior where it fits. For pickup, show “vorrätig” / “in stock” for confirmed stock; delivery wording “lieferbar”
remains for shipping. Use a context-specific localized value so the existing shipping translation is unchanged. The
new fixtures/tests/screens must include a long store+city name at the large monitor price in both languages/looks
and shipping/pickup stock wording.

## API

Server167 docs/API.md: PriceSearch.include_used defaultfalse, `GET
/hunts/{parent}/used?state=...&limit=...&before=...` → MatchPage{items,more}; normal
Match.id/state/hunt_id(parent)/Listing.item and normal GET/matches/{id}, POST/matches/{id}/state actions. Defaults
all nondismissed; explicit states match existing constants/bounds. No q on usedroute. Other kinds404. No internal
child fields/IDs are public.

## Checks and screenshots

Unit tests for absent defaults/explicit encoding/page shape/draft persistence and toggling without identity
invalidation; contract/samples; used list request/state/cursor/dedup/error/session fences; same-match actions
inline/full/global; parent item detail vs normal price-change detail; enabled-empty and off-retained cases;
counts/source copy bilingual. Meaningful cases, no test mirroring a helper alone.

Own iPhone17 iOS27.0 simulator, entire xcodebuild test with own derived data; strings sync restore all other apps
and “Could not load older listings.”; fill German with strings.py fill/check0. All changed states/screens DE/EN ×
light/dark to build/168-*.png: toggle off/on, pickup+used, monitor populated/empty/error, full Used page/state
selection, item detail/actions, retained saved while off. Wait for actual state/navigation before screenshot,
inspect all, provide manifest and exact arguments/test results. Shut down/delete own simulator. Worktree only; no
network/server/Keychain/install/commit/push/merge, Shared design/project/buildnumber/login untouched. No TestFlight.
No private source findings or personal/seller data in this public repo. Fixtures entirely fictional.

## Done

All checks pass, all screens readable and use existing components, API/samples current, report exact
files/commands/results/gaps. Claude reviews screenshots and uploads later.


## Root review follow-up: price alarms beside used listings

The server contract in `~/Arestemis/docs/API.md` now settles optional `GET /matches?kind=price`, selecting listing
kind before pagination/search/limit. Missing kind still returns mixed parent/global results. Other allowed kinds
are flat/item/watch; invalid or empty kind is400. The Used endpoint and mixed overview/counts stay as above.

The first implementation filters mixed latest results; newer used listings can hide an older price alarm.
A client cursor scan has been added during its review; complete the integration with the server's explicit kind
filter and a true paginated Alarms page. No new wire fields or local kind inference beyond Listing's existing data.

Add backend `priceAlarms(hunt:state:limit:before:) -> MatchPage`, using the existing GET/matches route with kind=price.
Filter sample data before pagination. Preserve unrelated test fakes through protocol defaults where suitable,
while live API and focused tests prove the actual kind query. All price monitors load their latest three actual
alarms through this request, including used-off monitors retaining matches. Alarms/Show all opens a price-only
page with ordinary New/Saved/All rows, detail/actions and cursor/retry behavior. Generic parent/global lists stay
mixed; Used stays item-only and calls its existing endpoint.

Reuse the new used page and loading machinery with a typed Used/Alarms scope whose cache key includes hunt,
filter and kind. Keep shared match IDs/actions, account and hunt/edit fences, deduplication and preserved rows on
retry; avoid a third duplicated pager. Keep ordinary Item/Watch/Flat navigation and every original168deliverable.
User-facing copy stays the existing Used/Alarms words and listing components, without explaining API internals.

Meaningful regressions: an older alarm behind more than three newer used matches, more than one interleaved
page, both latest and Alarms/Show all retain the alarm and exclude used rows; Used excludes alarms, mixed parent
results include both. Pin the wire kind query, distinct scope cursors, stale edit/signout replies and shared saved
state actions. Add a monitor fixture showing both sections and full Alarms page, DE/EN in light/dark.

The retained-offer screenshot currently has an eligible amount but a confirmation date more than24hours before
the screenshot. Use a plausible2hour-old timestamp or an injected coherent fixture clock for that scenario and
regenerate its four looks. Server remains responsible for eligibility; no app-side price/age calculation.

After this follow-up, run the whole simulator suite and strings check0; keep the original screenshots/manifest
and add or regenerate changed ones. Inspect every final screenshot, copy remains with orchestrator. No commit,
push, live/network/Keychain/server, Shared/project/buildnumber changes or TestFlight. First builder's other fixes,
all handover/preview/source wording and Claude's layout/stock wording are retained.

## Result (2026-11-04)

Implemented the Everywhere used switch, explicit persisted requests, separate Used and price-only Alarms
sections/pages with shared normal listing details/actions and fenced pagination. New goods source counts and
preview exclusions are respected. Pickup stock wording, the general German “Im Geschäft”, the long shop line
below the price, and original-time Last confirmed rows are included. Existing comparison labels and Things
routing remain. Server API contract and fictional samples are current.

The builder's final full simulator suite passed374tests (554 expanded cases), zero failures/skips. The
orchestrator independently ran `xcodebuild test -project Arestemis/Arestemis.xcodeproj -scheme Arestemis
-destination id=E1C33E33-65B4-43E3-959F-B19A4A87D8E1 -derivedDataPath build/RootReviewDerived` on its own iPhone17,
iOS27.0:374tests in31suites, zero failures,28.954s. Root read every feature/test/sample diff. Runtime/test/sample
bytes stayed unchanged after that run; the catalog sync only removed an unused newly added key.

Root ran `scripts/strings.py sync`, restored other catalogs and “Could not load older listings.”, checked German
translations and `scripts/strings.py check`:0problems. No Shared, project, login or build number changes. Root
visually inspected all104 final screenshots (26states × DE/EN × light/dark), including both monitor sections,
full Alarms filters, Used retained while off, auction/detail, source exclusion, retained date and long store.
Original PNGs and their launch/readiness manifest were copied to the orchestra screens/runs directories for
Claude; own simulator was deleted. No TestFlight upload. Server matching is being verified live separately;
this app adds no local matching rule.
