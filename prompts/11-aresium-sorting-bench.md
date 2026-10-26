# 11: Aresium sorting: default categories, starter rules, learning, and the measurements M1–M3

Status: merged 2026-10-26
Branch: `codex/11-sorting-bench` in aresium · Worktree: `~/aresium-11-sorting-bench` · Model: `gpt-6.1-sol`, effort `high`

## Goal

Build the sorting layers of Aresium for other people as part of the shared engine (they ship in the app later), and a
bench that measures them on Patrik's real payments **on the server**, printing only totals. Plan:
`~/ares-empire/docs/ARESIUM-FOR-OTHERS.md` → part 4 (categories), part 5 (sorting), Decisions D6, Measurements M1–M3.

## Rules (aresium has no AGENTS.md; these apply)

- Work only in the worktree. Never commit, push, deploy, or touch the server or another repo. You may run `npm ci`.
- **You never see real payments.** There is no database or real data on this Mac. Build and test everything on
  made-up data you generate. Claude runs the bench on the server and reads only its totals.
- No new npm packages. Groq is called with `fetch` (as `src/enrich/llm.ts` does); no API key is available to you, so
  test the Groq client with a fake `fetch`.
- Plain English in code and docs.

## Read first

- The plan (above), part 4's default list and built-ins, part 5's three layers.
- `src/engine/index.ts`, `scripts/build-engine.ts` (the engine: pure, no Node built-ins, bundled for the app),
  `src/sync/categorize.ts` and `scripts/seed-categories.ts` (today's rules and patterns), `src/enrich/llm.ts` (today's
  Groq call: batches of 25, temperature 0, JSON), `prisma/schema.prisma` (`Transaction`, `Category`,
  `categorySource`).

## Build

**Engine (pure, exported from `src/engine/index.ts`, bundled; unit tests for each):**

1. `src/engine/categories.ts`: the default list exactly as the plan's table (part 4): stable ids
   (`groceries`, `drugstore`, `eating-out`, … `other`; use exactly the ids that `bench/category-map.json` below names), English and German names, group, kind (`spend`, `income`,
   `transfer`; Savings & investing is `transfer`, not counted as spending), plus the two built-ins `own-transfers`
   (kind `transfer`) and `not-sorted`. No icons or colours (Claude decides those with the screen).
2. `src/engine/sorting/merchant.ts`: `merchantKey(payment)`: a stable key for "the same shop" from counterparty (or
   the start of the booking text when there is none): lower case, umlauts kept, card numbers, dates, times, long
   digit runs, city suffixes, legal forms (GmbH, AG, SE, KG, e.K.), "sagt danke", branch numbers removed. Many test
   cases (REWE branches, dm with branch numbers, PayPal lines, Lastschrift texts).
3. `src/engine/sorting/starter-rules.ts`: patterns → default category id, generic only: common German merchants and
   standard texts, from today's seed patterns (drop anything personal: parties, people, Anthropic/OpenAI, adult sites)
   plus the new categories (Bus & train: MVG, MVV, BVG, HVV, DB, Deutschlandticket…; Car & fuel; Taxi & sharing;
   Utilities: Stadtwerke, big energy companies, Rundfunkbeitrag; Internet & phone: the big carriers; Insurance; Fees;
   Cash: ATM withdrawal texts; Pets; Household: IKEA, Bauhaus, OBI…; Entertainment: cinema chains, ticket sellers;
   Kindergeld: Familienkasse; Taxes: Finanzamt; Salary; BAföG & scholarships). Leave ambiguous ones out (Amazon,
   PayPal, eBay): learning and auto-sort handle them. A rule applies only if its category is on the person's list.
