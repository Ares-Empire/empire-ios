# empire-ios

The iPhone apps of the **Ares Empire**. Native SwiftUI apps that talk to the existing
services' APIs and log in with an Empire account. Installed via **TestFlight**.

Why and how this was decided (incl. verified TestFlight facts):
[`ares-empire/docs/IPHONE-APPS.md`](https://github.com/carlsenares/ares-empire/blob/main/docs/IPHONE-APPS.md).
The login they use: [`ares-empire/docs/ACCOUNTS.md`](https://github.com/carlsenares/ares-empire/blob/main/docs/ACCOUNTS.md).

## Apps

| App | Status | Talks to | Bundle ID (planned) |
|---|---|---|---|
| **Aresium** | planned, first | `aresium.de` API (`/api/data`, `/api/transaction/…`, `/api/import`) | `de.ares-empire.aresium` |

## Layout (planned)

```
empire-ios/
  Aresium/        Xcode project: the Aresium app + its widget extension
  Shared/         added when the 2nd app arrives: Empire login, API client, design tokens
```

Shared code is extracted only once a second app needs it — until then it lives in the app.

## Working on it

- Needs a Mac with Xcode. Work with **Claude Code on the MacBook**, so it can build, run the
  simulator and fix errors itself. aresync clones this repo there automatically.
- The services themselves (Aresium server, Empire login) are changed in their own repos on the server.
- **Never commit secrets:** no API keys, no App Store Connect keys, no passwords. Server URLs are fine.

## Releasing to the phone (TestFlight)

1. Bump the build number, Product → Archive in Xcode, *Distribute App* → *TestFlight Internal Only*.
2. After processing (a few minutes) the build shows up in the TestFlight app on the iPhone → *Update*.
3. Each build stays installable for 90 days; any newer build restarts that clock.

Later: automate step 1 (Xcode Cloud or a script with an App Store Connect API key kept outside the repo).
