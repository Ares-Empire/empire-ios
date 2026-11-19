# Arestia app — decision record

**Decided 2026-11-19 (Patrik).** Status (2026-11-19): built and tested on the simulator against a fake flatd
(`scripts/fake-flatd.py`); not yet run against the real flatd, not on TestFlight. The name: Arestia (Ares + Hestia,
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
- **Connecting once:** flatd advertises itself over Bonjour (`_flatd._tcp`), so the app finds it without an address;
  Patrik pastes the key, or scans a QR code (`arestia://connect?url=…&token=…`, also opened by the iPhone's camera; an
  address with `?token=`, JSON or the key alone work too, `PairingCode`). The app checks it with flatd before keeping
  it. The key lives in Arestia's own Keychain group, shared with its Control Center extension and readable after the
  first unlock, so a control works from the lock screen (never synced, never restored to another device); the address
  and the Bonjour name in Arestia's own App Group. When the Mac's address changes, the app and the controls find flatd
  again under its Bonjour name. Plain HTTP is allowed for local addresses only (`NSAllowsLocalNetworking`).
- **The key goes only to an address that answers like flatd** (`GET /api/health` without the key first), and a new
  address is kept only after flatd worked there. Plain HTTP cannot prove who answers, so on another Wi-Fi a device
  pretending to be flatd at the saved address could still read the key (an independent review, 2026-11-19). Closing
  that needs flatd to prove it knows the key before the app sends it (for example `/api/health?challenge=<nonce>`
  answering with an HMAC of the nonce under the key): a contract change for the integration step.
- **Two tabs and the gear** ("not many buttons and big menu"): **Home** (what the flat is doing in one line; cooking
  while it runs, with Done cooking as the one big button; otherwise the modes and scenes as three tiles; the fans with
  on/off and the timers 15 min / 30 min / 1 h / ∞ and the time left; the blinds with their window drawn at its position,
  dragged to set it, up / favourite / down and stop while moving; then the automations, what runs by itself), and
  **Flat**, the 3D model full-bleed. Settings: the flat service (state, connect again, disconnect), then the shared
  sections.
- **Live state** from flatd's event stream (`/api/events?token=…`): the snapshot, then every change whoever made it (the
  app, Claude, a wall switch, a timer). It reconnects by itself with growing pauses and pings every 20 s, so a sleeping
  Mac is noticed. Not reachable: the last state stays, marked "Last seen 18:40", and one calm card when there is no
  state at all ("The Mac may be asleep, or you're not at home"); no alerts. Nothing is shown as done before flatd
  confirmed it, except a blind's target while a finger drags it.
- **Cooking** is flatd's mode `cooking` (which devices it moves and how is flatd's own config: on, the fans and one
  blind up; off, the fans off and that blind to its favourite spot). The app shows it while active with since when and
  what its devices do right now, and Done cooking ends it, with Undo for a few seconds. A device that did not follow is named
  ("Didn't answer: …"); the mode stays as flatd recorded it.
- **The 3D tab** loads flatd's phone viewer into a web view and speaks its bridge (the viewer's `BRIDGE.md` v1: the
  handler `flat3d`, `flat3d.receive`, one result per request): taps in 3D go to flatd through the app, live state goes
  back to the page. The page never touches the network.
- **Shortcuts, Siri and NFC** (App Intents, `ArestiaShared/ArestiaIntents.swift`): Start cooking, End cooking, Fans on
  (minutes and fan optional), Fans off, Move a blind (which, and up / down / favourite / stop, from flatd's list), Air
  out, All blinds down. Patrik's NFC tag is a personal automation in Shortcuts that runs Start cooking. They run without
  opening the app.
- **Control Center** (`ArestiaControls`, iOS 18 `ControlWidget`): Cooking and Fans as toggles, and a Blind control per
  blind (chosen when it is added; up when on, down when off). Home-screen widgets: not yet (Patrik).
- **Look:** the province apps' wall and glass cards, with **hearth ember** as the one accent (`AppAccent.arestia`:
  `#FF9A62` dark, `#A8481A` light, 4.98:1 on the light wall), used only for what is on or the one thing to press. The
  mark is a drawn flame (marble with an ember core) until there is a Hestia bust, as the other apps have.

## iPhone features (IPHONE-APPS.md checklist)

- Control Center controls: yes (above). Siri and Shortcuts: yes, also the way to NFC tags.
- Home and lock screen widgets: not yet (Patrik, 2026-11-19).
- Live Activities: a good fit later (cooking on the lock screen with Done cooking); not built.
- Share sheet, Spotlight, Maps, Calendar, Face ID, on-device AI: none fit. The camera only reads flatd's QR code.

## Not in this repo

flatd (its code and contract), the flat's model and the viewer stay private, in Patrik's own folders. The fake flatd
here has made-up devices only (Fan 1, Fan 2, Blind 1, Blind 2, Lamp 1) and a stand-in page at `/viewer` that speaks the
same bridge.
