# Design brief: the Arestemis and Aresus apps

The lead (Claude) designs; you implement this design faithfully and with care. **The look is the point of these
apps** (Patrik: "UI and design is key. It needs to be classy, it needs to look clean and very good."). When this brief
does not decide something, choose the quieter, cleaner option and say so in your final message.

## The family look (study before you start)

Run the two existing apps on your simulator and look at them: `Empire` with `-sampleData` and `Aresium` with
`-sampleData` (build from `~/empire-ios`'s projects in your worktree). Read their screens' code:
`Aresium/Aresium/Screens/` (ScreenHeader, IconButton, ValueRow, the start screen, the band) and `Empire/Empire/Screens/`
(EmpireRing's `RingTab` box, the province page in EmpireSheets, the login). The new apps belong to this family: same black
wall, glass, Space Grotesk text, JetBrains Mono numbers, tracked small-caps labels, generous spacing. **Don't copy
screens; stay in their style.**

Use `Shared/Design/` (read it): `ProvinceWall(accent:)`, `.glassCard(accent:raised:)`, `StatusLabel`, `StatusTone`,
`SectionHeading`, `GlassIconButton`, `WordmarkBand`, `Ink` colours, `AppAccent.arestemis` / `.aresus`,
`ProvinceLogin`, `ProvinceLoading`, `ProvinceMarkView` + `ProvinceMarks`; fonts via `AppFont.text(...)` /
`AppFont.number(...)`. **Do not edit `Shared/`**; if you need a shared piece, build it in your app's `Screens/` and name
it in your final message (the lead moves it).

## Rules

- **The accent is an accent.** It appears on: the wall's faint light (already in `ProvinceWall`), the selected tab, the
  one primary button of a screen, small highlights (a "new" dot, a selected chip's edge and text, a progress line). Never
  as a background of large areas, never on body text, never on more than one button per screen. Everything else is
  ink on black and glass.
- **No gold** (gold is the Empire's), **no red mode**, no gradients on buttons, no emoji, no slogans or "empire voice"
  ("The hunt begins", "Your domain", …). Plain, short labels.
- Numbers (money, m², counts, times) in `AppFont.number`; words in `AppFont.text`.
- Text sizes: screen title 17 bold (header) · hero 24–30 bold · row title 15 semibold · body 14 · secondary 12–13 ·
  labels 10–11 tracked caps. Colours: `Ink.primary`, `Ink.secondary`, `Ink.muted`; status via `StatusTone`.
- Spacing: 18 pt side margins, 12–14 pt between rows, 26–30 pt between sections. Corner radius 16 (cards) / 11 (rows
  inside cards, chips 999).
- Native iOS 26 controls where they exist (TabView with the Liquid Glass tab bar tinted with the accent, `Picker`
  `.segmented`, `Toggle` tinted with the accent, `DatePicker` `.compact`, `Stepper`, `.swipeActions`, `.refreshable`,
  sheets with `.presentationDetents`, `.contentTransition(.numericText())` for changing numbers). Dark only
  (`.preferredColorScheme(.dark)`).
- Motion: restrained. A soft pulse on the "hunting" dot, numeric transitions, default navigation. Respect Reduce Motion.
- Accessibility: every icon button has a label, rows combine their text into one VoiceOver element, Dynamic Type must not
  break layouts at the default and one size larger.
- Empty, loading and error states are designed, not afterthoughts: a calm sentence in `Ink.muted`, centred, with one
  action if there is one.
- The app's bust (`Image("Bust")`) is its identity: 38 pt in the header's left slot (like Aresium's Hermes), bigger on
  login/loading. The `WordmarkBand` with the app's name ends the main tab's scroll content (not fixed on screen).

## Screenshots

For each screen in your brief, save a screenshot (`xcrun simctl io <your device> screenshot build/screens/<name>.png`)
using the sample-data launch arguments. Look at every screenshot yourself (open the PNG) and fix what looks off:
alignment, clipped text, crowded rows, accent overuse, inconsistent spacing. The lead reviews them all before merging.
