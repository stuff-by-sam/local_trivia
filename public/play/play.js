'use strict';

/* Player phone client — thin: renders whatever the server broadcasts.
   Stores only its session token + nickname draft (reconnect restores state). */

const socket = io();

const SCREENS = ['s-join', 's-lobby', 's-wait', 's-question', 's-result', 's-rank', 's-final'];
function show(id) { SCREENS.forEach(s => { $(s).hidden = s !== id; }); }

const store = {
  get token() { return localStorage.getItem('trivia_token') || ''; },
  set token(v) { v ? localStorage.setItem('trivia_token', v) : localStorage.removeItem('trivia_token'); },
  get nickDraft() { return localStorage.getItem('trivia_nick') || ''; },
  set nickDraft(v) { localStorage.setItem('trivia_nick', v); }
};

const STATUS_LOCKED = 'ANSWER LOCKED ▸ WAITING FOR ROOM';
const STATUS_OPEN = 'TAP AN ANSWER — FAST = MORE PTS';

let me = { nickname: '', score: 0, rank: null };
let eligibleFrom = 0;
let question = null;   // active questionStart payload
let lockedIndex = null;

const countdown = createCountdown(({ whole, fraction, low }) => {
  $('q-timer').textContent = 'T-' + pad(whole, 3);
  $('q-timer').classList.toggle('low', low);
  const fill = $('q-bar-fill');
  fill.style.width = (100 * fraction).toFixed(1) + '%';
  fill.classList.toggle('low', low);
});

$('in-nick').value = store.nickDraft;
$('in-nick').addEventListener('input', e => { store.nickDraft = e.target.value; });

// ---- join ----

$('btn-join').addEventListener('click', () => {
  $('join-err').hidden = true;
  socket.emit('join', { pin: $('in-pin').value.trim(), nickname: $('in-nick').value.trim() });
});
[$('in-pin'), $('in-nick')].forEach(el =>
  el.addEventListener('keydown', e => { if (e.key === 'Enter') $('btn-join').click(); }));

socket.on('joinError', err => {
  if (!err || !err.message) return;
  $('join-err').textContent = err.message;
  $('join-err').hidden = false;
});

socket.on('joined', snap => {
  store.token = snap.token;
  $('kicked-msg').hidden = true;
  applySnapshot(snap);
});

socket.on('connect', () => {
  if (store.token) socket.emit('resume', { token: store.token });
});

socket.on('resumed', snap => applySnapshot(snap));

socket.on('resumeFailed', () => {
  store.token = '';
  countdown.stop();
  show('s-join');
});

socket.on('kicked', data => {
  store.token = '';
  countdown.stop();
  $('kicked-msg').textContent = (data && data.message) || 'REMOVED BY OPERATOR';
  $('kicked-msg').hidden = false;
  show('s-join');
});

function applySnapshot(snap) {
  me = { nickname: snap.nickname, score: snap.score || 0, rank: snap.rank || null };
  eligibleFrom = snap.eligibleFrom || 0;
  if (snap.sound != null) SFX.setEnabled(!!snap.sound);
  if (snap.accent) applyAccent(snap.accent);

  switch (snap.state) {
    case 'LOBBY':
      renderLobby(snap.playerCount || 0);
      break;
    case 'QUESTION_ACTIVE':
      if (!snap.question) return show('s-wait');
      question = snap.question;
      lockedIndex = snap.lockedIndex != null ? snap.lockedIndex : null;
      renderQuestion(snap.question.elapsedMs || 0);
      break;
    case 'REVEAL':
      if (snap.lastResult) renderResult(snap.lastResult);
      else show('s-wait');
      break;
    case 'LEADERBOARD':
      renderRank(me.rank, me.score);
      break;
    case 'PODIUM':
      renderFinal(me.rank, me.score);
      break;
  }
}

// ---- lobby ----

function renderLobby(count) {
  $('lb-name').textContent = me.nickname;
  $('lb-count').textContent = plural(count, 'PLAYER') + ' READY';
  show('s-lobby');
}

socket.on('playerCount', d => {
  if (!$('s-lobby').hidden) $('lb-count').textContent = plural(d.count, 'PLAYER') + ' READY';
});

socket.on('stateChange', d => {
  if (d.state === 'LOBBY' && store.token) {
    lockedIndex = null;
    countdown.stop();
    renderLobby(0);
    socket.emit('resume', { token: store.token }); // refresh count + state
  }
});

