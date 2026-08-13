'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const crypto = require('node:crypto');
const express = require('express');
const multer = require('multer');
const QRCode = require('qrcode');
const { Server } = require('socket.io');
const { requireAdmin, socketIsAdmin, reqIsAdmin, tokenEnabled } = require('./auth');
const repo = require('./questions');
const { GameSession } = require('./gameSession');

const PORT = Number(process.env.PORT) || 3000;
const PUBLIC_DIR = path.join(__dirname, '..', 'public');
const UPLOADS_DIR = path.join(__dirname, '..', 'uploads');
fs.mkdirSync(UPLOADS_DIR, { recursive: true });

// The address phones dial. Prefers the primary interface (en0 on macOS) and
// falls back to localhost when there's no LAN — the presenter QR then just
// won't be reachable from other devices.
function lanIp() {
  const candidates = Object.entries(os.networkInterfaces())
    .flatMap(([name, addrs]) => (addrs || []).map(a => ({ name, ...a })))
    .filter(a => a.family === 'IPv4' && !a.internal);
  const primary = candidates.find(a => a.name === 'en0');
  return (primary || candidates[0] || {}).address || 'localhost';
}

const JOIN_URL = `http://${lanIp()}:${PORT}`;

// Rendered once at boot and handed to every presenter that connects.
const QR_COLORS = { dark: '#7dff9e', light: '#0b1f12' };
let qrDataUrl = '';
QRCode.toDataURL(JOIN_URL, { color: QR_COLORS, margin: 1, scale: 8 })
  .then(url => { qrDataUrl = url; })
  .catch(() => {});

const app = express();
app.use(express.json({ limit: '2mb' }));

app.get('/', (_req, res) => res.sendFile(path.join(PUBLIC_DIR, 'play', 'index.html')));
app.get('/play', (_req, res) => res.sendFile(path.join(PUBLIC_DIR, 'play', 'index.html')));
app.get('/present', (_req, res) => res.sendFile(path.join(PUBLIC_DIR, 'present', 'index.html')));
app.get('/admin', (req, res) => {
  if (!reqIsAdmin(req)) {
    return res.status(403).type('text/plain').send(
      'ADMIN IS RESTRICTED TO THE MACHINE RUNNING THE SERVER.\n\n' +
      'Open http://localhost:' + PORT + '/admin there, or set TRIVIA_ADMIN_TOKEN\n' +
      'and append ?k=<token> to operate from this device.'
    );
  }
  res.sendFile(path.join(PUBLIC_DIR, 'admin', 'index.html'));
});
app.use(express.static(PUBLIC_DIR));
app.use('/uploads', express.static(UPLOADS_DIR));

const server = http.createServer(app);
const io = new Server(server);

// ---- game session, wired to Socket.IO through a small bus ----

let pushAdminSoon = null;
function pushAdmins() {
  // Coalesce bursts (e.g. 100 answers landing at once) into one sync per 150 ms.
  if (pushAdminSoon) return;
  pushAdminSoon = setTimeout(() => {
    pushAdminSoon = null;
    io.to('admins').emit('admin:sync', session.adminSnapshot());
  }, 150);
}

const bus = {
  playersChanged() {
    io.to('presenters').emit('playerList', session.presenterSnapshot().players);
    io.to('players').emit('playerCount', { count: session.connected().length });
    pushAdmins();
  },
  questionStart(payload) {
    io.emit('questionStart', payload);
    io.to('presenters').emit('answeredCount', session.answeredCount());
    pushAdmins();
  },
  answerAck(player, payload) {
    if (player.socketId) io.to(player.socketId).emit('answerAck', payload);
  },
  answeredCount(payload) {
    io.to('presenters').emit('answeredCount', payload);
    pushAdmins();
  },
  questionEnd(payload) {
    io.emit('questionEnd', payload);
    pushAdmins();
  },
  personalResult(player, payload) {
    if (player.socketId) io.to(player.socketId).emit('personalResult', payload);
  },
  leaderboard(payload) {
    io.to('presenters').to('admins').emit('leaderboard', payload);
    pushAdmins();
  },
  personalRank(player, payload) {
    if (player.socketId) io.to(player.socketId).emit('personalRank', payload);
  },
  gameOver(payload) {
    io.emit('gameOver', payload);
    pushAdmins();
  },
  stateChange(state) {
    io.emit('stateChange', { state });
    pushAdmins();
  },
  kicked(socketId) {
    io.to(socketId).emit('kicked', { message: 'REMOVED BY OPERATOR' });
    const s = io.sockets.sockets.get(socketId);
    if (s) s.leave('players');
  }
};

