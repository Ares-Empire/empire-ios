# 01: Aresium app foundation and the three main screens

Status: merged 2026-10-23. 21 tests (incl. Claude's check that every list matches the website on the server sample, 511 values). Live login not tried yet.
Branch: `codex/01-aresium-foundation` · Worktree: `../empire-ios-01-aresium-foundation` · Model: `gpt-6.1-sol`, effort `high`

## Goal

The Aresium iPhone app logs in with an Empire account, loads the dashboard from the Aresium API and shows
the same three screens as the mobile website: start (Expenses/Income), a category by month, and a
category's transactions in one month. It should look and feel like the mobile website, as native SwiftUI.

## Read first

- `AGENTS.md`, `CLAUDE.md`, `README.md` (always).
- **The API:** `~/aresium/docs/API-DATA.md` (version 2 of `/api/data`; the server is being switched to it in
  parallel, so build against the doc, not against the live server). Auth: `~/aresium/src/web/empire-auth.ts`,
  `~/ares-empire/docs/ACCOUNTS.md`.
- **The template (mobile website):** `~/aresium/web/public/app/mobile.jsx` (screens, navigation, controls),
  `~/aresium/web/public/app/panels.jsx` (`CategoryListPanel`, `MonthListPanel`, `TransactionsPanel`, `fmtMoney`),
  `~/aresium/web/public/app/chart.jsx` (chart look), `~/aresium/web/public/index.html` (CSS: colour tokens in
  `:root` / `[data-theme]`, the `mob-*` classes for sizes, spacing and type).
- Other repos are read-only for you. Write only inside your worktree.

## Build (all inside `Aresium/`)

1. **Models** (`Aresium/Model/`): `Codable` types exactly matching `API-DATA.md`.
2. **Sample data:** a small hand-made `Aresium/Preview Content/dashboard.sample.json` that follows the contract
   exactly (3 months with the last one partial, ~6 categories incl. one income and one transfer, ~25
   transactions incl. a tagged one, a refund and an uncategorised payment in). Used by previews and tests.
   Claude will later swap in the server's generated sample; your decoding must not depend on your file's quirks.
3. **Empire login** (`Aresium/Auth/`): email + password →
   `POST https://auth.ares-empire.de/api/collections/users/auth-with-password` with `{identity, password}` →
   `{token, record}`. Store the token in the **Keychain** (never `UserDefaults`, files or logs). On launch, renew
   it with `POST https://auth.ares-empire.de/api/collections/users/auth-refresh` (`Authorization: <token>`); on
   400/401 show the login screen. Log out deletes the token. Show PocketBase's error message on failure.
4. **API client** (`Aresium/API/`): base URL `https://aresium.de`; `GET /api/data` with
   `Authorization: Bearer <token>`; a 401 logs out. Built so a test can inject a fake transport.
5. **Store:** one `@Observable` object holding the decoded `Dashboard`, loading state and errors, with
   `reload()`. Clients only look up, filter and sort (the table "What clients do" in `API-DATA.md`); no money
   is calculated in the app.
6. **Screens** (`Aresium/Screens/`), following `mobile.jsx`:
   - **Header:** Hermes mark (copy `~/aresium/web/public/brand/hermes.png` into the asset catalog) or a back
     button; title and subtitle per screen; theme toggle (dark ↔ light); log out.
   - **Start:** `Current` / `Overview` segmented control (current = latest month, overview = all time); a graph
     toggle that reveals the chart (current: per day; overview: per month); two swipeable pages, Expenses and
     Income, with page dots; each page shows the range label, the side's total (`expense` / `income`, never the
     sum of the rows) and the category rows (icon, name, amount, bar). Tapping a row opens the category.
   - **Category:** months with a value > 0, in the same order as `MonthListPanel`; or with the graph on, the chart
     by month, and tapping a month opens it.
   - **Category in a month:** the transactions (day, place, city, amount; a marker when it is only listed
     here via an "Add" tag), as `TransactionsPanel`.
   - Pull to refresh reloads. Loading and error states that do not hide stale data.
7. **Look:** colours from the website's CSS tokens for dark and light (expenses `#FF2D4B`/`#E11030`, balance
   `#2E8BFF`/`#1452F0`, income `#34E27A`, backgrounds and inks from `index.html`); Space Grotesk for text and
   JetBrains Mono for numbers. The font files are in `Aresium/Fonts/` (variable fonts, OFL); register them at
   launch with Core Text, no Info.plist edit. Category colours come from the API. Category icons: the API sends
   Lucide names (Beer, CircleHelp, Code, Dumbbell, GraduationCap, Handshake, House, Laptop, Palmtree, Pill,
   Receipt, Repeat, RotateCcw, Scissors, Shirt, ShoppingBag, ShoppingCart, SprayCan, Tag, TrainFront,
   TrendingUp, Tv, Users, Utensils, Wallet); map each to the closest SF Symbol, fallback `tag`.
   Charts with Swift Charts (area + line, like `chart.jsx`). Money formatted like `fmtMoney`.
8. **Tests** (`AresiumTests/`): decoding the sample; the store's lookups for a category's months and a month's
   transactions (filter, sort, "tagged" flag) against known answers from your sample; the API client sends the
   Bearer header and logs out on 401 (fake transport); the Keychain wrapper saves, reads and deletes.

## Settled: do not re-open

- Native SwiftUI, iOS 26+, no third-party packages; Swift Charts for charts.
- Navigation with `NavigationStack`; the swipe pages with a paged `TabView` (or equivalent native paging).
- The app never calculates totals or series; it reads `API-DATA.md` version 2. If something you need to show
  is not in the contract, write `TODO(api)` and list it; do not compute it.
- Only dark and light themes now.

## Out of scope (later briefs)

- Transaction detail and recategorise (`TxnDetailModal`), import (file picker and share sheet), the red
  "Aresium mode" with the ARESIUM band and intro animation, widgets, signing and TestFlight.

## Done when

- `xcodebuild test` passes on your own simulator (commands in `AGENTS.md`), with the tests above.
- The app launches on your simulator in a sample-data mode (a launch argument, e.g. `-sampleData`, that skips
  login and loads the bundled sample) and you saved screenshots to `build/01-start.png`, `build/01-start-income.png`
  (income page), `build/01-category.png` and `build/01-category-month.png`. Navigate there with launch arguments
  or a UI test; say which.

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshots you saved, any
`TODO(api)`, and what is missing or doubtful.
