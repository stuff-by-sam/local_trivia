'use strict';

/* Admin console — session control, game settings, CSV import, question bank.
   Reads live session state over Socket.IO; mutates the bank over the REST API. */

/* Operator credential. The server authorizes by loopback, so on the host
   machine there's nothing to supply. ?k=<token> is the opt-in path for running
   this console from another device (requires TRIVIA_ADMIN_TOKEN on the server). */
const ADMIN_KEY = new URLSearchParams(location.search).get('k') || '';

const socket = ADMIN_KEY ? io({ auth: { token: ADMIN_KEY } }) : io();

let sync = null;       // last admin:sync payload
let settings = null;   // last known settings
let bank = [];         // question list from GET /api/questions

// TIME_MIN / TIME_MAX come from /shared/common.js.
const IMAGE_TYPES = /^image\/(png|jpe?g|webp|gif)$/;
const IMAGE_MAX_BYTES = 5 * 1024 * 1024;
const IMAGE_MAX_EDGE = 720; // longest edge after client-side downscale

async function api(path, options) {
  const opts = Object.assign({}, options);
  if (ADMIN_KEY) opts.headers = Object.assign({}, opts.headers, { 'x-admin-token': ADMIN_KEY });
  const res = await fetch(path, opts);
  const data = await res.json().catch(() => ({}));
  return { ok: res.ok, data };
}

const postJson = (path, body) => api(path, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(body)
});

socket.on('connect', () => socket.emit('admin:hello'));

// The server refuses admin:hello from anything that isn't loopback or holding
// the token. Say so plainly rather than leaving an empty console sitting there.
socket.on('adminDenied', d => {
  document.body.innerHTML =
    '<main style="padding:2rem;font-family:monospace;color:var(--c-text,#9effb8);line-height:1.6">' +
    '<h1 style="font-size:1.2rem">ADMIN LOCKED</h1><p>' + (d && d.message ? d.message : 'NOT AUTHORIZED') + '</p>' +
    '<p>Open the console on the computer running the server, or start it with ' +
    'TRIVIA_ADMIN_TOKEN set and load <code>/admin?k=&lt;token&gt;</code>.</p></main>';
});

socket.on('admin:sync', s => {
  sync = s;
  settings = s.settings;
  renderSession();
  renderSettings();
  renderBankTitle();
});

// ---- session control ----

const BADGE_COLORS = { QUESTION_ACTIVE: 'var(--c-amber)', PODIUM: 'var(--c-magenta)' };

function renderSession() {
  const badge = $('state-badge');
  badge.textContent = '● ' + sync.state.replace('_', ' ');
  const col = BADGE_COLORS[sync.state] || 'var(--c-green)';
  badge.style.borderColor = col;
  badge.style.color = col;
  $('pin').textContent = sync.pin;
  $('progress').textContent = sync.state === 'LOBBY' ? 'READY' : `Q ${Math.max(1, sync.qNum)}/${sync.qTotal}`;
  renderOpButtons();
  renderPlayers();
}

// Which operator buttons + hint belong to each session state.
function opControls(s, S) {
  switch (s.state) {
    case 'LOBBY': {
      const canStart = s.connectedCount > 0 && s.bank.included > 0;
      return {
        buttons: [{ label: '▸ START GAME', event: 'host:start', primary: canStart, disabled: !canStart }],
        hint: `${s.bank.included} QUESTIONS IN SET · ${S.shuffle ? 'SHUFFLED' : 'SAVED ORDER'}` +
          (s.connectedCount ? '' : ' · WAITING FOR PLAYERS')
      };
    }
    case 'QUESTION_ACTIVE':
      return {
        buttons: [
          { label: '■ END ROUND NOW', event: 'host:endRound' },
          { label: '≫ SKIP QUESTION', event: 'host:skip' },
          { label: '× END GAME', event: 'host:end' }
        ],
        hint: 'ROUND ENDS AT 0s OR WHEN ALL CONNECTED PLAYERS ANSWER'
      };
    case 'REVEAL':
      return {
        buttons: [
          { label: '▸ SHOW LEADERBOARD', event: 'host:showLeaderboard', primary: true },
          { label: '× END GAME', event: 'host:end' }
        ],
        hint: S.autoAdvance ? 'AUTO-ADVANCE ON — 5s' : 'OPERATOR-PACED'
      };
    case 'LEADERBOARD':
      return {
        buttons: [
          { label: s.qNum < s.qTotal ? '▸ NEXT QUESTION' : '▸ FINAL PODIUM', event: 'host:next', primary: true },
          { label: '× END GAME', event: 'host:end' }
        ],
        hint: `${s.qTotal - s.qNum} QUESTIONS REMAINING`
      };
    case 'PODIUM':
      return {
        buttons: [{ label: '↺ NEW GAME (SAME ROOM)', event: 'host:newGame', primary: true }],
        hint: 'SCORES RESET · QUESTION BANK KEPT'
      };
    default:
      return { buttons: [], hint: '' };
  }
}

