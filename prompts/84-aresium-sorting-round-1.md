# 84: Sorting, improvement round 1

Status: merged 2026-11-01 (see the merge commit in aresium)
Repo: **aresium** · Worktree: `../aresium-84-sorting-round-1` (branch `codex/84-sorting-round-1`) · Model:
`gpt-6.1-sol`, effort `high` · Runs beside brief 85 (reading bank files, `src/engine/readers/`); you own
`src/engine/sorting/`, `scripts/shop-list.de.ts` and the shop list build.

## Goal

Patrik (2026-11-01): "Once we have first numbers on the test set we can investigate failures and try to improve
autosort." Brief 79's test set has its first numbers (`eval/history.csv`, `npm run eval:sorting`):

| Part | Cases | Sorted | Right | Wrong | Missed | Unsorted right |
|---|---:|---:|---:|---:|---:|---:|
| Worked on | 1,415 | 766 | 745 | 21 | 304 | 345 |
| Held back | 622 | 333 | 322 | 11 | 138 | 151 |

When Aresium sorts it is right 97% of the time; it leaves too much unsorted that has a clear answer (304 "missed").
Patrik's own data (checked by Claude, counts only) agrees: a new person's day one sorts 77.5%, 98.9% of those as he
has them. This round makes the built-in sorting find more, **without more wrong answers** (Patrik: a wrong category
is worse than a gap).

## Read first

- `AGENTS.md`, `eval/sorting/README.md` (**its first lines: the held-back rule**), `eval/sorting/categories.md` (what
  counts as right), `src/engine/sorting/` (`sort.ts`, `starter-rules.ts`, `merchant.ts`, `shop-matcher.ts`,
  `shop-words.ts`, `transfers.ts`), `scripts/shop-list.de.ts`, `scripts/build-shop-list.ts`, `src/engine/sorting.test.ts`,
  `src/engine/shop-list.test.ts`, `src/engine/transfers.test.ts`.
- `~/ares-empire/docs/ARESIUM-FOR-OTHERS.md` (the sorting decisions: the shop list with directions, the structural
  rules, no AI).

## The rules of this round

- **Work from the worked-on part only.** `npm run eval:sorting` prints its wrong and missed cases. Never open
  `cases.heldback.jsonl`, `labels.heldback.jsonl` or the judging files; the score's held-back totals are the only
  thing you see of them, and they tell whether a change helps beyond the cases you looked at.
- **General fixes only.** A fix is a word, a rule or a list entry that is right for everyone in Germany, never a
  test case's name copied into a list. Words come from what the word means (Floristik, Croissanterie, Hofladen),
  brands from the name-suggestion-index or another general source, with the source named in a comment where it is
  not obvious. The test set's names are made up or anonymised, so copying them would help nobody.
- **Wrong must not rise**, in either part. Prefer leaving a case unsorted to a guess.
- Do not change the test set, its labels, the guide or the scorer. Do not run `--record` (Claude records after the
  merge).

## Build

Look at the worked-on failures and fix their general causes. Claude's first look found these groups; confirm them,
find the rest, and say for each what you changed:

1. **Selling things:** money in from Vinted, eBay, Kleinanzeigen, momox and the like with "Auszahlung", "Verkauf",
   "Verkaufserlös" is never sorted (17 of 17 missed): `selling-things`.
2. **Florists and gift shops** ("Floristik", "Blumenladen", "Blumen", "Geschenke", "Geschenkeladen"): never sorted;
   `gifts` (the guide accepts household too for florists).
3. **Food and drink words** the rules do not know yet, German and the cuisines common in Germany: for example grill,
   burrito, veggie/vegan, croissant(erie), brot(manufaktur), back(stube/haus), hofladen, bauernhof, ramen, pho, poke,
   bowl, noodle, falafel, taverna, trattoria, osteria, brasserie, wirtshaus, gasthaus, brauhaus, kaffeerösterei.
   Words must be safe inside other names (whole words or clear word parts; a test for each that it does not fire on
   an unrelated name, e.g. "Grillparzer Straße", "Backup GmbH").
4. **Brands** the shop list does not know: clothes, shoes and jewellery brands, unknown chains. Find why the
   name-suggestion-index entries are missing (filtered categories, Germany-only, matching) and widen what is safe.
5. **Non-shop payments** missed (look at the 74 in the worked-on part: other income, work, gifts, insurance, …):
   general wording rules where the bank text says what it is.
6. **PayPal bank lines and a PayPal export that covers less time** (found while building the score): with any PayPal
   export imported, `transfers.ts` treats every bank-side PayPal line as the funding of a PayPal purchase (an own
   transfer). A person whose PayPal export covers fewer months than the bank file loses the bank's PayPal purchases
   of the other months. Treat a bank PayPal line as an own transfer only within the dates the person's PayPal rows
   cover (with a few days' margin), and add a test for a bank file longer than the PayPal export. Patrik's own
   payments must not change by this (Claude checks; his exports cover the same months).

After each group run `npm run eval:sorting` and keep the change only when the worked-on part finds more and wrong does
not rise. Report the held-back totals before and after (totals only).

## Settled: do not re-open

- No AI and no server in sorting; no learning from the test set.
- Wrong is worse than missed; leaving unsorted is fine.
- The held-back part stays unopened.

## Out of scope

- Reading bank files (brief 85), the app, the test set itself.

## Done when

- `npm run typecheck`, `npm test` (which runs the eval tests too) and `npm run engine` pass; new behaviour has tests in
  `src/engine/` (each new word or rule with a positive and a negative case).
- The final message has the score before and after for both parts (`npm run eval:sorting`), per group above what
  changed and its effect, and anything you chose not to do and why.
- Claude then runs `eval/sorting/own-data.ts` on Patrik's export (counts only) and records the scores.

## Final message

As in `AGENTS.md`: files changed, the exact check results, the score table before and after, anything doubtful.
Never commit, push or merge: Claude does.
