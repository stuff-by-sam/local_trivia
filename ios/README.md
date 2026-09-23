# Trivia for iOS

The native app: SwiftUI, Liquid Glass, iOS 27. Every game it plays is hosted
from a phone — one player taps **Host a Game**, and everyone else joins with
the app. It doesn't join laptop-hosted games: the laptop server and its
browser clients carry on without it.

## Build and run

Open `LocalTrivia.xcodeproj` in **Xcode 27** and run the `LocalTrivia` scheme.
To install on a device, set a team under *Signing & Capabilities* first.

On one phone, tap **Host a Game**, write or import a round, and start hosting.
On the others, the game shows up on the join screen by itself. Type the PIN
from the host's phone; the fourth digit joins.

## What makes it fast

- **No typing an address.** A hosting phone advertises `_trivia-phone._tcp`
  over Bonjour, and the app browses for it with `NetworkBrowser` at launch.
  When there's exactly one game, it's already connected by the time the player
  looks. The host's QR code is the fallback.
- **One round trip to join.** The app goes straight to a WebSocket instead of
  the long-polling handshake the browser client starts with. Nickname and last
  game are remembered, and the fourth PIN digit submits.
- **Answers lock on tap.** The button locks and a haptic fires before the
  server's ack, as the web client does. Points depend on speed.
- **The clock costs nothing.** The countdown and progress bar are
  `Text(timerInterval:)` / `ProgressView(timerInterval:)`, drawn by the system
  from a date range. The app does no per-frame work while a question runs.
- **Drops are routine, not fatal.** Phones lock and leave Wi-Fi mid-game. The
  socket retries on a short, jittered backoff, probes itself the moment the app
  returns to the foreground, and resumes with the server's token. An answer
  tapped while the link was down is re-sent after resume. The resume token is
  persisted, so even a force-quit mid-game reopens straight back into it.
- **The screen stays on during a game**, so auto-lock can't make a player miss
  a question.

## Design

A broadcast terminal, built from native parts.

- **Two typefaces, with separate jobs.** SF Pro carries content: questions,
  answers, names. SF Mono is the game's own voice: labels, figures, the clock,
  status lines (`Typography.swift`). That split makes it read as a terminal
  without asking anyone to read a paragraph in mono.
- **Glass is for the control layer.** Answers, inputs, buttons, and one top bar
  whose chips keep their glass identity from screen to screen, so the leading
  chip morphs from `● ROBIN` to `Q 01/12 · TECH` and back. Content goes in
  hairline readout boxes rather than glass, which is Apple's guidance and what
  keeps the glass meaningful.
- **It opens in the dark.** The launch screen is plain black (the app is
  dark-only, so it never flashes white), and the answer set dots on in the
  middle — circle, triangle, square, diamond — before the game fades up.
  That's an overlay, not a gate: the app is already finding games under it,
  and it takes no touches.
- **One light source.** The backdrop is near-black with a single phosphor glow
  and faint scanlines for the glass to refract. Its hue follows the game:
  the accent while playing, green or red at the reveal, gold on the podium.
  It only animates when that mood changes.
- **The answer set is the brand.** Each answer is a keycap (`▲ B`) in the same
  colour, shape and letter as on the TV (`AnswerStyle` mirrors `PAL` in
  `public/shared/common.js`). The answers stay neutral glass with a breath of
  their colour until you choose one, which lights up. Its glass then flows into
  the result badge at the reveal.
- **Terminal details, used sparingly.** A blinking cursor marks anything that's
  waiting (`WAITING FOR HOST_`), the nickname field is a `>` prompt, and the
  PIN is four cells with the cursor in the next one. All of it is drawn over
  real system controls, so focus, paste and VoiceOver behave normally.
- **Layout that holds up under real content.** On a phone the answers sit in
  the thumb zone; on iPad the round stays together, centred. All four answers
  share one size, stepped down by the longest, so none shrinks on its own.
  Readouts stack a long value under its label rather than truncate it, and
  messages sit under the field they concern, where the keyboard can't hide them.
