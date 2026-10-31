# Arestemis on Patrik's iPhone (build 0.1 (1), 2026-10-31)

Patrik installed Arestemis from TestFlight on 2026-10-31 ("very nice work") and started fine-tuning. Push works: the phone
registered a production device on 2026-10-30 23:34, and Claude's test notification went through APNs on 2026-10-31.

## Round 1 (2026-10-31)

1. **The login's line "One Ares account for all Ares apps" goes.** It sat under the app's name on the shared login
   (`AresLogin`, `Shared/Design/ProvinceLogin.swift`), so it goes in Arestemis, Aresus, Arestoteles and the Empire app
   alike; the fields keep the same distance below the name. The no-access line stays. Create account's first sentence
   and Aresium's Sign in note still say it (not asked).
2. **"Jagd starten" → "Suche starten"** (the Hunt card's button; English stays "Start hunting").
3. **No "Die KI …".** Small things do not name the AI at all; the autofill says it in a few words; the important places
   name it without "die" (Patrik: "Die KI" sounds weird).

   | Where | Before | Now (German · English) |
   |---|---|---|
   | Search → Extras | Die KI prüft jedes Angebot darauf. | Jedes Angebot wird darauf geprüft. · Every listing is checked against it. |
   | Describe it | Die KI füllt daraus die Felder. … | KI füllt die Felder aus. … (round 2: without KI) |
   | Listings → Filtered out | … aber nicht durch die Prüfung der KI kamen. | … aber nicht durch die Prüfung kamen. · … but not the check … |
   | Settings → AI per listing | Die KI schreibt für jedes Angebot … | Jedes Angebot bekommt einen eigenen deutschen Text, … · Each listing gets its own German text, … |
   | Settings → About you | Angaben, die die KI verwenden darf; andere erfindet sie nie. | Nur diese Angaben werden verwendet, erfunden wird nichts. · Only these facts are used, nothing is made up. |
   | Application sheet | Von der KI geschrieben | Mit KI geschrieben (English stays "Written by AI") |
   | Server: a match not checked | Nicht von der KI geprüft | Nur nach den Feldern geprüft (English key unchanged) |
   | Server: AI down | Die KI ist nicht erreichbar, … | KI nicht erreichbar, … (round 2: without KI) |

   The segment "KI pro Angebot" stays. Checked on the simulator in both languages and looks; Arestemis tests pass,
   Aresus, Arestoteles and Empire build, `strings.py check` 0 problems; server 506 tests.

## Round 2 (2026-10-31)

1. **The test notification arrived**, so Arestemis's **Telegram copy is off** (the `TELEGRAM_*` lines in
   `/root/Arestemis/.env` commented out, the service restarted; its start line says `telegram_fallback: off`).
2. **No sentence names the AI** (Patrik: "Let's cut KI from all sentences, I think it sounds better. Like automatic fill
   in"). Describe it: "Die Felder werden automatisch ausgefüllt. Prüf sie, dann speichern." · "The fields are filled in
   automatically. Check them, then save." Server: "Only checked against the fields" (German unchanged) and "Not available
   right now, try again in a minute." · "Gerade nicht verfügbar, versuch es in einer Minute noch einmal." The two short
   labels went too (Patrik: "Yes let's remove them too"): the switch in Settings → Application is "Dein Text | Pro
   Angebot" · "Your text | Per listing", and above an application "Automatisch geschrieben" · "Written automatically".
   Arestemis now shows no "KI"/"AI" anywhere.

**Build 0.1 (2)** (uploaded 2026-10-31 19:46 with `scripts/testflight.sh Arestemis`, commit e7cccc7) carries both
rounds. Patrik's further notes go into build 3.

## Round 3 (build 2, 2026-10-31 evening)

1. **"Jagd läuft" → "Suche läuft"**, and the hunt's other sentences say "Suche" like its start button ("Die Suche konnte
   nicht gestartet werden", "Die Suche beginnt pausiert …", "Die Suche endet …"). The tab keeps the name "Jagd" (the
   tab next to it is "Suche"). Done by Claude (fc7807a).
2. **Settings → Application, compact** (brief 61, Claude agent): Notifications first, then Application as rows like
   General's: a switch "Automatisch schreiben", a row that opens either "Dein Text" or "Hinweise" (notes every
   automatic text includes), and "Über dich". The automatic text then uses the facts about you and the notes, not the
   own text (brief 62, Codex, server field `application_notes`).
3. **The flicker** with a small black corner when Settings opens or closes (brief 61).
4. **More portals** (brief 63, Codex, server): ImmoScout24, and Immowelt in every town it knows
   instead of only München (`garching-b-muenchen` resolves; some towns, e.g. Freising, Immowelt does not know by
   name). No proxies needed. The server with ImmoScout24 goes live only after build 3 is on the phone, since build 2
   does not know the new portal.

**Build 0.1 (3)** (uploaded 2026-10-31 21:40, commit cd602f5) carries round 3's app side: "Suche läuft", Settings →
Application as rows (briefs 61, 62 live on the server since 20:51), settings loaded with the home screen so the sheet
opens complete (the brief-61 agent could not reproduce the black corner on iOS 27.0; the "Loading settings…" swap was the
visible jump it found), and ImmoScout24 known to the app. **Kleinanzeigen** changed its list layout on 2026-10-31 (no
`aditem` classes): scans found none from about 20:50; brief 66 fixed it, live 21:32 (23 listed per scan again).
**Brief 63** (ImmoScout24 in every town, Immowelt everywhere) waits on branch `codex/63-more-portals` until build 3 is on
the phone; then merge, deploy, tell the Aresus session (it adds an ImmoScout24 check), and Patrik turns ImmoScout24 on in
Suche → Portale.

## Round 4 (build 3, 2026-11-01 night)

Build 3 installed. **Brief 63 live** (Arestemis 3c20edd, 00:36): Garching got its Immowelt page (the first scan seeded 8
Immowelt listings) and its ImmoScout24 place `/de/bayern/muenchen-kreis/garching-bei-muenchen`; the Aresus session was
told. ImmoScout24 scans once Patrik turns it on in the search's portals.

1. **The black corner is still there**, now "very frequently", in the "Suche läuft" card on the Hunt tab (Patrik: "The
   black field goes black in the corner. It needs fixing."). His hunt is active all the time since build 3, so the
   card's status dot pulses all the time; the card is a glass card (material, shadow) inside a scroll view faded by a
   mask. Brief 67 (Claude agent) finds the cause and fixes it without changing the look; build 4 carries it.
2. **Tabs renamed in German**: "Jagd" → "Suche", and the search's own tab "Suche" → "Filter" (its slider icon; places,
   portals, rent). English stays Hunt / Search. Done by Claude (0e89d13).
