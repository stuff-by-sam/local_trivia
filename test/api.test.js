'use strict';

/* The admin REST surface.

   smoke.test.js proves the game plays; auth.test.js proves the operator
   boundary holds. Neither touches the routes the admin console actually spends
   its time in — creating, editing, reordering and importing questions, saving
   settings, and uploading images.

   That gap matters most during a framework upgrade. Express's breaking changes
   land on request parsing, route matching, multipart bodies and the error
   handler, which is precisely this file's territory and nowhere else's. */

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');
const os = require('node:os');

const ROOT = path.join(__dirname, '..');
const PORT = Number(process.env.TEST_PORT_API) || 3197;
const BASE = `http://127.0.0.1:${PORT}`;

let srv, tmpDir, logs = '';
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function api(method, url, body) {
  const res = await fetch(BASE + url, {
    method,
    headers: body === undefined ? {} : { 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  let parsed = null;
  try { parsed = await res.json(); } catch { /* no body */ }
  return { status: res.status, body: parsed };
}

const sampleQuestion = (over = {}) => Object.assign({
  text: 'What colour is a ripe banana?',
  options: ['Blue', 'Yellow', 'Crimson', 'Teal'],
  correct: 1,
  category: 'FRUIT',
  time: 30
}, over);

before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'trivia-api-'));
  srv = spawn(process.execPath, ['server/index.js'], {
    cwd: ROOT,
    env: Object.assign({}, process.env, { PORT: String(PORT), TRIVIA_DB: path.join(tmpDir, 'api.sqlite') }),
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

test('creates a question and reads it back', async () => {
  const before = (await api('GET', '/api/questions')).body.length;

  const created = await api('POST', '/api/questions', sampleQuestion());
  assert.equal(created.status, 200);

  const list = (await api('GET', '/api/questions')).body;
  assert.equal(list.length, before + 1, 'the bank grew by exactly one');

  const q = list[list.length - 1];
  assert.equal(q.text, 'What colour is a ripe banana?');
  assert.deepEqual(q.options, ['Blue', 'Yellow', 'Crimson', 'Teal']);
  assert.equal(q.correct, 1);
  assert.equal(q.category, 'FRUIT', 'category is upper-cased on the way in');
  assert.equal(q.time, 30);
  assert.equal(q.included, true, 'new questions join the game set');
});

test('rejects malformed questions with a useful message', async () => {
  const cases = [
    [{}, 'empty body'],
    [sampleQuestion({ text: '   ' }), 'blank text'],
    [sampleQuestion({ options: ['only', 'three', 'here'] }), 'three options'],
    [sampleQuestion({ options: ['a', 'b', 'c', ''] }), 'one blank option'],
    [sampleQuestion({ correct: 9 }), 'correct out of range'],
    [sampleQuestion({ correct: 'B' }), 'correct not an integer'],
    [sampleQuestion({ time: 2 }), 'time below the floor'],
    [sampleQuestion({ time: 9999 }), 'time above the ceiling']
  ];
  for (const [body, label] of cases) {
    const res = await api('POST', '/api/questions', body);
    assert.equal(res.status, 400, `${label} should be refused`);
    assert.ok(res.body && typeof res.body.error === 'string' && res.body.error.length,
      `${label} should explain itself`);
  }
});

test('edits an existing question', async () => {
  const list = (await api('GET', '/api/questions')).body;
  const target = list[list.length - 1];

  const res = await api('PUT', `/api/questions/${target.id}`, sampleQuestion({
    text: 'Edited question text', correct: 3, category: 'edited'
  }));
  assert.equal(res.status, 200);

  const after = (await api('GET', '/api/questions')).body.find(q => q.id === target.id);
  assert.equal(after.text, 'Edited question text');
  assert.equal(after.correct, 3);
  assert.equal(after.category, 'EDITED');
});

test('editing a question that does not exist is a 404', async () => {
  const res = await api('PUT', '/api/questions/99999', sampleQuestion());
  assert.equal(res.status, 404);
});

test('reorders questions with move', async () => {
  const before = (await api('GET', '/api/questions')).body;
  assert.ok(before.length >= 2, 'need at least two questions to swap');
  const [first, second] = before;

  const res = await api('POST', `/api/questions/${first.id}/move`, { dir: 1 });
  assert.equal(res.status, 200);

  const after = (await api('GET', '/api/questions')).body;
  assert.equal(after[0].id, second.id, 'the second question moved up');
  assert.equal(after[1].id, first.id, 'the first question moved down');

  // put it back so later tests see the original order
  await api('POST', `/api/questions/${first.id}/move`, { dir: -1 });
  const restored = (await api('GET', '/api/questions')).body;
  assert.equal(restored[0].id, first.id);
});

test('toggles a question in and out of the game set', async () => {
  const q = (await api('GET', '/api/questions')).body[0];
  const started = q.included;

  await api('POST', `/api/questions/${q.id}/toggle`);
  let now = (await api('GET', '/api/questions')).body.find(x => x.id === q.id);
  assert.equal(now.included, !started, 'toggle flipped it');

  await api('POST', `/api/questions/${q.id}/toggle`);
  now = (await api('GET', '/api/questions')).body.find(x => x.id === q.id);
  assert.equal(now.included, started, 'toggle flipped it back');
});

test('imports a batch of questions and skips the invalid ones', async () => {
  const before = (await api('GET', '/api/questions')).body.length;

  const res = await api('POST', '/api/questions/import', {
    questions: [
      sampleQuestion({ text: 'Imported one' }),
      sampleQuestion({ text: 'Imported two' }),
      { text: 'no options here' },                        // invalid — dropped
      sampleQuestion({ text: 'Imported three', correct: 7 }) // invalid — dropped
    ]
  });

  assert.equal(res.status, 200);
  assert.equal(res.body.imported, 2, 'only the two valid rows count');

  const after = (await api('GET', '/api/questions')).body;
  assert.equal(after.length, before + 2);
  assert.ok(after.some(q => q.text === 'Imported one'));
  assert.ok(!after.some(q => q.text === 'no options here'), 'invalid rows never land');
});

test('an import with no usable rows is still a clean 200', async () => {
  const before = (await api('GET', '/api/questions')).body.length;
  for (const body of [{ questions: [] }, { questions: 'not an array' }, {}]) {
    const res = await api('POST', '/api/questions/import', body);
    assert.equal(res.status, 200);
    assert.equal(res.body.imported, 0);
  }
  assert.equal((await api('GET', '/api/questions')).body.length, before);
});

test('deletes a single question', async () => {
  const list = (await api('GET', '/api/questions')).body;
  const victim = list[list.length - 1];

  const res = await api('DELETE', `/api/questions/${victim.id}`);
  assert.equal(res.status, 200);

  const after = (await api('GET', '/api/questions')).body;
  assert.ok(!after.some(q => q.id === victim.id), 'it is gone');
  assert.equal(after.length, list.length - 1);
});

test('saves settings, clamping out-of-range values', async () => {
  const saved = await api('PUT', '/api/settings', {
    MAX_POINTS: 2500,
    TIME_LIMIT: 45,
    shuffle: false,
    autoAdvance: true,
    accent: '#FF00AA',
    bankName: '  quiz night  '
  });
  assert.equal(saved.status, 200);
  assert.equal(saved.body.MAX_POINTS, 2500);
  assert.equal(saved.body.TIME_LIMIT, 45);
  assert.equal(saved.body.shuffle, false);
  assert.equal(saved.body.autoAdvance, true);
  assert.equal(saved.body.accent, '#ff00aa', 'accent is normalised to lower case');
  assert.equal(saved.body.bankName, 'QUIZ NIGHT', 'bank name is trimmed and upper-cased');

  // and it persists
  const reread = await api('GET', '/api/settings');
  assert.equal(reread.body.MAX_POINTS, 2500);
  assert.equal(reread.body.bankName, 'QUIZ NIGHT');

  // nonsense resets to the documented defaults rather than being stored
  const clamped = await api('PUT', '/api/settings', {
    MAX_POINTS: -5, TIME_LIMIT: 99999, accent: 'not-a-colour', bankName: ''
  });
  assert.equal(clamped.body.MAX_POINTS, 1000);
  assert.equal(clamped.body.TIME_LIMIT, 100);
  assert.equal(clamped.body.accent, '#56ff8a');
  assert.equal(clamped.body.bankName, 'LOCAL BROADCAST');

  const longName = await api('PUT', '/api/settings', { bankName: 'x'.repeat(80) });
  assert.equal(longName.body.bankName.length, 28, 'bank name is capped for the presenter header');
});

test('uploads an image and serves it back', async () => {
  // Smallest valid PNG: 1x1, so the test stays honest about content type
  // without carrying a binary fixture around.
  const png = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    'base64'
  );
  const form = new FormData();
  form.append('image', new Blob([png], { type: 'image/png' }), 'pixel.png');

  const res = await fetch(BASE + '/api/upload', { method: 'POST', body: form });
  assert.equal(res.status, 200, 'multipart upload is accepted');
  const { path: served } = await res.json();
  assert.match(served, /^\/uploads\/q-\d+-[0-9a-f]{8}\.png$/, 'stored under a generated name');

  const fetched = await fetch(BASE + served);
  assert.equal(fetched.status, 200, 'the uploaded image is served back');
  assert.equal(fetched.headers.get('content-type'), 'image/png');
  const bytes = Buffer.from(await fetched.arrayBuffer());
  assert.deepEqual(bytes, png, 'byte-for-byte what we uploaded');

  fs.rmSync(path.join(ROOT, 'uploads', path.basename(served)), { force: true });
});

test('refuses a non-image upload', async () => {
  const form = new FormData();
  form.append('image', new Blob([Buffer.from('#!/bin/sh\necho nope\n')], { type: 'text/x-shellscript' }), 'evil.sh');

  const res = await fetch(BASE + '/api/upload', { method: 'POST', body: form });
  assert.equal(res.status, 400, 'the mimetype filter rejects it');
  const body = await res.json();
  assert.ok(body.error, 'and says why');
});

test('a malformed JSON body is a 400, not a crash', async () => {
  const res = await fetch(BASE + '/api/questions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: '{"text": "unterminated'
  });
  assert.equal(res.status, 400, 'the error handler turns it into a 400');

  const alive = await fetch(BASE + '/api/questions');
  assert.equal(alive.status, 200, 'and the server is still serving');
});

test('reset restores the seed bank', async () => {
  const res = await api('POST', '/api/questions/reset');
  assert.equal(res.status, 200);

  const seed = JSON.parse(fs.readFileSync(path.join(ROOT, 'seed_questions.json'), 'utf8'));
  const list = (await api('GET', '/api/questions')).body;
  assert.equal(list.length, seed.length, 'the bank is back to exactly the seed set');
});

test('DELETE /api/questions clears the whole bank in LOBBY', async () => {
  const before = (await api('GET', '/api/questions')).body.length;
  assert.ok(before > 0);

  const res = await api('DELETE', '/api/questions');
  assert.equal(res.status, 200);
  assert.equal(res.body.deleted, before, 'it reports how many it removed');
  assert.equal((await api('GET', '/api/questions')).body.length, 0);

  await api('POST', '/api/questions/reset'); // leave the bank usable
});
