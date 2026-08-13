'use strict';

// The points formula itself lives in public/shared/scoring.js so the admin
// console previews exactly what the server awards. Re-exported here so the
// rest of the server has one scoring import.
const { scoreAnswer } = require('../public/shared/scoring');

// Ranking: total points desc; tiebreak = lower cumulative correct-answer
// response time; equal on both → shared rank.
function rankPlayers(players) {
  const list = players
    .slice()
    .sort((a, b) => b.score - a.score || a.cumTimeMs - b.cumTimeMs || a.nickname.localeCompare(b.nickname));
  const ranks = new Map();
  let prev = null;
  let prevRank = 0;
  list.forEach((p, i) => {
    const rank = prev && p.score === prev.score && p.cumTimeMs === prev.cumTimeMs ? prevRank : i + 1;
    ranks.set(p.token, rank);
    prev = p;
    prevRank = rank;
  });
  return { list, ranks };
}

module.exports = { scoreAnswer, rankPlayers };
