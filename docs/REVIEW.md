# Review: the council

A **council** is a few fresh agents, each with its own role and question, who look at the same subject blind, then
check each other's answers; Claude puts the result together. **The method (both rounds, how big, how it ends, where
records go) is in [`ares-empire/docs/COUNCIL.md`](https://github.com/Ares-Empire/ares-empire/blob/main/docs/COUNCIL.md)**
(locally `~/ares-empire/docs/COUNCIL.md`). This file adds only what is specific to the iPhone apps. A build that
compiles and a screen that looks right can still store the token in the wrong place or show last week's numbers.

## When to run one (iPhone apps)

| Trigger | Example |
|---|---|
| A choice that is hard to undo | login and token handling, the app's data model and caching, what moves into `Shared/`, an API change in a service |
| A milestone | before the first TestFlight build, before adding external testers, before a second app starts |
| The same kind of bug shows up twice | two fixes in one area that each caused the next |
| An agent has built a lot since the last look | every 2–3 weeks, over everything merged since |
| Patrik asks | any time |

Not for: a single screen's layout, mechanical changes with tests, or a question a decision record
(`ares-empire/docs/IPHONE-APPS.md`, `ACCOUNTS.md`) already answers.

## How big (iPhone apps)

| Size | When |
|---|---|
| **2** (default) | an ordinary design question or a periodic sweep |
| **3–4** | login, tokens, anything holding financial data on the phone |
| **5** (maximum) | before other people get the app |

## Focuses for the iPhone apps

Besides the roles in `COUNCIL.md`:

- **Goal:** does this make the phone the better place for this job than the website (quick to open, widgets,
  Face ID)? Does it match the decision records?
- **Security and privacy:** token only in the Keychain, re-checked as `ACCOUNTS.md` says; nothing sensitive
  in logs, screenshots, caches or the repo; what an unlocked or lost phone exposes.
- **API boundary:** does the app match what the service really sends (read the service code, not the
  brief)? Is it working around a missing endpoint instead of changing the service? What happens offline,
  with an expired token, or with an empty account?
- **Apple platform:** TestFlight and signing, entitlements, widget and background limits, what Beta App
  Review would flag once external testers come.

Records of councils over the iPhone apps go to `docs/reviews/YYYY-MM-DD-topic.md` in this repo; seats' full answers
stay in `codex-runs/` (git-ignored).
