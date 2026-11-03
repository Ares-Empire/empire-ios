# Planning council: the work board and decisions tab ("The Council" in EXPAND)

2026-11-03 evening · subject: the expansion as written in `ares-empire/EMPIRE.md` → Expansions (ares-empire `b760a8a`)
· a planning council (no code to review) · about 20 minutes.

| Seat | Focus | Model |
|---|---|---|
| A | The evidence: real coordination failures and decision bottlenecks in the briefs, reviews and run outputs | Codex `gpt-6-astra` |
| B | The system: where it lives, its data, automatic reporting, claims, outages, security | Codex `gpt-6-astra` |
| C | Patrik's side: the Empire app tab, evidence on a phone, decisions, notifications | Codex `gpt-6-astra` |
| D | Claude Code facts: which features the plan may rely on | Claude (`claude-code-guide`) |

Seat answers (local, not committed): `codex-runs/council-seat-{A,B,C,D}.md`.

## What all seats agree on

1. **Not called "council".** That word already means these review panels. Names offered: *Empire Work* (A, C),
   *Workboard* (B), *Desk* (D); the phone tab is **Decisions / Entscheidungen** (A, B, C).
2. **Status comes from what happens, never from someone remembering.** A Claude session reports through hooks
   (`SessionStart` registers and hands over open decisions; `PreToolUse` checks claims before Edit/Write; `Stop`, which
   fires after every reply, is a heartbeat; `SessionEnd` best effort). Codex runs go through a launch wrapper that
   registers the run and its intended files before it starts and records how it ended. Evidence: six briefs still said
   "running" after their reports existed (144, 225, 228 among them); 218 said "not deployed" after it was live.
3. **Separate facts, separate states:** a run is running / exited / interrupted / unknown; the work is awaiting review /
   awaiting a decision / merged / deployed / verified. "Codex finished" never means reviewed, merged or deployed.
4. **Claims warn, they do not lock.** Two writers in one checkout are refused; overlapping files in separate worktrees
   warn and ask the lead to split or sequence; merge and deploy take a short exclusive claim. Claims include files a
   brief will create: briefs 145 and 146 each created `Arestemis/core/facts.py` for different things (renamed at merge).
   Claims are coordination, not a sandbox (a shell `sed` bypasses an Edit hook).
5. **Only what needs Patrik reaches the tab:** a change of scope or direction, seats that disagree, an owner action
   ("install build 22, then the server can require versions"). Corrections a brief already allows stay Claude's
   (`docs/REVIEW.md`). No idea lists, no progress feed, no productivity numbers.
6. **A decision outlives the session that asked.** One tap approves an exact, frozen proposal ("Approve the fixes",
   "Investigate first", "Keep it as it is", "Discuss"); a changed proposal refuses an old tap. The app says "saved ·
   waiting for pickup", then who picked it up, then a short receipt of the result. A live session gets it at its next
   hook; an ended one by `claude -p --resume <id>` on its machine, or the next session on that repo takes it over. A
   running Codex job is never interrupted: its lead carries the answer into the next run.
7. **Nothing sensitive on the board or in a push:** no secrets, transcripts, real financial data or details of unfixed
   weaknesses (the push service keeps notification text). Such items show a neutral summary and say "needs the
   computer". Owner-only, checked on the server; one credential per machine (Keychain / Credential Manager).
8. **Aresync takes part:** it commits and pushes checkouts by itself, so it waits for a checkout a session holds.

Also supported by the evidence: brief numbers handed out by the board (no hand-kept ranges); deployment prerequisites
("requires build N installed"); checks still owed after "done" (226's restore drill, 228's live test); a follow-up that
reopens the original finding (brief 67 merged, the black corner still there, brief 87 fixed it); waiting time measured
by who acts next. Left out: automatic ideas, scores, transcript search, a scheduler, hard repo locks, auto-merging, a
remote shell, a second hand-kept status file.

## Where it lives (one seat, accepted)

Seat B: a small service of its own in `ares-empire/workboard/` with SQLite, behind Caddy, in the nightly backup;
PocketBase only for the login, the push service for notifications, the Aresus machine-token pattern for machines. Not
PocketBase collections (the lead's first idea): atomic claims, frozen proposals and delivery receipts are logic, and
account-server hooks would tie a busy workflow to everyone's login. Claude agrees.

## For Patrik to decide

1. **The name:** Empire Work, Workboard or Desk (tab: Decisions).
2. **The first version.** Seat B's smallest worthwhile release (both computers, the Codex wrapper, claims,
   offline handling, Aresync's lock, decisions, the phone tab) is about **8–12 working days** before the tab's design;
   Seat A counts 4–6 briefs. Claude's recommendation: three steps, each useful alone.
   - **Step 1, the loop that hurt today:** the Codex wrapper and run/work states, decisions with pickup and receipts,
     the Decisions tab (Mac first). Ends "running" lines that lie and questions left in a terminal.
   - **Step 2, clashes:** session hooks on both computers, file claims, Aresync waiting for a held checkout.
   - **Step 3:** discussions on an item, brief numbers from the board, waiting-time numbers, a desktop view on the hub.

## Outcome

A plan, not a review: nothing built yet. Accepted corrections to the sketch: the name, the separate service, decisions
only for what needs Patrik, nothing sensitive on the board. Next: Patrik's two choices above; then the plan goes into
`ares-empire/docs/` under the chosen name and the EXPAND entry is renamed.
