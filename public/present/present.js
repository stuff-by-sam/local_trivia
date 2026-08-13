'use strict';

/* Presenter — passive fullscreen output. Renders whatever the server
   broadcasts; the countdown is rendered locally but never scored here. */

const socket = io();
const stage = $('stage');

const V = {
  state: 'LOBBY',
  pin: '····',
  joinUrl: '',
  qrDataUrl: '',
  bankName: 'LOCAL BROADCAST', // operator-set label in the lobby header
  players: [],
  q: null,           // questionStart payload
  answered: { answered: 0, total: 0 },
  reveal: null,      // { correctIndex, distribution }
  lb: null,          // leaderboard payload
  podium: null,      // gameOver payload
  lastWhole: null    // last whole second shown, so the tick sfx fires once
};

const ASCII_CELLS = 30; // width of the █░ progress bar next to the clock

// Display-only clock; the server decides when a question actually ends.
const countdown = createCountdown(({ whole, fraction, low }) => {
  const num = $('t-num');
  if (num) {
    num.textContent = pad(whole, 3);
    num.classList.toggle('low', low);
  }
  const ascii = $('t-ascii');
  if (ascii) {
    const filled = Math.round(fraction * ASCII_CELLS);
    ascii.textContent = '█'.repeat(filled) + '░'.repeat(ASCII_CELLS - filled);
  }
  if (whole !== V.lastWhole) {
    V.lastWhole = whole;
    if (low && whole > 0) SFX.play('tick');
  }
});

// ---- server events ----

socket.on('connect', () => socket.emit('present:hello'));

socket.on('present:sync', snap => {
  V.state = snap.state;
  V.pin = snap.pin;
  if (snap.joinUrl) V.joinUrl = snap.joinUrl;
  if (snap.qrDataUrl) V.qrDataUrl = snap.qrDataUrl;
  V.players = snap.players || [];
  if (snap.bankName) V.bankName = snap.bankName;
  SFX.setEnabled(!!snap.sound);
  applyAccent(snap.accent);
  if (snap.answered) V.answered = snap.answered;
  if (snap.reveal) V.reveal = snap.reveal;
  if (snap.leaderboard) V.lb = snap.leaderboard;
  if (snap.podium) V.podium = snap.podium;
  if (snap.question) V.q = snap.question;
  render();
  if (snap.question && snap.state === 'QUESTION_ACTIVE') {
    countdown.start(snap.question.timeLimit, snap.question.elapsedMs || 0);
  }
});

socket.on('playerList', players => {
  const grew = players.length > V.players.length;
  V.players = players;
  if (V.state !== 'LOBBY') return;
  updateLobbyPlayers(grew);
  if (grew) SFX.play('join');
});

socket.on('questionStart', payload => {
  V.state = 'QUESTION_ACTIVE';
  V.q = payload;
  V.answered = { answered: 0, total: V.answered.total };
  V.lastWhole = null;
  render();
  countdown.start(payload.timeLimit, payload.elapsedMs || 0);
  SFX.play('qstart');
});

socket.on('answeredCount', d => {
  const grew = d.answered > V.answered.answered;
  V.answered = d;
  const el = $('t-answered');
  if (el) el.textContent = `${d.answered}/${d.total}`;
  if (grew && V.state === 'QUESTION_ACTIVE') SFX.play('blip');
});

socket.on('questionEnd', d => {
  countdown.stop();
  V.state = 'REVEAL';
  V.reveal = d;
  render();
  SFX.play('reveal');
});

socket.on('leaderboard', d => {
  V.state = 'LEADERBOARD';
  V.lb = d;
  render();
  SFX.play('lb');
});

socket.on('gameOver', d => {
  countdown.stop();
  V.state = 'PODIUM';
  V.podium = d;
  render();
  SFX.play('fanfare');
});

socket.on('stateChange', d => {
  if (d.state !== 'LOBBY') return;
  countdown.stop();
  V.state = 'LOBBY';
  render();
});

socket.on('settingsChanged', d => {
  if (d.sound != null) SFX.setEnabled(!!d.sound);
  if (d.accent) applyAccent(d.accent);
  if (d.bankName && d.bankName !== V.bankName) {
    V.bankName = d.bankName;
    if (V.state === 'LOBBY') render(); // header only shows in the lobby
  }
});

// ---- renderers ----

const RENDERERS = {
  LOBBY: renderLobby,
  QUESTION_ACTIVE: renderActive,
  REVEAL: renderReveal,
  LEADERBOARD: renderLeaderboard,
  PODIUM: renderPodium
};

function render() {
  const fn = RENDERERS[V.state];
  if (fn) fn();
}

