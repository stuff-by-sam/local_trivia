'use strict';

/* Helpers shared by the player, presenter and admin screens.
   Loaded as a plain script before each screen's own file. */

// Fixed answer-option palette: colour + shape + letter (never colour alone,
// so the options stay distinguishable for colour-blind players).
const PAL = [
  { col: '#56ff8a', tint: '#c9ffd9', rgb: '86,255,138', sym: '●', L: 'A' },
  { col: '#55e6ff', tint: '#c9f6ff', rgb: '85,230,255', sym: '▲', L: 'B' },
  { col: '#ffb347', tint: '#ffe4bd', rgb: '255,179,71', sym: '■', L: 'C' },
  { col: '#ff6ad5', tint: '#ffd2f1', rgb: '255,106,213', sym: '◆', L: 'D' }
];

// Per-question time-limit bounds, shared by the CSV parser and the editor.
// NOTE: everything declared here is a top-level `const` in the page's single
// shared script scope — re-declaring any of these names in another script on
// the same page is a SyntaxError that kills that whole file.
const TIME_MIN = 5;
const TIME_MAX = 600;

const $ = id => document.getElementById(id);

const fmt = n => Number(n || 0).toLocaleString('en-US');

const esc = s => String(s ?? '')
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;').replace(/'/g, '&#39;');

// plural(1, 'PLAYER') → '1 PLAYER'; plural(3, 'PLAYER') → '3 PLAYERS'
const plural = (n, word, suffix = 'S') => `${n} ${word}${n === 1 ? '' : suffix}`;

const pad = (n, width = 2) => String(n).padStart(width, '0');

// `[A]● ` prefix in the option's own colour, followed by the escaped text.
function optionLabel(i, text, glowPx = '6px') {
  const P = PAL[i];
  return `<span style="color:${P.col};text-shadow:0 0 ${glowPx} rgba(${P.rgb},.6);flex:none">[${P.L}]${P.sym}</span> ${esc(text)}`;
}

/* Display-only countdown. The server is authoritative for when a question
   actually ends; this just drives the on-screen clock and progress bar.
   `onTick({ remainingMs, remainingSec, fraction, low })` fires every 100 ms. */
function createCountdown(onTick, { lowAtSec = 10 } = {}) {
  let timerId = null;
  let deadline = 0;
  let limitMs = 0;

  function fire() {
    const remainingMs = Math.max(0, deadline - performance.now());
    const remainingSec = remainingMs / 1000;
    onTick({
      remainingMs,
      remainingSec,
      whole: Math.ceil(remainingSec),
      fraction: limitMs ? remainingMs / limitMs : 0,
      low: remainingSec <= lowAtSec
    });
    if (remainingMs <= 0) stop();
  }

  function start(timeLimitSec, elapsedMs = 0) {
    stop();
    limitMs = timeLimitSec * 1000;
    deadline = performance.now() + limitMs - elapsedMs;
    fire();
    timerId = setInterval(fire, 100);
  }

  function stop() {
    if (timerId) { clearInterval(timerId); timerId = null; }
  }

  return { start, stop, get running() { return timerId != null; } };
}
