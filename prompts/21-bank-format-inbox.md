# 21: An inbox for bank formats people share from Aresium

Status: merged and deployed 2026-10-27 (live checks: refusals 400, anonymous read 403, rate limit 5/h)
Repo: ares-empire · Worktree: `~/ares-empire-21-format-inbox` (branch `claude/21-format-inbox`) · Built by: a Claude
agent

## Goal

When Aresium does not know someone's bank, they confirm the columns once, type the bank's name and tap Send. The app
then sends the file's **format** (a `CsvLayout` from the engine's `shareableLayout`: separator, header names, which
column means what, date and number style; never a payment, amount, IBAN or name) and the bank's name to us. Claude
adds it to Aresium's bank list for everyone with the next app update. No Ares account is needed to send (Aresium may
become usable without an account). This brief builds the receiving end on the account server, the same way the
website's contact form works.

## Read first

`AGENTS.md`/`CLAUDE.md`, `accounts/pb_migrations/1793200000_contact.js`, `accounts/pb_hooks/contact.pb.js`,
`accounts/pb_hooks/lib/mail.js`, `accounts/test-rules.sh`, `docs/PRIVACY.md` (contact form section), `docs/ACCOUNTS.md`.

## Build

1. Collection `bank_formats` (migration): `bank` (text, required, ≤ 100), `layout` (json, required), `app_version`
   (≤ 40), `language` (`en`/`de`), created. Create: anyone (like `contact`); list/view/update/delete: superusers only.
2. Validation in a hook before create: `layout` is a JSON object, ≤ 8 KB serialised, `version` 1, `separator` one of
   `,` `;` tab `|`, `header` an array of ≤ 80 strings each ≤ 80 characters, `columns` an object of small integers or
   integer arrays, and **no string anywhere** that looks like an IBAN, an email address, a date, an amount, or 5+
   digits in a row (the app checks this too; the server refuses it anyway). Refuse with a plain 400 message.
3. Rate limit like the contact form (5 per hour per IP; PocketBase's limiter), honeypot not needed (no web form).
4. A hook mails each new format through `lib/mail.js` to the contact address: subject "Aresium: bank format for
   <bank>", body the bank, app version, language and the layout pretty-printed, and the command Claude runs to turn it
   into a profile (`npx tsx scripts/add-shared-layout.ts <file> --name "<bank>"` in `~/aresium`).
5. Tests in `accounts/test-rules.sh` style (anonymous create ok; read refused; an IBAN in a header refused; too big
   refused) and a short section in `docs/PRIVACY.md` → Per service (what is stored, no personal data in it apart from
   the request's IP in the request log for 5 days; kept until the format is added, at most 12 months, deleted by hand).

## Done when

The migration and hooks are written and tested the way `test-rules.sh` runs locally (read it). Final message: files,
how to deploy (Claude does that), the exact request the app sends (URL, JSON body), and the answers it gets. Never
commit, push, merge or deploy; never touch the server, any database or other repos.
