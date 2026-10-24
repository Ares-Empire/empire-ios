# empire-ios

The iPhone apps of the **Ares Empire**. Native SwiftUI apps that talk to the existing
services' APIs and log in with an Empire account. Installed via **TestFlight**.

Why and how this was decided (incl. verified TestFlight facts):
[`ares-empire/docs/IPHONE-APPS.md`](https://github.com/Ares-Empire/ares-empire/blob/main/docs/IPHONE-APPS.md).
The login they use: [`ares-empire/docs/ACCOUNTS.md`](https://github.com/Ares-Empire/ares-empire/blob/main/docs/ACCOUNTS.md).

## Apps

| App | Status | Talks to | Bundle ID (planned) |
|---|---|---|---|
| **Aresium** | built (TestFlight pending) | `aresium.de` API (`/api/data`, `/api/transaction/…`, `/api/import`) | `de.ares-empire.aresium` |

## Layout

```
empire-ios/
  Aresium/        Aresium.xcodeproj: the Aresium app, its widget extension, tests
  Empire/         Empire.xcodeproj: the Ares Empire app (the hub), tests
  Shared/         compiled into every app: the Empire login (one login for all apps), the network
                  layer, the fonts; each project includes it as a synchronized folder
  scripts/        new-app-project.py (a new app project, wired to Shared/), check-shared-login.sh,
                  aresium-fixtures.mjs
```

Code moves into `Shared/` when a second app needs it (2026-10-24: the login, network layer and fonts, for the
Empire app). A new province app: `python3 scripts/new-app-project.py <Name> <bundle id> "<display name>"`.

## Working on it

- Needs a Mac with Xcode. Work with **Claude Code on the MacBook**, so it can build, run the
  simulator and fix errors itself. aresync clones this repo there automatically.
- The services themselves (Aresium server, Empire login) are changed in their own repos on the server.
- **Never commit secrets:** no API keys, no App Store Connect keys, no passwords. Server URLs are fine.

## Releasing to the phone (TestFlight)

1. Bump `CURRENT_PROJECT_VERSION` (project-level build settings, the one place for app and widget), Product → Archive in Xcode, *Distribute App* → *TestFlight Internal Only*.
2. After processing (a few minutes) the build shows up in the TestFlight app on the iPhone → *Update*.
3. Each build stays installable for 90 days; any newer build restarts that clock.

Later: automate step 1 (Xcode Cloud or a script with an App Store Connect API key kept outside the repo).
