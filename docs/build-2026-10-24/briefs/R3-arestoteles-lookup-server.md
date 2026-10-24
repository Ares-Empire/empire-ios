# R3: Arestoteles server additions for quick lookups, notes and "discuss later"

Read `COMMON.md` (same folder) first; its rules hold (only your worktree, commit but never push or merge, no SSH, no
secrets; Patrik's real vault `~/Documents/Patrik Breeck/Weltbild` is read only for you, never copy its content).
Worktree: `~/wt/Arestoteles-lookup` (branch `lookup`; the service is live from `main`). Venv:
`/opt/homebrew/bin/python3 -m venv .venv && .venv/bin/pip install -e '.[dev]'`; tests `.venv/bin/python -m pytest -q`.
Read `CLAUDE.md`, `docs/API.md` (the contract, version 1 with its additions), `src/arestoteles/` (reader, edits,
index, models), and the vault's own `CLAUDE.md` (Inbox notes: raw input, verbatim, `status: new` until processed).

## Why

Patrik uses the app mostly to look up a fact, a figure or a source, and wants to leave notes and "discuss this later"
marks from the phone instead of changing his considered positions there. The app gets a compact note view, sentence
search, editing of a single paragraph, notes attached to a position or note, and a "to discuss" list. The server needs
three additions to the contract (mark each `CONTRACT ADDITION (2026-10-24, lookup)` in `docs/API.md`, update the
samples, keep everything else unchanged and backwards compatible: old apps keep working).

## Build

1. **Where each block sits:** every `Block` gets `lines: [start, end] | null`: the block's line range in the body that
   `GET /notes/{id}/source` returns (0-based, end exclusive), so the app can replace exactly that paragraph or list
   item group and send the whole body with `edit_note` (version check as now). Also list items: each item gets its own
   `lines`. `null` only for blocks the server makes up. markdown-it tokens carry `.map`; mind the offset between the
   file and the body (frontmatter, title line and summary box are left out of `blocks` but are in the body).
   A test proves for every block of the fixture vault and (read-only) the real vault that replacing `lines` with the
   same text gives back the identical body.
2. **Notes and "discuss later" from the phone:** `quick_note` takes optional `about` (a note id, or a position id
   `"<note>#<n>"`) and `kind` (`"note"` default, or `"discuss"`; then `text` may be empty). The Inbox note's frontmatter
   gets `kind: discuss` (only when discuss) and `about: "[[<note>]]"` (a position: `"[[<note>#My position]]"` plus
   `position: <n>`); the body stays the text verbatim. File name: `Inbox/YYYY-MM-DD HHMM <first words, or "discuss
   <note title>">.md`. Make sure the vault's own check (`.tools/check.rb`) accepts these keys (read it; if it rejects
   unknown keys, say so in your final message instead of changing the vault).
3. **Inbox notes in the index:** `Note.inbox: { status: string; kind: "note" | "discuss"; about: string | null;
   position: number | null } | null` (inbox notes only; `about` resolved to a note id). And a new op
   `{ op: "set_inbox_status"; note: string; status: "new" | "processed" }` (sets `status` in the frontmatter; the app
   ticks off a discussed item).
4. Tests for all of it (both kinds of quick note, about a note and a position, the status op, versions, lines round
   trip), and the real-vault test extended with the lines round trip (counts only).

## Done when

`pytest` passes; `docs/API.md` and `docs/samples/*.json` are updated (the samples gain `lines`, one inbox note with
`kind: discuss` about "Printing press#1" and its `inbox` object); final message as `COMMON.md` says, with the deploy
steps (a push to `main` deploys through the Aresync hook).
