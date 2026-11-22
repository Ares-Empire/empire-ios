# Aresus (iPhone)

The owner's own servers and machines at a glance, its widget, the board's For you tab and the Aresync tab (files from the iPhone to the MacBook). Decisions: `ares-empire/docs/ARESUS-APP.md`, `ares-empire/docs/ARESYNC-DROP.md`. Rules for every app: `CLAUDE.md`. Owner decisions are tagged "(owner, date)"; when one changes, change its line (git keeps the old one).

## Decisions and rules in force

- Aresus and Aresync stay the owner's own tools and never go to others (owner, 2026-10-25).
- "For you" shows only the asks put to the owner, and every card has a free-text field (owner, 2026-11-07).
- Blocking asks are marked in the accent colour, not in the issue red.
- An answer is sent only when the undo bar ends: the server cannot take one back.
- Drops are never resent blind: the server's list is checked first.
- The widget never logs in: it only reads the token (readable only while the phone is unlocked) and deletes its saved
  status on logout.

## Open

- Aresync drops, step 2: receipts filed into Rechnungen with their inventory line
  (`ares-empire/docs/ARESYNC-DROP.md`).
- On the phone: the Aresus widget on the home and lock screen (refreshes by itself; the medium one's rows open their
  province).

## As built

### Aresus app

**Aresus app** (2026-10-24, `Aresus/`): two tabs, Aresus (summary, server card, province boxes, province page) and
Aresync (machines, runs by day, run sheet), on the Aresus API (`aresus/docs/API.md`, samples in
`Aresus/Aresus/Samples/` = copies of `aresus/docs/samples/`). Data in `Model/` + `API/`, look in `Screens/` (Shared/Design).
Links `aresus://province/<slug>`, `aresus://sync/run/<id>`, `aresus://server` go through `AresusNavigation.open(_:)`
(notification taps too). Launch arguments (DEBUG): `-sampleData` (`-sampleAllGood`,
`-sampleEmpty`), `-tab aresus|aresync`, `-openProvince <slug>`, `-openRun <id>`, `-scrollToEnd`, and `-sampleLoading` for the loading screen (the login screens: the
shared `-sampleLogin` and friends, "Accounts in every app"). Sample mode runs its clock from the samples' moment, so times read as live.

### Widget

**Widget** (`AresusWidgetExtension`, kind `AresusStatus`, `de.ares-empire.aresus.widget`; small, medium, lock-screen
rectangular and circular): "All running" or the issues, with the check's live age. Its timeline provider reads the
shared Empire token (never logs in), fetches `GET /overview` every 15 min and saves a `WidgetStatus` in the App Group
(`aresus-widget-status.json`); the app saves it after every overview and deletes it on logout. Offline, or with the
Keychain locked (the token is readable only while the phone is unlocked), it shows the saved status; after an hour it
loses its status colour. `Aresus/AresusShared/` is compiled into app and widget (overview types, API client core,
widget status, store, loader, views). DEBUG `-widgetGallery good|issues|loggedout` shows the views for screenshots.
`AresusUITests` (UI tests, in the scheme): Settings → Language switched both ways with the real taps, about a minute.

### For you