- **Accessible by construction.** At
  accessibility text sizes the round becomes one scrolling column, readouts
  stack their label above their value, and chrome stops growing at a sensible
  cap. The lit answer switches to dark ink for contrast, results are announced
  to VoiceOver, leaving asks for confirmation, and Reduce Motion stops the
  cursor blinking and swaps blur transitions for cross-fades.

## Hosting from a phone

The only way to host: **Host a Game** on the join screen turns the phone into
the server, and its owner plays too.

- **Set up the round** — name the game, write questions (four answers, tap a
  key to mark the right one, optional category and time limit) or import a CSV
  in the web console's format, reorder and include/exclude, and set the
  scoring: top points, time per question, a floor for slow correct answers,
  points for wrong answers, shuffle and auto-advance — with a live preview of
  what an answer earns. The round is kept on the phone between games.
- **Run it** — the lobby shows the join code and a QR code; the action bar
  offers the next move (Start Game, Show Standings, Next Question, Final
  Results, Play Again); the menu has players (swipe to remove), the join code
  at full size, End Round / Skip / End Game, Edit Round between games, and
  Stop Hosting, which tells every phone the game is over. The game's name and
  the host's own name are fixed once hosting starts.
- **Join** — other phones find the game over Bonjour, or scan
  the QR code: in the app, or with the Camera, which opens the app straight
  into the game with the PIN filled in. With no router, the host can turn on
  Personal Hotspot and everyone joins that — turned on after hosting starts,
  it's picked up when the host comes back to the app.
- **On a TV, if there is one** — mirror the phone to an Apple TV or any
  AirPlay TV (Control Center → Screen Mirroring), or plug in an HDMI adapter,
  and the TV becomes the big screen for the room: the join code and QR code,
  each question with its clock and answers, the reveal with how the room
  voted, the standings and the podium. The phone keeps its own screens and
  controls. Any phone in the game can do it; **Show on a TV…** in the host's
  menu explains how.
- **No TV needed** — the full standings and the live "3 of 5 answered" count
  go to every player's phone either way.

How it's built:

- `HostedGame` — the game engine: `server/gameSession.js`, ported rule for
  rule (states, scoring, tie-breaks, late joiners, reconnects), speaking the
  same events. It has no networking of its own, so the tests drive it directly.
- `HostServer` — an actor serving Socket.IO over WebSocket with `NWListener`,
  advertised over Bonjour. It speaks the laptop server's wire, so the Node
  test bots play against it too: `node scripts/loadtest.js <PIN> 3 http://<phone>:3000`.
- `HostController` — starts and stops hosting, bridges the two, and seats the
  host in their own game over loopback, so the host's player screens are
  everyone else's. The host's controls call the engine directly; nothing on
  the network can reach them.

Limits: phone-hosted games are app-only (no browser players) and have no
question images. iOS suspends a backgrounded app, so the host should keep
Trivia open — a quick switch away is covered by a background grace period,
and the server comes back on the same port when the app returns. If the host
never does come back, players aren't stranded: once the link has failed, a
leave button appears on every screen.

## Themes and icons

Optional, and out of the way: a quiet **Themes & Icons** link under Host a
Game on the join screen, and nowhere in a game. Everything is a one-time,
non-consumable in-app purchase — each theme and icon on its own, or
**Everything** in one go. Phosphor and the classic icon are free.