function renderOpButtons() {
  const { buttons, hint } = opControls(sync, settings);
  const box = $('op-btns');
  box.innerHTML = '';
  for (const spec of buttons) {
    const b = document.createElement('button');
    b.className = 'btn' + (spec.primary ? ' primary' : '');
    b.textContent = spec.label;
    b.disabled = !!spec.disabled;
    b.addEventListener('click', () => socket.emit(spec.event));
    box.appendChild(b);
  }
  $('op-hint').textContent = hint;
}

function playerDotClass(p) {
  if (p.answered) return 'answered';
  return p.connected ? 'online' : 'offline';
}

function renderPlayers() {
  const box = $('player-list');
  box.innerHTML = '';
  for (const p of sync.players) {
    const row = document.createElement('div');
    row.className = 'p-row';
    row.innerHTML = `
      <span class="p-dot ${playerDotClass(p)}"></span>
      <span class="p-name">${esc(p.nickname)}</span>
      <span class="p-type">${p.connected ? 'PHONE' : 'OFFLINE'}</span>
      <span class="p-score">${fmt(p.score)}</span>`;
    const kick = document.createElement('button');
    kick.className = 'p-kick';
    kick.textContent = 'KICK';
    kick.addEventListener('click', () => socket.emit('host:kick', { token: p.token }));
    row.appendChild(kick);
    box.appendChild(row);
  }
}

// ---- game settings ----

// Preview uses the same scoreAnswer() the server scores with (/shared/scoring.js).
const previewPts = (elapsed, S) =>
  scoreAnswer({ isCorrect: true, answerElapsedSeconds: elapsed, settings: S });

const FLOOR_NOTES = { 0: 'PURE LINEAR (SPEC DEFAULT)', 0.5: 'KAHOOT-STYLE' };

function renderSettings() {
  const S = settings;
  // Don't stomp on a field the operator is currently typing in.
  const setIfIdle = (el, v) => { if (document.activeElement !== el) el.value = v; };
  setIfIdle($('set-max'), S.MAX_POINTS);
  setIfIdle($('set-time'), S.TIME_LIMIT);
  setIfIdle($('set-wrong'), S.WRONG_ANSWER_POINTS);
  setIfIdle($('set-floor'), S.MIN_CORRECT_FRACTION);

  $('floor-label').textContent = Math.round(S.MIN_CORRECT_FRACTION * 100) + '%';
  $('floor-note').textContent = FLOOR_NOTES[S.MIN_CORRECT_FRACTION] || 'CUSTOM';
  $('formula-preview').textContent =
    `CORRECT AT ${Math.round(S.TIME_LIMIT / 2)}s → ${previewPts(S.TIME_LIMIT / 2, S)} PTS` +
    ` · AT ${Math.round(S.TIME_LIMIT * 0.95)}s → ${previewPts(S.TIME_LIMIT * 0.95, S)} PTS` +
    ` · WRONG → ${S.WRONG_ANSWER_POINTS}`;
  $('tgl-shuffle').textContent = 'SHUFFLE: ' + (S.shuffle ? 'ON' : 'OFF');
  $('tgl-auto').textContent = 'AUTO-ADVANCE: ' + (S.autoAdvance ? 'ON (5s)' : 'OFF');
  $('tgl-sound').textContent = 'SOUND: ' + (S.sound ? 'ON' : 'OFF');

  setIfIdle($('set-bankname'), S.bankName);
  $('bank-name-preview').textContent = S.bankName;
  renderAccent(S.accent);
}

// ---- presentation: accent colour + bank name ----

// Handy starting points; the colour input still allows anything.
const ACCENT_PRESETS = ['#56ff8a', '#55e6ff', '#ffb347', '#ff6ad5', '#ff6a6a', '#b98cff', '#ffffff'];