// ---- lobby ----

const CHIP_LIMIT = 40;

function playersLabel() { return plural(V.players.length, 'PLAYER') + ' READY'; }

function chipNames() {
  const names = V.players.map(p => p.nickname);
  return names.length > CHIP_LIMIT
    ? names.slice(0, CHIP_LIMIT).concat([`+${names.length - CHIP_LIMIT} MORE`])
    : names;
}

function renderLobby() {
  stage.innerHTML = `
    <div class="pad-lobby">
      <div class="hrow">
        <span class="h-brand">TRIVIA//${esc(V.bankName)}</span>
      </div>
      <div class="lobby-mid">
        <div class="lobby-left">
          <div class="lobby-logo">TRIVIA</div>
          <div class="lobby-join">JOIN AT <span class="lobby-url">${esc(V.joinUrl)}</span></div>
          <div class="lobby-pinrow">
            <span class="lobby-pinlabel">PIN</span>
            <span class="lobby-pin">${esc(V.pin)}</span>
          </div>
        </div>
        <div class="qr-col">
          ${V.qrDataUrl ? `<img class="qr-img" src="${V.qrDataUrl}" alt="QR">` : ''}
          <span class="qr-cap">SCAN TO JOIN</span>
        </div>
      </div>
      <div class="lobby-foot">
        <div class="lobby-count"><span id="p-count">${playersLabel()}</span><span class="blink">_</span></div>
        <div class="chips" id="chips"></div>
      </div>
    </div>`;
  updateLobbyPlayers(false);
}

function updateLobbyPlayers(grew) {
  const count = $('p-count');
  const chips = $('chips');
  if (!count || !chips) return;
  count.textContent = playersLabel();

  const names = chipNames();
  const canAppend = grew && chips.children.length && names.length >= chips.children.length;
  if (!canAppend) {
    chips.innerHTML = names.map(n => `<span class="chip${grew ? ' pop' : ''}">${esc(n)}</span>`).join('');
    return;
  }
  // Append only the new chips so the pop-in animation plays once per joiner.
  for (let i = chips.children.length; i < names.length; i++) {
    const s = document.createElement('span');
    s.className = 'chip pop';
    s.textContent = names[i];
    chips.appendChild(s);
  }
  // The "+N MORE" tail may need refreshing after the append.
  const last = chips.lastChild;
  if (last && names[chips.children.length - 1] !== last.textContent) {
    last.textContent = names[names.length - 1];
  }
}

// ---- question / reveal ----

function headerRow(mode) {
  const q = V.q || {};
  const left = mode === 'reveal' ? `Q.${q.qNum}/${q.total} · RESULTS` : `Q.${q.qNum}/${q.total}`;
  const right = mode === 'active' ? '<span class="h-live">◉ LIVE</span>' : '';
  return `
    <div class="hrow">
      <span class="h-q">${left}</span>
      <span class="h-cat">CATEGORY: ${esc(q.category || 'GENERAL')}</span>
      ${right}
    </div>
    <div class="rule"></div>`;
}

function renderActive() {
  const q = V.q;
  const tiles = q.options.map((t, i) => {
    const P = PAL[i];
    return `<div class="o-tile" style="border:1px solid ${P.col};background:rgba(${P.rgb},.07);color:${P.tint}">
      <span style="color:${P.col};text-shadow:0 0 .6cqw rgba(${P.rgb},.6);flex:none">[${P.L}]${P.sym}</span><span>${esc(t)}</span>
    </div>`;
  }).join('');
  stage.innerHTML = `
    <div class="pad">
      ${headerRow('active')}
      <div class="q-mid">
        <div class="q-text ${q.text.length > 80 ? 'long' : 'short'}">${esc(q.text)}</div>
        ${q.imagePath ? `<img class="q-img" src="${esc(q.imagePath)}" onerror="this.remove()">` : ''}
      </div>
      <div class="t-row">
        <div class="t-nums"><span class="t-big" id="t-num">${pad(q.timeLimit, 3)}</span><span class="t-sec">SEC</span></div>
        <div class="t-ascii" id="t-ascii">${'█'.repeat(ASCII_CELLS)}</div>
        <div class="t-count"><span id="t-answered">${V.answered.answered}/${V.answered.total}</span> ANSWERED<span class="blink">█</span></div>
      </div>
      <div class="o-grid">${tiles}</div>
    </div>`;
}

