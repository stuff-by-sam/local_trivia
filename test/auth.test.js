'use strict';

/* Operator authorization.

   These assertions exist because the failure they guard against is invisible:
   the server works perfectly for the operator whether or not the rules hold,
   and only a player poking at the API finds out otherwise. */

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');
const os = require('node:os');
const io = require('socket.io-client');

const ROOT = path.join(__dirname, '..');
const PORT = Number(process.env.TEST_PORT_AUTH) || 3198;
const LOOPBACK = `http://127.0.0.1:${PORT}`;
const TOKEN = 'test-operator-token';

// A non-loopback address for this host — this is what a player's phone is.
function lanAddress() {
  for (const addrs of Object.values(os.networkInterfaces())) {
    for (const a of addrs || []) if (a.family === 'IPv4' && !a.internal) return a.address;
  }
  return null;
}

const LAN_IP = lanAddress();
const REMOTE = LAN_IP ? `http://${LAN_IP}:${PORT}` : null;
let srv, tmpDir;
const sleep = ms => new Promise(r => setTimeout(r, ms));

before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'trivia-auth-'));
  srv = spawn(process.execPath, ['server/index.js'], {
    cwd: ROOT,
    env: Object.assign({}, process.env, {
      PORT: String(PORT),
      TRIVIA_DB: path.join(tmpDir, 'auth.sqlite'),
      TRIVIA_ADMIN_TOKEN: TOKEN
    }),
    stdio: 'ignore'
  });
  for (let i = 0; i < 60; i++) {
    try { await fetch(LOOPBACK + '/'); return; } catch { await sleep(250); }
  }
  throw new Error('server did not start');
});

after(() => {
  if (srv) srv.kill('SIGKILL');
  if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true });
});

test('loopback reaches the admin API without a token', async () => {
  const res = await fetch(LOOPBACK + '/api/questions');
  assert.equal(res.status, 200);
});

test('the player screens stay public', async t => {
  if (!REMOTE) return t.skip('no non-loopback interface on this host');
  for (const p of ['/', '/present', '/play', '/shared/theme.css']) {
    const res = await fetch(REMOTE + p);
    assert.equal(res.status, 200, `${p} must stay reachable from a phone`);
  }
});

test('a remote client cannot read the answer key', async t => {
  if (!REMOTE) return t.skip('no non-loopback interface on this host');
  const res = await fetch(REMOTE + '/api/questions');
  assert.equal(res.status, 403, 'GET /api/questions returns `correct` — it must not be public');
});

test('a remote client cannot wipe or edit the bank', async t => {
  if (!REMOTE) return t.skip('no non-loopback interface on this host');
  const del = await fetch(REMOTE + '/api/questions', { method: 'DELETE' });
  assert.equal(del.status, 403);
  const put = await fetch(REMOTE + '/api/settings', {
    method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ MAX_POINTS: 99999 })
  });
  assert.equal(put.status, 403);
  // and the settings really are untouched
  const now = await (await fetch(LOOPBACK + '/api/settings')).json();
  assert.notEqual(now.MAX_POINTS, 99999);
});

test('a remote client is refused the admins room', async t => {
  if (!REMOTE) return t.skip('no non-loopback interface on this host');
  const socket = io(REMOTE, { transports: ['websocket'], forceNew: true });
  await new Promise(r => socket.once('connect', r));
  socket.emit('admin:hello');
  const outcome = await new Promise(resolve => {
    const timer = setTimeout(() => resolve('silence'), 2000);
    socket.once('admin:sync', () => { clearTimeout(timer); resolve('GRANTED'); });
    socket.once('adminDenied', () => { clearTimeout(timer); resolve('denied'); });
  });
  assert.equal(outcome, 'denied', 'admin:hello must not hand out the admins room');
  socket.close();
});

test('host:* controls do nothing for a client that was refused', async t => {
  if (!REMOTE) return t.skip('no non-loopback interface on this host');
  const attacker = io(REMOTE, { transports: ['websocket'], forceNew: true });
  await new Promise(r => attacker.once('connect', r));
  attacker.emit('admin:hello');
  await sleep(300);

  const victim = io(REMOTE, { transports: ['websocket'], forceNew: true });
  await new Promise(r => victim.once('connect', r));
  const admin = io(LOOPBACK, { transports: ['websocket'], forceNew: true });
  await new Promise(r => admin.once('connect', r));
  admin.emit('admin:hello');
  const snap = await new Promise(r => admin.once('admin:sync', r));

  victim.emit('join', { pin: snap.pin, nickname: 'VICTIM' });
  const joined = await new Promise(r => { const t = setTimeout(() => r(null), 2000); victim.once('joined', d => { clearTimeout(t); r(d); }); });
  assert.ok(joined, 'victim joined');

  const kicked = await new Promise(resolve => {
    const timer = setTimeout(() => resolve(false), 1500);
    victim.once('kicked', () => { clearTimeout(timer); resolve(true); });
    attacker.emit('host:kick', { token: joined.token });
    attacker.emit('host:end');
  });
  assert.equal(kicked, false, 'a refused client must not be able to kick anyone');

  attacker.close(); victim.close(); admin.close();
});

test('the token lets a remote operator in', async t => {
  if (!REMOTE) return t.skip('no non-loopback interface on this host');
  const viaHeader = await fetch(REMOTE + '/api/questions', { headers: { 'x-admin-token': TOKEN } });
  assert.equal(viaHeader.status, 200, 'x-admin-token header is accepted');

  const viaQuery = await fetch(REMOTE + `/api/questions?k=${TOKEN}`);
  assert.equal(viaQuery.status, 200, '?k= is accepted');

  const wrong = await fetch(REMOTE + '/api/questions', { headers: { 'x-admin-token': 'nope' } });
  assert.equal(wrong.status, 403, 'a wrong token is refused');

  const socket = io(REMOTE, { transports: ['websocket'], forceNew: true, auth: { token: TOKEN } });
  await new Promise(r => socket.once('connect', r));
  socket.emit('admin:hello');
  const granted = await new Promise(resolve => {
    const timer = setTimeout(() => resolve(false), 2000);
    socket.once('admin:sync', () => { clearTimeout(timer); resolve(true); });
  });
  assert.equal(granted, true, 'a token-bearing socket is admitted');
  socket.close();
});