4. `src/engine/sorting/sort.ts`: `sortPayments(payments, { categories, learned })` → per payment a category id and its
   source (`learned` | `starter` | none), learned first (the person's own choice wins), then starter rules. And
   `learn(learned, payment, categoryId)` → the updated map (merchant key → category id).

**Server-side (not in the bundle):**

5. `src/sort/groq.ts`: the auto-sort call the future server route will use: given category names and payments (date,
   amount, booking text, counterparty, a reference), asks Groq in batches of 25 (temperature 0, JSON answer), returns a
   category name from the list or null per reference; unknown names count as null. A generic prompt (a person's bank
   payments, their own category list; nothing about Patrik). Model as a parameter, default `llama-3.3-70b-versatile`.
   Reports tokens and time per batch. Never logs payment content.

**The bench (`bench/`, run with `npx tsx bench/run.ts`):**

6. `bench/export.ts`: reads from the database **read only** (Prisma `findMany` only): every transaction whose
   `categorySource` is `rule` or `manual` (the answer key, D6), with date, amount, description, counterparty, true
   category name; writes `bench/out/data.json` (`bench/out/` git-ignored).
7. `bench/category-map.json`: Patrik's category → acceptable default ids, exactly:
   ```json
   {"Groceries":["groceries"],"Drogerie":["drugstore"],"Restaurants":["eating-out","coffee-snacks"],
    "Drinking":["going-out"],"Clothes":["clothes"],"Non-essentials":["shopping","household"],
    "Tech":["electronics"],"Education":["education"],
    "Travel":["travel","bus-train","car-fuel","taxi-sharing"],"Rent":["rent","utilities"],
    "Health":["health","insurance"],"Fitness":["sports-fitness"],"Personal care":["personal-care"],
    "Subscriptions":["subscriptions"],"Memberships":["memberships","donations"],
    "Basis":["parents-family","kindergeld"],"Tax":["taxes"],"Income":["salary","bafoeg-scholarships"],
    "Transfer":["own-transfers","savings-investing"],"Development":null,"Trash":null}
   ```
   `null`: a category of his own with no default (in the default scenario it stays a custom category by that name).
8. `bench/run.ts`: reads `bench/out/data.json`, runs, writes `bench/out/results.md` and prints it. Two scenarios:
   - **A, his own list:** the category list is Patrik's names as custom categories. Starter rules count when their
     default id maps to exactly one of his categories.
   - **B, the default list:** he ticks every default id that appears in the map, plus `Development` and `Trash` as
     custom ones and the built-in `own-transfers`; a prediction is right when it is in the payment's acceptable set.

   Per scenario:
   - **M1:** starter rules alone: share sorted, share of those right.
   - **M2:** replay in date order as a new user who fixes every wrong or missing category (learned first, then
     starter): fixes needed in total, in the first month, in the first 100 payments; share sorted automatically per
     month (a small table).
   - **M3** (only with `--groq`; needs `GROQ_API_KEY`): (a) **new user:** everything starter rules leave open, sorted
     by Groq: share right; (b) **in the replay:** each month's payments that learned and starter rules leave open go to
     Groq as one import would; a wrong or missing answer is a fix; fixes with Groq vs without. Requests, tokens,
     seconds, and cost (Groq's price per million tokens for the model as constants with their source URL and date).
   - **Confusions:** the 10 most frequent (true category → predicted category) pairs, names only.
   - `--model <id>` to compare Groq models; `--limit <n>` for a quick run.

   **The output never contains a booking text, counterparty, amount or date of a single payment**: only counts,
   shares, category names and month labels. Test this: generate made-up data with marked texts and assert none appears
   in `results.md`.
9. `bench/fake-data.ts`: writes made-up `bench/out/data.json` in the export's shape (a few hundred payments over 12
   months, realistic German merchants and Patrik's category names) for testing.

## Settled: do not re-open

- The default list, built-ins and the category map as given. Learned beats starter. Ambiguous merchants are not in
  the starter rules. Groq through our server (the plan, D2).
- The bench reads the database only through `bench/export.ts`, read only.

## Done when

- `npm run typecheck`, `npm test` (new tests included) and `npm run engine` pass; the bundle still has no Node
  built-ins.
- `npx tsx bench/fake-data.ts && npx tsx bench/run.ts` prints a complete results table for both scenarios without
  `--groq`, and with `--groq` against a fake Groq (a test).

## Final message

Files changed; the exact test lines; the results table from the fake data; how many starter rules per category; and
anything doubtful (especially merchant keys that could merge two different shops).