// ---- question ----

socket.on('questionStart', payload => {
  if (!store.token) return;
  if (eligibleFrom > payload.index) return show('s-wait');
  question = payload;
  lockedIndex = null;
  renderQuestion(payload.elapsedMs || 0);
});

// Longer questions step down a size so the answer buttons stay on screen
// without scrolling. Thresholds are character counts of the question text.
const SIZE_STEPS = [[45, 'len-s'], [100, 'len-m'], [180, 'len-l']];
const sizeClass = text => (SIZE_STEPS.find(([max]) => text.length <= max) || [, 'len-xl'])[1];

function renderQuestion(elapsedMs) {
  $('q-nick').textContent = me.nickname;
  $('q-text').textContent = question.text;
  $('q-text').className = 'q-text ' + sizeClass(question.text);

  const wrap = $('q-opts');
  wrap.innerHTML = '';
  question.options.forEach((text, i) => {
    const b = document.createElement('button');
    b.className = 'q-opt';
    b.dataset.i = i;
    b.innerHTML = optionLabel(i, text);
    b.addEventListener('click', () => tap(i));
    wrap.appendChild(b);
  });
  paintOptions();

  $('q-status').textContent = lockedIndex != null ? STATUS_LOCKED : STATUS_OPEN;
  countdown.start(question.timeLimit, elapsedMs);
  show('s-question');
}

// Dims the options the player didn't choose once an answer is locked in.
function paintOptions() {
  const locked = lockedIndex != null;
  document.querySelectorAll('.q-opt').forEach(b => {
    const i = Number(b.dataset.i);
    const P = PAL[i];
    const chosen = locked && lockedIndex === i;
    b.style.border = `1px solid ${P.col}`;
    b.style.background = `rgba(${P.rgb},${chosen ? '.28' : '.08'})`;
    b.style.color = P.tint;
    b.style.boxShadow = chosen ? `0 0 14px rgba(${P.rgb},.5)` : 'none';
    b.style.opacity = locked && !chosen ? '.32' : '1';
    b.style.cursor = locked ? 'default' : 'pointer';
  });
}

function tap(i) {
  if (lockedIndex != null || !question) return;
  lockedIndex = i; // locks instantly; the server ack only confirms
  paintOptions();
  $('q-status').textContent = STATUS_LOCKED;
  SFX.play('blip');
  socket.emit('submitAnswer', { questionId: question.questionId, optionIndex: i });
}

socket.on('answerAck', () => { $('q-status').textContent = STATUS_LOCKED; });

socket.on('questionEnd', () => countdown.stop());

// ---- reveal / leaderboard / podium ----

socket.on('personalResult', r => {
  me.score = r.totalScore;
  me.rank = r.rank;
  renderResult(r);
});

const RESULT_STYLES = {
  none: { text: 'NO ANSWER', cls: 'none' },
  correct: { text: 'CORRECT!', cls: 'ok' },
  wrong: { text: 'WRONG', cls: 'bad' }
};

function renderResult(r) {
  const style = RESULT_STYLES[!r.answered ? 'none' : r.correct ? 'correct' : 'wrong'];
  const title = $('r-title');
  title.textContent = style.text;
  title.className = 'r-title ' + style.cls;
  $('r-pts').textContent = `+${fmt(r.points)} PTS`;
  $('r-total').textContent = `TOTAL ${fmt(r.totalScore)} PTS`;
  $('r-rank').textContent = `RANK #${r.rank || '—'}`;
  show('s-result');
}

socket.on('personalRank', d => {
  me.rank = d.rank;
  me.score = d.score;
  if (d.phase === 'podium') renderFinal(d.rank, d.score);
  else renderRank(d.rank, d.score);
});

function renderRank(rank, score) {
  $('k-rank').textContent = '#' + (rank || '—');
  $('k-score').textContent = `${fmt(score)} PTS`;
  show('s-rank');
}

function renderFinal(rank, score) {
  $('f-rank').textContent = '#' + (rank || '—');
  $('f-name').textContent = me.nickname;
  $('f-score').textContent = `${fmt(score)} PTS`;
  show('s-final');
}

socket.on('gameOver', () => {
  if (store.token && $('s-final').hidden) renderFinal(me.rank, me.score);
});

socket.on('settingsChanged', d => {
  if (d.sound != null) SFX.setEnabled(!!d.sound);
  if (d.accent) applyAccent(d.accent);
});
