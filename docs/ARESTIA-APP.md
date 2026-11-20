# Arestia app — decision record

**Decided 2026-11-19 (Patrik).** Status (2026-11-20): built and tested on the simulator against a fake flatd
(`scripts/fake-flatd.py`, HTTPS with its own identity and pairing code); one pairing identity on all work in the app
(below); not yet run against the real flatd, not merged, not on TestFlight. The fifth review (Codex gpt-6.2-astra) found
the re-pairing class once more outside the app's store: the Control Center toggles' value and action, `FlatdReach`'s
results, the Blind control's display and the connect attempt's expected pairing do not yet carry the identity; that
and its ordinary findings are open. The name: Arestia (Ares + Hestia,
goddess of the hearth and home), confirmed by Patrik on 2026-11-19.

Arestia is the flat on the iPhone: the fans, the blinds (Rollos), the modes and scenes and the flat in 3D, all through
Patrik's own flat service **flatd** on the home network. The app talks only to flatd, never to a device; flatd is the
one place for drivers, modes, timers and history, and Claude, the desktop viewer, NFC tags and the app all use it.
flatd's contract and the flat itself are private (they are not in any Ares Empire repo); this repo holds no flat data:
devices, their names, rooms, modes and scenes come from flatd at runtime, and the 3D page is flatd's `GET /viewer`,
loaded with the key and never bundled.

## What Patrik asked for (2026-11-19, his words)

- "Now I want proper phone control. I say we start with our own app so it can be better than apple home."
- "yes ares app. name? no account needed, just me."
- "An overview of functions and automations (connected things). the flat model but well made for easy navigation on an
  iphone. so not many buttons and big menu but just easy navigation and movement. needs good design. phone model actions
  should affect things too (like activating a fan). fans with timers is good. blind controls also good. live state yes,
  also displayed in model. modes yes also. shortcuts good idea, especially control center (widgets not needed yet)."
- "i wanna set up a process and NFC tag which upon tapping rolls the blinds up and activates both fans. default
  indefinetly. but in the app it shows that cooking is active and one click deactivates fans and rolls blind to fav
  spot." (He also named the one blind cooking moves; that stays in flatd's private config.)

## The decisions

- **No Ares account** (Patrik: "no account needed, just me"), a deliberate deviation from the Empire standard, where
  every app logs in with the one Ares account. Arestia authenticates to flatd with flatd's own key, entered once. So:
  no login screen, not in the shared login's Keychain group or App Group, no account section in Settings
  (`EmpireAppIdentity.arestia.hasAccount` false, `SettingsAccountSection.hidden`), not in `EmpireAppIdentity.all` (the
  account server has no `arestia` service). Contact & support goes without a login, as Aresium's
  (`supportWithoutLogin`). Everything else of the standard applies: English and German, light and dark, Settings
  behind the gear, the band at the end of the main screen, the shared design.
