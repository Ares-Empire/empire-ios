A made-up notification for the Empire app on the simulator, in the shape the account server sends through the push
service when Patrik approves a member's request (ares-empire docs/EMPIRE-APP.md → Notifications):

    xcrun simctl push <udid> de.ares-empire.empire app-ready.apns   # tap → the ring, refreshed, no sheet over it

The app must be allowed to notify and route taps: launch it with `-sampleData -sampleUser -samplePush` (or
`-sampleCatalog`). The sample never signs in, so no device is registered with the push service.
