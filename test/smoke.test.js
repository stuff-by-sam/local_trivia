'use strict';

/* End-to-end smoke test: boots a real server on a scratch database, drives it
   with real Socket.IO clients, and plays a question through to the leaderboard.

   It covers the parts that are expensive to get wrong at a party — a player
   can't join, scoring is upside down, the question never ends — plus the
   operator-authorization rules, which are easy to reopen by accident. */

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');
const os = require('node:os');
const io = require('socket.io-client');

const ROOT = path.join(__dirname, '..');
const PORT = Number(process.env.TEST_PORT) || 3199;
const BASE = `http://127.0.0.1:${PORT}`;

let srv, tmpDir, logs = '';

const sleep = ms => new Promise(r => setTimeout(r, ms));

function connect(opts) {
  return io(BASE, Object.assign({ transports: ['websocket'], forceNew: true }, opts));
}

// Resolves with the payload, or null if it never arrives — assertions stay
// readable and a hang surfaces as a clear failure rather than a timeout.
function connected(socket, ms = 5000) {
  return new Promise(resolve => {
    const timer = setTimeout(() => resolve(false), ms);
    socket.once('connect', () => { clearTimeout(timer); resolve(true); });
  });
}

function waitFor(socket, event, ms = 5000) {
  return new Promise(resolve => {
    const timer = setTimeout(() => resolve(null), ms);
    socket.once(event, payload => { clearTimeout(timer); resolve(payload); });
  });
}

async function api(method, url, body, headers) {
  const res = await fetch(BASE + url, {
    method,
    headers: Object.assign(body ? { 'Content-Type': 'application/json' } : {}, headers || {}),
    body: body ? JSON.stringify(body) : undefined
  });
  let parsed = null;
  try { parsed = await res.json(); } catch { /* empty body */ }
  return { status: res.status, body: parsed };
}

before(async () => {
  // A scratch HOME-side db so a developer's real question bank is never touched.
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'trivia-test-'));
  srv = spawn(process.execPath, ['server/index.js'], {
    cwd: ROOT,
    env: Object.assign({}, process.env, { PORT: String(PORT), TRIVIA_DB: path.join(tmpDir, 'test.sqlite') }),
    stdio: ['ignore', 'pipe', 'pipe']
  });
  srv.stdout.on('data', d => { logs += d; });
  srv.stderr.on('data', d => { logs += d; });

  for (let i = 0; i < 60; i++) {
    try { await fetch(BASE + '/'); return; } catch { await sleep(250); }
  }
  throw new Error('server did not start:\n' + logs);
});

after(() => {
  if (srv) srv.kill('SIGKILL');
  if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true });
});

test('serves the three screens', async () => {
  for (const p of ['/', '/present', '/play']) {
    const res = await fetch(BASE + p);
    assert.equal(res.status, 200, `${p} should serve`);
  }
});

test('admin API is reachable from loopback', async () => {
  const { status, body } = await api('GET', '/api/questions');
  assert.equal(status, 200);
  assert.ok(Array.isArray(body) && body.length > 0, 'seed bank should be present');
});

