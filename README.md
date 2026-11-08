<p align="center">
  <img src="docs/images/banner.png" alt="The five Ares iPhone apps side by side" width="100%">
</p>

# The Ares iPhone apps

Five native iPhone apps, written in SwiftUI. Four share one account; Aresium needs none. Each works in English and
German, in light and dark, and, in a build from Xcode, on made-up sample data without an account. Aresium and Arestemis
also come with a tour on made-up data.
**[See them on patrikbreeck.com](https://patrikbreeck.com/en/apps/)**

<table>
  <tr>
    <td width="34%" valign="top">
      <h3>Aresium</h3>
      Personal finance from your bank's own exports: imported, sorted and counted on the iPhone, where the data stays.
      Widgets, receipts from a photo and a red mode.<br><br>
      Server and engine: <a href="https://github.com/Ares-Empire/aresium">aresium</a>
    </td>
    <td><img src="showcase/aresium/01-overview-dark.png" alt="Aresium: three months of spending by category"></td>
    <td><img src="showcase/aresium/02-overview-light.png" alt="Aresium in light mode"></td>
    <td><img src="showcase/aresium/03-red-mode.png" alt="Aresium in red mode"></td>
  </tr>
  <tr>
    <td valign="top">
      <h3>Arestemis</h3>
      Searches that run for you: flats, things for sale, a product's price in one shop or in every shop that sells it,
      and changes on a web page. New finds arrive as notifications, and a search for things shows what fitting listings
      ask.<br><br>
      Demo: <a href="https://arestemis.de">arestemis.de</a>
    </td>
    <td><img src="showcase/arestemis/01-hunt-dark.png" alt="Arestemis: every search at a glance"></td>
    <td><img src="showcase/arestemis/05-price-monitor-light.png" alt="Arestemis: a price monitor with its price history"></td>
    <td><img src="showcase/arestemis/03-listing-dark.png" alt="Arestemis: one listing and why it fits"></td>
  </tr>
  <tr>
    <td valign="top">
      <h3>Ares Empire</h3>
      The hub: every app of the account on a ring, the chronicle of what was built, access requests and approvals.<br><br>
      Server: <a href="https://github.com/Ares-Empire/ares-empire">ares-empire</a>
    </td>
    <td><img src="showcase/empire/01-throne-room-dark.png" alt="Ares Empire: the apps on a ring and the chronicle"></td>
    <td><img src="showcase/empire/02-marble-hall-light.png" alt="Ares Empire in light mode"></td>
    <td><img src="showcase/empire/03-province-light.png" alt="Ares Empire: one app's page"></td>
  </tr>
  <tr>
    <td valign="top">
      <h3>Arestoteles</h3>
      A personal knowledge map: positions, topics and sources from an Obsidian vault, searched by meaning and edited on
      the phone.<br><br>
      Server: <a href="https://github.com/Ares-Empire/Arestoteles">Arestoteles</a>
    </td>
    <td><img src="showcase/arestoteles/01-positions-dark.png" alt="Arestoteles: positions grouped by topic"></td>
    <td><img src="showcase/arestoteles/02-position-light.png" alt="Arestoteles: one position and how it changed"></td>
    <td><img src="showcase/arestoteles/04-search-light.png" alt="Arestoteles: search by meaning"></td>
  </tr>
  <tr>
    <td valign="top">
      <h3>Aresus</h3>
      The watchtower: the server and every service at a glance, each machine's sync runs, files sent from the iPhone
      to the Mac, the questions Claude Code sessions wait on (answered with a tap or in your own words), and widgets
      for the home and lock screen.
    </td>
    <td><img src="showcase/aresus/01-watchtower-dark.png" alt="Aresus: the server and every service"></td>
    <td><img src="showcase/aresus/03-aresync-light.png" alt="Aresus: each machine's sync runs"></td>
    <td><img src="showcase/aresus/04-widgets-dark.png" alt="Aresus: the widgets"></td>
  </tr>
</table>

More pictures with captions: [showcase/](showcase/README.md).

## Shared by the apps

- **One account.** Arestemis, Ares Empire, Arestoteles and Aresus share one Ares account: logging in to one logs in to
  all of them, through a shared Keychain group, and logging out ends it everywhere. Each asks for its own access;
  accounts are created and run from inside any of them. Aresium needs no account.
- **Push.** One service on the server sends the notifications of Arestemis, Aresus and Ares Empire. Aresium's
  notifications are made on the iPhone itself, with no server.
- **The same Settings.** Language, appearance, notifications, a contact form, the legal pages, the account.
- **Private when switching apps.** A cover hides the screen in the app switcher.

## How it's built

- SwiftUI for iOS 26 and later, with Apple's frameworks only (Swift Charts, SwiftData, WidgetKit, Vision,
  JavaScriptCore, Core Spotlight) and no third-party packages.
