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
