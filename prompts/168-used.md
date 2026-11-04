# 168: Arestemis: also used in Everywhere

Status: running; server167 contract committed eb91f7a
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