- One Xcode project per app. `Shared/` (login, network, push, settings, design) is compiled into every one of them.
- Aresium keeps its data on the iPhone and runs the aresium server's TypeScript engine there, in JavaScriptCore. The
  other four apps talk to their own server's JSON API.
- Every text lives in String Catalogs, in English and German.
- In Debug builds, a sample mode (`-sampleData`) shows each app on made-up data with no server; Release builds leave
  the sample files out. `scripts/showcase.py` makes the pictures above from it.

## Run it

Open an app's project in Xcode 27 (for example `Aresium/Aresium.xcodeproj`), choose an iOS 26 simulator, and add
`-sampleData` to the scheme's launch arguments to look around without an account.

## Tests

GitHub runs all five apps' unit tests on every push and pull request, using Xcode 27.1 and an iPhone 17 on iOS 27.0.
The String Catalog check runs once too. On a Mac with that Xcode and runtime:

```sh
bash scripts/test-unit.sh --all
bash scripts/test-unit.sh Aresium Empire
bash scripts/test-unit.sh --timing Aresium
python3 scripts/strings.py check
```

The script creates and deletes its own simulator, keeps build output and result bundles in `build/test-unit/`, and
needs no Apple account. `--keep-simulator` keeps that simulator for inspection. Speed budgets and measurement suites
run only with `--timing`; correctness tests run by default. Different apps can run concurrently; two runs of the same
app cannot share its output directory.

On GitHub the workflow adds `--ci`, which also leaves out the six receipt tests that read the made-up receipt's code:
Vision's barcode detection finds nothing on GitHub's virtual Macs. They run on this Mac.

The smoke tap-throughs (below), the shared-login probe (`scripts/check-shared-login.sh`) and Aresus's UI tests run on a
Mac, not on GitHub; Face ID, push delivery, the camera and rendering on a phone are checked by hand. CI uploads no
artifacts.

The layout, push and releasing to TestFlight: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Smoke tests

`python3 scripts/smoke-ios/run.py --all --language en --appearance light` taps through all five apps on invented sample data on a fresh, disposable simulator. Run again with `--language de --appearance dark` for German and dark mode. Requirements, scenarios and failure artifacts: [scripts/smoke-ios/README.md](scripts/smoke-ios/README.md).

## License

Free to use, change and share for non-commercial purposes, such as study, research, hobby projects, schools and
charities, under the [PolyForm Noncommercial License 1.0.0](LICENSE.md). Commercial use, also inside a company, needs
permission: [ares-empire.de/contact](https://www.ares-empire.de/contact).

The licence covers the code. It does not cover the Ares names, the busts, the app icons or the screenshots. Parts from
others keep their own licences:

- The fonts Space Grotesk and JetBrains Mono: SIL Open Font License 1.1
  ([OFL-SpaceGrotesk.txt](Shared/Fonts/OFL-SpaceGrotesk.txt),
  [OFL-JetBrainsMono.txt](Shared/Fonts/OFL-JetBrainsMono.txt)).
- Aresium's engine (`Aresium/Aresium/Engine/aresium-engine.js`) is built from the
  [aresium](https://github.com/Ares-Empire/aresium) repo, under the same licence as this one. Inside it:
  - the shop names from the [name-suggestion-index](https://github.com/osmlab/name-suggestion-index): BSD-3-Clause
    ([name-suggestion-index-licence.txt](Aresium/Aresium/Engine/name-suggestion-index-licence.txt));
  - the libraries csv-parse, fast-xml-parser, strnum and fflate: MIT
    ([csv-parse](https://unpkg.com/csv-parse@5.6.0/LICENSE),
    [fast-xml-parser](https://unpkg.com/fast-xml-parser@4.5.6/LICENSE),
    [strnum](https://unpkg.com/strnum@1.1.2/LICENSE), [fflate](https://unpkg.com/fflate@0.8.2/LICENSE)).
- Aresium's local places (`Aresium/Aresium/Engine/de.places.bin.gz`): © OpenStreetMap contributors, Open Database
  License 1.0 ([local-places-licence.txt](Aresium/Aresium/Engine/local-places-licence.txt)).
- Arestemis holds no OpenStreetMap data, but its server looks up the towns of a search there (ODbL 1.0):
  [town-locations-licence.txt](Arestemis/Arestemis/Licences/town-locations-licence.txt).
