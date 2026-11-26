# 341: Arestia: lamp levels and Toggle cooking

Status: running
Branch: `codex/341-lamp-levels` · Worktree: `../empire-ios-341-lamp-levels` · Model: `gpt-6.2-sol`, effort `high`
(a well-scoped app change against a written contract; no new trust or pairing code)

## Goal

Two of the owner's wishes for Arestia:
1. A light whose lamp has stepped brightness levels shows its current level, and the owner can pick a level; the flat
   service then steps the lamp there and confirms it.
2. One Shortcuts action, **Toggle cooking**, that ends cooking when it is on and starts it when it is off, so one NFC
   tag does both (today his automation can only start it).

## Read first

- `AGENTS.md`, `CLAUDE.md`, `docs/apps/Arestia.md` if it exists, and `docs/ARESTIA-APP.md` (the app's notes).
- The flat service's contract v1.6, which this build follows. It lives in a private repo; the parts you need are
  copied under "API" below. Nothing about the owner's flat (device names, rooms, addresses) goes into this repo:
  code, tests and text speak of "lights with levels" in general.
- `Arestia/ArestiaShared/FlatdModels.swift` (`Device`, `DeviceState`), `FlatdClient.swift` (requests, timeouts),
  `FlatActions.swift` (cooking: `setCooking`, the cooking state read), `Arestia/Intents/FlatIntents.swift`
  (`StartCookingIntent`, `EndCookingIntent`, `CookingDialog`), `Arestia/Screens/HomeScreen.swift` (`SwitchCard`,
  `SwitchRow`, the Lighting section), `Arestia/Model/FlatStore.swift` (`isWorking`, `setFan` and its error handling),
  `Arestia/Model/FlatWords.swift` (status lines).

## Build

1. **Model.** `Device` gains optional `levels: [String]?` (absent on most devices and on a flatd before v1.6);
   `DeviceState` gains optional `level: String?`. Decoding stays tolerant: unknown fields ignored, missing ones nil.
   A device "has levels" when `levels` has at least 2 names **and** `controls` contains `"level"`.
2. **Client.** `setLevel(id:level:)` → `POST api/devices/{id}` with `{"level": "<name>"}`, answering the `Device`.
   Its timeout is **40 s** (a level change takes up to ~23 s on the service), not the 12 s `commandTimeout`. A 502
   answer carries `{"error": "..."}`: surface it like the other command errors (the store's existing error path),
   and refresh that device's state from the answer or the event stream (the service has published the real level).
3. **Store.** `setLevel(_ id:, level:)` alongside `setFan`, with its own busy key (`"level:" + id`), so the row can
   show it is working. While busy, the row's power button and picker are disabled.
4. **The row** (`SwitchRow`, only for a device that has levels; every other row unchanged):
   - **Status line:** the level after the on/off text, e.g. "On · Mid". `"unknown"` shows "On · Level unknown";
     while a level change runs: "Setting to High…". Off: as today.
   - **Picker:** under the name/status/power line, full row width, a segmented control with one segment per level,
     in the service's order. Use the app's existing pieces if the shared code has a segmented control; otherwise
     SwiftUI's `Picker` with `.pickerStyle(.segmented)` tinted with the Arestia accent. Selected segment = the current
     level; none selected when off or unknown. Picking a segment calls `setLevel` (also when the light is off: the
     service turns it on). Picking the current level does nothing.
   - **Level names:** `low`, `mid`, `high` are shown as **Low / Mid / High** (German **Niedrig / Mittel / Hoch**);
     any other name is shown as the name with its first letter capitalised.
   - Rename mode (`editor.isEditing`) hides the picker as it hides the power button.
   - VoiceOver: the picker reads "Level, Mid" and its segments their names.
   - Light and dark mode as every screen (`AGENTS.md`).
5. **Toggle cooking.** `ToggleCookingIntent` next to Start/End in `FlatIntents.swift`: title "Toggle cooking",
   description "Ends cooking if it is on, starts it if it is off." It reads the cooking state from the service (the
   same read the Cooking control uses), then calls `setCooking(!active)` and answers with `CookingDialog.text` (so
   "Cooking is on." / "Cooking is off." plus any failure line). If the state read fails, it fails with the usual
   intent error; it never guesses. Register it wherever Start/End cooking are registered (the app's
   `AppShortcutsProvider` if they have phrases there, with a phrase "Toggle cooking in ${applicationName}"; German
   "Kochen umschalten in ${applicationName}").
6. **Strings:** English in code, German in the String Catalogs: "Level unknown" → "Stufe unbekannt",
   "Setting to %@…" → "Stelle auf %@…", "Level" → "Stufe", "Toggle cooking" → "Kochen umschalten",
   "Ends cooking if it is on, starts it if it is off." → "Beendet das Kochen, wenn es läuft, sonst startet es es.".
   List every string you add in your final message.

## Settled: do not re-open

- The level comes only from the service (`state.level`); the app never derives it from watts.
- No level picker in the 3D page in this build (it comes with a later viewer round), no Control Center control for
  levels, no Siri intent for levels.
- The 40 s timeout applies to the level request only.

## Out of scope

- Pairing, trust, transport (`FlatdTransport.swift`, `FlatdPin.swift`, `PairingCode.swift`): don't touch.
- Other apps, `Shared/` beyond using existing pieces, the project file.

## API (flatd contract v1.6, the parts this build uses)

- `Device` may carry `"levels": ["low", "mid", "high"]` (stepping order) and then `"level"` in `controls`.
- `state.level`: one of `levels`, `"unknown"`, or `null` (relay off). Absent on devices without levels.
- `POST /api/devices/{id}` body `{"level": "<name>"}` → 200 with the `Device` (reached, or already there); 400 bad
  body or unknown name; 502 `{"error": "..."}` when the lamp didn't reach the level (the relay stays on, the state
  shows the real level); 504 the device did not answer. Takes up to ~23 s.
- The pulses are not sent as separate events; the command's result is one `state` event.
- Cooking: unchanged (`GET /api/modes`, `POST /api/modes/cooking` with `{"active": bool}`).

## Done when

- `bash scripts/test-unit.sh Arestia` passes, with new tests for: decoding with and without `levels`/`level`; "has
  levels" rule; the status line for each case (level, unknown, setting, off); the 40 s timeout on the level request
  only; a 502 surfaced as an error and the state taken from the service; picking the current level sends nothing;
  `ToggleCookingIntent` calls `setCooking(false)` when active and `setCooking(true)` when not, and fails without a
  change when the state read fails.
- The Home screen on your simulator against a fake service (the tests' fake, or a stub in the preview) shows a light
  with levels in light and dark: screenshots `build/341-lighting-light.png`, `build/341-lighting-dark.png`.

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the strings added, what is missing or
doubtful.