- **Pairing once, and who the app trusts** (2026-11-19, flatd contract v1.2; replaces "the key goes only to an address
  that answers like flatd"). On the home network flatd speaks **HTTPS only**, with a self-signed certificate for one
  private key it made itself. `flatd pair`, run on flatd's own machine, shows a QR code with JSON
  `{"url", "token", "spki_sha256"}`: where flatd is right now, its key (the bearer token), and its **identity**, the
  SHA-256 of its public key. Patrik scans it with Arestia's own scanner (or pastes the same text); that is all there is
  to enter. From then on the app talks only to a server that proves in the TLS handshake that it holds that key
  (`FlatdPin`, checked by `FlatdTransport`'s session delegate on every connection). Before that proof nothing is
  sent: no key, no request. So:
  - a device that poses as flatd (a forged Bonjour answer, ARP, the saved address on another Wi-Fi) gets nothing, and
    someone listening on the Wi-Fi reads nothing;
  - **Bonjour and the saved address are only where to look.** The app tries the saved address, then every address
    `_flatd._tcp` is advertised at, and keeps the one where the pinned key answered. No Bonjour name is remembered;
  - the pin is the **key, not the certificate**, and nothing else about the certificate is checked (no CA, no name, no
    dates). So flatd can renew its certificate, get a new address or machine name, or move to the always-on box with
    its identity folder, without pairing again. A new key or a new token on flatd's side means pairing again
    (Settings → Pair again);
  - nothing in the app speaks plain HTTP: no App Transport Security exception, the transport and the event stream
    refuse a non-TLS address themselves, a pairing code with a plain address is refused, and a saved pairing without a
    pin (from a build before this) counts as no pairing;
  - no redirect is ever followed, no proxy set up on the iPhone is used, and iOS fetches nothing on the certificate's
    behalf; one URLSession per pin, so a connection checked against one identity never carries a request for another;
  - never an `arestia://` link with the key (another app may claim the scheme and would get it when the camera opens
    the link), and no pairing by key alone or by address: neither carries the identity.

  **Why this and not the alternatives.** An HMAC challenge in `/api/health` (flatd proves it knows the key before the
  app sends it) would stop a device that merely answers at the address, but the key would still cross the Wi-Fi in
  the clear on every request, and someone relaying between the phone and the real flatd passes the challenge and
  reads it. Three review rounds had each found the same root one level deeper (the app cannot prove who answers on
  plain HTTP); only an authenticated, encrypted channel removes it. Pinning the certificate itself (its fingerprint)
  would work until the certificate is renewed and then force a new pairing; pinning the key does not. A CA or an
  account would be more machinery for one phone and one service.

  The pairing (address, key, pin; one item) lives in Arestia's own Keychain group, shared with its Control Center
  extension and readable after the first unlock, so a control works from the lock screen (never synced, never
  restored to another device). Settings → Flat service shows the address flatd was last reached at and the identity's
  first 16 hex digits, the same ones `flatd pair` prints under its QR code and flatd logs at startup.
- **Pairing again with another flatd** (a code whose identity differs from the paired one, or when the saved pairing
  cannot be read) never happens by itself: the code is shown with its identity and waits for Connect, because the
  code decides who the app trusts from then on. A first pairing, and a fresh code of the same flatd, connect at once
  (a first scan is not confirmed against the identity on flatd's screen: whoever could put another code in front of
  the camera would only pair the app with their own service, and learns nothing of the flat's). An attempt connects
  exactly the code it was started with (scanning another cancels it), and the store checks again, when it keeps the
  pairing, that what is saved is still what the decision was made against.
- **One pairing identity for all work** (2026-11-20, after the trust review's rounds 1–4 each found work of one pairing
  reaching the next one level deeper: the old 3D page, its queued task, saved Shortcut and control choices, then a
  second window's counter, the picker's two readings, the connect task's late reading of the code). The class is
  closed by design, not by another patch: the pairing's Keychain UUID (`FlatdPairing.id`) is the one value every piece
  of work carries: the store (`pairingID`), its event stream, every command, the 3D page (its web view, listener and
  requests), every client (`pairingID`), and a blind or fan chosen in a Shortcut or a control (`SavedDevice`: the
  device id with the pairing's identity). Anything tagged with another identity is dropped, never acted on; a
  command's client is built from the same Keychain reading whose identity was checked, so its key and pin are that
  pairing's. Then:
  - **another flatd is paired only through a full Disconnect**: the old pairing is forgotten with the names kept for
    it, the store leaves it completely (its tasks cancelled, the stream and the 3D page gone, its state cleared), and
    the new pairing is saved fresh, with an identity of its own, only while nothing is saved. Its flatd is checked
    first, so an unreachable one leaves the old pairing as it was. Choices made in the old pairing do nothing in the
    new one (flatd's device ids are only names inside one flatd): they are made again, as after any Disconnect;
  - **a fresh code of the same flatd** (a new key or address) is a light update: the same identity, so its page,
    choices and work go on; the stream starts again with the new key, and a refusal counts only for the key it was
    sent with;
  - **the Keychain item is versioned** (its label is a revision that every write renews): a new address or key is
    written only over the version it was read as, so a late address update from a control never brings back an older
    key, and a new pairing never overwrites one made meanwhile;
  - **one window** (`UIApplicationSupportsMultipleScenes` false, the generated scene manifest off): one store. A
    store would still notice a pairing made elsewhere and leave its own before following it;
  - the 3D page speaks only once WebKit committed the very navigation the app started for it (`PageHandover`).
- **What the pin does not cover:** anything behind flatd (how flatd reaches its devices is flatd's own matter, in
  its private contract); what the 3D page does inside WebKit beyond HTTP and WebSocket loads, which are blocked (the
  page is flatd's own, fetched from the proven flatd, and is trusted as that); and someone who can read flatd's
  machine (its `key.pem` and config) or this iPhone's Keychain, or who photographs the QR code while it is on screen:
  they have what flatd or the phone has.
- **Two tabs and the gear** ("not many buttons and big menu"): **Home** (what the flat is doing in one line; cooking
  while it runs, with Done cooking as the one big button; otherwise the modes and scenes as three tiles; the fans with
  on/off and the timers 15 min / 30 min / 1 h / ∞ and the time left; the blinds with their window drawn at its position,
  dragged to set it, up / favourite / down and stop while moving; then the automations, what runs by itself), and
  **Flat**, the 3D model full-bleed. Settings: the flat service (state, connect again, disconnect), then the shared
  sections.
- **Live state** from flatd's event stream (`wss://…/api/events`, the key in its header): the snapshot, then every change whoever made it (the
  app, Claude, a wall switch, a timer). It reconnects by itself with growing pauses and pings every 20 s, so a sleeping
  Mac is noticed. Not reachable: the last state stays, marked "Last seen 18:40", and one calm card when there is no
  state at all ("The Mac may be asleep, or you're not at home"); no alerts. Nothing is shown as done before flatd
  confirmed it, except a blind's target while a finger drags it.
- **Cooking** is flatd's mode `cooking` (which devices it moves and how is flatd's own config: on, the fans and one
  blind up; off, the fans off and that blind to its favourite spot). The app shows it while active with since when and
  what its devices do right now, and Done cooking ends it, with Undo for a few seconds. A device that did not follow is named
  ("Didn't answer: …"); the mode stays as flatd recorded it.
- **The 3D tab** shows flatd's phone viewer in a web view and speaks its bridge (the viewer's `BRIDGE.md` v1: the
  handler `flat3d`, `flat3d.receive`, one result per request): taps in 3D go to flatd through the app, live state goes
  back to the page. The app fetches `GET /viewer` itself, over the pinned connection, and hands the page to the web
  view (under a made-up `.invalid` origin, with every network load blocked): the web view never talks to the network,
  the key never enters it, and flatd's identity is checked in one place instead of also in WebKit.
- **Shortcuts, Siri and NFC** (App Intents, `ArestiaShared/ArestiaIntents.swift`): Start cooking, End cooking, Fans on
  (minutes and fan optional), Fans off, Move a blind (which, and up / down / favourite / stop, from flatd's list), Air
  out, All blinds down. Patrik's NFC tag is a personal automation in Shortcuts that runs Start cooking. They run without
  opening the app.
- **Control Center** (`ArestiaControls`, iOS 18 `ControlWidget`): Cooking and Fans as toggles, and a Blind control per
  blind (chosen when it is added; up when on, down when off). Home-screen widgets: not yet (Patrik).
- **Look:** the province apps' wall and glass cards, with **hearth ember** as the one accent (`AppAccent.arestia`:
  `#FF9A62` dark, `#A8481A` light, 4.98:1 on the light wall), used only for what is on or the one thing to press. The
  mark is real fire (Patrik, 2026-11-20: "lets go real fire", after five rounds of drawn flames and Hestia busts,
  which he found ugly or too close to Artemis): the icon a flame on black, the header's mark the same flame on clear,
  with a light-appearance variant whose core is gold instead of white and whose fringe is orange instead of pink, so it
  reads on the light wall. Generic fire, nothing of the flat.

## iPhone features (IPHONE-APPS.md checklist)

- Control Center controls: yes (above). Siri and Shortcuts: yes, also the way to NFC tags.
- Home and lock screen widgets: not yet (Patrik, 2026-11-19).
- Live Activities: a good fit later (cooking on the lock screen with Done cooking); not built.
- Share sheet, Spotlight, Maps, Calendar, Face ID, on-device AI: none fit. The camera only reads flatd's QR code.

## Not in this repo

flatd (its code and contract), the flat's model and the viewer stay private, in Patrik's own folders. The fake flatd
here has made-up devices only (Fan 1, Fan 2, Blind 1, Blind 2, Lamp 1) and a stand-in page at `/viewer` that speaks the
same bridge.