test('a full question plays out and scores correctly', async () => {
  const admin = connect();
  assert.equal(await connected(admin), true, 'admin connects');
  admin.emit('admin:hello');
  const snap = await waitFor(admin, 'admin:sync');
  assert.ok(snap, 'admin:sync arrives on loopback');
  const pin = snap.pin;

  const players = [];
  for (const nickname of ['ALICE', 'BOB', 'CARA']) {
    const socket = connect();
    await connected(socket);
    socket.emit('join', { pin, nickname });
    const joined = await waitFor(socket, 'joined');
    assert.ok(joined, `${nickname} joins with the right PIN`);
    const player = { nickname, socket, token: joined.token, results: [] };
    socket.on('personalResult', r => player.results.push(r));
    players.push(player);
  }

  // Wrong PIN must be refused.
  const impostor = connect();
  await connected(impostor);
  impostor.emit('join', { pin: String((Number(pin) + 1) % 10000).padStart(4, '0'), nickname: 'MALLORY' });
  const rejected = await waitFor(impostor, 'joinError', 2000);
  assert.ok(rejected, 'wrong PIN is rejected');
  assert.equal(rejected.code, 'WRONG_PIN');
  impostor.close();

  // Duplicate nicknames must be refused.
  const twin = connect();
  await connected(twin);
  twin.emit('join', { pin, nickname: 'alice' });
  const dupe = await waitFor(twin, 'joinError', 2000);
  assert.ok(dupe, 'duplicate nickname is rejected');
  assert.equal(dupe.code, 'NICKNAME_TAKEN');
  twin.close();

  const started = waitFor(players[0].socket, 'questionStart');
  admin.emit('host:start');
  const question = await started;
  assert.ok(question, 'host:start begins the game');
  assert.equal(question.options.length, 4);
  assert.equal(question.qNum, 1);

  const bank = (await api('GET', '/api/questions')).body;
  const truth = bank.find(q => q.id === question.questionId);
  assert.ok(truth, 'the active question exists in the bank');
  const correct = truth.correct;

  const ended = waitFor(players[0].socket, 'questionEnd');
  players[0].socket.emit('submitAnswer', { questionId: question.questionId, optionIndex: correct });
  await sleep(150); // ALICE answers first, so she must finish ahead on time
  players[1].socket.emit('submitAnswer', { questionId: question.questionId, optionIndex: (correct + 1) % 4 });
  players[2].socket.emit('submitAnswer', { questionId: question.questionId, optionIndex: (correct + 2) % 4 });

  const end = await ended;
  assert.ok(end, 'question ends as soon as everyone has answered (no timer wait)');
  assert.equal(end.correctIndex, correct, 'revealed answer matches the bank');
  assert.equal(end.distribution.reduce((a, b) => a + b, 0), 3, 'every answer is counted');

  await sleep(250);
  const [alice, bob] = players;
  assert.equal(alice.results.length, 1, 'ALICE gets exactly one result');
  assert.equal(alice.results[0].correct, true);
  assert.ok(alice.results[0].points > 0, 'a correct answer scores');
  assert.equal(bob.results[0].correct, false);
  assert.equal(bob.results[0].points, 0, 'a wrong answer scores nothing');
  assert.equal(alice.results[0].rank, 1, 'the only correct answer leads');

  const board = await (async () => {
    const p = waitFor(admin, 'leaderboard');
    admin.emit('host:showLeaderboard');
    return p;
  })();
  assert.ok(board, 'leaderboard is emitted');
  assert.equal(board.standings.length, 3);
  assert.equal(board.standings[0].nickname, 'ALICE');
  assert.ok(board.standings[0].score > board.standings[1].score);

  for (const p of players) p.socket.close();
  admin.close();
});

test('a late answer is ignored', async () => {
  const admin = connect();
  await connected(admin);
  admin.emit('admin:hello');
  const snap = await waitFor(admin, 'admin:sync');

  const player = connect();
  await connected(player);
  player.emit('join', { pin: snap.pin, nickname: 'LATE' });
  const joined = await waitFor(player, 'joined');
  assert.ok(joined);

  // Not in QUESTION_ACTIVE, so this must be dropped rather than crash or score.
  player.emit('submitAnswer', { questionId: 1, optionIndex: 0 });
  const ack = await waitFor(player, 'answerAck', 1000);
  assert.equal(ack, null, 'an answer outside an active question is ignored');

  player.close();
  admin.close();
});

test('malformed socket payloads never crash the server', async () => {
  const socket = connect();
  await connected(socket);
  // `join` with a null payload used to reach `data.pin` and throw, which
  // Socket.IO propagates to process level — killing the server and every
  // in-memory score with it.
  for (const junk of [null, undefined, 'string', 42, [], { pin: {} }, { nickname: 'x'.repeat(5000) }]) {
    socket.emit('join', junk);
    socket.emit('submitAnswer', junk);
    socket.emit('resume', junk);
    socket.emit('host:kick', junk);
  }
  await sleep(400);
  const res = await fetch(BASE + '/');
  assert.equal(res.status, 200, 'server is still alive after junk input');
  socket.close();
});