function renderAccent(accent) {
  const hex = (accent || ACCENT_DEFAULT).toLowerCase();
  if (document.activeElement !== $('set-accent')) $('set-accent').value = hex;
  $('accent-hex').textContent = hex;
  $('accent-reset').disabled = hex === ACCENT_DEFAULT;
  for (const sw of $('accent-swatches').children) {
    sw.classList.toggle('on', sw.dataset.hex === hex);
  }
  applyAccent(hex); // the admin console re-tints itself too
}

function buildSwatches() {
  const box = $('accent-swatches');
  box.innerHTML = '';
  for (const hex of ACCENT_PRESETS) {
    const b = document.createElement('button');
    b.className = 'swatch';
    b.dataset.hex = hex;
    b.style.background = hex;
    b.title = hex === ACCENT_DEFAULT ? hex + ' (default)' : hex;
    b.addEventListener('click', () => setAccent(hex));
    box.appendChild(b);
  }
}
buildSwatches();

function setAccent(hex) {
  renderAccent(hex);           // instant local feedback
  putSettings({ accent: hex }); // persist + broadcast to phones and presenter
}

// `input` fires continuously while dragging the wheel — preview locally and
// only write to the server on `change` (picker dismissed) to avoid a flood.
$('set-accent').addEventListener('input', e => {
  const hex = e.target.value.toLowerCase();
  $('accent-hex').textContent = hex;
  applyAccent(hex);
});
$('set-accent').addEventListener('change', e => setAccent(e.target.value.toLowerCase()));
$('accent-reset').addEventListener('click', () => setAccent(ACCENT_DEFAULT));

$('set-bankname').addEventListener('input', e => {
  // Live preview of the presenter header while typing.
  $('bank-name-preview').textContent = (e.target.value.trim() || 'LOCAL BROADCAST').toUpperCase();
});
$('set-bankname').addEventListener('change', e => putSettings({ bankName: e.target.value }));

async function putSettings(patch) {
  const { data } = await api('/api/settings', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(patch)
  });
  settings = data;
  renderSettings();
  renderBankList(); // per-question meta shows the default time limit
}

const numericSetting = (id, key) =>
  $(id).addEventListener('change', e => putSettings({ [key]: Number(e.target.value) }));

numericSetting('set-max', 'MAX_POINTS');
numericSetting('set-time', 'TIME_LIMIT');
numericSetting('set-wrong', 'WRONG_ANSWER_POINTS');

// The floor slider previews locally on drag, then persists on release.
$('set-floor').addEventListener('input', e => {
  settings.MIN_CORRECT_FRACTION = Number(e.target.value);
  renderSettings();
});
$('set-floor').addEventListener('change', e => putSettings({ MIN_CORRECT_FRACTION: Number(e.target.value) }));

$('tgl-shuffle').addEventListener('click', () => putSettings({ shuffle: !settings.shuffle }));
$('tgl-auto').addEventListener('click', () => putSettings({ autoAdvance: !settings.autoAdvance }));
$('tgl-sound').addEventListener('click', () => putSettings({ sound: !settings.sound }));

// ---- question bank ----

async function loadBank() {
  const { data } = await api('/api/questions');
  bank = Array.isArray(data) ? data : [];
  renderBankTitle();
  renderBankList();
}

function renderBankTitle() {
  const included = bank.filter(q => q.included).length;
  $('bank-title').textContent = `┌ QUESTION BANK — ${bank.length} SAVED · ${included} IN GAME SET`;
}

function renderBankList() {
  const box = $('bank-list');
  box.innerHTML = '';
  const defaultTime = settings ? settings.TIME_LIMIT : TIME_MAX;

  bank.forEach((q, i) => {
    const row = document.createElement('div');
    row.className = 'b-row';
    row.innerHTML = `
      <button class="b-inc ${q.included ? 'on' : 'off'}" title="include in game">${q.included ? '■' : '□'}</button>
      <span class="b-n">${pad(i + 1)}</span>
      ${q.imagePath ? `<img class="b-thumb" src="${esc(q.imagePath)}" alt="">` : ''}
      <span class="b-text">${esc(q.text)}</span>
      <span class="b-cat">${esc(q.category)}</span>
      <span class="b-meta">${q.time || defaultTime}s · ${'ABCD'[q.correct]}</span>
      <button class="b-btn up" title="move up">▲</button>
      <button class="b-btn down" title="move down">▼</button>
      <button class="b-btn edit">EDIT</button>
      <button class="b-btn del">DEL</button>`;

    const reload = fn => async () => { await fn(); loadBank(); };
    row.querySelector('.b-inc').addEventListener('click', reload(() => api(`/api/questions/${q.id}/toggle`, { method: 'POST' })));
    row.querySelector('.up').addEventListener('click', reload(() => postJson(`/api/questions/${q.id}/move`, { dir: -1 })));
    row.querySelector('.down').addEventListener('click', reload(() => postJson(`/api/questions/${q.id}/move`, { dir: 1 })));
    row.querySelector('.del').addEventListener('click', reload(() => api(`/api/questions/${q.id}`, { method: 'DELETE' })));
    row.querySelector('.edit').addEventListener('click', () => openEditor(q));
    box.appendChild(row);
  });
}

