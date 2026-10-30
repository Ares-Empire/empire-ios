# 48: One shop under changing names: the engine's shop identity

Status: merged to aresium main 2026-10-30 (01ebd85; on Patrik's files on the Mac: 1,246 payments, sorting unchanged, 3 card keys cleaned, 19 follow a same-shop rule, 0 lost; the server does not use sortPayments, so nothing to deploy). The app gets it with brief 54
Repo: **aresium** · Worktree: `../aresium-48-shop-identity` (branch `codex/48-shop-identity`) · Model: `gpt-6.1-sol`,
effort `high` · The app's side follows in a later brief (Claude wires it into empire-ios).

## Goal

Patrik (2026-10-30): his Vinted purchases from February are not recognised as the same shop as October's: the
counterparty was "MGP Vinted - Kleiderkreisel" then and is "Vinted, UAB" now (Vinted's former German company and its
Lithuanian one), so they sort, group ("all payments of one name") and rename separately. Claude scanned his real files
on the Mac (they never leave it) and found the same in many forms. After this brief the engine can say which merchant
keys are one shop, cheaply, so the app groups, renames and learns per shop.

**What Claude found** (the patterns, with made-up examples where people are involved; build fixtures from these
patterns, never from anyone's data):

1. **Company changes and legal forms:** "MGP Vinted - Kleiderkreisel" vs "Vinted, UAB"; "Too Good To Go ApS" vs "Too
   Good To Go". `merchantKey` strips German forms (GmbH, AG, SE, KG, OHG, e.K.) but not foreign or other ones: UAB,
   ApS, Ltd, Pte. Ltd., Limited, S.A., SAS, SARL, S.à r.l., B.V., N.V., S.L., S.r.l., S.p.A., Sp. z o.o., AB, AS, Oy,
   Inc, LLC, Corp, plc, Pty, oHG, mbH, UG (haftungsbeschränkt), e.V., gGmbH, KGaA, "Aktiengesellschaft".
2. **One chain, several spellings:** "dm-drogerie markt", "dm drogerie", "dm drogerie markt", "DM DROGERIEMARKT";
   Apple as "apple services", "apple.com bill", "apple store", "apple distribution international".
3. **Cut off at different lengths:** "autobahnen und schnellstraßen-finanzierungs" vs "autobahnen und
   schnellstrasen-fin"; "muenchener rueckversic" vs "muenchener rueckver"; "bauhaus e-business gesellschaft für bau-
   und hausbedarf mbh" vs "bauhaus e-business". Also ß vs ss.
4. **A person's name in another order or with a middle name** (transfers): "Erika Mustermann" vs "Mustermann, Erika";
   "Max Mustermann" vs "Max Otto Mustermann".
5. **A bug:** a foreign card payment keeps the card's exchange text in its key, e.g. a key like "openai usa san
   francisco usd 5 95 kurs: 1 1 00% auslandsums. 0 05umsatz vom mc hauptkarte" for a VR Bank card line "OPENAI  USA
   SAN FRANCISCO  USD 5,95 Kurs ... Auslandsums. ... Umsatz vom ... MC Hauptkarte" (look at the VR Bank card formats
   in `src/engine/readers` and the existing `cardMerchant`): every such payment is its own "shop".

## Read first

- `AGENTS.md` (this repo's rules: no real data, the engine stays pure, same results first)
- `~/ares-empire/docs/ARESIUM-FOR-OTHERS.md` (sorting, learned shops, the shop list)
- `src/engine/sorting/merchant.ts` (`merchantKey`, `cardMerchant`, `payeeText`), `src/engine/sorting/shop-matcher.ts`
  and `shop-words.ts` (the shop list's names, brands and merchants; `shops.de.json`), `src/engine/sorting/sort.ts`
  (`sortPayments`, learned lookups by `merchantKey`, `learn`), `src/engine/index.ts` (what the bundle exports), the
  readers' card formats and fixtures, the existing sorting tests.
- How the iPhone app uses the keys (read only): `~/empire-ios/Aresium/Aresium/Model/AresiumEngine.swift` (`merchantKeys`),
  `Model/PaymentNames.swift` (groups and name rules keyed by merchant key), `Model/PhoneBackend.swift`
  (`rebuildLearnedKeys`).

## Build

1. **Fix the card exchange text** (5) inside `merchantKey` or `cardMerchant`, so a foreign card payment's key is the
   merchant's name. This changes keys for those payments only; the app already rebuilds learned rules from corrections
   when the bundle changes.
2. **`shopIdentities(keys: string[]): string[]`** (exported from the engine, same order and length): for a set of
   merchant keys, the shop each belongs to. Keep `merchantKey` itself unchanged otherwise, so stored learned rules and
   the app's name rules (keyed by merchant key) stay valid; the identity is a layer over the keys:
   - a cleaned form for comparing: the legal forms of (1) removed, ß→ss, umlauts and accents folded, hyphens and
     punctuation as spaces, "sagt danke" and similar removed (check what `merchantKey` already does);
   - a **known shop** from the shop list wins: when the shop list names a merchant or brand at the start of the key
     (as the matcher would, with its existing word rules), the identity is that shop (all REWE stores are one "rewe", the
     dm spellings one "dm", "MGP Vinted - Kleiderkreisel" and "Vinted, UAB" one "vinted", Apple's four one "apple").
     Never from a word in the middle of a longer name unless the matcher's own rules allow it; tests with near misses;
   - **cut-off names:** a cleaned key that is a prefix of another cleaned key in the same set, at least 12 characters
     long and ending at a word boundary or inside the longer one's last word, gets the longer one's identity (the
     longest when several);
   - **names in another order:** the same words in another order (2 to 4 words) are one; first and last word equal with
     extra middle words (a middle name) are one, but only for keys of 2 to 4 words without digits;
   - everything else: its cleaned form. Empty keys stay empty (never grouped).
   - Deterministic and order-independent (the same set gives the same identities whatever the order). Cheap: it works
     on the distinct keys (a few hundred), not per payment; measure it on 5,000 made-up keys and report the time.
3. **Learning across one shop:** in `sortPayments`, a payment whose own key has no learned rule takes the rule of
   another key with the same identity (computed once per call over all keys involved). A rule for the exact key still
   wins. `learn` keeps storing by merchant key.
4. **Tests** (made-up data, real formats): each pattern above as a positive case, near misses as negatives (two
   different shops starting with the same word: "rewe" vs a café called "Rewe-Eck"? decide; two different people sharing
   a surname; "Apple" vs "Applebee's"; a short key that is a prefix only by accident, under 12 characters), the card
   exchange text, order independence, the learned rule across one shop, and that every existing test passes.

## Settled: do not re-open

- `merchantKey` stays as it is except the card exchange fix: rules stored by it stay valid.
- A chain is one shop (all REWE stores one), as the shop list sees it.
- No fuzzy edit-distance matching across all names (too easy to merge different shops, and slower); only the rules
  above.

## Out of scope

- The iPhone app (Claude wires `shopIdentities` into empire-ios afterwards); the server's dashboard code outside the
  engine (it gets the better sorting through `sortPayments`).
- Shop list contents (`shops.de.json`): no edits, unless a test shows a missing brand that Vinted or dm need; then say
  which.

## Done when

- `npm run typecheck`, `npm test` and `npm run engine` pass, with the new tests.
- Your final message lists: files changed, test counts, the time for 5,000 keys, every rule's exact behaviour, and
  what Claude must run on the server to compare the server's sorting before and after on real data (`AGENTS.md`:
  same results first; here the expected difference is more payments sorted, none sorted differently by a rule that
  existed before: say how to check that).
