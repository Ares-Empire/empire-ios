# 72: Arestoteles: the bust without the watermark

Status: running
Branch: `claude/72-arestoteles-bust` in three repos · Worktrees: `~/empire-ios-72-arestoteles-bust`,
`~/Arestoteles-72-bust`, `~/ares-empire-72-bust` · Agent: Claude (design)

## Goal

The Aristotle bust carries a "Magnific" watermark: an AI upscaler stamped its name diagonally across the face, and it
is plainly visible on the Arestoteles app icon, in the app (login, loading screen, the small mark), on arestoteles.de,
and on the ring of the hub and of the Empire iPhone app. Both apps go to Patrik's iPhone through TestFlight right after
this brief. After it, no picture of Aristotle anywhere in the empire carries the watermark, and the Arestoteles icon
sits on the home screen as a sibling of the other Empire app icons.

## Read first

- `AGENTS.md` and `CLAUDE.md` in empire-ios (the rules apply to you, as to Codex; you may commit, see below)
- `~/ares-empire/EMPIRE.md` → the crown language; the design restraint: gold only as an accent, app icons are black
  with the province's bust centred
- `~/Arestoteles/CLAUDE.md` → "The website" (how `web/` is served; nothing loads from another host)

## The files (facts)

All the watermarked pictures are one image (a 709×903 RGBA cut-out) or made from it:

| Repo | File | Used by |
|---|---|---|
| empire-ios | `Arestoteles/Arestoteles/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` | the app icon (1024², black, bust centred) |
| empire-ios | `Arestoteles/Arestoteles/Assets.xcassets/Bust.imageset/bust-aristotle.png` | `ProvinceLogin`/`ProvinceLoading` in `ContentView.swift`, the 38 pt mark in `Screens/Style.swift` (greyscale, contrast raised) |
| Arestoteles | `web/brand/aristotle-bust.png`, `aristotle-bust.webp`, `aristotle-bust-login.webp` | `web/app/brand.jsx`, `ares-shatter.js`, `arestoteles-intro.js`, `index.html` (favicon, apple-touch-icon, preload), `webauth/server.py` (login page) |
| ares-empire | `web/brand/arestoteles.png` (byte-identical to the website's `aristotle-bust.png`), `arestoteles.webp` | the province's `logo` in `web/app/empire-data.js`: the hub's ring and the Empire app's ring load it |

`Arestoteles/assets/bust_source.png` is the original download: the watermark (and a "Creada con IA" label) is already in
it, so there is no clean original of this picture.

**A clean Aristotle already exists:** `ares-empire/web/brand/arestoteles_transparent.png` (1024², RGBA), the hub's
chronicle marker (`panels.jsx`, `mobile.jsx`), with `.webp`. Same marble style, different render.

## Settled: do not re-open

- **One Aristotle across the empire:** build every replacement from `arestoteles_transparent.png`. First check it at
  full size (crops of hair, face, beard) for any watermark and look at its alpha (it may carry a soft glow or halo; the
  app and icon need a clean cut-out edge on black and on the light wall). If it is unusable, stop and report what you
  would use instead. Never pull an image from the web, and never paint over the old watermark.
- **App icon:** opaque 1024×1024 PNG, no alpha channel (App Store Connect refuses icons with alpha), black background,
  bust centred. Match the bust's size and position in the other apps' `AppIcon-1024.png` (Arestemis, Aresus, Aresium,
  Empire) so the five read as one family on the home screen.
- **In the app:** treat the new bust the way the other province apps treat theirs (`Arestemis/.../bust-artemis.png`,
  `Aresus/.../bust-zeus.png`): same kind of cut-out, no new decoration. Keep today's tone choice (greyscale marble)
  only if it still reads well; it must work on both the dark and the light wall.
- **Website and hub:** keep each file's name, pixel size and the bust's framing (its box within the canvas, measured
  from the alpha) close to the old file, so the CSS, the login page and the intro/shatter animations need no change.
  WebP with `cwebp` (installed), quality and size similar to the current files. Python with Pillow is installed (run
  it with `python3 -I`); no cv2 and no ImageMagick; Apple's Vision (subject lifting) is available from a small Swift
  script if a cleaner cut-out is needed.

## Out of scope

- Code changes (if a file name had to change, stop and ask instead).
- Other busts, other apps, `showcase/` (Claude regenerates it later), `Arestoteles/assets/` (the retired Telegram
  bot's avatar and the source download), `scripts/make_bust.py`.
- Pushing, merging, or touching the main checkouts `~/empire-ios`, `~/Arestoteles`, `~/ares-empire` (aresync
  auto-commits and pushes them). Patrik's Weltbild vault.

## Done when

- Every file in the table is replaced, and you checked each at 100% for any trace of the watermark (say how).
- On your own simulator (`xcrun simctl create claude-72 "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-0`,
  deleted at the end), Arestoteles in dark and light: the login screen, the loading screen, the main screen with the
  small mark, and the icon on the home screen. Screenshots in the empire-ios worktree's `build/72-*.png`.
  `xcodebuild test -scheme Arestoteles` passes (AGENTS.md → Building and running, with your simulator's name).
- `build/72-icons.png`: the old and the new Arestoteles icon next to the Arestemis, Aresus, Aresium and Empire icons.
- `build/72-web.png`: the old and new website and hub files side by side on the site's own background colours, with
  their alpha boxes printed, so the framing can be compared.
- One commit per repo on its branch `claude/72-arestoteles-bust` (plain English message saying what changed and why).

## Final message

Files changed per repo with the commit hashes, the exact test summary line, the screenshot paths, how you checked for
the watermark, and anything doubtful (for example, a place where the new bust reads differently from the old one).
