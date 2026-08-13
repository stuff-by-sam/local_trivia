'use strict';

const fs = require('node:fs');
const path = require('node:path');
const Database = require('better-sqlite3');

// Overridable so tests (and a second instance on another port) get their own
// bank instead of writing over the one you spent the evening curating.
const DB_PATH = process.env.TRIVIA_DB || path.join(__dirname, 'db.sqlite');
const SEED_PATH = path.join(__dirname, '..', 'seed_questions.json');

const db = new Database(DB_PATH);
db.pragma('journal_mode = WAL');

db.exec(`
  CREATE TABLE IF NOT EXISTS questions (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    text          TEXT    NOT NULL,
    image_path    TEXT,
    options       TEXT    NOT NULL,
    correct_index INTEGER NOT NULL,
    time_limit    INTEGER,
    category      TEXT,
    included      INTEGER NOT NULL DEFAULT 1,
    position      INTEGER NOT NULL,
    created_at    TEXT    NOT NULL
  );
  CREATE TABLE IF NOT EXISTS settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
  );
`);

const ACCENT_DEFAULT = '#56ff8a';
const BANK_NAME_DEFAULT = 'LOCAL BROADCAST';
const BANK_NAME_MAX = 28; // longer than this wraps the presenter header

const DEFAULT_SETTINGS = {
  MAX_POINTS: 1000,
  TIME_LIMIT: 100,
  MIN_CORRECT_FRACTION: 0,
  WRONG_ANSWER_POINTS: 0,
  shuffle: true,
  autoAdvance: false,
  sound: true,
  accent: ACCENT_DEFAULT,
  bankName: BANK_NAME_DEFAULT
};

function rowToQuestion(row) {
  return {
    id: row.id,
    text: row.text,
    imagePath: row.image_path || null,
    options: JSON.parse(row.options),
    correct: row.correct_index,
    time: row.time_limit || null,
    category: row.category || 'GENERAL',
    included: !!row.included,
    position: row.position
  };
}

// Returns null when valid, or an error string matching the admin UI copy.
function validate(q) {
  if (!q || typeof q.text !== 'string' || !q.text.trim()) return 'QUESTION TEXT REQUIRED';
  if (!Array.isArray(q.options) || q.options.length !== 4 || q.options.some(o => typeof o !== 'string' || !o.trim()))
    return 'ALL FOUR OPTIONS REQUIRED';
  const c = Number(q.correct);
  if (!Number.isInteger(c) || c < 0 || c > 3) return 'CORRECT OPTION MUST BE A–D';
  if (q.time != null && q.time !== '') {
    const t = Number(q.time);
    if (!Number.isInteger(t) || t < 5 || t > 600) return 'TIME LIMIT MUST BE 5–600s (OR BLANK FOR DEFAULT)';
  }
  return null;
}

function normalize(q) {
  return {
    text: q.text.trim(),
    options: q.options.map(o => o.trim()),
    correct: Number(q.correct),
    category: ((q.category || 'GENERAL').trim() || 'GENERAL').toUpperCase(),
    time: q.time != null && q.time !== '' ? Number(q.time) : null,
    imagePath: q.imagePath || null
  };
}

function nextPosition() {
  return (db.prepare('SELECT COALESCE(MAX(position), 0) AS m FROM questions').get().m || 0) + 1;
}

const insertStmt = db.prepare(`
  INSERT INTO questions (text, image_path, options, correct_index, time_limit, category, included, position, created_at)
  VALUES (@text, @imagePath, @options, @correct, @time, @category, 1, @position, @createdAt)
`);

function insert(q) {
  const n = normalize(q);
  insertStmt.run({
    text: n.text,
    imagePath: n.imagePath,
    options: JSON.stringify(n.options),
    correct: n.correct,
    time: n.time,
    category: n.category,
    position: nextPosition(),
    createdAt: new Date().toISOString()
  });
}

function list() {
  return db.prepare('SELECT * FROM questions ORDER BY position').all().map(rowToQuestion);
}

function get(id) {
  const row = db.prepare('SELECT * FROM questions WHERE id = ?').get(id);
  return row ? rowToQuestion(row) : null;
}

function update(id, q) {
  const n = normalize(q);
  db.prepare(`
    UPDATE questions SET text=@text, image_path=@imagePath, options=@options,
      correct_index=@correct, time_limit=@time, category=@category WHERE id=@id
  `).run({ id, text: n.text, imagePath: n.imagePath, options: JSON.stringify(n.options), correct: n.correct, time: n.time, category: n.category });
}

function remove(id) {
  db.prepare('DELETE FROM questions WHERE id = ?').run(id);
}

