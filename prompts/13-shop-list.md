# 13: A much bigger list of known shops (starter rules)

Status: draft
Repo: aresium · Worktree: `~/aresium-13-shop-list` (branch `claude/13-shop-list`) · Built by: a Claude agent

## Goal

The app sorts a payment with no AI and no manual step when the shop is on its built-in list (REWE → Groceries, ZARA
→ Clothes). Measured on Patrik's payments, today's 288 patterns sort 64% on day one with 95% right, and they cut a new
user's corrections by two thirds. Patrik (2026-10-27): expand the list as much as possible. More known shops means
fewer corrections for every friend who uses the app; a wrong match costs a correction and confuses, so **precision
comes first**.

## Read first

`AGENTS.md` (rules); the plan's part 4 (the default categories) and part 5 (layer 1); `src/engine/categories.ts`,
`src/engine/sorting/starter-rules.ts`, `src/engine/sorting/merchant.ts`, `src/engine/sorting/sort.ts` and
`src/engine/sorting.test.ts`.

## Build

1. **Brands from OpenStreetMap's name-suggestion-index (NSI)**, the open, curated list of real brands with their OSM
   tags and the countries they operate in (https://github.com/osmlab/name-suggestion-index; check its licence and
   attribute it in a `NOTICE` or the data file's header). Take the brands present in Germany (location sets that
   include `de`, Europe, or worldwide) in the OSM categories that map to our default ids (supermarkets and food shops →
   groceries; chemist → drugstore; clothes, shoes → clothes; electronics, mobile phone → electronics; furniture,
   doityourself, hardware, houseware → household; fast food, restaurant → eating-out; cafe, bakery → coffee-snacks;
   pub, bar, nightclub → going-out; fuel, car repair, car wash → car-fuel; cinema, theatre → entertainment; pet →
   pets; hairdresser, beauty → personal-care; fitness centre → sports-fitness; pharmacy, optician → health; books,
   sports, toys, gifts, department store → the closest id or leave out; and so on). Write the mapping table yourself,
   explicitly, one OSM tag value per line. Vendor the data you use (a pinned version, the source URL and date in the
   file) through a generator, `scripts/build-shop-list.ts`, that writes `src/engine/sorting/shops.de.json`; the engine
   loads the JSON (bundled), never the network.
2. **German services NSI does not cover**, hand-written in the same file's source: the larger cities' Stadtwerke and
   transport operators (MVG, BVG, HVV, KVB, VVS, RMV, VRR, VBB, MVV, DVB, LVB, …), energy suppliers, telecoms and
   mobile brands, insurers and statutory health insurers, streaming and software subscriptions, gyms and fitness
   chains, cinema chains and ticket sellers, food delivery, scooter, bike and car sharing, online shops that sell one
   kind of thing (Zalando, About You → clothes; Cyberport, Alternate → electronics), Studierendenwerke and semester
   fees, Familienkasse, Finanzamt, BAföG offices, Rundfunkbeitrag.
3. **Matching that stays precise:** case-insensitive, whole words, umlauts and their ae/oe/ue spellings, common bank
   spellings (REWE Markt GmbH, "SAGT DANKE", branch numbers). Names that are also common words or surnames ("Müller",
   "Kaiser", "Penny", "Spar", "Norma", "Real", "Hit", "Globus", "Bauhaus", "Total", "Jet", "Star",
   "Action", "Depot", "Lush", "Cafe", …) need a second token ("müller drogerie", "spar markt", "jet tankstelle") or go
   on a deny list. Very short brands (dm, C&A, H&M, OBI, DB) only as their own word. Marketplaces and payment services
   (Amazon, eBay, PayPal, Klarna, SumUp, Zettle) stay out: their payments can be anything. Keep the list deterministic
   and the matching fast: precompile it once (one index or a few regular expressions), not a loop over thousands of
   patterns per payment; measure in a test that 5,000 payments sort in well under a second in Node.
4. **Order and conflicts:** the hand-written German rules win over NSI; within NSI, the more specific name wins; a
   brand in two of our categories goes to the one most of its payments mean, or out.
5. **Tests:** for each category several realistic bank texts that must match (as banks write them: "REWE Markt GmbH-Zw
   1234", "LIDL DIENSTL GMBH SAGT DANKE", "Kartenzahlung ZARA DEUTSCHLAND") and a list of texts that must **not** match
   (people's names like "Max Müller", "Anna Kaiser"; "Miete Penny Lane 3"; "Total 23,50"; "Action required"). A test
   that no pattern is shorter than 3 characters unless it is on the short-brand list.

## Settled: do not re-open

- Precision before size. Patrik's payments decide (Claude runs the bench afterwards: the share sorted must rise and
  the share right must stay at least 95%).
- Starter rules apply only when their category is on the person's list (unchanged).
- No AI and no network at runtime.

## Done when

`npm run typecheck`, `npm test`, `npm run engine` pass; the final message gives the number of patterns per category,
the NSI version used, the bundle size before and after, and the deny list.
