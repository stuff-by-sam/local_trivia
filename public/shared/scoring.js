'use strict';

/* The scoring formula, shared verbatim between the server (which awards the
   points) and the admin console (which previews them). Keeping one copy means
   the "CORRECT AT 50s → N PTS" preview can never drift from what players get.

   Loaded as a plain <script> in the browser and require()d on the server, so
   it must not use module syntax beyond the guarded export at the bottom. */

// TIME_LIMIT is the effective limit for the question being scored — a
// per-question override when set, otherwise the global default.
function scoreAnswer({ isCorrect, answerElapsedSeconds, settings }) {
  const { MAX_POINTS, TIME_LIMIT, MIN_CORRECT_FRACTION, WRONG_ANSWER_POINTS } = settings;
  if (!isCorrect) return WRONG_ANSWER_POINTS; // also covers "no answer"
  const remaining = Math.max(0, Math.min(TIME_LIMIT, TIME_LIMIT - answerElapsedSeconds));
  const fraction = MIN_CORRECT_FRACTION + (1 - MIN_CORRECT_FRACTION) * (remaining / TIME_LIMIT);
  return Math.round(MAX_POINTS * fraction);
}

if (typeof module !== 'undefined' && module.exports) module.exports = { scoreAnswer };
