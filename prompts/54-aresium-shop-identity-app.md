# 54: One shop under changing names in the app: groups, names and "also the others" per shop

Status: draft
Branch: `codex/54-shop-identity-app` · Worktree: `../empire-ios-54-shop-identity-app` · Model: `gpt-6.1-sol`, effort
`high` · No screens change (brief 53, a Claude agent, changes the lists in parallel).

## Goal

Patrik (2026-10-30): his Vinted purchases from February ("MGP Vinted - Kleiderkreisel", Vinted's former company) and
from October ("Vinted, UAB") are two shops in Aresium: they group, rename and learn separately. Brief 48 (aresium,
merged as 01ebd85) taught the engine which merchant keys are one shop: `shopIdentities(keys)`, learning across one shop
inside `sortPayments`, and foreign card lines no longer keep the exchange text in their key. Claude checked it on
Patrik's real files on the Mac (counts only): 1,246 payments, sorting unchanged on the built-in list, 3 card keys
cleaned, 19 payments follow a learned rule of the same shop, nothing lost. The bundle is already in this branch
(Claude ran `scripts/aresium-engine.sh`; `Engine/engine-version.txt` says 01ebd85). This brief makes the app use it.

## Read first

- `AGENTS.md` (rules: your worktree, your simulator `codex-54`, no commits, no real data: made-up names and amounts
  only; company names like "Vinted, UAB" or "dm-drogerie markt" are fine, people's names only made up like "Erika
  Mustermann")
- `CLAUDE.md` → "Aresium phone mode": "Payment names and groups" (brief 43), "Brief 44 API", "Renaming and the name's
  page" (briefs 44 and 47), learned merchants and `PhoneBackend.rebuildLearnedKeys`, "Off the main thread" (the ledger's
  own executor)
- `~/aresium/src/engine/sorting/shop-identity.ts` (the rules, read only) and `~/aresium/src/engine/sorting/sort.ts`
  (how `sortPayments` uses an identity's learned rule: exact key first)
- `Aresium/Aresium/Model/AresiumEngine.swift` (the bridge: `merchantKeys`; add `shopIdentities` the same way),
  `Model/PaymentNames.swift` (`key(ownName:merchant:bankName:)`, `apply`, `renameInfo`, `rename`),
  `Model/PhoneBackend.swift` (`rebuildLearnedKeys`, the category change and `otherPayments(of:besides:target:)`),
  `Model/PhonePickerWork.swift` (where the dashboard's keys are computed), `Model/PhoneReceipts.swift` and
  `Model/ReceiptCorrections.swift` (receipts' shop keys, `learnedCategory(forShop:)`), and their tests.

## Build

1. **The bridge:** `AresiumEngine.shopIdentities(_ keys: [String]) -> [String]` (same order and length; checked like
   `merchantKeys`). Call it once per job over the distinct keys involved (payments, receipts, the stored name rules),
   on the ledger's executor, never on the main thread; add a `PickerTiming` span (`names.identities`).
2. **Groups by shop:** a bank payment's and a receipt's `nameKey` comes from its shop identity instead of its merchant
   key (own names keep `own:`, empty keys keep the exact bank line), so "All from", the name's page, the swipe and brief
   53's sums take every name of one shop together. `nameKey` stays opaque to the screens.
3. **Names by shop:** a shop's own name (the merchant name rule) applies to every key of its identity; a rule for the
   payment's exact key wins over another key's rule of the same identity (deterministic and tested when several
   exist). Renaming with `.shop` stores the rule and removes the other rules of the same identity, so one shop has one
   name; "Use the bank's name" for the shop removes them all. `renameInfo`: `shopOwnName` is the identity's rule and
   `otherPaymentCount` counts the other bank payments of the same identity. A payment's own name (`.payment`) is
   unchanged.
4. **"Also the other payments" by shop:** the category change's question counts and moves the other payments of the
   same identity (still never own transfers, never ones set by hand, as today), and after **All** every payment of that
   shop shows the new category, also those whose key had a learned rule of its own (replace or remove the learned
   rules of the other keys in the identity; your call, say which). The count on the button equals what moves (test).
5. **Other lookups by merchant key** (receipts' learned category for a shop, anything else you find): where a learned
   category or a name is looked up by merchant key, the same identity rule applies. List every place in your final
   message, including ones you deliberately left alone and why.
6. **The card key fix and stored rules:** this bundle changes the key of foreign card payments (the exchange text is
   gone, e.g. "fiktivshop usa musterstadt usd 7 43 kurs: …" becomes "fiktivshop"). Learned category rules are rebuilt
   from corrections by `rebuildLearnedKeys` already (check that it covers this). Name rules are not: when the engine
   version changes, a name rule whose key no payment has any more moves to the current key it starts with at a word
   boundary (the longest such key), unless that key has a rule of its own. Tested with made-up card lines in the VR
   Bank format.
7. **Same results first:** a store without shops under several names gives the same dashboard, groups, names and
   counts as before (a test over the phone sample). Measure the dashboard build and `renameInfo` at 5,000 payments
   before and after (the `PickerTimingTests` way) and report both.

## Settled: do not re-open

- `merchantKey` and the stored rules stay keyed by merchant key (no schema or export change); the identity is a layer
  over them, computed when needed.
- A chain is one shop, as the engine's identity says; the app adds no matching rules of its own.

## Out of scope

- Screens and words (brief 53 runs in parallel on the lists: do not touch `Screens/`).
- The engine (`~/aresium`): if it lacks something, describe it in your final message.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium` passes on `codex-54`, with tests for each point
  above (the Vinted pair and the dm spellings as made-up payments in the VR Bank and PayPal formats; a person's name in
  two orders; near misses that must stay apart, such as "Apple" and "Applebee's").
- `scripts/strings.py check`: 0 problems.
- `CLAUDE.md` → "Payment names and groups" says what is grouped and named by shop now.

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the timings before and after, every lookup
you changed or left (point 5), your choice in point 4, what is missing or doubtful. Never commit, push or merge: Claude
does.
