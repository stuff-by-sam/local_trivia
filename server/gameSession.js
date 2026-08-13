'use strict';

const crypto = require('node:crypto');
const { scoreAnswer, rankPlayers } = require('./scoring');

// In-memory session state machine (GDD §6/§7.4).
// LOBBY → QUESTION_ACTIVE → REVEAL → LEADERBOARD → … → PODIUM → LOBBY
//
// The session never talks to Socket.IO directly: index.js injects a `bus`
// with emit callbacks so this module stays a pure state machine.
class GameSession {
  constructor({ repo, bus }) {
    this.repo = repo;
    this.bus = bus;
    this.pin = String(1000 + Math.floor(Math.random() * 9000));
    this.players = new Map(); // token → player
    this.resetGame();
    this.tickTimer = setInterval(() => this.tick(), 100);
    this.tickTimer.unref?.();
  }

  resetGame() {
    this.state = 'LOBBY';
    this.order = [];
    this.idx = -1;
    this.current = null; // full question row for the active/last question
    this.qStart = 0;
    this.qLimit = this.settings().TIME_LIMIT;
    this.dist = [0, 0, 0, 0];
    this.correctIdx = -1;
    this.prevRanks = null;
    this.deltas = new Map();
    this.clearAuto();
  }

  settings() { return this.repo.getSettings(); }
  connected() { return [...this.players.values()].filter(p => p.connected); }
  eligible() { return this.connected().filter(p => p.eligibleFrom <= this.idx); }
  // Everyone who was allowed to answer the current question — including players
  // who answered and then dropped (their answer stands; GDD §9).
  scoringPool() { return [...this.players.values()].filter(p => p.eligibleFrom <= this.idx); }

  clearAuto() { if (this.autoTimer) { clearTimeout(this.autoTimer); this.autoTimer = null; } }

  // ---- players ----

  join(pin, nickname, socketId) {
    const name = String(nickname || '').trim();
    if (String(pin || '').trim() !== this.pin)
      return { error: { code: 'WRONG_PIN', message: 'WRONG PIN — CHECK THE BIG SCREEN' } };
    if (name.length < 1 || name.length > 20)
      return { error: { code: 'BAD_NICKNAME', message: 'NICKNAME MUST BE 1–20 CHARS' } };
    if (this.connected().some(p => p.nickname.toLowerCase() === name.toLowerCase()))
      return { error: { code: 'NICKNAME_TAKEN', message: 'NICKNAME TAKEN — PICK ANOTHER' } };
    const player = {
      token: crypto.randomBytes(9).toString('hex'),
      nickname: name,
      socketId,
      connected: true,
      score: 0,
      cumTimeMs: 0,
      eligibleFrom: this.state === 'LOBBY' ? 0 : this.idx + 1,
      current: null, // { optionIndex, elapsedMs } for the active question
      lastResult: null,
      joinedAt: Date.now()
    };
    this.players.set(player.token, player);
    this.bus.playersChanged({ joined: player.nickname });
    return { player };
  }

  resume(token, socketId) {
    const p = this.players.get(token);
    if (!p) return null;
    p.connected = true;
    p.socketId = socketId;
    this.bus.playersChanged({});
    return p;
  }

  disconnectSocket(socketId) {
    const p = [...this.players.values()].find(x => x.socketId === socketId);
    if (!p) return;
    p.connected = false;
    p.socketId = null;
    this.bus.playersChanged({});
    this.checkAllAnswered();
  }

  kick(token) {
    const p = this.players.get(token);
    if (!p) return;
    this.players.delete(token);
    if (p.socketId) this.bus.kicked(p.socketId);
    this.bus.playersChanged({});
    this.checkAllAnswered();
  }

  // ---- flow (operator-driven) ----

  start() {
    if (this.state !== 'LOBBY') return;
    const set = this.repo.includedQuestions();
    if (!set.length || !this.connected().length) return;
    const ids = set.map(q => q.id);
    this.order = this.settings().shuffle ? shuffle(ids) : ids;
    this.idx = -1;
    this.prevRanks = null;
    this.deltas = new Map();
    for (const p of this.players.values()) {
      p.score = 0;
      p.cumTimeMs = 0;
      p.current = null;
      p.lastResult = null;
      p.eligibleFrom = 0;
    }
    this.nextQuestion();
  }

  nextQuestion() {
    this.clearAuto();
    let q = null;
    while (this.idx + 1 < this.order.length && !q) {
      this.idx++;
      q = this.repo.get(this.order[this.idx]); // skip questions deleted mid-game
    }
    if (!q) return this.podium();
    this.current = q;
    this.qLimit = q.time || this.settings().TIME_LIMIT;
    this.qStart = Date.now();
    this.state = 'QUESTION_ACTIVE';
    this.dist = [0, 0, 0, 0];
    this.correctIdx = -1;
    for (const p of this.players.values()) p.current = null;
    this.bus.questionStart(this.questionStartPayload());
  }

