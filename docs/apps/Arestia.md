# Arestia (iPhone)

The owner's flat through his flat service flatd on the home network. Decisions and details: `docs/ARESTIA-APP.md`. Rules for every app: `CLAUDE.md`. Owner decisions are tagged "(owner, date)"; when one changes, change its line (git keeps the old one).

## Decisions and rules in force

- No Ares account (owner, 2026-11-19).
- The flat and flatd's contract stay outside every repo; devices, names, modes and the 3D page come from flatd at
  runtime. One flat per install; device names live in flatd.
- Trust: HTTPS only, a pinned SHA-256 of flatd's public key, no redirects; Bonjour addresses are only candidates. The
  pairing code is only the JSON with `spki_sha256`, never a key alone, an address with `?token=`, plain HTTP or an
  `arestia://` link carrying the key. Its own Keychain group, readable after first unlock.
- Simulator work uses the fake flatd, never the real one; files passed with `--viewer`/`--devices` are never committed.
- "Always daylight" setting (owner, 2026-11-19); the mark is real fire, busts were rejected (owner, 2026-11-20); no
  Automations card (owner, 2026-11-20).

## As built

### Arestia app

**Arestia app** (2026-11-19, `Arestia/`, bundle id `de.ares-empire.arestia`, URL scheme `arestia`; decisions
`docs/ARESTIA-APP.md`): the owner's flat through his own flat service **flatd** on the home network (its contract and the
flat stay private, outside every repo; nothing of the flat is in this one: devices, names, modes and the 3D page come
from flatd at runtime). **No Ares account** (owner: "no account needed, just me"): `EmpireAppIdentity.arestia`
(`hasAccount` false, not in `all`), no login, no account section in Settings, the contact form without a login; its
own App Group `group.de.ares-empire.arestia` and Keychain group `de.ares-empire.arestia` (device names, language;
the pairing, flatd's address, key and identity pin as one item, readable after the first unlock), shared with **`ArestiaControlsExtension`** (`Arestia/ArestiaControls/`,
`de.ares-empire.arestia.controls`: Control Center's Cooking, Fans and Blind controls). `Arestia/ArestiaShared/` is
compiled into both: the contract's types (`FlatdModels`, read leniently, states merged key by key), `FlatdClient`
(every call but health with the Bearer key; 401 refused, 404 unknown, 409 not possible, 504 no answer from the
device), `FlatdConnection`, **trust** (`FlatdPin`: the SHA-256 of flatd's public key from the pairing code;
`FlatdTransport`: HTTPS only, one URLSession per pin whose delegate accepts only a server holding that key, no
redirects; decisions and reasons in `docs/ARESTIA-APP.md`, "Pairing once, and who the app trusts"), Bonjour
(`FlatdBonjour`, `FlatdReach`: the saved address, else every advertised `_flatd._tcp` address, each only a candidate
until the pinned key answered there), `PairingCode` (only JSON `{"url", "token", "spki_sha256"}` from `flatd pair`'s QR
code, read by the app's own scanner or pasted; never a key alone, an address with `?token=`, a plain-HTTP address or
an `arestia://` link with the key),
`FlatActions` and what the intents share (`IntentSupport`). **Each intent lives in one target:** the Siri, Shortcuts
and NFC ones in the app (`Arestia/Intents/FlatIntents.swift`, the phrases in `AppShortcuts.xcstrings`), the Control
Center ones in the extension (`ArestiaControls/ControlIntents.swift`); an intent compiled into both was run by iOS in
the extension, which has no `AppShortcutsProvider`, so Spotlight's App Shortcut failed with "Couldn't find shortcut"
(2026-11-19; checked after the split: Spotlight's Lüften ran in the app and reached flatd, the Cooking control in
Control Center toggled flatd's mode). The
app: `FlatStore` (the event stream's snapshot and events, reconnecting with growing pauses and 20 s pings, commands
with their answers shown at once, listeners for the 3D page), `FlatWords` and `DeviceNames` (the words and a name's rules, pure),
`ViewerBridge` (the viewer's `BRIDGE.md` v1: handler `flat3d`, `flat3d.receive`, one `result` per request), screens
Home, Flat (the WKWebView with one protected, ETag-checked copy per pairing), Connect, Settings' Flat service and 3D
flat sections (Always daylight, the bridge's `lighting: "day"`, the owner 2026-11-19; off: the real sun, `"real"`).
The real phone viewer was checked in the
WKWebView on the simulator through the fake (`--viewer`, `--devices`, local files only): WebGL2 works, a blind tapped
in 3D moved through the app. Accent: hearth ember (`AppAccent.arestia`), the
mark real fire (owner, 2026-11-20: "lets go real fire"; busts were rejected): the icon an opaque flame on black,
the `Mark` image with a light-appearance variant (`mark-light.png`: the same flame with a gold core and an orange
fringe, which the plain one turned pink on the light wall). **The fake flatd** for the simulator:
`python3 scripts/fake-flatd.py` (HTTPS on port 8790 with its own identity in `build/fake-flatd/`, pairing code printed, also alone with `--pairing`; `--new-identity` = flatd lost its key; Bonjour "flatd (fake)", made-up Fan 1/2, Desk lamp, Blind 1/2, `--extra`
Plug 1, renaming as flatd 1.3 does (`--no-rename`: a flatd before it, PATCH answers 405), a stand-in `/viewer` that speaks the bridge, test hooks under `/fake/`; `--viewer <file>` and `--devices
<file>` serve a local page and its device ids instead, never committed); never the real flatd (port 8787, its own
key). Its key has letters and digits only: AXe types through the simulator's German keyboard, where "y", "z" and "-"
land elsewhere. Test hooks: `curl -k https://127.0.0.1:8790/fake/…`. DEBUG launch arguments: `-flatdPairing '<the pairing code>'` (pair without the screen; AXe
cannot tap the connect screen's system paste button), `-connectCode '<the pairing code>'` (the connect sheet with that code, as scanned: another flat's is refused, Forget first), `-forgetFlatd`, `-tab home|flat`, `-openSheet settings|connect`,
`-scrollToEnd`, `-scrollTo lights|blinds`, `-renameDevice <id>` (its name's field open; `-renameText <text>`), `-probeViewer` (logs WebGL2, frames and the page's text every 5 s,
category `viewer`). Screenshots: `axe screenshot` (`xcrun simctl io … screenshot` caught the launch screen at times). Tests: `ArestiaTests` (contract, client, actions, store, words,
bridge; a fake transport and event stream; `TrustTests`: the pin against made-up certificates, the pairing code,
rediscovery past a server without flatd's key; `OneFlatTests`: one flat per install, Forget ending every piece of the old
flat's work, another flat's code refused, a fresh code of the same flat, the page's handover, one scene;
`ReviewRound5Tests`: Keychain hiccups, the 3D tab's loading, Reconnecting, a released blind, Cooking's failures, a gone
blind; and `LiveFlatdTests`, the pinned URLSession and WebSocket over real TLS against a fake flatd that
`scripts/test-unit.sh Arestia` starts for the run, on loopback and a free port, locally and on GitHub alike).

### One flat per install

**One flat per install** (2026-11-20, `docs/ARESTIA-APP.md`): `FlatSession` holds the store for the saved pairing;
Settings → Forget this flat retires it and builds a new one; a store never changes flat. **`scripts/strings.py fill` writes a key's German into every catalog
that has it** (an "Up" meant for blinds overwrote Aresus's uptime "Laufzeit" once): give it only new keys, and read
`git diff` of the other apps' catalogs after it.

### Renaming and Lighting

**Renaming and Lighting** (2026-11-20, after build 2; `docs/ARESTIA-APP.md` → "After build 2"): a device's name lives in
flatd (contract v1.3, `PATCH /api/devices/{id}`, the `device` event, `default_label`), so every client shows one
name; on Home a long press on a device's row offers Rename (the name becomes a field where it stands, Cancel beside
it, Return or a scroll saves an edited name, an untouched field sends nothing, empty = flatd's name) and Original
name (`Screens/DeviceNameViews.swift`, `FlatStore.rename`, shown muted until flatd confirmed it, Rename again only
once flatd answered; a flatd before 1.3 gets a calm line). The names kept for Shortcuts and the controls are one
file in the App Group (`DeviceNameFile`, never `UserDefaults`: its values reach the other process late), read and
replaced under the lock the app and the extension share: a snapshot replaces the list, a confirmed rename changes its
device alone (`rememberName`), a list a request read is kept only if nothing was kept since it began
(`remember(_:for:readSince:)`), and every consumer shows the name kept (`FlatActions.read`; `NameFileTests`). Lights have their own
section, Lighting / Licht, after Fans; the Automations card is gone (owner: "I dont think we need them").

### Build 3 uploaded 2026-11-20 17:15

**Build 3 uploaded 2026-11-20 17:15** (renaming in flatd 1.3, Lighting, no Automations card, 3D walk mode, the page kept
on the phone; PRs #2 and #3). **Build 2 uploaded 2026-11-20** (internal group "Arestia"). Build 1 was refused by Apple (ITMS-90626, Invalid Siri
Support): App Intent titles, descriptions and phrases may not name Apple products ("Mac", "iPhone", "Siri" …);
in-app texts may.
