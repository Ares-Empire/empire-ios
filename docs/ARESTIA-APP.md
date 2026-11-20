# Arestia app — decision record

**Decided 2026-11-19 (Patrik).** Since build 2 (2026-11-20): renaming devices in flatd, the Lighting section, no
Automations card ("After build 2" below). Status (2026-11-20): built and tested on the simulator against a fake flatd
(`scripts/fake-flatd.py`, HTTPS with its own identity and pairing code); one flat per install (below), which replaced
the re-pairing in place after the fifth review; merged after the final review (round 9, SAFE); not yet run against the
real flatd. The name: Arestia (Ares + Hestia,
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
    fails cleanly ("This blind isn't in your flat anymore. Choose it again.") and nothing else moves (iOS asks the
    app for a saved choice, and one the flat does not have comes back as "Not in your flat" rather than none, which for
    the fans' optional choice would mean every fan; round 8); the Blind control
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
  - *Accepted risk: a request already on the wire* (the lead, 2026-11-20, after the seventh review). "Started before
    Forget" means the request's task was resumed before the delete. Its connection and TLS handshake may still be under
    way when Forget completes, so its first bytes can leave a few milliseconds after it, to the forgotten flat, which
    still has to prove its pinned key first. That counts as already on the wire: the command was given by Patrik,
    before Forget, to his own flat. There is no cross-process registry of requests in flight that Forget waits for and
    drains; nothing new starts after Forget.
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
  on/off and the timers 15 min / 30 min / 1 h / ∞ and the time left; the lights under Lighting; the blinds with their
  window drawn at its position, dragged to set it, up / favourite / down and stop while moving; then More, the plugs
  and any kind a newer flatd brings), and
  **Flat**, the 3D model full-bleed. Settings: the flat service (state, its identity, Pair again for a new code of the
  same flat, Forget this flat), then the shared sections.
- **Live state** from flatd's event stream (`wss://…/api/events`, the key in its header): the snapshot, then every change whoever made it (the
  app, Claude, a wall switch, a timer). It reconnects by itself with growing pauses and pings every 20 s, so a sleeping
  Mac is noticed. Not reachable: the last state stays, marked "Last seen 18:40", and one calm card when there is no
  state at all ("The Mac may be asleep, or you're not at home"); no alerts. Back from the background, or when the
  stream drops, the last state shows as "Reconnecting…" until flatd's next snapshot, never as "Live". Nothing is shown
  as done before flatd confirmed it: a blind follows the finger while it drags, and once let go reads "Sending: 40 %
  closed" until flatd answered that very request or its state confirmed that target (an older drag's answer never
  clears a newer one; a failure puts flatd's position back, with the reason). The commands for one device (or one
  mode) go to flatd one after another in the order given, from Home and the 3D page alike (round 8: two taps on a fan
  in 3D could otherwise arrive the other way round); a blind's command still waiting when a newer one comes is not
  sent (also when the newer one comes while flatd is still being found), so Stop never arrives before the movement it
  stops, and positions dragged past while one is out are not sent at all.
- **Cooking** is flatd's mode `cooking` (which devices it moves and how is flatd's own config: on, the fans and one
  blind up; off, the fans off and that blind to its favourite spot). The app shows it while active with since when and
  what its devices do right now, and Done cooking ends it, with Undo for a few seconds. A device that did not follow is named
  ("Didn't answer: …"); the mode stays as flatd recorded it. Changed outside the app (the Cooking control, a Shortcut,
  the NFC tag), the devices that did not follow are kept with the mode's state (`ModeTrouble`, in the App Group, for two
  hours at most, while the mode is still in that state, written and cleared only for the pairing it belongs to, and
  cleared by a change where every device followed: a start, which sends every device its command again, or an end of
  a mode that was on; a second End cooking, which sends no device commands, leaves it): the
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

## After build 2 (2026-11-20, Patrik's first day with it)

Patrik, after trying build 2 on his iPhone: he loved it, and asked for three changes.