const session = new GameSession({ repo, bus });

io.on('connection', socket => {
  /* Two hazards live on this boundary, both reachable by any phone on the wifi.

     1. Socket.IO does not catch exceptions thrown by a listener — they reach
        process level and kill the server. The session is held in memory, so a
        crash doesn't just drop one client, it ends the game and erases every
        score. One malformed emit must not be able to do that.
     2. `(data = {})` only defaults on `undefined`. A client emitting `null`
        (or a string, or a number) sails past it and the first property read
        throws. Coerce to an object instead of trusting the default.        */
  const obj = v => (v && typeof v === 'object' && !Array.isArray(v) ? v : {});
  const on = (event, handler) => socket.on(event, (...args) => {
    try {
      handler(...args);
    } catch (err) {
      console.error(`[socket] ${event} from ${socket.id} failed:`, (err && err.message) || err);
    }
  });

  on('present:hello', () => {
    socket.join('presenters');
    const snap = session.presenterSnapshot();
    snap.joinUrl = JOIN_URL;
    snap.qrDataUrl = qrDataUrl;
    socket.emit('present:sync', snap);
  });

  on('admin:hello', () => {
    // admin:sync carries the PIN and every player's token, and joining this
    // room is what unlocks host:* below — so authorize before, not after.
    if (!socketIsAdmin(socket)) return socket.emit('adminDenied', {
      message: 'ADMIN IS RESTRICTED TO THE MACHINE RUNNING THE SERVER'
    });
    socket.join('admins');
    socket.emit('admin:sync', session.adminSnapshot());
  });

  on('join', data => {
    data = obj(data);
    const r = session.join(data.pin, data.nickname, socket.id);
    // Named 'joinError' rather than 'error' so it can't be confused with
    // Socket.IO's own transport-level error handling on the client.
    if (r.error) return socket.emit('joinError', r.error);
    socket.join('players');
    const p = r.player;
    socket.emit('joined', Object.assign({ state: session.state }, session.playerSnapshot(p)));
  });

  on('resume', data => {
    data = obj(data);
    const p = session.resume(String(data.token || ''), socket.id);
    if (!p) return socket.emit('resumeFailed', {});
    socket.join('players');
    socket.emit('resumed', session.playerSnapshot(p));
  });

  on('submitAnswer', data => {
    data = obj(data);
    const p = [...session.players.values()].find(x => x.socketId === socket.id);
    if (!p) return;
    session.submit(p.token, Number(data.questionId), data.optionIndex);
  });

  // Operator controls — only sockets that identified as admin.
  const asAdmin = fn => (...args) => { if (socket.rooms.has('admins')) fn(...args); };
  on('host:start', asAdmin(() => session.start()));
  on('host:next', asAdmin(() => session.next()));
  on('host:showLeaderboard', asAdmin(() => session.showLeaderboard()));
  on('host:skip', asAdmin(() => session.skip()));
  on('host:endRound', asAdmin(() => session.endRound()));
  on('host:end', asAdmin(() => session.endGame()));
  on('host:newGame', asAdmin(() => session.newGame()));
  on('host:kick', asAdmin((data) => session.kick(String(obj(data).token || ''))));

  on('disconnect', () => session.disconnectSocket(socket.id));
});

// ---- REST API (admin console) ----
//
// Operator-only, without exception: GET /api/questions returns `correct` for
// every question, so leaving it open hands the answer key to anyone who can
// reach the server. Mounted before the routes so a new one can't miss it.
app.use('/api', requireAdmin);

app.get('/api/questions', (_req, res) => res.json(repo.list()));

app.post('/api/questions', (req, res) => {
  const err = repo.validate(req.body);
  if (err) return res.status(400).json({ error: err });
  repo.insert(req.body);
  pushAdmins();
  res.json({ ok: true });
});

