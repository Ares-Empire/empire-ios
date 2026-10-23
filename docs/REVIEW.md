# Review: the council

A **council** is a few fresh reviewers who read the same thing at the same time, each with a different
focus, without seeing each other's answers. Claude then puts the answers together. It checks that we are
building the right thing, not only that the code does what the plan says. A build that compiles and a
screen that looks right can still store the token in the wrong place or show last week's numbers.

Taken from nametbd3 (`docs/REVIEW.md` there), which took it from nametbd. What they learned: one reviewer
noticing a deeper problem is luck; several distinct focuses make it likely.

## When to run one

| Trigger | Example |
|---|---|
| A choice that is hard to undo | login and token handling, the app's data model and caching, what moves into `Shared/`, an API change in a service |
| A milestone | before the first TestFlight build, before adding external testers, before a second app starts |
| The same kind of bug shows up twice | two fixes in one area that each caused the next |
| Codex has built a lot since the last look | every 2–3 weeks during the Codex month, over everything merged since |
| Patrik asks | any time |

Not for: a single screen's layout, mechanical changes with tests, or a question a decision record
(`ares-empire/docs/IPHONE-APPS.md`, `ACCOUNTS.md`) already answers. Quote the record instead; if Patrik
wants to revisit it, that is a conversation, not a council.

## How big

Every seat needs **its own named question**. If you cannot say what one seat would find that the others
would not, drop it.

| Size | When |
|---|---|
| **2** (default) | an ordinary design question or a periodic sweep |
| **3–4** | login, tokens, anything holding financial data on the phone |
| **5** (maximum) | before other people get the app |

Mix vendors: Claude agents plus Codex (`codex exec -s read-only -m gpt-6-astra`). Different models miss
different things, and during the Codex month that costs nothing extra.

## Focuses to pick from

- **Goal:** does this make the phone the better place for this job than the website (quick to open, widgets,
  Face ID later)? Does it match the decision records?
- **Security and privacy:** token only in the Keychain, re-checked as `ACCOUNTS.md` says; nothing sensitive
  in logs, screenshots, caches or the repo; what an unlocked or lost phone exposes.
- **API boundary:** does the app match what the service really sends (read the service code, not the
  brief)? Is it working around a missing endpoint instead of changing the service? What happens offline,
  with an expired token, or with an empty account?
- **General case:** is this one instance of a wider problem? Name it in one sentence, even if the answer
  is no. This is the question a council exists for.
- **Apple platform:** TestFlight and signing, entitlements, widget and background limits, what Beta App
  Review would flag once external testers come.

## How to run it

1. **Freeze the subject:** a brief, a plan, a decision draft, or a commit range. Write down the commit.
2. **Write one prompt** naming the subject, what the repo is for (`CLAUDE.md`), the decision records it
   touches, and each seat's focus. Each seat answers its focus and also reports anything else it notices.
3. **Run the seats in parallel**, blind to each other: Claude agents with the Agent tool; Codex with
   `/opt/homebrew/bin/codex exec -s read-only -m gpt-6-astra -c model_reasoning_effort=high -o <file>`.
   Each finding in the form: what is wrong · why it matters · what to change · blocks or not.
4. **Claude reconciles.** Where seats disagree on substance, or a seat says the subject is the wrong thing
   to build, give Patrik the disagreement in a few lines to decide.
5. **Save** to `docs/reviews/YYYY-MM-DD-topic.md`: subject and commit, seats with focus and model, findings,
   outcome, roughly how long it took.

## How it ends: one of two outcomes, no second round

- **Corrected.** The fixes do not change what gets built or why: a bug, a missing test, an unnamed risk.
  Claude applies them and work goes on. No re-review.
- **Redesign.** The outcome or the scope is wrong, or a decision record is contradicted. Work stops and the
  question goes to Patrik.

The test between them: **does the change alter what gets built, or why?** If yes, it is a redesign.

An accepted finding becomes a change in the code or the docs, plus a test where it is code. A finding that
only lives in the review file did not happen.
