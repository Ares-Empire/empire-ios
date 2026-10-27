# 17: The shop list knows money in from money out, and branch numbers

Status: merged 2026-10-27 (M1 98.4% right, M2 51 fixes in 14 months on the real data)
Repo: aresium · Worktree: `~/aresium-17-direction` (branch `claude/17-direction`) · Built by: a Claude agent

## Goal

Measured on Patrik's real payments after brief 13 (2026-10-27), two weaknesses of the shop list remain (the other wrong
matches come from his PayPal double import, which the structural rule handles):

1. **Keywords ignore the direction of the money.** "Miete" in money coming **in** (parents' "Miete und Unterhalt", a
   flatmate's share) was sorted as Rent (10 payments). The same holds for "Gehalt", "Lohn", "Honorar" on money going
   out, "Nebenkosten" refunds, gig payouts (Wolt, Uber) on money in.
2. **Branch numbers break chains that need a second word.** "PENNY 4211 GARCHING" no longer matches (12 groceries
   lost), because whole-merchant names only work when the city is in the short list `merchantKey` strips.

## Read first

`AGENTS.md`; the plan's part 5; `src/engine/sorting/shop-matcher.ts`, `shop-words.ts`, `starter-rules.ts`,
`scripts/shop-list.de.ts`, `scripts/build-shop-list.ts`, `src/engine/shop-list.test.ts`, `src/engine/sorting/sort.ts`.

## Build

1. **Direction:** each hand-written **keyword** rule (generic words, not shop names) says which way it applies:
   spending keywords (miete, nebenkosten, kontoführung, …) only on money out; income keywords (gehalt, lohn, honorar,
   bafög, kindergeld, zinsen, …) only on money in; transfer keywords both. **Shop and brand names** keep matching both
   ways (money back from Zalando is a clothes refund), except where the money in is a payout from a platform that
   pays people (Wolt, Uber, Lieferando, Deliveroo, Bolt, FreeNow, Etsy, Vinted payouts, …): those do not match on
   money in. `starterCategory` gets the payment's amount (the sorting payment already carries it, or add it).
2. **Branch numbers:** a chain that needs a second word or the whole merchant name also matches when its name is the
   first word of the counterparty (or of the text when there is no counterparty) and is followed by a branch number (2
   to 6 digits) — "PENNY 4211 GARCHING", "NETTO 1234 Dachau", "NORMA 123", "SPAR 5678" — but not "Penny Lane 3"
   (a word between) or "Max Müller 12" (not first, a person).
3. Tests for both, including every example above, money in and out for each kind, and the existing must-not-match
   list. Keep the generated JSON deterministic (`npm run shops` twice → identical).

## Settled: do not re-open

- Precision first; the share right on Patrik's payments must reach at least 95% again (Claude measures).
- No change to the list's sources or the deny list beyond what these two rules need.

## Done when

`npm run typecheck`, `npm test`, `npm run engine`, `npm run shops` (deterministic) pass; the final message lists the
keyword rules by direction and anything doubtful.
