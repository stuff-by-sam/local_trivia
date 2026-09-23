# Security

## What this software assumes

LOCAL TRIVIA is a party game for a trusted room. It binds to `0.0.0.0` so phones
on the same wifi can reach it, and it has no user accounts. **Do not port-forward
it, expose it to the internet, or run it on a network you don't control.**

Everyone who can reach the server can:

- load the player screen and join with the PIN shown on the TV
- load the presenter screen at `/present`
- fetch uploaded question images from `/uploads/`

That is the intended surface. Everything else is operator-only.

## The iOS app

The app joins only games hosted from a phone, never the laptop server. Its own
rules:

- **Local network only.** It joins servers at private, link-local or loopback
  addresses, or at names only a local resolver answers (bare hostnames,
  `.local`, `.home.arpa`, `.lan`, `.internal`). A join link pointing anywhere
  else is refused, so a code stuck on a wall can't send players' phones to a
  server on the internet. App Transport Security is scoped to match
  (`NSAllowsLocalNetworking`, no arbitrary loads).
- **The resume token lives in the Keychain**, device-only and readable only
  while unlocked (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). It's a bearer
  credential for the player's seat, so it never goes into preferences or logs,
  never syncs through iCloud Keychain, and can't be restored onto another
  phone. iOS keeps Keychain items when an app is deleted; a reinstall discards
  the old token on its first launch.
- **Nothing leaves for anywhere but the game.** No analytics, no accounts, no
  third-party SDKs or dependencies. Preferences hold only the nickname draft and
  the last game's address. The privacy manifest declares exactly that.
- **Untrusted text is rendered as text.** Questions, answers and other players'
  nicknames are displayed verbatim — never interpreted as Markdown or links.

### Hosting from a phone

A phone that hosts runs a small server of its own (`ios/LocalTrivia/Hosting/`).
Its surface is deliberately narrower than the laptop's:

- **Player events only.** It speaks `join`, `resume` and `submitAnswer`; there
  is no admin API and no `host:*` event. The host's controls act on the game
  engine in-process and never cross the network, so nothing on the Wi-Fi can
  start, skip, kick or end anything.
- **Local peers only.** Connections from outside private, link-local and
  loopback ranges are refused before the handshake.
- **The PIN can't be walked.** A phone that guesses wrong five times can't
  try again for a minute. That's counted by address, not by connection, so
  reconnecting doesn't reset it. A game caps at 100 players. WebSocket frames
  over 64 KB are
  refused rather than buffered, and anything that doesn't decode as a known
  player event is ignored.
- **The answer key stays on the host's phone**, in a file encrypted whenever
  the phone is locked (`.completeFileProtection`). Players are only ever sent a
  question's correct answer at the reveal, exactly as on the laptop.
- **Join links** (`localtrivia://join?url=…&pin=…`, what the host's QR code
  holds) are held to the local-network rule above: a local-network server and
  a four-digit PIN, or nothing. A link can put a phone into a game on your
  Wi-Fi; it can't send it anywhere else.

## The operator boundary

`/api/*` and the `admin:*` / `host:*` socket events are restricted to **loopback**
— the machine running the server. This matters more than it might look: the
question bank returned by `GET /api/questions` includes `correct` for every
question, so opening it up hands the answer key to anyone in the room, and the
`host:*` events can kick players or end a game in progress.

To operate from another device (a tablet at the back of the room), start the
server with a token:

```
TRIVIA_ADMIN_TOKEN=some-long-random-string npm start
```

then open `http://<host>:3000/admin?k=some-long-random-string`. The token is also
accepted as an `x-admin-token` header. Loopback continues to work without it.

The rules are covered by `test/auth.test.js`, which asserts them from a
non-loopback address rather than trusting that the code reads correctly.

## Known limitations

- **The join PIN is not a secret.** It's displayed on a TV. It keeps the wrong
  room out, not a determined guest — a 4-digit PIN is brute-forceable and there
  is no join rate limit.
- **Uploads are unbounded in count.** Each image is capped at 5 MB and must be a
  real image type, but nothing prunes `uploads/` and nothing limits how many an
  operator can add. Since uploading is operator-only, this is a disk-space
  question, not an attack.
- **Player nicknames are trusted to be rendered safely.** They are escaped at the
  point of display; if you add a new surface that shows nicknames, escape them.
- **No transport encryption.** Everything is plain HTTP over your LAN.

## Reporting a problem

Open an issue. If you'd rather not do that publicly, use GitHub's
**Report a vulnerability** button on the Security tab.
