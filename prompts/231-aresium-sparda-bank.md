# 231: Aresium reads Sparda-Bank exports

Status: running (started 2026-11-04, a Claude agent)
Worktrees: `~/aresium-231-sparda` (repo `aresium`, branch `claude/231-sparda`) and `~/empire-ios-231-sparda` (repo
`empire-ios`, branch `claude/231-sparda`) · Simulator: `claude-231` (create it as `AGENTS.md` says)

## Goal

A tester asked for Sparda-Bank. After this brief Aresium reads a Sparda-Bank export (the formats its online banking
offers: CSV and, if offered, CAMT or MT940) as reliably as the banks it knows, and the app's "How do I get my file?"
guide shows the steps for Sparda-Bank. The Sparda-Banks are several regional banks; cover the export they share, and
any regional difference you can establish.

## Read first

`~/aresium/AGENTS.md` (no real data: real header lines, invented payments), `~/aresium/src/engine/readers/`
(`bank-profiles.ts`, `profiles.ts`, `csv.ts`, `read.ts`, their tests), how earlier banks were added (briefs
`~/empire-ios/prompts/14-bank-readers.md`, `19-bank-export-guide.md`, `21-bank-format-inbox.md`), the eval set
(`~/aresium/eval/`), and in `~/empire-ios`: `AGENTS.md`, `CLAUDE.md` (Aresium), the bank guide's screens and data.

## Build

1. **Find the real format** from public sources: the bank's own help pages, open-source importers (for example
   Hibiscus/Jameica, GnuCash, Firefly III importer configs, homebanking forums) and published sample headers. Write
   down in the final message every source and what it established (header line, separator, encoding, date and amount
   format, column names, the order of rows). Where sources disagree or nothing confirms a detail, say so; never guess
   silently. If Sparda-Bank's online banking is one of the shared platforms Aresium already reads (for example the
   Volksbank/Atruvia layout), reuse that profile and name the evidence.
2. **The reader:** a bank profile in the engine, following the existing pattern, with tests on made-up payments in the
   real format (and a file in the eval set if earlier banks got one). Every existing test stays green; nothing else's
   reading changes.
3. **The guide:** Sparda-Bank in the app's bank guide, with export steps from the bank's own help, in English and
   German, in the guide's existing words and look.
4. **The app's engine:** `npm run engine` in the aresium worktree, copy `dist/aresium-engine.js` into the app worktree's
   engine resource and record the bundled commit as the app does.

## Settled

- The engine stays pure; no new packages. No real account data anywhere. Readable code in the existing style.
- Do not commit, push, merge, deploy or upload. The lead session checks, merges and sends the build to TestFlight.

## Done when

In aresium: `npm run typecheck`, `npm test`, `npm run engine` pass. In empire-ios: `xcodebuild test` for Aresium passes
on `claude-231` and `scripts/strings.py check` says 0 problems. A screenshot of the guide's Sparda-Bank page in German:
`build/231-guide-de.png`.

## Final message

Files changed in both worktrees; the exact check results; the sources and what each established; anything unconfirmed.
