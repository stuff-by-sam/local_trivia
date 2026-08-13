'use strict';

/* One-shot operator command for testing:
     node scripts/op.js <start|next|lb|skip|endround|end|new> [url] */

const { io } = require('socket.io-client');

const cmd = process.argv[2];
const URL = process.argv[3] || 'http://localhost:3000';
const MAP = {
  start: 'host:start',
  next: 'host:next',
  lb: 'host:showLeaderboard',
  skip: 'host:skip',
  endround: 'host:endRound',
  end: 'host:end',
  new: 'host:newGame'
};

const socket = io(URL, { transports: ['websocket'] });
socket.on('connect', () => {
  socket.emit('admin:hello');
  setTimeout(() => {
    socket.emit(MAP[cmd] || cmd);
    setTimeout(() => process.exit(0), 300);
  }, 200);
});
socket.on('admin:sync', s => console.log('state:', s.state, 'players:', s.players.length));