- **Renaming devices.** "can we make the names of things changable so I can name rename things?"
  - *Where the name lives: in flatd*, not in the app (flatd contract v1.3, `PATCH /api/devices/{id}` with
    `{"label": …}`; flatd 1.3 keeps the own name in its database over the config's). So the app, its Shortcuts and
    Control Center controls, the 3D page, the desktop viewer and Claude all read one name. A name kept in the app
    would have been a second truth that Shortcuts, the controls and Claude never see.
  - *The rules are flatd's*: trimmed, 1 to 40 characters, no control characters or line breaks; an empty name (or
    the config's own) brings the config's name back. Every device reports that config name as `default_label`.
    The field applies the same rules while typing (`DeviceNames`), so flatd refuses nothing the field let through.
  - *Every client hears it*: flatd sends `{"type": "device", "device": Device, "source": …}` and the next snapshot
    carries the name. The app takes the name from it (`FlatStore.apply`, `Device.named(like:)`; the state stays the
    state events'), keeps it for Shortcuts' choices (`FlatdConnection.remember`), asks Control Center to read again
    when a blind's name changed (its control shows the name), and passes the event on to the 3D page as flatd sent
    it, `source` included (BRIDGE.md: a page ignores what it does not know). The names kept for Shortcuts and the
    controls carry a version: the stream's names always replace them, while a list a picker or a control read
    (`GET /api/devices`) is kept only if nothing was kept since that reading began, so an older list never brings
    back a name from before a rename. The Blind control's gallery preview shows the chosen blind's name as kept for
    the paired flat now, else "Blind" (never the name stored in the control's configuration, which may be a
    forgotten flat's).
  - *The look* (Claude): a long press on a device's row (on a blind: on its words and buttons, not on the window,
    which a slow drag would otherwise turn into a long press) offers **Rename** and, once renamed, **Original name**
    with flatd's name under it. Rename turns the name into a field where it stands, as Arestemis's and Aresium's names
    do: the name's own font, in a well reaching into the margin, the name selected, the clear button, **Cancel**
    beside it; Return or scrolling away saves what was edited. A field left as it opened sends nothing, so a rename
    made elsewhere meanwhile stands and a config name longer than 40 characters is never cut. An empty field shows
    flatd's name in grey. No autocorrection (names are names). The new name shows in muted ink until flatd confirmed
    it, never as done before; Rename (and Original name, and VoiceOver's action) wait until flatd answered the
    request, even when the stream confirmed the name first, so a second name is never dropped unseen.
  - *An older flatd* (before v1.3) answers 405: the line at the bottom says "This flat service can't rename yet.
    Update flatd, then try again." and the name stays.
- **No Automations card.** "why are there these text boxes for automations at the bottom? I dont think we need
  them." The card at the end of Home is gone (`AutomationsCard`, `Model/Automations.swift`, its strings, its test and
  `-scrollTo automations`). The modes and scenes stay as the three tiles at the top. His earlier wish for "an overview
  of functions and automations" is met by those tiles and the sections; the card only explained, in sentences, what
  the tiles, the NFC tag and Control Center do. He asked for it, so it needs no further sign-off.
- **Lighting.** "put the lamp under 'Lighting' in Arestia" (relayed by the lead, 2026-11-20). Lights (`kind` light)
  get their own section, **Lighting** / **Licht**, after Fans and before Blinds: a card with each light's name, its
  state and on/off, renamed the same way. Plugs and kinds a newer flatd brings stay under More.

Codex's review of the renaming (gpt-6.2-astra, 2026-11-20, NOT SAFE, eight findings) and its fixes, all with tests:
an untouched field saved the name it opened with (finding 1); a confirming event re-enabled Rename while the request
was still out (2); an older device list could overwrite a rename in the names kept for Shortcuts and the controls (3);
in flatd 1.3, a rename cancelled during its database write never reached memory or the clients (4); the Blind
control's preview named a forgotten flat's blind (5); a long paste was cut in quadratic time on the main thread (6);
flatd compared a name in NFC with the config's raw spelling (7); the `source` of a `device` event was dropped on its
way to the 3D page (8).

## Follow-ups

From the renaming (2026-11-20):

- [ ] The real 3D page shows its own translated names for the devices it knows, never flatd's, so a rename does
  not show there yet. Suggested for the viewer (its bridge contract first): use the snapshot's `label` when it
  differs from `default_label` (an own name), else its own translated name, and take `{"type": "device"}` messages,
  which the app already forwards. The fake's stand-in page does this.
- [ ] The desktop viewer takes names from `GET /api/devices` and each snapshot, so it shows a rename after its next
  connect; handling the `device` event would make it live.
- [ ] Claude reads names through the MCP tools' `list_devices`; there is no rename tool yet (Patrik renames in the
  app). Add `rename_device(id, label)` if he wants Claude to rename too.
- [ ] Deploy flatd 1.3 before an Arestia build with renaming reaches the phone (the build works with 1.2, but Rename
  then only says flatd can't rename yet).

Left from the final reviews (rounds 8 and 9, Codex gpt-6.2-astra, 2026-11-20; none blocking):

- [ ] On Patrik's iPhone, the first run against the real flatd: pairing with `flatd pair`'s code, Cooking on and off
  (the NFC tag's Shortcut too), the fans with a timer, a blind dragged and stopped, the 3D tab, the Cooking, Fans and
  Blind controls in Control Center, Forget this flat and pairing again.
- [ ] A blind sent down from the 3D page while flatd is being found (reconnecting), then stopped on Home: the
  movement still goes out before Stop (the order is right, but the blind starts briefly). Give the page's blind
  commands the same per-blind newest number as Home's, check it after `readyClient()`, answer a skipped page request
  `.notPossible`.
- [ ] Two Cooking starts at once (Home and a Shortcut): the earlier one's successful answer, arriving last, can clear
  the later one's failure note. Clear only the trouble that was saved when the command was sent (its id, under the
  lock).
- [ ] Tests: a coordinator test that the page gets exactly one result per `reqId` for its own document (also across a
  reload that reuses ids while a command is in line); a two-process test of the dispatch lock on the App Group's real
  path, with a lock-acquired signal instead of timing.
- [ ] Tests: about twenty store and review tests (rounds 5 to 7) race a short `Task.sleep` against a delayed fake
  answer. A busy GitHub runner broke three of them on 2026-11-20 (the lock test, the live TLS suite's first request,
  the Forget test; each fixed since). Make the rest wait for a step they can see (a request seen, a latch) instead.

## iPhone features (IPHONE-APPS.md checklist)

- Control Center controls: yes (above). Siri and Shortcuts: yes, also the way to NFC tags.
- Home and lock screen widgets: not yet (Patrik, 2026-11-19).
- Live Activities: a good fit later (cooking on the lock screen with Done cooking); not built.
- Share sheet, Spotlight, Maps, Calendar, Face ID, on-device AI: none fit. The camera only reads flatd's QR code.

## Not in this repo

flatd (its code and contract), the flat's model and the viewer stay private, in Patrik's own folders. The fake flatd
here has made-up devices only (Fan 1, Fan 2, Desk lamp, Blind 1, Blind 2, Plug 1) and a stand-in page at `/viewer` that speaks the
same bridge.
