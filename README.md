# LOCAL TRIVIA — locally hosted, real-time multiplayer trivia

[![CI](https://github.com/stuff-by-sam/local_trivia/actions/workflows/ci.yml/badge.svg)](https://github.com/stuff-by-sam/local_trivia/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Node](https://img.shields.io/badge/node-%3E%3D20-green.svg)](https://nodejs.org)

Kahoot-style trivia that runs entirely on your local network. One laptop runs the
server; a TV shows the presenter screen; players join from their phones with a PIN.
No internet needed after install.

## Requirements

- **Node.js 20 or newer** ([nodejs.org](https://nodejs.org) — the LTS build is fine)
- Every device on the **same wifi network**
- Internet once, for `npm install`. After that it runs fully offline.

## Run it

```
git clone https://github.com/stuff-by-sam/local_trivia.git
cd local_trivia
npm install
npm start
```

Or, with no terminal at all: double-click **local_trivia.command** (Mac) or **local_trivia.bat** (Windows) —
it installs dependencies on first run, starts the server, and opens the presenter
screen in your browser. If the server is already running it just opens the presenter.

The server prints the LAN join URL and a QR code, e.g.:

- **Phones** → `http://192.168.x.x:3000` (scan the QR on the presenter screen)
- **Presenter (TV)** → `http://localhost:3000/present` — fullscreen it
- **Admin (operator)** → `http://localhost:3000/admin`

First run seeds the question bank from `seed_questions.json` (12 questions).

## Notes

- Same wifi required; guest/hotel networks with client isolation won't work.
- Allow Node through the OS firewall when prompted.
- Question bank + settings persist in `server/db.sqlite`; uploaded images in `uploads/`.
- **The admin console is restricted to the machine running the server.** Phones on
  the wifi get a 403 — `/api/questions` returns the correct answer to every
  question, so it can't be public. To operate from another device, see
  [SECURITY.md](SECURITY.md).
- Fonts (VT323, Space Mono) are self-hosted in `public/fonts/` — fully offline.
- Targets 100 concurrent players.

## Environment variables

| Variable | Default | What it does |
|---|---|---|
| `PORT` | `3000` | Port the server binds on (`0.0.0.0`). |
| `TRIVIA_DB` | `server/db.sqlite` | Question-bank database path. Point it elsewhere to run a second instance, or to keep a scratch bank for testing. |
| `TRIVIA_ADMIN_TOKEN` | *(unset)* | Allows the admin console from a device other than the host. Load `/admin?k=<token>`. Loopback works with or without it. |

## Development

```
npm run check   # syntax-check every JS file
npm test        # boot real servers, join real Socket.IO clients, play a question
```

`npm test` is an integration suite, not unit tests: it starts the server on a
scratch database, joins three websocket clients, plays a question through to the
leaderboard, and asserts the operator-authorization rules from a non-loopback
address. CI runs it on Node 20, 22 and 24.

## Structure

```
server/
  index.js        Express + Socket.IO bootstrap, REST API, uploads, QR
  auth.js         Operator boundary — loopback by default, optional token
  gameSession.js  In-memory session state machine
  scoring.js      rankPlayers() + re-export of the shared scoreAnswer()
  questions.js    SQLite question bank + settings
public/
  play/           player phone UI (/)
  present/        presenter screen (/present)
  admin/          operator console (/admin)
  shared/         theme tokens, DOM/format helpers, sfx, scoring, CSV parser
  fonts/          self-hosted VT323 + Space Mono
uploads/          question images
scripts/          loadtest.js (simulated players), op.js (one-shot host command)
test/             smoke.test.js (game loop), auth.test.js (operator boundary)
```

> **One shared scope.** The browser loads these as classic `<script>` tags, so
> every top-level `const`/`function` across `shared/*.js` *and* the page's own
> file lives in one lexical scope. Re-declaring a name in two of them is a
> `SyntaxError` that silently kills the whole second file — the page just goes
> dead with no visible error. Keep shared constants in `common.js` and don't
> redeclare them downstream.

`public/shared/` is the deduplication layer:

- `theme.css` — every colour, font and keyframe as CSS custom properties. The
  three screen stylesheets declare layout only.
- `common.js` — `PAL`, `$`, `esc`, `fmt`, `plural`, `pad`, `optionLabel` and
  `createCountdown()` (the display clock used by both phone and presenter).
- `scoring.js` — the points formula, `require()`d by the server *and* loaded by
  the admin console so the scoring preview can't drift from real scoring.
- `csv.js` — the CSV → questions parser, kept free of DOM so it stays testable.

## CSV import

The parser (`public/shared/csv.js`) is positional, not name-based, so column
headings can be anything — only the order matters:

```
question, option_a, option_b, option_c, option_d, correct, category, time_limit
```

It tolerates the shapes real exports come in:

- a **title line above the header** (e.g. `marvel_movie_trivia`) is skipped —
  it scans the first 5 rows for the header instead of assuming row 1
- **no header at all** works too
- `correct` accepts `A`–`D`, a number, or the literal option text
- **numeric answer keys are auto-detected as 0-based or 1-based** per file. A
  `0` anywhere proves zero-indexed, a `4` proves one-indexed; if a file only
  uses 1/2/3 it's ambiguous and falls back to the documented 1–4 reading.
  Zero-indexed files raise a note in the import panel so it's visible.
- bad rows are reported by line number and skipped, never fatal

`questions/kids_general_q25.csv` is the zero-indexed one; the other eight use
`A`–`D`. All nine import with zero errors (275 questions).

## Presentation settings

The admin console's **PRESENTATION** panel drives two things, both applied
live to every connected phone and the presenter — no reload:

- **Question bank name** — the presenter lobby header reads
  `TRIVIA//<name>`. Trimmed, upper-cased, capped at 28 characters; blank falls
  back to `LOCAL BROADCAST`.
- **Accent colour** — a colour wheel plus seven presets and a
  **RESET TO GREEN** button.

The accent isn't a single value. `public/shared/theme.js` rotates the whole
green family — headings, the text ramp, dim labels, hairlines and panel
backgrounds — by the hue delta between the pick and the default, scaling
saturation and **leaving lightness alone**. That matters:

- the shipped green is reproduced byte-for-byte (there's an exact
  short-circuit, so no rounding drift)
- contrast survives any hue — body-on-panel stays between 17.2:1 and 12.9:1
  across all 360°, well above the 7:1 AAA bar
- the A/B/C/D answer colours are deliberately **not** rotated. They're a
  semantic set paired with shapes and letters, and shifting them would let two
  options collide (picking cyan would make A indistinguishable from B).

## Clearing the bank

**DELETE ALL** in the question-bank header wipes every saved question. It arms
on the first click (`CONFIRM — DELETE n?`) and only fires on a second click,
disarming itself after 4s. The server refuses it with a 409 unless the session
is in `LOBBY`, so the running order can't vanish mid-game. Images in `uploads/`
are left on disk.

## Question sizing on phones

`play.js` picks a `.len-*` class from the question's character count and
`play.css` maps that to a `clamp()` font size, so short questions render large
and long ones step down rather than pushing the answer buttons off screen.
Thresholds live in `SIZE_STEPS` in `public/play/play.js`.

## Question banks

`questions/` holds ready-to-import CSV banks — import them from the admin
console's CSV panel. They're sample content, not a fixed set: drop your own
CSVs in there in the column order documented above and they'll import the
same way.

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for
the two or three things in this codebase that will bite you if you don't know
about them.

## Security

It's a party game for a trusted room: don't expose it to the internet. The
operator boundary, the join PIN's real strength, and what's deliberately public
are all written up in [SECURITY.md](SECURITY.md).

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Sam Fox.

The question CSVs in `questions/` are provided as sample content for the app.