app.put('/api/questions/:id', (req, res) => {
  if (!repo.get(Number(req.params.id))) return res.status(404).json({ error: 'NOT FOUND' });
  const err = repo.validate(req.body);
  if (err) return res.status(400).json({ error: err });
  repo.update(Number(req.params.id), req.body);
  pushAdmins();
  res.json({ ok: true });
});

// Wipes the bank. Refused mid-game so the running order can't be pulled out
// from under an active session — the operator must end the game first.
app.delete('/api/questions', (_req, res) => {
  if (session.state !== 'LOBBY') {
    return res.status(409).json({ error: 'END THE GAME BEFORE CLEARING THE BANK' });
  }
  const deleted = repo.removeAll();
  pushAdmins();
  res.json({ ok: true, deleted });
});

app.delete('/api/questions/:id', (req, res) => {
  repo.remove(Number(req.params.id));
  pushAdmins();
  res.json({ ok: true });
});

app.post('/api/questions/:id/move', (req, res) => {
  repo.move(Number(req.params.id), Number(req.body.dir) < 0 ? -1 : 1);
  pushAdmins();
  res.json({ ok: true });
});

app.post('/api/questions/:id/toggle', (req, res) => {
  repo.toggleInclude(Number(req.params.id));
  pushAdmins();
  res.json({ ok: true });
});

app.post('/api/questions/import', (req, res) => {
  const rows = Array.isArray(req.body.questions) ? req.body.questions : [];
  const valid = rows.filter(r => !repo.validate(r));
  repo.importMany(valid);
  pushAdmins();
  res.json({ ok: true, imported: valid.length });
});

app.post('/api/questions/reset', (_req, res) => {
  repo.seedSamples();
  pushAdmins();
  res.json({ ok: true });
});

app.get('/api/settings', (_req, res) => res.json(repo.getSettings()));

app.put('/api/settings', (req, res) => {
  const s = repo.saveSettings(req.body || {});
  // Everything here is live-applied by the phone/presenter without a reload.
  io.emit('settingsChanged', { sound: s.sound, accent: s.accent, bankName: s.bankName });
  pushAdmins();
  res.json(s);
});

const upload = multer({
  storage: multer.diskStorage({
    destination: UPLOADS_DIR,
    filename: (_req, file, cb) => {
      const ext = { 'image/png': '.png', 'image/jpeg': '.jpg', 'image/webp': '.webp', 'image/gif': '.gif' }[file.mimetype] || '.img';
      cb(null, `q-${Date.now()}-${crypto.randomBytes(4).toString('hex')}${ext}`);
    }
  }),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => cb(null, /^image\/(png|jpe?g|webp|gif)$/.test(file.mimetype))
});

app.post('/api/upload', upload.single('image'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'PNG / JPG / WEBP / GIF ONLY (≤5MB)' });
  res.json({ path: `/uploads/${req.file.filename}` });
});

// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  res.status(400).json({ error: err.message || 'BAD REQUEST' });
});

// ---- boot ----

function printBanner(seeded) {
  const c = repo.counts();
  console.log([
    '',
    '  ████ TRIVIA — LOCAL BROADCAST ████',
    '',
    `  JOIN (phones)   ${JOIN_URL}`,
    `  PRESENTER (TV)  http://localhost:${PORT}/present`,
    `  ADMIN (you)     http://localhost:${PORT}/admin` +
      (tokenEnabled() ? '  [token also accepted]' : '  [this machine only]'),
    '',
    `  PIN             ${session.pin}`,
    `  QUESTION BANK   ${c.saved} saved · ${c.included} in game set` +
      (seeded ? ' (seeded from seed_questions.json)' : '')
  ].join('\n'));

  QRCode.toString(JOIN_URL, { type: 'terminal', small: true }, (err, qr) => {
    if (!err) console.log('\n' + qr.replace(/^/gm, '  '));
    console.log('  Phones must be on the same wifi network. Allow Node through the firewall if prompted.\n');
  });
}

server.on('error', err => {
  if (err.code === 'EADDRINUSE') {
    console.error(`\n  Port ${PORT} is already in use — TRIVIA may already be running.`);
    console.error(`  Open http://localhost:${PORT}/present, or start on another port with PORT=3001 npm start\n`);
    process.exit(1);
  }
  throw err;
});

const seeded = repo.seedIfEmpty();
server.listen(PORT, '0.0.0.0', () => printBanner(seeded));
