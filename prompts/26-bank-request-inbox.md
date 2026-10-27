# 26: An inbox for "my bank is missing" from Aresium

Status: merged 2026-10-27 (311 checks; not deployed yet: with brief 21 and the policy)
Repo: ares-empire · Worktree: `~/ares-empire-26-bank-requests` (branch `claude/26-bank-requests`) · Built by: a Claude
agent

## Goal

In Aresium's bank guide, someone whose bank is not listed can send its name to Patrik in two taps, so we know which
banks to add. No account. This brief builds the receiving end on the account server, next to the bank formats inbox
of brief 21 (merged, not deployed yet; same patterns).

## Read first

`AGENTS.md`/`CLAUDE.md`; `accounts/pb_migrations/1793500000_bank_formats.js`, `accounts/pb_hooks/bank-formats.pb.js`,
`accounts/pb_hooks/lib/bank-formats.js` (its personal-data check), `accounts/pb_hooks/lib/mail.js`,
`accounts/test-rules.sh`, `docs/ACCOUNTS.md` (bank formats), `docs/PRIVACY.md` (bank formats section).

## Build

1. Collection `bank_requests` (a new migration after 1793500000): `bank` (text, required, one line, ≤ 100),
   `app_version` (≤ 40, the same characters as bank_formats), `language` (`en`/`de`, optional), created. Create:
   anyone; list/view/update/delete: superusers only. Rate limit `bank_requests:create`, 5 per hour per IP.
2. A hook before create refuses a bank name that looks like personal data, reusing `lib/bank-formats.js`'s check (do
   not copy it): 400 with a sentence in the request's language (`Accept-Language`) and `data.bank.code`
   `personal_data`.
3. A hook after create mails Patrik through `lib/mail.js`: subject "[Aresium] Bank wish: <bank>", the bank, app
   version, language, and a line on what to do (find the bank's export steps and format; add it to the guide and, once
   a file's format is known, the engine). A failed mail is logged and the record stays.
4. Tests in `accounts/test-rules.sh` (anonymous create ok and mailed; read refused; personal-looking names refused;
   the rate limit; the migration down and up) and `docs/ACCOUNTS.md` (the request and its answers),
   `docs/PRIVACY.md` (a short section: what is stored, no personal data apart from the request's IP in the request log
   for 5 days and the rate limiter; kept until handled, at most 12 months, deleted by hand).

The app sends: `POST https://auth.ares-empire.de/api/collections/bank_requests/records`, JSON `{"bank": "…",
"app_version": "1.0 (12)", "language": "de"}`, `Accept-Language`, no token. Answers: 200, 400 (`message` +
`data.bank.code`), 429.

## Done when

`bash accounts/test-rules.sh` passes locally. Final message: files, test results, the request and answers as built,
how Claude deploys it. Never commit, push, merge or deploy; never touch the server, any database or other repos;
don't touch the public pages in `web/legal` (Claude does those).