  questionStartPayload(elapsedMs = 0) {
    const q = this.current;
    return {
      index: this.idx,
      qNum: this.idx + 1,
      total: this.order.length,
      questionId: q.id,
      text: q.text,
      imagePath: q.imagePath,
      options: q.options,
      category: q.category,
      timeLimit: this.qLimit,
      serverStartTime: this.qStart,
      elapsedMs
    };
  }

  submit(token, questionId, optionIndex) {
    if (this.state !== 'QUESTION_ACTIVE') return;
    const p = this.players.get(token);
    if (!p || !p.connected || p.current || p.eligibleFrom > this.idx) return;
    if (!this.current || questionId !== this.current.id) return;
    const opt = Number(optionIndex);
    if (!Number.isInteger(opt) || opt < 0 || opt > 3) return;
    const elapsedMs = Date.now() - this.qStart;
    if (elapsedMs > this.qLimit * 1000) return; // late — ignored server-side
    p.current = { optionIndex: opt, elapsedMs };
    this.bus.answerAck(p, { questionId, locked: true });
    this.bus.answeredCount(this.answeredCount());
    this.checkAllAnswered();
  }

  answeredCount() {
    const el = this.eligible();
    return { answered: el.filter(p => p.current).length, total: el.length };
  }

  checkAllAnswered() {
    if (this.state !== 'QUESTION_ACTIVE') return;
    const el = this.eligible();
    if (el.length && el.every(p => p.current)) this.endQuestion();
  }

  tick() {
    if (this.state !== 'QUESTION_ACTIVE') return;
    if (Date.now() - this.qStart >= this.qLimit * 1000) this.endQuestion();
  }

  endQuestion() {
    if (this.state !== 'QUESTION_ACTIVE') return;
    this.clearAuto();
    const q = this.current;
    this.state = 'REVEAL';
    this.correctIdx = q.correct;
    const settings = Object.assign({}, this.settings(), { TIME_LIMIT: this.qLimit });
    const dist = [0, 0, 0, 0];
    const pool = this.scoringPool();
    for (const p of pool) if (p.current) dist[p.current.optionIndex]++;
    this.dist = dist;
    for (const p of pool) {
      const correct = !!p.current && p.current.optionIndex === q.correct;
      const points = scoreAnswer({
        isCorrect: correct,
        answerElapsedSeconds: p.current ? p.current.elapsedMs / 1000 : this.qLimit,
        settings
      });
      if (correct) p.cumTimeMs += p.current.elapsedMs;
      p.score += points;
      p.lastResult = {
        correct,
        points,
        answered: !!p.current,
        chosenIndex: p.current ? p.current.optionIndex : -1
      };
    }
    const { ranks } = rankPlayers(this.connected());
    for (const p of pool) if (p.lastResult) p.lastResult.rank = ranks.get(p.token) || 0;
    this.bus.questionEnd({ correctIndex: q.correct, distribution: dist });
    for (const p of this.eligible()) {
      if (p.socketId && p.lastResult) {
        this.bus.personalResult(p, {
          correct: p.lastResult.correct,
          points: p.lastResult.points,
          totalScore: p.score,
          rank: p.lastResult.rank,
          answered: p.lastResult.answered,
          chosenIndex: p.lastResult.chosenIndex
        });
      }
    }
    if (this.settings().autoAdvance) this.autoTimer = setTimeout(() => this.showLeaderboard(), 5000);
  }

  showLeaderboard() {
    if (this.state !== 'REVEAL') return;
    this.clearAuto();
    const { ranks } = rankPlayers(this.connected());
    this.deltas = new Map();
    for (const p of this.connected()) {
      const prev = this.prevRanks ? this.prevRanks.get(p.token) : null;
      this.deltas.set(p.token, prev ? prev - ranks.get(p.token) : null);
    }
    this.prevRanks = ranks;
    this.state = 'LEADERBOARD';
    this.bus.leaderboard(this.leaderboardPayload());
    for (const p of this.connected()) {
      if (p.socketId) this.bus.personalRank(p, { rank: ranks.get(p.token), score: p.score, phase: 'leaderboard' });
    }
    if (this.settings().autoAdvance) this.autoTimer = setTimeout(() => this.next(), 5000);
  }