$('q-reset').addEventListener('click', async () => {
  await api('/api/questions/reset', { method: 'POST' });
  bankMessage(`RESTORED SAMPLE QUESTIONS`);
  loadBank();
});

function bankMessage(text, isError = false) {
  const el = $('bank-msg');
  el.textContent = text;
  el.classList.toggle('err', isError);
  el.hidden = false;
}

/* DELETE ALL — destructive, so it arms on the first click and only fires on
   the second. Disarms itself after CONFIRM_MS so a forgotten armed button
   can't be triggered by a later stray click. */
const CONFIRM_MS = 4000;
let confirmTimer = null;

function disarmClear() {
  clearTimeout(confirmTimer);
  confirmTimer = null;
  const btn = $('q-clear');
  btn.textContent = 'DELETE ALL';
  btn.classList.remove('armed');
}

function armClear() {
  const btn = $('q-clear');
  btn.textContent = `CONFIRM — DELETE ${bank.length}?`;
  btn.classList.add('armed');
  confirmTimer = setTimeout(disarmClear, CONFIRM_MS);
}

$('q-clear').addEventListener('click', async () => {
  if (!bank.length) return bankMessage('BANK IS ALREADY EMPTY');
  if (!confirmTimer) return armClear();

  disarmClear();
  const { ok, data } = await api('/api/questions', { method: 'DELETE' });
  if (!ok) return bankMessage(data.error || 'DELETE FAILED', true);
  $('editor').hidden = true; // it may be editing a row that no longer exists
  bankMessage(`DELETED ${plural(data.deleted, 'QUESTION')} — BANK EMPTY`);
  loadBank();
});

// ---- editor ----

let editId = null;
let editCorrect = 1;
let editImagePath = null;

function currentOptValues() {
  return [0, 1, 2, 3].map(i => {
    const el = $('f-opt-' + i);
    return el ? el.value : '';
  });
}

function buildOptRows(values) {
  const box = $('f-opts');
  box.innerHTML = '';
  'ABCD'.split('').forEach((letter, i) => {
    const row = document.createElement('div');
    row.className = 'opt-row';

    const mark = document.createElement('button');
    mark.className = 'opt-mark ' + (editCorrect === i ? 'on' : 'off');
    mark.title = 'mark correct';
    mark.textContent = letter + (editCorrect === i ? ' ✓' : '');
    mark.addEventListener('click', () => {
      editCorrect = i;
      buildOptRows(currentOptValues()); // re-render so the ✓ moves
    });

    const input = document.createElement('input');
    input.id = 'f-opt-' + i;
    input.placeholder = 'Option ' + letter;
    input.value = values[i] || '';

    row.append(mark, input);
    box.appendChild(row);
  });
}

function openEditor(q) {
  editId = q ? q.id : null;
  editCorrect = q ? q.correct : 1;
  editImagePath = q ? q.imagePath : null;
  $('editor-title').textContent = q ? '┌ EDIT QUESTION' : '┌ NEW QUESTION';
  $('f-text').value = q ? q.text : '';
  $('f-cat').value = q ? q.category : '';
  $('f-time').value = q && q.time ? q.time : '';
  $('editor-err').hidden = true;
  buildOptRows(q ? q.options : ['', '', '', '']);
  renderImagePreview();
  $('editor').hidden = false;
}

function renderImagePreview() {
  $('img-preview').hidden = !editImagePath;
  if (editImagePath) $('img-thumb').src = editImagePath;
}

function editorError(msg) {
  $('editor-err').textContent = msg;
  $('editor-err').hidden = false;
}

$('q-new').addEventListener('click', () => openEditor(null));
$('f-cancel').addEventListener('click', () => { $('editor').hidden = true; });
$('img-remove').addEventListener('click', () => { editImagePath = null; renderImagePreview(); });