**For you** / "Für dich" (brief 234, build 9, 2026-11-06; the board, `aresus/docs/API.md` → Board, plan
`ares-empire/docs/reviews/2026-11-05-work-board.md`): the third tab, `tray`, badge = open asks. Only the asks Claude
sessions put to the owner (`board ask` in aresync); work for sessions never shows, only the line "N open items have no
session". A card: the question, why, "topic · age · due …" (the due day in the issue red once reached), the answers
(up to three side by side when they fit, the first `FormButtonStyle` primary, the others its `secondary` kind,
outlined; an action has Done / Erledigt), a field for his own words on every card ("Or answer in your own words" /
"Oder in eigenen Worten antworten", up to five lines, the send arrow once something is typed; the owner 2026-11-07: "each
question should have a way for me to enter free text"; it replaced "Own answer…" and its sheet; build 11,
2026-11-07), then one quiet line
Not needed / Ask in Claude ("Claude fragen", `https://claude.ai/code/<session>` through iOS's `openURL`); long press:
Not needed, Ask in Claude. A typed answer stays in its field until the ask leaves the server's list, so Undo brings
the card back with it. **Blocking asks** (`BoardItem.blocking`, `board ask --blocking`: the session cannot go on
without the answer; the server lists them first and pushes "Claude is waiting for you"): "CLAUDE IS WAITING" /
"CLAUDE WARTET" with an hourglass above the question, small caps in the accent, not the issue red. Answered
in one card below. **An answer waits for the undo bar** (the server cannot take one back): `BoardStore.perform`
hides the card and offers Undo (`UndoOffer(message:onDismiss:undoImmediately:)`); it is sent when the bar times
out, when another answer replaces it, when the tab is left or the app leaves the foreground; a failed send puts the
card back with "Not sent. Try again."; 409 refreshes ("Already answered elsewhere."), 404 drops it.
`aresus://board` opens the tab (the daily board push). DEBUG `-tab board`, `-sampleBoardEmpty`,
`-sampleBoardManyAsks`, `-boardOwnWords <text>` (fills the first ask's field), `-sampleBoardFailed`. Tests: `BoardTests`.

### Aresync drops

**Aresync drops** (briefs 88–94 and 100, plan `ares-empire/docs/ARESYNC-DROP.md`): files and photos from the iPhone to a
folder on the MacBook through the aresus server (`aresus/docs/API.md` → Drops; encrypted there with `age`, fetched by
the Mac's `com.aresync.drop` agent, which needs Full Disk Access for `/usr/bin/python3`). The drop code lives in
`Aresus/AresusDrops/` (models, `DropsStore`, `DropOutbox`, the API calls, `SendSheet`, `FolderPicker`), compiled into
the app and **`AresusShareExtension`** (`Aresus/AresusShare/`, `de.ares-empire.aresus.share`: Aresus in the share sheet
for photos, videos and files, up to 20, showing the send sheet itself, since an extension cannot open its app; it
follows the app's language and appearance through the App Groups). The queue, recent folders and the last folder list
live in Aresus's own App Group `group.de.ares-empire.aresus` (`DropContainer`); the bytes go up in a background
`URLSession` (one per share, `DropBackgroundUploads`; `AresusAppDelegate` reconnects it when iOS wakes the app), so an
upload goes on after the share sheet closes. The Aresync tab: the send button, the newest three drops and Show all,
each row deleted with the shared Mail-like swipe (`Shared/Design/RowSwipe.swift`, `DELETE` in any state). The picker:
every folder opens, New folder under Choose (one new folder per send; the Mac makes it on arrival). Files dropped on
either tab open the send sheet (`Shared/ProviderFiles.swift`, `ProviderDropTarget`, shared with Aresium's file drop).
Shared pictures keep a name a person chose; a camera's or the system's name becomes the capture time
(`DropNames.isCameraName`). DEBUG: `-tab aresync`, `-openSheet send`, `-samplePick photo|photos|file|files|mixed`,
`-sampleDropHover <count|name>`, `-sampleShareExtension`, `-sampleShareState loading|loggedOut|unreadable`.

### Never resend blind

**Never resend blind** (brief 238, 2026-11-07: a receipt PDF landed on the Mac on 2026-11-05, the phone lost the
upload's 200, sent the bytes again the next day, got `409` and showed the landed file as "Not sent" with Retry):
before the bytes of a record that already has a server id go again (a retry, a launch, Retry, a deferred retry), and
after any `409` on the upload, `DropOutbox.reconcile` asks `GET /drops` once: `waiting`/`failed`/`landed` discards the
phone's copy (`onUploaded`), `cancelled` discards it, `uploading` sends; a failed check never sends. A row missing
from the list proves nothing (the list is bounded), but the upload's own `404` does: the server has no such drop (its
`uploading` row is deleted after 24 hours, a landed one stays 30 days), so `finished` forgets the server id and sends
the file again as a new drop, at most twice per record (`restarts`, `DropOutbox.maximumRestarts`), then it fails as
before; Retry starts the count again, and a record being removed is never sent again (2026-11-08: three photos whose
first upload had failed were stuck with 404 once their rows expired; fixed 2026-11-09, Aresus build 12). At launch and on
coming to the foreground `reconnect()` checks every idle record with a server id in the same one request, but only
removes those the server has: a record that failed for good (413, 507) or waits for its retry stays as it was. A
server row past `uploading` always shows the server's line, never the phone's copy (`DropRow.hidden(for:in:)`).
