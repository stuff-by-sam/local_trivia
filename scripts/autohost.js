'use strict';

/* Hosts a scripted game, for testing a client end to end without clicking
   through the admin console:
     node scripts/autohost.js [--bots 3] [--questions 3] [--wait NICKNAME] [url]

   Joins bot players, optionally waits for NICKNAME to join, then plays the
   operator: start → (question ends) → leaderboard → next … → podium. Prints
   one line per phase so a harness can react, starting with `pin <PIN>`.
   Operator events are loopback-only, so run it on the machine hosting the
   server. */

const { io } = require('socket.io-client');

const args = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 ? args.splice(i, 2)[1] : fallback;
};
const BOTS = Number(flag('--bots', 3));
const QUESTIONS = Number(flag('--questions', 3));
const WAIT_FOR = flag('--wait', '');
const URL = args[0] || 'http://localhost:3000';
const PAUSE_MS = 3000; // how long the reveal and the leaderboard each stay up

const say = line => console.log(line);
const connect = () => io(URL, { transports: ['websocket'], forceNew: true });

const admin = connect();
let pin = null;
let state = null;
let played = 0;
let started = false;
let timer = null;
const answered = new Set();

admin.on('connect', () => admin.emit('admin:hello'));
admin.on('adminDenied', d => {
  console.error('operator refused:', d && d.message);
  process.exit(1);
});

admin.on('admin:sync', snap => {
  if (!pin) {
    pin = snap.pin;
    say(`pin ${pin}`);
    for (let i = 1; i <= BOTS; i++) joinBot(`BOT ${i}`);
  }

  // Report each non-bot player's first answer to a question, once.
  if (snap.state === 'QUESTION_ACTIVE') {
    for (const p of snap.players) {
      const key = `${snap.qNum}:${p.nickname}`;
      if (p.answered && !p.nickname.startsWith('BOT') && !answered.has(key)) {
        answered.add(key);
        say(`answered ${p.nickname}`);
      }
    }
  }

  if (!started) {
    // Left over from an earlier run: wind it back to the lobby first.
    if (snap.state === 'PODIUM') return admin.emit('host:newGame');
    if (snap.state !== 'LOBBY') return admin.emit('host:end');
    const waiting = WAIT_FOR && !snap.players.some(p => p.connected && p.nickname === WAIT_FOR);
    if (snap.state === 'LOBBY' && !waiting && snap.connectedCount > 0) {
      started = true;
      say('joined');
      setTimeout(() => admin.emit('host:start'), 1500);
    }
    return;
  }

  if (snap.state === state) return;
  state = snap.state;
  say(`state ${state}${state === 'QUESTION_ACTIVE' ? ` q=${snap.qNum}` : ''}`);
  clearTimeout(timer);
  if (state === 'REVEAL') {
    played++;
    timer = setTimeout(() => admin.emit('host:showLeaderboard'), PAUSE_MS);
  } else if (state === 'LEADERBOARD') {
    timer = setTimeout(() => admin.emit(played >= QUESTIONS ? 'host:end' : 'host:next'), PAUSE_MS);
  } else if (state === 'PODIUM') {
    setTimeout(() => process.exit(0), PAUSE_MS);
  }
});

function joinBot(nickname) {
  const bot = connect();
  bot.on('connect', () => bot.emit('join', { pin, nickname }));
  // Slow enough that the real player's "locked in" state is visible first.
  bot.on('questionStart', q => {
    setTimeout(() => {
      bot.emit('submitAnswer', { questionId: q.questionId, optionIndex: Math.floor(Math.random() * 4) });
    }, 2500 + Math.random() * 2500);
  });
}

process.on('SIGINT', () => process.exit(0));
