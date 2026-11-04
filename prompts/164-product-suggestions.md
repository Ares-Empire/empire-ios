# 164: Arestemis: product suggestions and the price comparison label

Status: merged; app ready for review (round 2, step 3)
Branch: `codex/164-product-suggestions` · Worktree: `../empire-ios-164-product-suggestions` · Model: `gpt-6.1-sol`, effort `xhigh`

## Authorization

Patrik explicitly assigns the screens to Codex for this round; this overrides the usual Claude-only design workflow. Use the existing components carefully and capture every changed state for Claude’s review.

## Goal

When the Everywhere words name a family or kind, show at most four concrete choices and a short route to all offers in Things. Patrik: “good but let's not make it too long.” Where it looks gains one small “Preisvergleich” label under the comparison sites.

## Read first

`AGENTS.md`, `CLAUDE.md` (top design rules, Languages, Light mode, Arestemis entry), `README.md`, `docs/DEVELOPMENT.md`, prompt 157; `~/Arestemis/docs/API.md` (price preview's structured product refusal, added by brief 163, read only), and its samples. Existing `PriceSearchScreen`, `PriceSitesScreen`, `PricePreviewModel`, `PriceModels`, `ArestemisAPI`, `ItemSearchScreen`/draft, `NewSearch` chips and navigation, existing tests.

## Build and settled design

- Use the server's `400 field: product` optional suggestions/item_search fields exactly as documented. Keep old-server refusal and successful-preview decoding lenient. No client-side product inference.
- In the Everywhere product section, a calm “Did you mean…” / “Meintest du …” line, then up to four chips in the existing New search chip style. Long names wrap naturally at normal type size. No new icon, card decoration or slogan.
- A chip puts that suggestion into Product, keeps Details, clears old confirmation, then runs the existing paced preview. Saving remains unavailable until the new identity is confirmed. Stale answers/suggestions disappear when the words change, including concurrent or 429 cases.
- One quiet text row below the choices: “All offers for ‘Lenovo Laptop’ → Things search” / “Alle Angebote zu „Lenovo Laptop“ → Dinge-Suche”. It opens the normal Dinge form, original query and details filled from item_search; it creates/saves/starts nothing. Back returns to the intact Everywhere draft. Even zero suggestions can show this row after a completed family/generic refusal. No row for a transient unavailable response.
- Under the names of idealo, billiger.de and Geizhals on Where it looks, show “Price comparison” / “Preisvergleich” in the existing small secondary style using PriceSite.kind comparison. Keep the existing site state; fit both in the row calmly without an explanatory paragraph. Unknown site kinds remain supported leniently.
- Preserve page previews, normal New search examples, unrelated forms and login. Keep logic/data out of views; no shared design changes or project file edits.
- Add synthetic sample/debug launch arguments for a family with four choices, generic words with zero choices, a chip after re-preview, and the prefilled Dinge route. Sample names/data invented. UI code English, German via catalog. Run scripts/strings.py sync; undo changes to other apps' catalogs and restore Arestemis “Could not load older listings.” if dropped. Fill German and check 0 problems.

## Tests and screenshots

Use your own codex-164 iPhone 17 simulator, iOS 27.0 only, output under build/. Test response decoding with/without fields, four-choice bound, stale/429/cancel behavior, chip clearing confirmation and asking again, original query/details navigation with draft retained, kind-based flag, page mode unchanged.

Run `xcodebuild test -project Arestemis/Arestemis.xcodeproj -scheme Arestemis -destination id=<own udid> -derivedDataPath build/DerivedData`. Save screenshots from the installed app of every changed screen in English/German × light/dark: four choices, zero choices, chip confirmed, prefilled Things form, Where it looks. Keep all under build/164-*.png. Shut down your simulator when done; report its UDID. Orchestrator independently builds/tests/reviews and copies screenshots for Claude.

## Out of scope

Server changes, site-reading implementation details, delivery, used listings, TestFlight, build-number bump, other apps. This repo is public: describe the feature only, with no personal data or private implementation/research findings.

## Done when

Build/tests pass, strings check has 0 problems, screenshots complete and reviewed by you. No commit/push/merge, installs of tools/runtimes, server access or network except Xcode's existing build needs. Final message: changed files, exact test/build summary, strings and screenshots, any missing API or doubts.

## Result (orchestrator review, 2026-11-04)

Read every diff and independently ran the whole app test suite on a separate iPhone17/iOS27.0 simulator: **332tests/485parameterized runs/0failures**. Strings check0problems; sync preserved the legacy older-listings sentence and other apps’ catalogs. Independently captured and viewed20screens (5states×English/German×light/dark) from that build; copied to `~/Arestemis-orchestra/screens/164-*.png`. Own simulator shut down/deleted. Build number unchanged; Claude owns TestFlight. No API, login or token doubts.
