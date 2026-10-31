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

Both rounds go to the phone with the next Arestemis build, together with the rest of Patrik's notes.
