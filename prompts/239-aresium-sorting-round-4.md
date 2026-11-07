# 239: Sorting, improvement round 4

Status: running
Repo: **aresium** · Worktree: `../aresium-239-sorting-round-4` (branch `codex/239-sorting-round-4`) · Model:
`gpt-6-astra`, effort `high` (picked 2026-11-07: what is left is the long tail, where telling a general rule from one
that only fits the test set takes judgment, and wrong must not rise; the weekly allowance is 28% used and the Codex
month ends 2026-11-21) · Runs beside brief 240 (reading ZIP and Excel files, `src/engine/readers/`); you own
`src/engine/sorting/`, `scripts/shop-list.de.ts` and the shop list build.

## Goal

Round 3 (brief 96) left the test set at: worked-on part 1,415 payments, **100 missed**, 2 wrong; held back 622, **73
missed**, 1 wrong (`npm run eval:sorting`, `eval/history.csv`). Aresium now has testers through a public TestFlight
link, and what sorts on day one is what they judge it by. Find the next general causes and fix them, without raising
wrong.

## Read first

- `AGENTS.md`, `eval/sorting/README.md` (**the held-back rule**), `eval/sorting/categories.md`, brief 96
  (`~/empire-ios/prompts/96-aresium-sorting-round-3.md`: the same rules hold) and brief 84's prompt, `src/engine/sorting/`
  (`merchant.ts`, `shop-matcher.ts`, `shop-words.ts`, `starter-rules.ts`, `payment-purpose.ts`, `local-places.ts`),
  `scripts/shop-list.de.ts`, `scripts/build-shop-list.ts`.

## The rules of this round

As rounds 1 and 3: work from the worked-on part only, never open the held-back files; general fixes only, nothing
copied from a test case (a rule must name a kind of business or a public list, never one test line); **wrong must not
rise** in either part; no change to the test set, labels, guide or scorer; no `--record`. Run `npm run eval:sorting`
after each group and keep only changes that find more without more wrong. A name that could be two kinds of business
stays unsorted: missed is better than wrong.

## Build

Start from the worked-on misses (`npm run eval:sorting` prints them). The groups with the most misses today: eating-out
30, groceries 19, coffee-snacks 18, clothes 13, going-out 13 (of 31), hobbies 8, personal-care 8, health 7; by kind,
25 of 154 unknown brands. Themes seen in them, to check and generalise:

1. **Payment-service prefixes with an unknown shop behind them** ("Worldline *", "NEXI *", "SUMUP *" and others in the
   bank layouts and fixtures): the shop after the prefix is what counts; where that shop's words say what it is, use
   them as for any other line.
2. **Food and drink words** in names that are not in the shop list (a word that says restaurant, café, bakery, bar,
   ice cream, kiosk; in German, English, Italian and other common menu languages), at the start of a compound or cut
   off as in round 3, with negative tests.
3. **Going out:** clubs, bars, cinemas, concert and ticket sellers, by kind of name and by a public list.
4. **Clothes brands** not in the shop list: a public list of fashion brands (for example the name-suggestion-index's
   clothes shops, or another source you name with its licence), matched with round 3's spelling rules.
5. **Florists and gifts** (gifts), **resale payouts** (money in from selling second-hand: Vinted, Kleinanzeigen,
   momox, rebuy and the like, to other-income or the category the guide names).
6. **Health and personal care** practices and shops by their kind words (Praxis, Physiotherapie, Apotheke, Kosmetik,
   Nagelstudio, Barbier, …) where round 3 did not reach them.
7. Anything else general you find.

## Settled: do not re-open

- No AI and no server; wrong is worse than missed; the held-back part stays unopened.
- Patrik's payments never reach you. Claude checks the result on his Mac after the merge.

## Out of scope

- The app, the local places list's contents, the readers (brief 240), the test set.

## Done when

- `npm run typecheck`, `npm test` and `npm run engine` pass; each new rule has positive and negative tests.
- The final message: the score before and after (both parts; held back as totals), per group what changed and its
  effect, and what you chose not to do.

## Final message

As in `AGENTS.md`: files changed, the exact check results, the score table before and after, anything doubtful (above
all any rule that might be wrong on real payments). Never commit, push or merge: Claude does.
