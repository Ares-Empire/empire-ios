# 237: Light and dark carried between the hub and the Arestemis demo

Status: running
Repos: `ares-empire` (branch `codex/237-look`, worktree `../ares-empire-237-look`) and `Arestemis` (branch
`codex/237-look`, worktree `../Arestemis-237-look`) · Model: `gpt-6.1-sol`, effort `high`

## Goal

A visitor moving between the Ares Empire hub and the Arestemis demo (arestemis.de) keeps the look they had (light or
dark), as they already do coming from patrikbreeck.com (Patrik, 2026-11-07: "hub light / dark mode should also just
transfer"). The convention exists: a link passes `?look=light` or `?look=dark`, and the page it opens starts in that
look for the visit without remembering it. Today the hub's links pass nothing, so the demo follows the device (a light
phone shows it light under the dark hub), and the demo's "Ask for access" opens the request form in whatever look
that form remembered.

## Read first

- `ares-empire`: `CLAUDE.md`, `EMPIRE.md` → "How we build apps"; `web/app/empire-api.js` (`destination(province)`,
  the demo band); its callers `web/app/app.jsx` (`goTo`), `web/app/mobile.jsx` (`Province`, `launch`),
  `web/app/panels.jsx`; `web/contact/appearance.js` (how the hub's contact pages read and carry `?look`);
  `webauth/contact.py` (the contact pages and their paths); `web/legal/page.html`, `web/legal/imprint.html`,
  `web/legal/impressum.html`, `web/legal/privacy.html`, `web/legal/datenschutz.html` (links to the contact pages);
  `web/app/samples/empire.demo.json` (the public demo's links: `https://aresium.de/demo`, `https://arestemis.de/`,
  `https://www.ares-empire.de/contact`).
- `Arestemis`: `CLAUDE.md` → "Public web demo", `docs/WEB-DEMO.md`; `web/app/language.js` (`A.accessLink`, and
  `A.setAppearance` / the passed look added in ec48b7c); its callers in `web/app/app.jsx`, `settings.jsx`,
  `price-fields.jsx`; `scripts/check-web-parity.mjs`, `scripts/check-web-data.mjs`.
- For comparison only (do not edit): `~/ares/static/js/apps.js` → `passLook` (patrikbreeck.com's version) and
  `~/aresium/web/public/app/appearance.js`.

## Build

1. **The hub passes its look (ares-empire).** The hub's pages (the desktop hub, the phone hub, the public demo at
   `/demo`, the login and the legal pages) have one look, dark (`data-theme="empire"`). Every link from them to a page
   that reads `?look` passes `look=dark`. Those pages are: `aresium.de` (every page; its `appearance.js`),
   `arestemis.de` (the demo, and its `/contact` and `/kontakt`, which are the hub's Arestemis request form), and the
   hub's own contact pages (`/contact`, `/kontakt`, `/arestemis/contact`, `/arestemis/kontakt`, on
   `www.ares-empire.de` or relative). Keep that list and the hub's look (`"dark"`) in one place in
   `web/app/empire-api.js`, with one helper that adds the parameter to a URL on the list (keeping its other
   parameters and its `#fragment`) and returns every other URL unchanged. Use it in `destination(province)` and for
   the demo band's "Get the app". The legal pages are static HTML: add `?look=dark` to their links to the contact
   pages directly.
2. **The demo passes its look (Arestemis).** Every "Ask for access" link (`A.accessLink()` and its callers) passes
   the look the demo shows at the moment of the click: the one chosen in Settings → Appearance, or with "Like this
   device" the device's (`matchMedia("(prefers-color-scheme: light)")`). It must be right after a change in Settings
   and after the device switches while "Like this device" is chosen, without a reload, so do not bake the look into
   the `href` only at render; set it when the link is used (for example a click handler, or computing the `href` on
   `pointerdown`/`focus` as well as on click; keyboard and middle-click opening must get it too). The contact page
   (`web/contact/appearance.js` in ares-empire) already reads it.
3. **Comments and docs.** Short comments where the look is passed, naming the convention. `docs/WEB-DEMO.md` in
   Arestemis: one sentence that "Ask for access" passes the demo's look. Claude updates `EMPIRE.md`.

## Settled: do not re-open

- The convention stays as it is: `?look=light|dark`, read for the visit, never remembered by the page it opens
  (Patrik, 2026-11-01, patrikbreeck.com and Aresium).
- No hand-off through `/sso?to=aresium`: the logged-in Aresium dashboard keeps its own remembered look. Only the
  pages listed above get the parameter.
- `arestoteles.de` and other provinces' sites do not read a look: their links stay unchanged.
- The hub stays dark; no light mode for the hub, the login or the legal pages in this brief.
- `web/app/language.js` must keep loading without a page: `scripts/check-web-data.mjs` runs it in Node with no
  `document` or `window.matchMedia`. Touch the DOM only inside functions that run in the browser.

## Out of scope

Everything else: no restyling, no new text on screen, no change to the contact pages' own switch, the hub's server
code or the demo's data. Do not touch `web/app/empire-data.js` or the samples' URLs.

## Checks

- **ares-empire:** `python3 -m unittest discover -s webauth -p 'test_*.py'` and
  `python3 -m unittest tools/test_empire_samples.py` pass (give the result lines). Add an offline check of the helper:
  a small Node script under `tools/` that loads `web/app/empire-api.js` in a `vm` context with a fake `location`
  (as `Arestemis/scripts/check-web-data.mjs` does with its files) and asserts `destination()` for the three demo
  provinces and for a non-demo province on `arestemis.de`, `aresium.de` (the `/sso` hand-off unchanged),
  `arestoteles.de` (unchanged) and a URL with its own query and fragment; plus a Python test in
  `webauth/test_server.py` that the served imprint and privacy pages link the contact page with `look=dark`.
- **Arestemis:** `.venv/bin/python -m pytest -q` (the worktree may use `~/Arestemis/.venv/bin/python` with
  `PYTHONPATH=src`), `node scripts/check-web-data.mjs > /dev/null`, and `node scripts/check-web-parity.mjs` against a
  local server (`docs/WEB-DEMO.md` → Run and check, with a database under `build/`). Extend
  `check-web-parity.mjs`: on a light device, Settings → Dark, then "Ask for access" goes to an address with
  `look=dark`; "Like this device" then gives `look=light`; with `?look=dark` passed in, the link carries `look=dark`.
  Read the address the click navigates to (or the `href` at the moment of the click), not only the rendered attribute.
- Privacy: `grep -rliF -f ~/.config/aresync/private-terms --exclude-dir=.git .` prints nothing in either worktree
  (file names only).

## Rules

Stay in the two worktrees. Never commit, push, merge or deploy, no installs, no requests to the live sites.

## Final message

Files changed per repo, the exact test and check result lines, and anything doubtful.
