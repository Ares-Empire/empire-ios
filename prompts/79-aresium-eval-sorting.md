# 79: A test set for automatic sorting, with a score

Status: brief
Repo: **aresium** · Worktree: `../aresium-79-eval-sorting` (branch `codex/79-eval-sorting`) · Model: `gpt-6.1-sol`,
effort `high` · Runs beside brief 78 (bank files, `eval/files/`); you own `eval/sorting/` only.

## Goal

Patrik (2026-11-01), before Aresium goes to more testers: "What we should definetly test is autosort with different
kinds of real and made up data meaning real and fictional shops to cover general and also edge cases. Like that we can
track how good the sorting is and improve it. I say we make a test set of lots of cases so we have a baseline for
evaluation." A new person has taught Aresium nothing yet, so the built-in sorting is their first impression.

Today sorting was measured once, on Patrik's own payments (day one: 76% sorted, 98.4% of those right;
`~/ares-empire/docs/ARESIUM-FOR-OTHERS.md`, the measurements), which covers his shops only. `bench/` holds 480
made-up payments for the learning replay. Nobody has measured the sorting on the shops other people pay at.

This brief builds **a test set of single payments as banks print them, with right answers that do not come from the
engine**, a way for **two independent judges** to check those answers, and **a score**. It measures only: no change to
the sorting, the shop list or the starter rules. Improvements come in later briefs, measured against this set.

Two points from Patrik that shape it:

- **What is right is partly personal.** "each user will have personal preferences etc so my data in some aspects isnt
  ground truth." A bakery can be Groceries or Coffee & snacks; money from a person can be anything. So a case has **a
  set of accepted categories**, not one, and a case whose answer depends on the person says so (then leaving it
  unsorted is right, and so is any category the judges accept).
- **Who decides what is right.** "it doesnt make much sense to have the agent that makes test sets be the sole judge
  of correctness … if one or two other agents judge it too then it could work … most of it is very straight forward
  like supermarkets, bakeries". So the answers come from an independent source where one exists (OpenStreetMap's own
  tag for a place, below), then two judges label every case without seeing that answer, and the majority decides.

## Read first

- `AGENTS.md` (no real data), this brief.
- `src/engine/categories.ts` (the default categories, their ids and kinds), `src/engine/sorting/sort.ts`
  (`sortPayments`, `SortResult`), `src/engine/sorting/merchant.ts` (how bank text becomes a shop),
  `src/engine/sorting/transfers.ts` (own transfers, PayPal pairs), `src/engine/readers/` and the bank fixtures in
  `src/engine/fixtures/banks/` (how each bank prints a payment: which text lands in counterparty, description and
  booking text), `bench/` (its fake data and replay), `scripts/check-shop-sorting.ts` (how a bundled engine is loaded),
  `scripts/build-shop-list.ts` (where the name-suggestion-index comes from).
- Do **not** read `src/engine/sorting/shops.de.json`, `scripts/shop-list.de.ts` or `starter-rules.ts` for deciding
  answers or writing the category guide: the answers must not be copied from the engine. Code may ask the shop list
  whether a name is in it (a fact recorded per case, below).

## Build

