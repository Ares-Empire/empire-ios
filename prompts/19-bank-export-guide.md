# 19: How to get the bank file: exact steps per bank (research)

Status: open (2026-10-27)
Repo: empire-ios · Worktree: `../empire-ios-19-bank-guide` (branch `claude/19-bank-guide`) · Built by: a Claude agent
(research; no app code)

## Goal

A friend opening Aresium does not know how to get a file of their payments out of their bank (Patrik didn't either,
the first time). Aresium will show, per bank, the exact steps: where to click on the bank's website and, when it can,
in the bank's iPhone app, which file type to pick, and how the file then reaches Aresium on the iPhone. This brief
collects those steps from public sources; a later brief builds the screen.

## Banks

The banks Aresium already reads (`~/aresium/src/engine/readers/bank-profiles.ts`): Sparkasse, Volksbanken und
Raiffeisenbanken (incl. VR Bank), ING, DKB (account and credit card), comdirect, Commerzbank, Deutsche Bank, Postbank,
N26, Revolut, Trade Republic, Consorsbank, C24, American Express, Targobank, Barclays; plus PayPal; plus "another
bank" (generic steps: look for Umsätze → Export / Download / CSV / CAMT).

## What to find, per bank

- Website: the exact path with the labels as the German site shows them ("Umsätze" → "Export" → "CSV"), and the
  English labels if the site has an English version.
- iPhone app: whether the bank's own app can export a file at all; if yes the path, if no say "website only".
- Which file type to pick when there is a choice (Aresium reads CSV, CAMT (XML) and MT940; prefer the one that carries
  the other party's IBAN, usually CAMT, unless it is much harder to get), and the limits (how far back, how many
  months per file, ZIP files: Sparkasse's CAMT comes zipped, which Aresium cannot open: then recommend CSV).
- How the file gets into Aresium on an iPhone: from Safari's download (Downloads → share → Aresium, or Aresium's
  Import → Files → Downloads), from the bank's app (share sheet → Aresium).
- The source URL of every fact and the date you checked it; how sure you are; what differs between regional banks
  (Sparkasse and Volksbank sites differ per institute: give the common path and say so).

## Output

1. `docs/bank-export-guide/steps.json`: one entry per bank: `id` (the engine profile id where one exists, else a
   short slug), `names` (what people call it, for a search box), `website` and `app` steps as short German and
   English lines (`de`, `en`; "du" in German, plain, max ~12 words per step, the bank's own labels in quotes),
   `fileType`, `limits`, `sources` (url + checked date), `confidence` (high/medium/low), `notes`.
2. `docs/bank-export-guide/README.md`: how the data was collected, per bank what is unsure, and what a person with
   an account at that bank should check once.

## Rules

- Research and write only these two files in your worktree. Never commit, push or merge; never touch the server, a
  database or other repos. Never log in anywhere, never download anyone's real payment data.
- Public sources only (the bank's help pages first, then community guides, then accounting tools' import guides such
  as Firefly III, Actual, Finanzguru, MoneyMoney, YNAB, Lexoffice). Do not guess a label: say "unsure" instead.

## Done when

Both files exist; every bank has website steps with a source, or a clear "not found" with what you tried.
Final message: per bank one line (found / unsure / website only), and the files.
