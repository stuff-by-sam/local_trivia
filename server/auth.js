'use strict';

const crypto = require('node:crypto');

/* Operator authorization.

   The threat model here isn't the internet — it's the room. Players are on the
   same wifi by design, they can see the join URL on the TV, and some of them
   would very much like to read `/api/questions` (which returns `correct` for
   every question) or emit `host:kick` at the person currently winning.

   The topology does the work: the operator console runs on the machine hosting
   the server, and players never do. So loopback is the default credential —
   nothing to configure, nothing to type, and the double-click launcher keeps
   working exactly as before.

   Set TRIVIA_ADMIN_TOKEN to also allow operating from another device (a tablet
   at the back of the room). Loopback still passes when a token is set. */

const TOKEN = String(process.env.TRIVIA_ADMIN_TOKEN || '');

// Node reports IPv4 loopback over a dual-stack socket as '::ffff:127.0.0.1',
// and the whole 127/8 block is loopback, not just 127.0.0.1.
function isLoopback(address) {
  if (!address) return false;
  const a = String(address).replace(/^::ffff:/i, '');
  return a === '::1' || a === '0:0:0:0:0:0:0:1' || /^127\./.test(a);
}

// Constant-time compare so a token can't be recovered a byte at a time.
function tokenMatches(candidate) {
  if (!TOKEN || !candidate) return false;
  const a = Buffer.from(String(candidate));
  const b = Buffer.from(TOKEN);
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

function reqIsAdmin(req) {
  if (isLoopback(req.socket && req.socket.remoteAddress)) return true;
  return tokenMatches(req.get('x-admin-token') || (req.query && req.query.k));
}

function socketIsAdmin(socket) {
  const hs = socket.handshake || {};
  if (isLoopback(hs.address)) return true;
  return tokenMatches((hs.auth && hs.auth.token) || (hs.query && hs.query.k));
}

// 403 rather than 401: there is no login to redirect to, and the answer key is
// deliberately not obtainable by asking nicely from another machine.
function requireAdmin(req, res, next) {
  if (reqIsAdmin(req)) return next();
  res.status(403).json({
    error: 'ADMIN IS RESTRICTED TO THIS MACHINE',
    detail: TOKEN
      ? 'Send the operator token as the x-admin-token header or ?k=… .'
      : 'Open the admin console on the computer running the server, or set TRIVIA_ADMIN_TOKEN to operate remotely.'
  });
}

module.exports = { isLoopback, reqIsAdmin, socketIsAdmin, requireAdmin, tokenEnabled: () => !!TOKEN };
