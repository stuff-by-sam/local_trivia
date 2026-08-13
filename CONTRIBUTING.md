# Contributing

Thanks for taking a look. This is a small project with no build step — clone it,
`npm install`, `npm start`, and you're developing.

## Before you open a PR

```
npm run check   # syntax-checks every JS file
npm test        # boots real servers and plays a game over Socket.IO
```

CI runs both on Node 20, 22 and 24, plus `npm audit`.

## Things that will bite you

**One shared browser scope.** `public/` is loaded as classic `<script>` tags, so
every top-level `const` and `function` across `shared/*.js` *and* the page's own
file lives in one lexical scope. Re-declaring a name in two of them is a
`SyntaxError` that silently kills the second file — the page just goes dead with
no visible error. Keep shared constants in `common.js`.

**The operator boundary is load-bearing.** `/api/*` returns the answer key and
`host:*` can end a running game, so both are loopback-only (see
[SECURITY.md](SECURITY.md)). New routes under `/api` inherit this automatically;
new socket events do not — check `socket.rooms.has('admins')` via the existing
`asAdmin` wrapper.

**Socket handlers must not throw.** The session lives in memory, so an uncaught
exception doesn't drop one client, it ends the game and erases every score. All
handlers are registered through the guarded `on()` helper in `server/index.js`,
and payloads are coerced with `obj()` rather than trusted to be objects. Keep new
handlers inside that pattern.

**Scoring has one source of truth.** `public/shared/scoring.js` is `require()`d by
the server *and* loaded by the admin console, so the preview can't drift from
real scoring. Change it in one place.

## Style

Match what's there: two-space indent, semicolons, single quotes, `'use strict'`.
Comments explain *why* rather than restating the code — the existing ones are a
fair guide to the level of detail that's useful.

## Adding question banks

Drop a CSV in `questions/` using the positional column order documented in the
README. `npm test` doesn't validate these, but the admin console reports bad rows
by line number on import.
