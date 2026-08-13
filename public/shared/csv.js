'use strict';

/* CSV → question rows. Pure parsing, no DOM: admin.js owns the UI wiring.

   Expected columns (header row optional):
     question, option_a, option_b, option_c, option_d, correct, category, time_limit
   `correct` accepts A–D, 1–4, or the literal option text. */

const CSV_SAMPLE = [
  'question,option_a,option_b,option_c,option_d,correct,category,time_limit',
  'Which ocean is the deepest?,Atlantic,Indian,Pacific,Arctic,C,GEOGRAPHY,60',
  '"What is 7 × 8?",54,56,58,64,B,MATH,30',
  'Who painted the Mona Lisa?,Van Gogh,Da Vinci,Picasso,Rembrandt,B,ART,',
  'Which gas do plants absorb from the air?,Oxygen,Nitrogen,Carbon dioxide,Helium,C,SCIENCE,'
].join('\n');

// TIME_MIN / TIME_MAX come from common.js, which every page loads first.

// RFC-4180-ish reader: handles quoted fields, escaped "" and CRLF.
function splitRows(text) {
  const rows = [];
  let row = [''];
  let field = 0;
  let inQuotes = false;

  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (inQuotes) {
      if (ch !== '"') { row[field] += ch; continue; }
      if (text[i + 1] === '"') { row[field] += '"'; i++; } else inQuotes = false;
    } else if (ch === '"') {
      inQuotes = true;
    } else if (ch === ',') {
      row.push('');
      field++;
    } else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && text[i + 1] === '\n') i++;
      rows.push(row);
      row = [''];
      field = 0;
    } else {
      row[field] += ch;
    }
  }
  rows.push(row);
  return rows.filter(r => r.some(c => c.trim() !== ''));
}

// Exported files often carry a title line above the real header, e.g.
//   marvel_movie_trivia
//   question,option_a,…,correct,category,time_limit
// so scan the first few rows for the header instead of only checking row 0.
// Anything above it is treated as preamble and skipped silently.
const HEADER_SCAN_ROWS = 5;
const QUESTION_HEADERS = ['question', 'text', 'prompt'];

function looksLikeHeader(row) {
  const cells = row.map(c => c.trim().toLowerCase());
  return cells.includes('correct') && cells.some(c => QUESTION_HEADERS.includes(c));
}

// First data row: just past the header if there is one, else the very top.
function firstDataRow(rows) {
  const limit = Math.min(rows.length, HEADER_SCAN_ROWS);
  for (let i = 0; i < limit; i++) if (looksLikeHeader(rows[i])) return i + 1;
  return 0;
}

/* Numeric answer keys come in two flavours in the wild: 1–4 (the documented
   format) and 0–3 (zero-indexed exports). Guessing per row is impossible, so
   decide once for the whole file from unambiguous evidence:
     a 0 anywhere  -> must be zero-indexed (1-based never emits 0)
     a 4 anywhere  -> must be one-indexed  (zero-indexed never emits 4)
   With neither, the file only uses 1/2/3 and is genuinely ambiguous, so fall
   back to the documented 1–4 reading. Detection can only ever rescue rows
   that would otherwise have been rejected outright. */
function detectNumericBase(rows) {
  const nums = new Set();
  for (const cells of rows) {
    const v = (cells[5] || '').trim();
    if (/^\d+$/.test(v)) nums.add(Number(v));
  }
  if (nums.has(0)) return 0;
  if (nums.has(4)) return 1;
  return 1;
}

// Returns the 0-based option index, or -1 if `raw` names no option.
function resolveCorrect(raw, options, numericBase) {
  const trimmed = (raw || '').trim();
  const upper = trimmed.toUpperCase();
  if (/^[A-D]$/.test(upper)) return upper.charCodeAt(0) - 65;
  if (/^\d+$/.test(trimmed)) return Number(trimmed) - numericBase;
  return options.findIndex(o => o.toLowerCase() === trimmed.toLowerCase());
}

// → { questions, errors, notes }. Bad rows are skipped, never fatal; `notes`
// carries non-fatal observations worth showing the operator.
function parseQuestionCsv(text) {
  const rows = splitRows(text || '');
  const questions = [];
  const errors = [];
  const notes = [];
  const start = firstDataRow(rows);

  const dataRows = rows.slice(start).map(r => r.map(c => c.trim()));
  const numericBase = detectNumericBase(dataRows);
  if (numericBase === 0) {
    notes.push('ZERO-INDEXED ANSWER KEYS DETECTED (0–3) — MAPPED A–D');
  }

  for (let i = start; i < rows.length; i++) {
    const cells = rows[i].map(c => c.trim());
    const line = i + 1;

    if (cells.length < 6) {
      errors.push(`LINE ${line}: NEED ≥6 COLUMNS (GOT ${cells.length})`);
      continue;
    }
    const [text_, a, b, c, d, correctRaw] = cells;
    if (!text_ || !a || !b || !c || !d) {
      errors.push(`LINE ${line}: EMPTY QUESTION/OPTION FIELD`);
      continue;
    }
    const options = [a, b, c, d];
    const correct = resolveCorrect(correctRaw, options, numericBase);
    if (correct < 0 || correct > 3) {
      errors.push(`LINE ${line}: CORRECT '${correctRaw}' NOT A–D / 1–4 / OPTION TEXT`);
      continue;
    }

    let time = null;
    if (cells[7]) {
      const t = parseInt(cells[7], 10);
      if (t >= TIME_MIN && t <= TIME_MAX) time = t;
      else errors.push(`LINE ${line}: TIME_LIMIT MUST BE ${TIME_MIN}–${TIME_MAX} (IGNORED)`);
    }

    questions.push({
      text: text_,
      options,
      correct,
      category: (cells[6] || 'GENERAL').toUpperCase(),
      time
    });
  }

  return { questions, errors, notes };
}
