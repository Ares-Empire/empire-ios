# 129: Arestemis app: sites that only ship or only hand over, and the OpenStreetMap credit

Status: merged 2026-11-02 (Arestemis app tests pass; built by a Claude agent). Uploaded as Arestemis build 8.
Branch: `claude/129-arestemis-delivery-sites` · Worktree: `../empire-ios-129-arestemis-delivery` · **For a Claude
agent** (screens and their small data part)

## Goal

The server now offers more thing sites, and two of them do not fit every search (Arestemis briefs 126, 128):

- **IKEA Preowned** is pickup only (private sellers, collected near the hunt's towns).
- **Vinted** and **mydealz** only ship.

`GET /kinds` says this per site: `delivery: "both" | "pickup" | "shipping"` (absent = both). The server refuses a
search that picks a site its delivery choice cannot use ("IKEA Preowned is pickup only." / "Vinted only ships.", in
German "IKEA Preowned gibt es nur zur Abholung." / "Vinted gibt es nur mit Versand."). After this brief the thing form
**shows that before Save**: a site that cannot serve the chosen delivery is greyed with one line saying why, so a
search never fails on it. And the server now looks up the hunt's towns on OpenStreetMap (Nominatim) for coordinates,
so the app credits OpenStreetMap under Settings → About → Fonts & licences.

## Read first

- `AGENTS.md`, `CLAUDE.md` (design rules, Languages, the Arestemis app entry, Settings)
- The contract: `~/Arestemis/docs/API.md` → "Available kinds and sites" (`delivery`), the item listing (`ItemDetails`),
  and the samples `~/Arestemis/docs/samples/kinds.json`, `overview.json`, `matches.json` (IKEA Preowned and Vinted
  matches are in them after brief 128)
- `Arestemis/Arestemis/Model/Sites.swift` (`KindSource`, `SiteChoices`: `canSwitch`, `notReadyLine`),
  `Screens/ItemSearchScreen.swift` (the sites under Portals, the delivery choice), `Model/ItemSearchDraft.swift`,
  `Model/ItemFormatting.swift`, `ArestemisTests/ServerSamplesTests.swift`
- Aresium's OpenStreetMap credit as the model: `Aresium/Aresium/Model/ShopListLicence.swift` (`localPlaces()`) and its
  bundled text file; `Shared/Settings/SettingsInfo.swift` (`BundledLicence`), `SettingsApp.licences`

## Build

1. **Data:** `KindSource.delivery` (`both`, `pickup`, `shipping`), decoded leniently (absent or unknown = both).
   `SiteChoices` learns the form's delivery: a site whose delivery cannot serve it cannot be switched on, and one line
   under the sites says why, in the server's words ("IKEA Preowned is pickup only.", "Vinted and mydealz only ship.",
   German as above; with the not-set-up line when both apply: your call how the two lines read together, short).
2. **Changing the delivery** while such a site is on: switch it off at once (the server would refuse the search) and
   let the line explain it; switching back does not turn it on again by itself. Tested both ways, also for a search
   that is edited (its saved sites).
3. **The look** follows the existing greyed site (brief 119's not-set-up chip): same grey, same line style, no new
   decoration. Check the form in English and German, light and dark, with delivery pickup, shipping and either.
4. **Fonts & licences:** Arestemis gains an OpenStreetMap entry like Aresium's `localPlaces()`: "© OpenStreetMap
   contributors", purpose "Town locations for thing searches" / "Ortslagen für Suchen nach Dingen" (or shorter if it
   wraps), ODbL 1.0, with the copyright and licence links; a short bundled text file (copy Aresium's, without the
   download link: the app ships no OpenStreetMap data, the server only looks up town coordinates).
5. **Listings from the new sites:** look at an IKEA Preowned match (pickup, a distance, "VB" with no amount for
   "Preis vorschlagen") and a Vinted match (shipping, the buyer-protection fee among the facts, brand and size) on the
   row and the page in both languages; fix only what reads wrong (the server's facts arrive in German; that is fine).
6. **Samples:** copy the server's current samples into `ArestemisTests/ServerSamples/` again and into the app's sample
   data where the sites and matches come from; `ServerSamplesTests` decodes `delivery` and the new matches.
7. **Words:** English in code; `scripts/strings.py sync` (undo its changes to other apps' catalogs; restore
   `"Could not load older listings."` if it drops it), German with `fill`, `check` at 0 problems.
8. **Tests:** the delivery rule in `SiteChoices` (each delivery against each site kind, greyed and switched off, the
   line in both languages), decoding `delivery` (absent, unknown), the licence entry.

## Check before you report

- `xcodebuild test -scheme Arestemis` on your own simulator (`claude-129`); screenshots `build/129-*.png`: the thing
  form with delivery shipping (IKEA greyed, the line) and pickup (Vinted and mydealz greyed), English and German, light
  and dark; the Fonts & licences page; an IKEA and a Vinted match row and page. Look at each yourself.

## Settled: do not re-open

- Sites and their names come from the server; the app never invents a site's delivery (absent = both).
- A site that cannot serve the chosen delivery is greyed and switched off, never left on for the server to refuse.

## Out of scope

- The server, TestFlight (Claude), any new screen.

## Final message

Files changed; build and test summary lines; screenshots; strings added (English and German); anything doubtful.
