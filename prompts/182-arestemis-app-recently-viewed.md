# 182: Arestemis app: an opened listing leaves New, "Zuletzt angesehen" keeps it for a week

Status: merged (Claude agent build, Claude review; 429 tests passed; Arestemis build 22)
Branch: `claude/182-recently-viewed` · Worktree: `../empire-ios-182-recent` · Builder: Claude agent (design)

## Goal

Build 20 (brief 180) marks a listing read when its page opens, and read listings stayed in Angebote → Neu without
their dot. Patrik, 2026-11-05: "It should leave neu. Not sure to where. Like a past / history sort of thing but limited
time maybe? Because if you want to look at it again just favor it". Decided (Claude):

- **Neu shows only unread listings.** Opening a listing takes it out of Neu (when the person comes back from its page,
  it is gone; never while its page is open).
- **"Zuletzt angesehen" / "Recently viewed"** holds the listings opened in the last 7 days that are still new (not
  favourited, applied or dismissed), the latest opened first. After the 7 days a listing is only in its search's
  "Alle" and in the search over listings. Favoriten stays the way to keep one.

The server is built (Arestemis brief 181, being deployed): build from the contract below.

## Read first

- `AGENTS.md` and `CLAUDE.md` (always: the design rules at the top, "Languages", "Light mode", the Arestemis entry, above
  all "Angebote as New | Searches"), `~/ares-empire/EMPIRE.md` → design language.
- The contract: `~/Arestemis/docs/briefs/181-recently-viewed.md`, `~/Arestemis/docs/API.md` (search for "brief 181":
  `Match.seen_at`, `GET /matches?recent=true`); the new server sample `~/Arestemis/docs/samples/matches-recent.json`
  (copy it into `ArestemisTests/ServerSamples/` and decode it in `ServerSamplesTests`, as brief 180 did; the other
  server samples now carry `seen_at: null`, copy them again too).
- `Model/AppNavigation.swift` (`MatchFilter.seen`: its comment names the one line), `Model/ArestemisStore.swift`
  (`ListScope`, `list(_:hunt:)`, `matches(_:hunt:)`, `loadMatches`, `markRead`, `setState`, `rejected`/`loadRejected`),
  `API/ArestemisAPI.swift`, `Model/SampleBackend.swift` (or wherever sample mode answers `matches`),
  `Screens/ListingsScreen.swift` (`NewPart`, `FilteredOutButton`, `SearchListingsPage`, `ListingsRoute`),
  `Screens/ListingRows.swift`, `Model/ArestemisModels.swift` (or wherever `Match` lives), `Localizable.xcstrings`, the
  tour (`Model/TourData.swift`: its listings must stay unread so step 4 still rings one in Neu), and the tests next to
  them (`ListingsTests`, `ReadListingsTests` or brief 180's tests).

## Build

### 1. Neu is unread only

- `MatchFilter.seen`: `.new` asks `seen=false` (both Angebote → Neu and a search's own "Neu" filter). Update its comment.
- When a listing's page opens, the store marks it read as today and it leaves the New lists locally; the person sees it
  gone when they come back (a short removal animation is fine; nothing moves under the open page). A group in Neu
  disappears with its last unread listing, as today.

### 2. "Zuletzt angesehen"

- Decode `Match.seen_at` (optional date; missing = nil). The store keeps a Recently viewed list per scope (all searches,
  and one search: `GET /matches?recent=true[&hunt=<id>]`), loaded together with Neu (and on pull to refresh), like
  Filtered out. Opening a listing puts it at the top of the loaded lists at once with `seen_at` now (the next load
  confirms); favouriting, applying or dismissing takes it out at once; setting it back to new brings it back while its
  first opening is within the 7 days (or simply at the next load: your choice, keep it simple and right).
- **Angebote → Neu**: after the listings and before "Filtered out", one row in Filtered out's look:
  "Zuletzt angesehen" with its count (en "Recently viewed"), shown only while the list has listings. Do not copy
  `FilteredOutButton`: make the one row component take its words and symbol (a clock, `clock.arrow.circlepath`, is
  a fair choice; yours to pick) and use it for both.
- The row pushes a page on the Angebote stack (`ListingsRoute.recent(hunt:)`): the title "Zuletzt angesehen", one quiet
  line on top saying what it is and how to keep one (en e.g. "Listings you opened in the last 7 days. To keep one, mark
  it as a favourite." / de "Angebote, die du in den letzten 7 Tagen geöffnet hast. Behalten: als Favorit markieren.";
  you may word both better, short and plain, "du", no "KI"/"AI"), then the listings as the usual rows (`ListingRow`:
  tap, swipes, long press as everywhere; no dot, they are read), latest opened first; over all searches, each row with
  its search's mark and name above it as the search over listings does. Empty (everything favourited or dismissed
  while the page is open): a calm line. Loading and failure as the other lists.
- **A search's own listings page** (`SearchListingsPage`) gets the same row for its own Recently viewed (with `hunt`),
  where its own Filtered out row is.
- Sample mode imitates the server (opened listings with `seen_at`, 7 days, order); add a DEBUG argument to open the
  page (e.g. `-openRecent` with `-sampleRead <ids>`).

## Settled: do not re-open

- Opened = read = out of Neu. 7 days, decided on the server; the app never counts days itself.
- Nothing is dismissed or changed by itself; Recently viewed is only a list.
- No new component style: Filtered out's row, the usual listing rows, the quiet line.

## Out of scope

- The server; the hunt cards' "● N NEU" counts (already unread); Favoriten.

## Done when

- `xcodebuild test` passes on your own simulator (commands in `AGENTS.md`), with new tests for: `.new` asking
  `seen=false`; decoding `seen_at` (present, missing) and `matches-recent.json`; opening a listing taking it out of Neu
  and into Recently viewed at the top; favourite/apply/dismiss taking it out; the row shown only with listings and its
  count; the page's order; a search's own row asking with `hunt`; the words in both languages.
- `scripts/strings.py check` says 0 problems.
- Screenshots in `build/182-*.png`, light and dark, German and English, at the smallest phone width: Angebote → Neu with
  the row (and with Filtered out under it), the Recently viewed page, a search's listings page with its row, and Neu
  when everything was read (the calm line and the row).

## Final message

Files changed, the exact build and test summary lines, the screenshot paths, new DEBUG arguments, what is missing or
doubtful.