function renderReveal() {
  const q = V.q;
  const { correctIndex, distribution } = V.reveal;
  const total = Math.max(1, distribution.reduce((a, b) => a + b, 0));
  const C = PAL[correctIndex];

  const rows = q.options.map((t, i) => {
    const P = PAL[i];
    const isCorrect = i === correctIndex;
    const style = `border:1px solid ${P.col};background:rgba(${P.rgb},${isCorrect ? '.16' : '.05'});color:${P.tint};` +
      (isCorrect ? `box-shadow:0 0 1.4cqw rgba(${P.rgb},.45);` : 'opacity:.42;');
    return `<div class="r-row" style="${style}">
      <div class="r-row-top">
        <span style="color:${P.col};flex:none">[${P.L}]${P.sym}</span>
        <span style="flex:1">${esc(t)}</span>
        <span class="r-count">${distribution[i]}</span>
      </div>
      <div class="r-bartrack"><div class="r-bar" style="background:${P.col};width:0%"></div></div>
    </div>`;
  }).join('');

  stage.innerHTML = `
    <div class="pad">
      ${headerRow('reveal')}
      <div class="correct-line">▸ CORRECT: [${C.L}]${C.sym} ${esc(q.options[correctIndex].toUpperCase())}</div>
      <div class="r-list">${rows}</div>
      <div class="foot-hint">OPERATOR ▸ SHOW LEADERBOARD</div>
    </div>`;

  // Two frames of 0% so the CSS width transition has something to animate from.
  requestAnimationFrame(() => requestAnimationFrame(() => {
    stage.querySelectorAll('.r-bar').forEach((el, i) => {
      el.style.width = Math.round((100 * distribution[i]) / total) + '%';
    });
  }));
}

// ---- leaderboard / podium ----

function rankDelta(d) {
  if (d == null || d === 0) return { text: '—', cls: 'flat' };
  return d > 0 ? { text: `▲${d}`, cls: 'up' } : { text: `▼${-d}`, cls: 'down' };
}

const LB_ROWS = 8;

function renderLeaderboard() {
  const lb = V.lb;
  const rows = lb.standings.slice(0, LB_ROWS).map(r => {
    const delta = rankDelta(r.delta);
    return `<div class="lb-row${r.rank === 1 ? ' first' : ''}">
      <span class="lb-rank">${pad(r.rank)}</span>
      <span class="lb-name">${esc(r.nickname)}</span>
      <span class="lb-delta ${delta.cls}">${delta.text}</span>
      <span class="lb-score">${fmt(r.score)}</span>
    </div>`;
  }).join('');
  stage.innerHTML = `
    <div class="pad tight">
      <div class="hrow">
        <span class="lb-title">STANDINGS · AFTER Q.${lb.afterQuestion}</span>
        <span class="h-cat">${lb.totalQuestions} QUESTIONS TOTAL</span>
      </div>
      <div class="rule"></div>
      <div class="lb-list">${rows}</div>
      <div class="foot-hint">OPERATOR ▸ NEXT QUESTION</div>
    </div>`;
}

// Pedestal styling for 1st / 2nd / 3rd — amber, green, cyan.
const PODIUM_STEPS = {
  1: { col: '#ffb347', rgb: '255,179,71', height: 17, label: '1ST' },
  2: { col: '#56ff8a', rgb: '86,255,138', height: 12, label: '2ND' },
  3: { col: '#55e6ff', rgb: '85,230,255', height: 9, label: '3RD' }
};
const FINAL_ROWS = 12;

function podiumColumn(p) {
  const step = PODIUM_STEPS[Math.min(3, p.rank)];
  const block = `height:${step.height}cqw;border:1px solid ${step.col};` +
    `background:rgba(${step.rgb},.1);box-shadow:0 0 1.2cqw rgba(${step.rgb},.35);color:${step.col}`;
  return `<div class="pod-col">
    <div class="pod-name">${esc(p.nickname)}</div>
    <div class="pod-score">${fmt(p.score)} PTS</div>
    <div class="pod-block" style="${block}">${step.label}</div>
  </div>`;
}

function renderPodium() {
  const { podium, standings } = V.podium;
  const byRank = r => podium.find(p => p.rank === r) || podium[r - 1];
  // 2nd on the left, 1st in the middle, 3rd on the right.
  const cols = [byRank(2), byRank(1), byRank(3)].filter(Boolean).map(podiumColumn).join('');
  const finals = standings.slice(0, FINAL_ROWS).map(p => `
    <div class="final-row">
      <span class="final-rank">${pad(p.rank)}</span>
      <span class="final-name">${esc(p.nickname)}</span>
      <span>${fmt(p.score)}</span>
    </div>`).join('');
  stage.innerHTML = `
    <div class="pad flush">
      <div class="pod-title">★ FINAL RESULTS ★</div>
      <div class="pod-row">${cols}</div>
      <div class="final-grid">${finals}</div>
    </div>`;
}