All under `eval/sorting/`, TypeScript run with `npx tsx`, no new packages (Node's own `fetch` for downloads).

1. **The category guide** (`eval/sorting/categories.md`), written first, from the category names and common sense,
   not from the engine: for each default category what belongs there and what goes elsewhere, with examples, and a
   short list of the borderline kinds of payment with every category a typical person might reasonably choose (bakery,
   kiosk, pharmacy vs drugstore, Amazon, Deutschlandticket, gym membership, streaming, a takeaway, a hotel abroad,
   PayPal to a person, money from a person, a refund from a shop, a cash withdrawal…). Money in and money out are
   separate questions (a refund from a clothes shop, a sale on Vinted, a salary). This guide is what the judges read.
   Claude reviews it before judging starts; Patrik may read it.
2. **Where cases come from** (target about 2,000 cases; each case one payment):
   - **Local places from OpenStreetMap** (about 800): shops, cafés, restaurants, bakeries, pharmacies, doctors' and
     dentists' practices, hairdressers, petrol stations, hotels, cinemas, gyms, clubs, kiosks and the like, from about
     eight places of different size across Germany (for example Garching, a district of München, Köln, Berlin,
     Leipzig, Hamburg, a small town, a village), weighted roughly as people spend (many food and everyday places, fewer
     rare ones). From the Overpass API, politely (one query per place, a pause between), raw answers cached in
     `eval/sorting/.cache/` (ignored by git). Keep each place's OSM tags: they are the independent first answer.
   - **Chains and brands** (about 450): from the name-suggestion-index entries for Germany (the version
     `scripts/build-shop-list.ts` pins) and well-known online services, subscriptions, utilities, insurers, telecoms,
     transport and delivery services. Record per case whether the shop list knows the name (`inShopList`), so the score
     shows known and unknown brands apart; aim for about half unknown.
   - **Made-up shops** (about 250): with a word that gives the answer ("Bäckerei Sonnenkorn", "Friseur Haarmonie",
     "Pizzeria Da Lorenzo"), with nothing that does ("Nordlicht Handels GmbH", "Kowalski & Partner"; unsorted is right
     there), and misleading ones ("Bar Apotheke", "Café Möbel Design", a shop named after a town).
   - **Payments that are not shops** (about 500): salaries from made-up employers, BAföG, Kindergeld, rent to a made-up
     landlord and to a housing company, Stadtwerke and energy companies, internet and phone, insurance, Finanzamt and
     other taxes, Rundfunkbeitrag, bank fees, interest and dividends, ATM withdrawals, donations, memberships (a club,
     ADAC), university fees, refunds from shops, sales on Vinted/Kleinanzeigen/eBay, money to and from made-up people,
     PayPal payments both as PayPal's export shows them and as the bank's line, card payments abroad with an exchange
     rate line.
   - **A few scenarios** (about 20, scored as groups): an own transfer between two accounts of one person, a PayPal
     purchase seen in both files, two unrelated equal amounts that must not pair.
3. **As banks print them** (`eval/sorting/make.ts`, seeded and repeatable): each case is rendered as one bank or PayPal
   prints it, the bank chosen across the layouts in `src/engine/fixtures/banks/` and the fields filled as that bank's
   reader fills them (counterparty, description, booking text, amount with sign, source, account, IBANs made up as the
   fixtures make them). Use the real variety: upper case, umlauts as `AE`/`OE`/`UE` or dropped, names cut at 22–27
   characters, a town and `DE` after the name, branch and terminal numbers, card lines with amount and date, booking
   types (`Kartenzahlung`, `Lastschrift`, `SEPA-Überweisung`, `Gutschrift`, `Dauerauftrag`, `girocard`, `VISA Debit`),
   and payment services in front of the shop (`SUMUP *`, `ZETTLE_*`/`iZ *`, `SQ *`, `PAYPAL *`, `Klarna`, `Stripe`,
   `Adyen`, `NEXI`/`Worldline` terminals, `AMZN Mktp`, `Lieferando`/`Wolt`/`Uber Eats`). Some shops appear twice under
   two renderings (a robustness check). Every case records its kind (`osm`, `brand`, `madeup`, `nonshop`, `scenario`),
   how it was rendered, and its source facts.
4. **No real people:** a local place's name that contains a person's name (a practice, a hairdresser "Friseur Petra
   Schmidt", a "Bäckerei Huber" that is a family name) gets that name replaced by a made-up one of the same shape; keep
   business words, brands and towns. Every private person, employer and landlord is made up. OSM-derived files carry
   the ODbL attribution (`eval/sorting/sources/LICENCE.md`).
5. **The first answer** (`generator`): for OSM places, from their tags through one mapping table you write in the
   guide (for example `shop=bakery` → Groceries or Coffee & snacks); for brands, from the index entry's tags; for
   made-up and non-shop cases, the category the case was made for. Each answer is a set (`best`, `alsoRight`) or
   `unclear` (nothing in the line tells) or `personal` (depends on the person).
6. **Judging, blind** (`eval/sorting/judging/`): `npm run eval:sorting -- --batches` writes batches of about 200 cases
   holding only what the app knows of a payment (the fields, the amount with sign, PayPal or bank) and an instruction
   file, `JUDGING.md` (read the guide; for each case answer `best`, `alsoRight`, or `unclear` / `personal`, one line
   per case, JSON lines). No first answer, kind, source fact, OSM tag or engine result is in a batch. Claude runs the
   two judges afterwards (a Claude agent and a Codex run, each in an empty folder holding only the batches, the
   instruction and the guide); you write the files and the merge, and test the merge with made-up judge answers.
7. **The merge** (`eval/sorting/labels.jsonl`, `--merge`): from the first answer and the two judges. A category is
   accepted when at least two of the three name it (as `best` or `alsoRight`); unsorted is right when at least two say
   `unclear` or `personal`; a case with no majority is `disputed`: kept out of the score and listed (count and a file)
   for Claude and Patrik to look at. Record the agreement rates (all three, two of three) per kind: a weak kind of case
   shows up there.
8. **Held back** (30% of cases, chosen by a stable hash of the case id, kept in `cases.heldback.jsonl` with their own
   labels file): later briefs that improve sorting must not open them. The score prints only totals for them, never a
   failing case. The README says so in its first lines.
9. **The score** (`npm run eval:sorting`, `eval/sorting/score.ts`): runs `sortPayments` as a new person (no learned
   rules; the default categories all chosen; one call over the cases, scenarios each in their own call) from the
   source, or with `--engine <path>` a bundled `dist/aresium-engine.js`; prints for the worked-on part and the held-back
   part:
   - **sorted**: how many cases got a category;
   - **right**: of those, how many got an accepted one;
   - **wrong**: sorted into a category not accepted, including sorted where unsorted is right (the number to push
     down: Patrik said errors are worse than gaps);
   - **missed**: left unsorted where a clear category exists;
   - by kind (`osm`, `brand` known and unknown, `madeup`, `nonshop`, `scenario`, money in and out, each payment
     service), by category (worked-on part only), and every wrong and missed case of the worked-on part with its line,
     the engine's answer and the accepted ones.
   `--record` appends one line to `eval/history.csv` (date, git commit, `sorting`, the headline numbers of both parts),
   creating it with a header when missing (brief 78 writes `files` lines to the same file).
10. **Patrik's own data** (`eval/sorting/own-data.ts <path to an Aresium export>`): Claude runs it on Patrik's export,
    which never enters the repo and which you never see; test it with a made-up export. It refuses a path inside the
    repo; it reads an Aresium export (`LedgerExport`, schema 1–5: payments with their fields, `category`,
    `categorySource`, chosen categories), sorts the payments as a new person with his chosen categories (no learned
    rules), and prints **only counts**: agreement with the categories he chose himself (`manual`), agreement with the
    ones he kept, a table of engine category × his category (counts only), sorted / unsorted, and the learning replay
    (fixes needed over the months, as `bench/run.ts` counts them). No shop name, text, amount or date is printed.
11. **`eval/sorting/README.md`**: what the set is, where answers come from, the held-back rule, how to add cases,
    judge, merge, score and record.
12. `package.json`: the `eval:sorting` script. `.gitignore`: `eval/sorting/.cache/` and anything else not meant for git.

## Settled: do not re-open

- Measure only: no change to `src/engine/`, the shop list or the bench.
- An answer never comes from the engine; the guide is written without the shop list.
- Answers are sets; `personal` and `unclear` exist; disputed cases are kept out of the score.
- A wrong category counts worse than a gap: wrong is its own headline number.
- No real people's names, IBANs or amounts anywhere; Patrik's data never enters the repo or your worktree.

## Out of scope

- Reading bank files (brief 78), receipts, the app, improving the sorting.

## Done when

- `npm run typecheck`, `npm test`, `npm run engine` pass.
- `npm run eval:sorting -- --batches` writes the judges' batches; `npm run eval:sorting` scores against the first answers
  alone until judged (say so in its output) and prints the first numbers.
- Tests (`eval/sorting/*.test.ts`; `npm test` covers only `src/`, so run them with
  `npx tsx --test eval/sorting/*.test.ts`; Claude adds `eval/` to `npm test` after merging; the typecheck already
  covers `eval/`): the merge (agreement,
  sets, unclear/personal, disputed), the held-back split is stable, the score's counts (right, wrong, missed, unsorted
  right), `own-data.ts` on a made-up export prints no name or amount.
- `eval/sorting/categories.md`, `JUDGING.md` and the README written.

## Final message

As in `AGENTS.md`: files changed, the exact check results, how many cases of each kind and from which places, the
first score against the first answers (headline numbers and the table by kind), anything in the guide you were unsure
about, anything doubtful. Never commit, push or merge: Claude does.
