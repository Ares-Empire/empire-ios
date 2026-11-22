# The Empire app (iPhone)

The phone hub: the ring of provinces, approvals, What's new. Decisions: `ares-empire/docs/EMPIRE-APP.md`. Rules for every app: `CLAUDE.md`. Owner decisions are tagged "(owner, date)"; when one changes, change its line (git keeps the old one).

## Decisions and rules in force

- The ring shows the apps the account has; members get a "+" card to ask for others; no adding or removing
  (owner, 2026-10-25).
- Tap the front province to open it, hold for its page; the name is the link (owner, 2026-10-24).
- No push to the owner: sign-ups and access requests arrive by email and are decided in the approvals sheet; members
  are told "<App> is ready" by a notification (owner, 2026-10-26).
- Opening offline (the last hub kept on the phone): not now, later (owner, 2026-10-26).
- No URL schemes are declared and there is no `LSApplicationQueriesSchemes`; links come only in the payload.
- Screens copy values from the approved hub CSS and name the CSS selector in comments.

## Open

- On the phone: the "<App> is ready" push for a member's account, its tap showing the ring.

## As built

### Empire app

**Empire app** (2026-10-24): the approved phone hub (`ares-empire/web/app/mobile.jsx` + `mobile.css`) in SwiftUI,
`Empire/Empire/Screens/` (Claude's look; values copied from the CSS, with the CSS selector named in comments), data
in `Model/` + `API/` (brief 08). Launch arguments (DEBUG): `-sampleData` (admin sample), `-sampleUser` (member
sample), `-sampleCatalog` (a member made up from the admin sample's provinces: Arestemis in the ring with an install
link; in "+" Aresolus to ask for, Aresync asked for, Aresium coming soon), `-samplePush` (push routing in sample
mode, for `simctl push` with `Empire/PushSamples/app-ready.apns`; the sample never signs in, so nothing registers), `-openSheet province|unopened|idea|add|approvals|support` (`add`:
the "+" sheet), `-tapProvince <slug>` (the ring tap at launch), `-scrollToEnd` for screenshots. Screenshots of the
new states: `-sampleData -sampleCatalog -openSheet add` (the "+" sheet), `-sampleData -sampleCatalog -openSheet
unopened` (the page with Install). **Whose ring shows what** (owner, 2026-10-25, `ares-empire/docs/EMPIRE-APP.md`):
the ring is `projects`, every app the account has (owner: every province); members get a "+" card ("More apps") at
the end, whose sheet lists `addable`, the other apps open to users, each with its state on the right: Ask for access
(a quiet gold button; `POST /api/empire/request`, whose answer is the new hub data, so the row then says "Asked ·
waiting for approval"; a refusal shows the hub's sentence), or Coming soon (not requestable). There is no adding or
removing any more (the old `POST /api/empire/ring` is gone from the app); leaving an app is Settings → Leave. Each
province's `access` (`granted` | `requested` | `none`) and `install` (its TestFlight or App Store link, only for apps
the account has) are read leniently: a hub without them, or an unknown value, counts as granted in the ring and not
asked for in "+" (`EmpireData.init(from:)`), no install link. Ring: tap the front province to open it (its app if
installed, else its website, else its page with "The … app isn't on this iPhone" and, when the hub sends an https
install link, **Install**), hold any tab for its page; on the page the name is the link (owner, 2026-10-24).

### Notification

**Notification** (2026-10-25): a member whose request the owner approved gets "<App> is ready" (`url` `empire://ring`,
thread `access`, no actions); tapping it closes any sheet and asks the hub again, so the new app is in the ring
(`EmpireLink`, `EmpireNavigation`, which `ContentView` owns so a tap works before the hub has loaded; `onChange(…,
initial: true)` so a tap that launched the app is not missed). The app declares no URL scheme: links come only in
the payload. No push to the owner: his sign-ups and access requests come by email and he decides in the approvals sheet
(owner, 2026-10-26). `ProvinceOpener` tries the app's URL and uses iOS's answer, so no
scheme is declared anywhere (no `LSApplicationQueriesSchemes`; a new province app needs no change here). Province marks load from the hub with the
Bearer token, so the samples show monograms. Approvals list new sign-ups and approved accounts asking for more apps
(`PendingAccount.requested`/`approved`), each with the apps asked for and "Email not confirmed yet" while `verified`
is false; approving sends the apps the card shows (`requested`), and the hub's answer carries the list and the count
(`DecisionAnswer`; an older hub's `{"ok": true}` makes the app ask for both). A failed decision asks for the list
again. `pending` is null when the hub could not count (no badge). A hub answer that does not decode is logged by its
key path (`log show --predicate 'subsystem == "de.ares-empire.shared" && category == "decoding"'`).
