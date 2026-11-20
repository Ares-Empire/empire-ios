# Arestia app — decision record

**Decided 2026-11-19 (Patrik).** Status (2026-11-20): built and tested on the simulator against a fake flatd
(`scripts/fake-flatd.py`, HTTPS with its own identity and pairing code); one flat per install (below), which replaced
the re-pairing in place after the fifth review; not yet run against the real flatd. The name: Arestia (Ares + Hestia,
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
    (a new token: Settings → Pair again, the same flat; a new key is another identity, so another flat: Forget first);
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
- **One flat per install** (the lead's decision, 2026-11-20, after the fifth review). The app is paired with one flatd
  identity at a time, and another flat is paired only after **Settings → Forget this flat**.
  - *Why.* The trust boundary held in four reviews in a row (the key and every command reach only a server that proved
    the pinned key). But five reviews in a row found a new variant of one other class: consistency when the phone is
    re-paired from one flatd to a *different* one in the middle of use (the old 3D page, its queued task, saved Shortcut
    and control choices, a second window's counter, the picker's two readings, the connect task's late reading of the
    code, then the Control Center toggles' value and action and `FlatdReach`'s results). Patrik has one flat and one
    flatd. Chasing multi-flat consistency through every surface costs more than it is worth, so the case is removed by
    design instead of patched one level deeper again.
  - *What Forget does* (`FlatSession.forget`): the pairing and everything kept for it go (the Keychain item; in the App
    Group the devices' names and a mode's trouble note, `FlatdConnection.forget`); the store retires
    (`FlatStore.retire`: its loop and every command cancelled, its event stream ended, its listeners and so the 3D
    page's bridge dropped, its state cleared, and whatever of it is still on its way finds it retired and changes
    nothing); a new store without a pairing takes its place, and the app's screens are built anew with it (the old web
    view and its bridge are dismantled with them); the controls read again. If the Keychain keeps the item, nothing
    changes and the app says so. A choice made in a Shortcut or a control carries the pairing it was made in
    (`SavedDevice`; iOS keeps those parameters and the app cannot delete them), so after Forget it acts on nothing.
  - *A store lives for one pairing.* `FlatStore.pairingID` is fixed for its life; a store never switches flat. A first
    pairing also makes a new store (the one without a pairing retires). A store that finds another pairing saved, or
    none (only Forget or a Debug launch argument can do that), retires and the session builds the right one.
  - *Codes.* A first pairing connects as soon as a well-formed code is scanned (and replaces an item that is no
    pairing, from a build before flatd had an identity). A fresh code of the same flat (the same pin) renews key and
    address in place, written only over the version read (the Keychain item's label is a revision, so a late address
    update from a control never brings back an older key); the stream starts again with the new key and the 3D page
    loads again. A code of another flat while one is paired is refused at once, before anything is asked anywhere:
    "This is a different flat. Forget the current one first." There is no switch in place, and no confirmation step.
  - *Controls, Shortcuts and Siri act on the flat paired when they run*: a Control Center toggle is "my flat's
    cooking", not one flat's. After Forget and a new pairing they act on the new flat by definition. A device chosen
    in one (a blind, a fan) that the flat does not have (flatd answers 404 for it, or it was chosen before Forget)
    fails cleanly ("This blind isn't in your flat anymore. Choose it again.") and nothing else moves; the Blind control
    then shows "Not in your flat" under the plain word Blind, never its old name or a made-up state. A blind flatd
    has no position for (offline, or before the board's first reading) shows "Position unknown", never Up.
  - *Nothing starts after Forget, in any process* (round 6): every request with a pairing's key starts only while
    that pairing is the saved one, checked under one lock that Forget's delete takes too (`FlatdDispatchLock`, a file
    in the App Group locked with `flock`, so the app and the Control Center extension share it). The pinned transport
    makes and resumes the request's task inside that same step (`FlatdTransport`, `FlatdGate`), so no await and no
    other process can come between the last check and the start: a request either started before Forget, or never.
    The lock is held only for that moment, never across a wait (iOS ends a process suspended with a lock in the App
    Group), and it fails closed (round 7): without its file (in Application Support, never in Caches, which iOS may
    empty) no request with the key starts and Forget reports that it failed. The event stream and a fresh code of the
    same flat start inside the gate too; only a first pairing asks flatd before anything is saved. A Shortcut's answer
    (or flatd's refusal) counts only while its pairing is still the saved one; one that arrives after Forget is dropped,
    one the Keychain cannot vouch for says so. A root built anew (a language switch) retires its session's store, so no
    old store's work goes on beside the new one.
  - *Accepted.* Until Control Center reads a control again after Forget, its toggle may show the old flat's state.
    Losing flatd's identity key (a new machine without its identity folder) makes it another flat: Forget and pair
    anew.
  - *Open, for the lead and Patrik (round 7):* "started before Forget" means the request's task was resumed before
    the delete. Its connection and TLS handshake may still be under way when Forget completes, so its first bytes can
    leave a few milliseconds after it (to the forgotten flat, which proved its key). Closing that too would take a
    cross-process registry of requests in flight that Forget waits for and drains. The review asks for it; the
    proposal here is to accept it as "already on the wire", since the command was given before Forget, by the owner,
    to his own flat.
  - *Out of scope by design*: consistency between two flats without Forget in between, since the app never does that.
- **The Keychain may fail to answer** (before the iPhone's first unlock after a restart, or a hiccup): that is never
  taken as "no pairing" (`FlatdConnection.Saved.unreadable`). The live loop and the session read again with growing
  pauses; a command says "Arestia couldn't read its pairing just now", and the 3D tab shows it with Try again.
- **One window** (`UIApplicationSupportsMultipleScenes` false, the generated scene manifest off): one session, one
  store at a time. The 3D page speaks only once WebKit committed the very navigation the app started for it
  (`PageHandover`).
- **What the pin does not cover:** anything behind flatd (how flatd reaches its devices is flatd's own matter, in
  its private contract); what the 3D page does inside WebKit beyond HTTP and WebSocket loads, which are blocked (the
  page is flatd's own, fetched from the proven flatd, and is trusted as that); and someone who can read flatd's
  machine (its `key.pem` and config) or this iPhone's Keychain, or who photographs the QR code while it is on screen:
  they have what flatd or the phone has.
- **Two tabs and the gear** ("not many buttons and big menu"): **Home** (what the flat is doing in one line; cooking
  while it runs, with Done cooking as the one big button; otherwise the modes and scenes as three tiles; the fans with
  on/off and the timers 15 min / 30 min / 1 h / ∞ and the time left; the blinds with their window drawn at its position,
  dragged to set it, up / favourite / down and stop while moving; then the automations, what runs by itself), and
  **Flat**, the 3D model full-bleed. Settings: the flat service (state, its identity, Pair again for a new code of the
  same flat, Forget this flat), then the shared sections.
- **Live state** from flatd's event stream (`wss://…/api/events`, the key in its header): the snapshot, then every change whoever made it (the
  app, Claude, a wall switch, a timer). It reconnects by itself with growing pauses and pings every 20 s, so a sleeping
  Mac is noticed. Not reachable: the last state stays, marked "Last seen 18:40", and one calm card when there is no
  state at all ("The Mac may be asleep, or you're not at home"); no alerts. Back from the background, or when the
  stream drops, the last state shows as "Reconnecting…" until flatd's next snapshot, never as "Live". Nothing is shown
  as done before flatd confirmed it: a blind follows the finger while it drags, and once let go reads "Sending: 40 %
  closed" until flatd answered that very request or its state confirmed that target (an older drag's answer never
  clears a newer one; a failure puts flatd's position back, with the reason). A blind's commands go to flatd one after
  another in the order given; one still waiting when a newer one comes is not sent, so Stop never arrives before the
  movement it stops, and positions dragged past while one is out are not sent at all.
- **Cooking** is flatd's mode `cooking` (which devices it moves and how is flatd's own config: on, the fans and one
  blind up; off, the fans off and that blind to its favourite spot). The app shows it while active with since when and
  what its devices do right now, and Done cooking ends it, with Undo for a few seconds. A device that did not follow is named
  ("Didn't answer: …"); the mode stays as flatd recorded it. Changed outside the app (the Cooking control, a Shortcut,
  the NFC tag), the devices that did not follow are kept with the mode's state (`ModeTrouble`, in the App Group, for two
  hours at most, while the mode is still in that state, written and cleared only for the pairing it belongs to, and
  cleared only by a change that left that state: a second End cooking, which sends no device commands, leaves it): the
  control reads "On · not all followed" for as long; the app says which ones, once (its own acknowledgement, which
  leaves the control's line alone), at once while it follows flatd (a Darwin notification, and again when flatd's mode
  event arrives after it) or with its next snapshot. A device that does not confirm in time (504) may still have
  switched: the app says it did not confirm, never that nothing changed.
  flatd itself keeps no record of them. Siri and Shortcuts say only what flatd's answer confirmed ("Cooking is on.",
  "Cooking is off.", a scene's "Not everything followed." with the names, a blind's state as flatd answered it), never
  what the devices are assumed to do; nothing is read before a command to word it.
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
