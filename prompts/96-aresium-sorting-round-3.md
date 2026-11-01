# 96: Sorting, improvement round 3

Status: merged 2026-11-01 (aresium; worked-on missed 135 -> 100, wrong 4 -> 2; held back missed 82 -> 73; Patrik replay 113 -> 108)
Repo: **aresium** · Worktree: `../aresium-96-sorting-round-3` (branch `codex/96-sorting-round-3`) · Model:
`gpt-6.1-sol`, effort `high` · Runs beside brief 95 (the local places list in the app, in empire-ios); you own
`src/engine/sorting/`, `scripts/shop-list.de.ts` and the shop list build.

## Goal

Round 1 (brief 84) took the test set's worked-on misses from 304 to 135 and wrong from 21 to 4; round 2 (brief 86)
added an optional list of local places from OpenStreetMap, which Claude is bringing into the app separately. This
round fixes the next general causes, found in the test set's worked-on failures and in Patrik's own payments (Claude
looked at them on his Mac; you never see them: the patterns below are described with made-up examples).

## Read first

- `AGENTS.md`, `eval/sorting/README.md` (**the held-back rule**), `eval/sorting/categories.md`, brief 84's prompt
  (`~/empire-ios/prompts/84-aresium-sorting-round-1.md`: the same rules hold) and its merge commit `fd3e741`,
  `src/engine/sorting/` (`merchant.ts`, `shop-matcher.ts`, `shop-words.ts`, `starter-rules.ts`, `payment-purpose.ts`,
  `local-places.ts`), `scripts/shop-list.de.ts`, `scripts/build-shop-list.ts`.

## The rules of this round

As round 1: work from the worked-on part only, never open the held-back files; general fixes only, nothing copied
from a test case; **wrong must not rise** in either part; no change to the test set, labels, guide or scorer; no
`--record`. Run `npm run eval:sorting` after each group and keep only changes that find more without more wrong.

## Build

1. **Chains written differently on card statements** (from Patrik's payments): a known chain is missed when the card
   line spells it its own way: spaces or apostrophes ("MC DONALDS 2345 DEU KÖLN" for McDonald's), two brands run
   together ("MEDIAMARKTSATURN" for MediaMarkt/Saturn), the company's long legal name ("Bauhaus E-Business
   Gesellschaft für Bau- und …"), an operator's long official name instead of its short one (a motorway toll
   operator). Make matching of the shop list's names robust to spacing, apostrophes, run-together forms and long legal
   names, with tests that it does not match unrelated names.
2. **Compound and cut-off words** (from Patrik's payments): business words inside German compounds and words cut by
   the bank's field length are missed: "Grillhütte", "Kaffeekontor", "Haarwerkstatt"/"Hairdesign"/"HAIRST." (a
   hairdresser cut short), "Lebensmit." (Lebensmittel cut short), "Praxis fur Podo…" (a podiatry practice cut short).
   Recognise a business word at the start of a compound and a clear word cut at the end of the field (only where the
   cut-off part is long enough to be unambiguous; tests with negative cases such as "Kaffeefahrt" or "Grillparzer").
3. **Payment-service prefixes** not handled yet: "SPC*" (as SumUp prints it on some cards) and any others you find
   in the bank layouts and fixtures; the shop after it is what counts.
4. **Card lines that lost their umlauts** ("K LN", "M NCHEN", "GARCHIN" cut): towns and words compared the way the
   bank prints them, for the shop list's towns and the local places list's town matching.
5. **Energy suppliers and municipal utilities** (from the test set): regional suppliers and Stadtwerke by their names
   (a general source, e.g. a public list of German energy suppliers or the name-suggestion-index's suppliers; name it).
6. **Cars and charging** (from the test set): car makers and dealers ("… Motors", "Autohaus", brand names as paid at a
   dealer or workshop) and charging operators: `car-fuel`, where safe.
7. **Memberships** in general terms: associations (`e.V.`), trade unions, political parties, clubs' dues wording:
   `memberships` (the guide accepts sports clubs as sports-fitness too).
8. Anything else general you find in the worked-on failures.

## Settled: do not re-open

- No AI and no server; wrong is worse than missed; the held-back part stays unopened.
- Patrik's payments never reach you; the examples here are made up.

## Out of scope

- The app, the local places list's contents, the test set.

## Done when

- `npm run typecheck`, `npm test` and `npm run engine` pass; each new rule has positive and negative tests.
- The final message: the score before and after (both parts; held back as totals), per group what changed and its
  effect, and what you chose not to do. Claude then checks Patrik's data and records.

## Final message

As in `AGENTS.md`: files changed, the exact check results, the score table before and after, anything doubtful.
Never commit, push or merge: Claude does.