// Clears the whole bank. Returns how many rows went, so the admin console can
// report it. Uploaded images in uploads/ are left on disk.
function removeAll() {
  const { n } = db.prepare('SELECT COUNT(*) AS n FROM questions').get();
  db.prepare('DELETE FROM questions').run();
  return n;
}

function toggleInclude(id) {
  db.prepare('UPDATE questions SET included = 1 - included WHERE id = ?').run(id);
}

const move = db.transaction((id, dir) => {
  const rows = db.prepare('SELECT id, position FROM questions ORDER BY position').all();
  const i = rows.findIndex(r => r.id === id);
  const j = i + (dir < 0 ? -1 : 1);
  if (i < 0 || j < 0 || j >= rows.length) return;
  const set = db.prepare('UPDATE questions SET position = ? WHERE id = ?');
  set.run(rows[j].position, rows[i].id);
  set.run(rows[i].position, rows[j].id);
});

const importMany = db.transaction(rows => {
  rows.forEach(insert);
});

function seedIfEmpty() {
  if (db.prepare('SELECT COUNT(*) AS n FROM questions').get().n > 0) return false;
  seedSamples();
  return true;
}

const seedSamples = db.transaction(() => {
  db.prepare('DELETE FROM questions').run();
  const seed = JSON.parse(fs.readFileSync(SEED_PATH, 'utf8'));
  seed.forEach(q => insert({ text: q.text, options: q.options, correct: q.correct, category: q.category, time: q.time_limit }));
});

function counts() {
  const row = db.prepare('SELECT COUNT(*) AS saved, SUM(included) AS included FROM questions').get();
  return { saved: row.saved, included: row.included || 0 };
}

function includedQuestions() {
  return db.prepare('SELECT * FROM questions WHERE included = 1 ORDER BY position').all().map(rowToQuestion);
}

// ---- settings (persisted as JSON in the settings table) ----

let settingsCache = null;

function getSettings() {
  if (!settingsCache) {
    const row = db.prepare("SELECT value FROM settings WHERE key = 'game'").get();
    let stored = {};
    try { stored = row ? JSON.parse(row.value) : {}; } catch { stored = {}; }
    settingsCache = Object.assign({}, DEFAULT_SETTINGS, stored);
  }
  return settingsCache;
}

// Clamping mirrors the design reference: out-of-range values reset to defaults.
function saveSettings(patch) {
  const s = Object.assign({}, getSettings());
  if ('MAX_POINTS' in patch) { const v = Math.round(Number(patch.MAX_POINTS)); s.MAX_POINTS = v >= 10 && v <= 100000 ? v : DEFAULT_SETTINGS.MAX_POINTS; }
  if ('TIME_LIMIT' in patch) { const v = Math.round(Number(patch.TIME_LIMIT)); s.TIME_LIMIT = v >= 5 && v <= 600 ? v : DEFAULT_SETTINGS.TIME_LIMIT; }
  if ('WRONG_ANSWER_POINTS' in patch) { const v = Math.round(Number(patch.WRONG_ANSWER_POINTS)); s.WRONG_ANSWER_POINTS = v >= 0 && v <= 100000 ? v : DEFAULT_SETTINGS.WRONG_ANSWER_POINTS; }
  if ('MIN_CORRECT_FRACTION' in patch) { const v = Number(patch.MIN_CORRECT_FRACTION); s.MIN_CORRECT_FRACTION = v >= 0 && v <= 0.9 ? Math.round(v * 100) / 100 : 0; }
  if ('shuffle' in patch) s.shuffle = !!patch.shuffle;
  if ('autoAdvance' in patch) s.autoAdvance = !!patch.autoAdvance;
  if ('sound' in patch) s.sound = !!patch.sound;
  if ('accent' in patch) {
    const v = String(patch.accent || '').trim();
    s.accent = /^#[0-9a-fA-F]{6}$/.test(v) ? v.toLowerCase() : ACCENT_DEFAULT;
  }
  if ('bankName' in patch) {
    // Presenter shows it verbatim in a fixed-width header, so cap and upper-case.
    const v = String(patch.bankName == null ? '' : patch.bankName).trim().slice(0, BANK_NAME_MAX);
    s.bankName = v ? v.toUpperCase() : BANK_NAME_DEFAULT;
  }
  settingsCache = s;
  db.prepare("INSERT INTO settings (key, value) VALUES ('game', @v) ON CONFLICT(key) DO UPDATE SET value=@v")
    .run({ v: JSON.stringify(s) });
  return s;
}

module.exports = {
  validate, insert, list, get, update, remove, removeAll, toggleInclude, move,
  importMany, seedIfEmpty, seedSamples, counts, includedQuestions,
  getSettings, saveSettings
};