- **Themes** — Amber, Cobalt, Synthwave, Noir, Gold, Holographic,
  Chalkboard, Glass and Titanium. A theme is the accent, the ink behind the
  glass, and the texture the glass refracts: Phosphor's scanlines, Cobalt's
  vector grid, Synthwave's horizon, Noir's dot matrix, Gold's brushed metal,
  Chalkboard's eraser smears and dust on slate. Three follow the phone's
  tilt: Holographic's iridescent foil slides across the screen the way Apple
  Card's does, Glass's pools of liquid colour run downhill under the glass
  controls, and a band of light slides across Titanium's brushed metal.
  These hold still while a question is up (the app still does no per-frame
  work then), under Reduce Motion, on a TV, and in the background; Core
  Motion runs only while one is following the phone, and needs no
  permission.
  Tapping one dresses the shop in it, so it's tried on before it's bought;
  closing the shop takes it off. A theme dresses this phone and any TV it's
  showing the game on. It never crosses the network, and never touches the
  answer set or the status colours: B is the cyan triangle on every phone in
  the room, whoever's wearing what, and red is still wrong.
- **App icons** — one to match every theme: the classic icon's four
  shapes, recoloured (Holographic's in foil, Chalkboard's in pastel chalk on
  slate, Titanium's in brushed metal). Glass's shapes are glass layers over
  liquid colour, which the system refracts and lights. Each is an Icon
  Composer file beside
  `AppIcon.icon`, named in the target's *Alternate App Icon Sets* build
  setting.
- **Everything** — one product that unlocks every theme and icon, including
  any added later: the app treats owning it as owning each of them. It's
  offered until there's nothing left to buy. Refunding it takes back only
  what came in it, not what was bought on its own.
- **Restore Purchases** asks the App Store for everything the Apple Account
  owns, for a new phone or a reinstall.

How it's built:

- `Shop` — StoreKit 2. Verified entitlements are the only record of what's
  owned. They're cached in preferences so a bought theme is on screen from
  the first frame, and checked again at every launch, so a refund takes a
  theme (or icon) back. A `Transaction.updates` listener picks up Ask to Buy
  approvals, refunds and purchases made elsewhere. Entitlements live on the
  device, so what's bought works offline; only buying and restoring need the
  internet. What the player chose and what they own are kept apart, so a
  theme that's taken back returns by itself if the purchase does.
- `Theme` — the catalog of looks, and the `theme` environment value the
  `Backdrop` draws from. Views keep reading `accent`, which follows it.
- `ShopView` — buys through SwiftUI's `purchase` action, which presents the
  App Store's sheet over the right scene.

For release, create the non-consumable products in App Store Connect with
the IDs in `LocalTrivia/Store/Products.storekit`. That file is the local
StoreKit configuration: the Run scheme uses it, so the shop works in the
simulator with no App Store account, and the unit tests load it. It isn't
copied into the app. To add a theme or icon, add its case, its product to the
configuration (and App Store Connect), and for an icon, its `.icon` file and
its name in the build setting; `ShopTests` fails if the code, the
configuration and the built app disagree.

## Security and privacy

The app never talks to the laptop server, and a hosting phone has no operator
surface on the network: the host's controls act on the game in-process.
[SECURITY.md](../SECURITY.md) has the full model; in short:

- **Local network only.** `GameServer` accepts only private, link-local and
  loopback addresses, and names only a local resolver answers. That rule is also
  applied when the last game is restored from settings, so there's no path to
  an internet host. ATS allows local networking and nothing broader.
- **The resume token is a credential**, so it's stored in the Keychain
  (`TokenStore`), device-only and unlock-only, and never in `UserDefaults` or
  logs. It never syncs through iCloud Keychain and can't be restored onto
  another phone. iOS keeps Keychain items when an app is deleted; a reinstall
  discards the old token on its first launch.
- **No analytics, accounts, entitlements or third-party code.** Log lines
  record error kinds and codes, never tokens, PINs, nicknames or addresses.
- **Purchases go through StoreKit, and nothing else leaves.** The app learns
  which themes and icons the Apple Account owns, as signed transactions it
  verifies, and nothing about the player. The owned list cached in
  preferences is replaced by StoreKit's answer at every launch, so editing it
  unlocks nothing.
- **Untrusted strings render verbatim.** Server text reaches the screen only
  through `Text(verbatim:)` / `String` initialisers, or as an interpolated
  argument, never as a localized format string. So it can't inject Markdown or
  links.

## Layout

```
LocalTrivia/
  Networking/
    Wire.swift              Engine.IO v4 / Socket.IO v5 framing — pure, no I/O
    SocketConnection.swift  URLSessionWebSocketTask actor: reconnects, heartbeat watchdog
    GameBrowser.swift       Bonjour discovery (Network.framework NetworkBrowser)
  Game/
    Protocol.swift          Typed server events + client events, decoded in one pass
    GameStore.swift         @Observable state machine — the app's play.js
    GameServer.swift        A game's address — local network only
    TokenStore.swift        The resume token, in the Keychain
  Hosting/
    HostedGame.swift        The game engine — gameSession.js, ported
    HostServer.swift        Socket.IO over WebSocket (NWListener) + Bonjour
    HostController.swift    Hosting lifecycle, and the host's own seat
    HostModels.swift        The round: questions, rules, scoring, on-device storage
    CSVImport.swift         public/shared/csv.js, ported
    JoinLink.swift          localtrivia:// join links, QR codes, the LAN address
  BigScreen/
    BigScreen.swift         A connected TV gets its own scene, not a mirror of the phone
    BigScreenView.swift     The game for the room: lobby, question, reveal, standings, podium
  Design/                   Typography, answer palette, themes and their textures, backdrop, shared components
  Store/
    Shop.swift              StoreKit 2: products, verified entitlements, buying, restoring
    ShopView.swift          Themes & Icons: try on, buy, wear
    AppIcon.swift           The alternate app icons, and a drawing of each
    Products.storekit       Local StoreKit configuration (Run scheme and tests; not in the app)
  Screens/                  One view per game phase, the launch, and the QR scanner
    Host/                   Round setup, question editor, host controls
LocalTriviaTests/           Swift Testing: wire format, payloads, the full game loop, the shop
LocalTriviaUITests/         Hosts a game in the simulator and plays it through; tries on a theme
```

No third-party dependencies. Swift 6 with strict concurrency, main-actor
isolation by default. The networking and protocol types are `nonisolated` and
`Sendable`.

## Tests

```
xcodebuild test -project LocalTrivia.xcodeproj -scheme LocalTrivia \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

The unit tests cover the wire format byte for byte, every payload a host
sends a player, address parsing, and whole games driven through a scripted
transport: joining, resuming, late joiners, answers re-sent after a drop, the
clock, being kicked, how discovery picks (or leaves alone) a game, and what a
TV shows at each stage.

Hosting is tested at three levels: scoring and CSV parsing against the
JavaScript's own results (every bank in `questions/` must import cleanly), the
engine's state machine driven directly, and the whole stack — a real
`HostServer` with the host and a guest, each a full `GameStore` on a real
socket, playing a game over loopback in one process.

The shop is tested against StoreKit's local test environment
(`SKTestSession`), loaded from the same configuration the Run scheme uses:
every product in the catalog is on sale, a theme has to be bought before
it's worn, a refund takes a theme or icon back, the bundle unlocks
everything and a refund of it keeps what was bought separately, Ask to Buy
unlocks nothing until it's approved, a cancelled purchase says nothing and a
failed one says why, the cached list gives way to StoreKit's, and every
alternate icon is built into the app under the name the shop asks for.

`ThemeTests` holds every theme to WCAG AAA contrast — its accent on its
ink, and dark text on a control lit with the accent — and checks each theme
for sale has an icon to match.

`HostAGameUITests` hosts a real game end to end through the UI: write a
question, start hosting, play it as the host, standings, podium, stop hosting.
It needs nothing but the simulator, so it runs with everything else.
Screenshots of every phase are attached to the test result.

## Protocol

The app plays the events `server/gameSession.js` defines — sent by `HostedGame`,
its port — and decodes them into the types in `Game/Protocol.swift`. A
player-facing event or field changed in one belongs in the other.
`ProtocolTests` pins the shapes it depends on.