// Downscale to IMAGE_MAX_EDGE before upload — keeps db/uploads small and the
// presenter image sharp enough at 26cqw.
function downscale(img) {
  const scale = Math.min(1, IMAGE_MAX_EDGE / Math.max(img.width, img.height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.round(img.width * scale);
  canvas.height = Math.round(img.height * scale);
  canvas.getContext('2d').drawImage(img, 0, 0, canvas.width, canvas.height);
  return canvas;
}

$('f-image').addEventListener('change', e => {
  const file = e.target.files && e.target.files[0];
  e.target.value = ''; // let the same file be picked again after an error
  if (!file) return;
  if (!IMAGE_TYPES.test(file.type)) return editorError('PNG / JPG / WEBP / GIF ONLY');
  if (file.size > IMAGE_MAX_BYTES) return editorError('IMAGE OVER 5MB CAP');

  const url = URL.createObjectURL(file);
  const img = new Image();
  img.onload = () => {
    URL.revokeObjectURL(url);
    downscale(img).toBlob(async blob => {
      const body = new FormData();
      body.append('image', blob, 'question.jpg');
      const { ok, data } = await api('/api/upload', { method: 'POST', body });
      if (!ok) return editorError(data.error || 'UPLOAD FAILED');
      editImagePath = data.path;
      $('editor-err').hidden = true;
      renderImagePreview();
    }, 'image/jpeg', 0.82);
  };
  img.onerror = () => { URL.revokeObjectURL(url); editorError('COULD NOT READ IMAGE'); };
  img.src = url;
});

$('f-save').addEventListener('click', async () => {
  const text = $('f-text').value.trim();
  const options = currentOptValues().map(o => o.trim());
  if (!text) return editorError('QUESTION TEXT REQUIRED');
  if (options.some(o => !o)) return editorError('ALL FOUR OPTIONS REQUIRED');

  let time = null;
  const rawTime = $('f-time').value.trim();
  if (rawTime) {
    time = parseInt(rawTime, 10);
    if (!(time >= TIME_MIN && time <= TIME_MAX)) {
      return editorError(`TIME LIMIT MUST BE ${TIME_MIN}–${TIME_MAX}s (OR BLANK FOR DEFAULT)`);
    }
  }

  const { ok, data } = await api(editId ? `/api/questions/${editId}` : '/api/questions', {
    method: editId ? 'PUT' : 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      text,
      options,
      correct: editCorrect,
      category: ($('f-cat').value.trim() || 'GENERAL').toUpperCase(),
      time,
      imagePath: editImagePath
    })
  });
  if (!ok) return editorError(data.error || 'SAVE FAILED');
  $('editor').hidden = true;
  loadBank();
});

// ---- CSV import (parsing lives in /shared/csv.js) ----

let csvParsed = null;

function setImportButton(count) {
  const btn = $('csv-import');
  btn.disabled = !count;
  btn.textContent = count ? `IMPORT ${count} ▸` : 'IMPORT';
}

function csvMessage(text) {
  $('csv-msg').textContent = text;
  $('csv-msg').hidden = false;
}

function processCsv() {
  const { questions, errors, notes } = parseQuestionCsv($('csv-text').value || '');
  csvParsed = questions;
  csvMessage(
    `PARSED ${plural(questions.length, 'QUESTION')}` +
    (errors.length ? ` · ${plural(errors.length, 'ERROR')}` : ' · READY TO IMPORT')
  );
  $('csv-errs').innerHTML =
    notes.map(m => `<div class="note">▸ ${esc(m)}</div>`).join('') +
    errors.map(m => `<div class="err">${esc(m)}</div>`).join('');
  setImportButton(questions.length);
}

$('csv-sample').addEventListener('click', () => {
  $('csv-text').value = CSV_SAMPLE;
  $('csv-msg').hidden = true;
  $('csv-errs').innerHTML = '';
});

$('csv-parse').addEventListener('click', processCsv);

$('csv-file').addEventListener('change', e => {
  const file = e.target.files && e.target.files[0];
  e.target.value = '';
  if (!file) return;
  const reader = new FileReader();
  reader.onload = () => { $('csv-text').value = String(reader.result || ''); processCsv(); };
  reader.readAsText(file);
});

$('csv-import').addEventListener('click', async () => {
  if (!csvParsed || !csvParsed.length) return;
  const { data } = await postJson('/api/questions/import', { questions: csvParsed });
  csvMessage(`IMPORTED ${plural(data.imported || 0, 'QUESTION')} → BANK`);
  $('csv-text').value = '';
  $('csv-errs').innerHTML = '';
  csvParsed = null;
  setImportButton(0);
  loadBank();
});

loadBank();
