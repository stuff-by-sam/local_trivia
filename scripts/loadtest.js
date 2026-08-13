'use strict';

/* Simulated players for load testing:
     node scripts/loadtest.js <PIN> [count=100] [url=http://localhost:3000]
   Each bot joins with the PIN and answers every question after a random delay. */

const { io } = require('socket.io-client');

const PIN = process.argv[2];
const N = Number(process.argv[3] || 100);
const URL = process.argv[4] || 'http://localhost:3000';

if (!PIN) {
  console.error('usage: node scripts/loadtest.js <PIN> [count] [url]');
  process.exit(1);
}

let joined = 0;
let errors = 0;
let acks = 0;
let results = 0;

for (let i = 0; i < N; i++) {
  const nick = 'BOT_' + String(i + 1).padStart(3, '0');
  const socket = io(URL, { transports: ['websocket'] });
  socket.on('connect', () => socket.emit('join', { pin: PIN, nickname: nick }));
  socket.on('joined', () => { joined++; if (joined === N) console.log(`all ${N} bots joined`); });
  socket.on('joinError', e => { errors++; console.error(nick, 'error:', e && e.message); });
  socket.on('questionStart', q => {
    const delay = 500 + Math.random() * 7500;
    setTimeout(() => {
      // ~70% pick a random option; correctness varies naturally
      socket.emit('submitAnswer', { questionId: q.questionId, optionIndex: Math.floor(Math.random() * 4) });
    }, delay);
  });
  socket.on('answerAck', () => acks++);
  socket.on('personalResult', () => results++);
  if (i === 0) {
    socket.on('gameOver', d => {
      console.log('game over — podium:', d.podium.map(p => `${p.rank}. ${p.nickname} ${p.score}`).join(' · '));
    });
  }
}

setInterval(() => {
  console.log(`joined=${joined} errors=${errors} acks=${acks} results=${results}`);
}, 5000).unref();

process.on('SIGINT', () => process.exit(0));
