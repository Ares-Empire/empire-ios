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
   own text (the Arestemis repo, `docs/briefs/62-arestemis-application-notes.md`, Codex, server field `application_notes`).
3. **The flicker** with a small black corner when Settings opens or closes (brief 61).
4. **More portals** (the Arestemis repo, `docs/briefs/63-arestemis-more-portals.md`, Codex, server): ImmoScout24
   support and broader Immowelt coverage. The server change goes live only after build 3 is on the phone, since
   build 2 does not know the new portal. Site access is handled by the server.

**Build 0.1 (3)** (uploaded 2026-10-31 21:40, commit cd602f5) carries round 3's app side: "Suche läuft", Settings →
Application as rows (brief 61; the Arestemis repo, `docs/briefs/62-arestemis-application-notes.md` live on the server since 20:51), settings loaded with the home screen so the sheet
opens complete (the brief-61 agent could not reproduce the black corner on iOS 27.0; the "Loading settings…" swap was the
visible jump it found), and ImmoScout24 known to the app. A server listing-reader fix went live at 21:32
(the Arestemis repo, `docs/briefs/66-arestemis-kleinanzeigen-cards.md`).
**More portals** (the Arestemis repo, `docs/briefs/63-arestemis-more-portals.md`) waits on branch `codex/63-more-portals` until build 3 is on
the phone; then merge, deploy, tell the Aresus session (it adds an ImmoScout24 check), and Patrik turns ImmoScout24 on in
Suche → Portale.

## Round 4 (build 3, 2026-11-01 night)

Build 3 installed. **Server portal support live** (the Arestemis repo, `docs/briefs/63-arestemis-more-portals.md`,
Arestemis 3c20edd, 00:36); the Aresus session was told. ImmoScout24 scans once Patrik turns it on in the search's portals.

1. **The black corner is still there**, now "very frequently", in the "Suche läuft" card on the Hunt tab (Patrik: "The
   black field goes black in the corner. It needs fixing."). His hunt is active all the time since build 3, so the
   card's status dot pulses all the time; the card is a glass card (material, shadow) inside a scroll view faded by a
   mask. Brief 67 (Claude agent) finds the cause and fixes it without changing the look; build 4 carries it.
2. **Tabs renamed in German**: "Jagd" → "Suche", and the search's own tab "Suche" → "Filter" (its slider icon; places,
   portals, rent). English stays Hunt / Search. Done by Claude (0e89d13).

**Build 0.1 (4)** (uploaded 2026-11-01, commit 1009513): the black corner (brief 67: the glass card's blur was drawn
offscreen inside its shadow and the scroll fade's mask, and the pulsing dot redrew the corner through both every frame;
now the blur draws straight onto the screen, the look unchanged; the simulator never showed it, so this build is the
test) and the German tabs Suche / Angebote / Filter. Server since build 3: portal support live (the Arestemis repo,
`docs/briefs/63-arestemis-more-portals.md`) and site access improved (Arestemis 5f3ead4; found by the Aresus session).
Evidence and before/after shots:
`build/67/` (local, not in git).
Patrik on build 4 (2026-11-01): "very nice, much better". The search's portals are enabled and working.

## Round 5 (build 4, 2026-11-01 evening)

Patrik: "I still get the black corner on my phone. I can even force it by reloading the screen." His screenshot (Hunt
tab, dark, hunt running) shows a sharp greenish-black rectangle over the card's top left, reaching past the card to the
screen's edge. Its edges are the pulse ring's shadow to the point, and it is drawn after the card's fill and before the
dot and the edge line: `GlassCard`'s `.shadow` gave every piece of the card's content a pathless shadow, and the pulsing
ring's was redrawn offscreen every frame. Brief 67 had blamed the blur, so build 4 did not fix it.

**Build 0.1 (5)** (uploaded 2026-11-01, commit 48b1d92; brief 87): the glass card draws no pathless shadow any more (a
still image inside the card, shape-style shadows outside, none on the content). Per pulse frame on the simulator: about
45 shadow, mask and group passes before, none after. All five apps' screens compared before and after: dark unchanged,
light within 4 levels except that chips and buttons inside cards lose a faint halo. Before/after shots: `build/87/`
(local).