  leaderboardPayload() {
    const { list, ranks } = rankPlayers(this.connected());
    return {
      standings: list.map(p => ({
        rank: ranks.get(p.token),
        nickname: p.nickname,
        score: p.score,
        delta: this.deltas.has(p.token) ? this.deltas.get(p.token) : null
      })),
      afterQuestion: this.idx + 1,
      totalQuestions: this.order.length,
      remaining: Math.max(0, this.order.length - this.idx - 1)
    };
  }

  next() {
    if (this.state !== 'LEADERBOARD') return;
    this.nextQuestion();
  }

  skip() {
    if (this.state !== 'QUESTION_ACTIVE') return;
    this.nextQuestion(); // no scoring, straight to next
  }

  endRound() {
    this.endQuestion(); // scores answers received so far
  }

  podium() {
    this.clearAuto();
    this.state = 'PODIUM';
    const payload = this.podiumPayload();
    this.bus.gameOver(payload);
    const { ranks } = rankPlayers(this.connected());
    for (const p of this.connected()) {
      if (p.socketId) this.bus.personalRank(p, { rank: ranks.get(p.token), score: p.score, phase: 'podium' });
    }
  }

  podiumPayload() {
    const { list, ranks } = rankPlayers(this.connected());
    const standings = list.map(p => ({ rank: ranks.get(p.token), nickname: p.nickname, score: p.score }));
    return { podium: standings.slice(0, 3), standings };
  }

  endGame() {
    if (this.state === 'PODIUM' || this.state === 'LOBBY') return;
    this.podium();
  }

  newGame() {
    if (this.state !== 'PODIUM') return;
    this.state = 'LOBBY';
    this.order = [];
    this.idx = -1;
    this.current = null;
    // PIN and players are kept; scores reset when the next game starts.
    this.bus.stateChange('LOBBY');
    this.bus.playersChanged({});
  }

  // ---- snapshots for (re)connecting clients ----

  presenterSnapshot() {
    const snap = {
      state: this.state,
      pin: this.pin,
      players: this.connected()
        .sort((a, b) => a.joinedAt - b.joinedAt)
        .map(p => ({ nickname: p.nickname })),
      sound: this.settings().sound,
      accent: this.settings().accent,
      bankName: this.settings().bankName
    };
    if (this.state === 'QUESTION_ACTIVE' && this.current) {
      snap.question = this.questionStartPayload(Date.now() - this.qStart);
      snap.answered = this.answeredCount();
    } else if (this.state === 'REVEAL' && this.current) {
      snap.question = this.questionStartPayload(this.qLimit * 1000);
      snap.reveal = { correctIndex: this.correctIdx, distribution: this.dist };
    } else if (this.state === 'LEADERBOARD') {
      snap.leaderboard = this.leaderboardPayload();
    } else if (this.state === 'PODIUM') {
      snap.podium = this.podiumPayload();
    }
    return snap;
  }

  adminSnapshot() {
    const { ranks } = rankPlayers([...this.players.values()]);
    return {
      state: this.state,
      pin: this.pin,
      qNum: this.idx + 1,
      qTotal: this.order.length,
      players: [...this.players.values()]
        .sort((a, b) => b.score - a.score || a.joinedAt - b.joinedAt)
        .map(p => ({
          token: p.token,
          nickname: p.nickname,
          score: p.score,
          connected: p.connected,
          answered: !!p.current,
          rank: ranks.get(p.token)
        })),
      connectedCount: this.connected().length,
      settings: this.settings(),
      bank: this.repo.counts()
    };
  }

  playerSnapshot(p) {
    const snap = {
      token: p.token,
      nickname: p.nickname,
      state: this.state,
      score: p.score,
      playerCount: this.connected().length,
      eligibleFrom: p.eligibleFrom,
      currentIndex: this.idx,
      sound: this.settings().sound,
      accent: this.settings().accent
    };
    const { ranks } = rankPlayers(this.connected());
    snap.rank = ranks.get(p.token) || null;
    const eligibleNow = p.eligibleFrom <= this.idx;
    if (this.state === 'QUESTION_ACTIVE' && this.current && eligibleNow) {
      snap.question = this.questionStartPayload(Date.now() - this.qStart);
      snap.lockedIndex = p.current ? p.current.optionIndex : null;
    } else if (this.state === 'REVEAL' && eligibleNow && p.lastResult) {
      snap.lastResult = {
        correct: p.lastResult.correct,
        points: p.lastResult.points,
        totalScore: p.score,
        rank: p.lastResult.rank,
        answered: p.lastResult.answered,
        chosenIndex: p.lastResult.chosenIndex
      };
    }
    return snap;
  }
}

function shuffle(a) {
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

module.exports = { GameSession };
