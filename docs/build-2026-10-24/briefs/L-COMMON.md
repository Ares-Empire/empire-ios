# Languages: rules for every server brief (2026-10-24)

You are Codex, run by Claude (the lead). Read `COMMON.md` (same folder) and follow it, with two differences: you are
not a "Claude build agent" but its rules hold for you in full, and you **may commit** on your branch in your worktree
(small commits, plain English, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`). Never push or
merge. No network except installing your brief's packages into the worktree's `.venv` / `node_modules`.

## Why

Patrik decided (2026-10-24) that every Empire app speaks English and German: `~/ares-empire/docs/LANGUAGES.md`. Read it
first; it is the rule you build. The iPhone apps are being translated by the lead. Your part: the sentences the
servers write for the apps and their notifications.

## The language contract (the same in every service)

- **Request language** from `Accept-Language`: German when, among the tags whose primary language is `de` or `en`, the
  one with the highest `q` (ties: the first) is German. So `de`, `de-DE`, `de-DE,de;q=0.9,en;q=0.8` → `de`;
  `en`, `en-GB,de;q=0.5`, `fr`, missing or unreadable → `en`. The apps send exactly `de` or `en`.
- Every answer that contains sentences sets `Content-Language: de` or `en`.
- **Codes never change**: enums, keys, slugs, numbers and timestamps are the same in both languages. Only the
  fields the brief names (sentences, words for people) follow the language.
- **Text kept for later** (incidents, AI notes) is stored so it can be shown in either language (both versions, or a
  key with its values), then put into words in the language of the request that reads it. Rows stored before your
  change have only English: show that English in both languages, never fail.
- **All texts of a service in one module** (e.g. `texts.py`), English and German side by side, so the lead can review
  the German in one place. No translation library, no gettext; a dict and a small function are enough.
- **German style:** "du", plain, short, same register as the English. Numbers: `1.400` (thousands with a dot),
  `99,6` (decimal comma), money `980 €` (`€980` in English), `92 %` in both, `182 ms` in both. Dates: English
  `23 Oct`, German `23. Okt.`; times `14:02` in both. Abbreviations: `Min.`, `Std.`, `Tag/Tage`. Do not use the
  `locale` module (the server's locale is not ours); write the month names yourself.
- Error bodies the apps show (`{"error": "..."}`) follow the language too, except developer messages for requests the
  apps never send (malformed JSON, unknown fields): those may stay English.
- **Tests:** every text in both languages through its real code path (not only the table), the header parsing
  (the cases above), and old stored rows. Existing English tests keep passing unchanged.
- **Docs:** the service's API doc gets a short "Language" section (the header, which fields follow it). Samples stay
  English.

## Final message

As `COMMON.md` says, plus: the full German table (or the file path and its line count) so the lead can review it.
