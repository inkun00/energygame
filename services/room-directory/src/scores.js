const games = new Set(["solar_align", "wind_rhythm", "grid_balance", "standby_hunt",
  "hydro_gate", "energy_sort", "battery_relay", "eco_commute", "heat_leak"]);
const adjectives = ["햇살", "바람", "물결", "새싹", "초록", "무지개", "구름", "별빛"];
const animals = ["여우", "토끼", "수달", "다람쥐", "고슴도치", "너구리", "고양이", "부엉이"];
export const scoreTicketLifetime = 15 * 60;

export function scoreAlias(hash) {
  return adjectives[parseInt(hash.slice(0, 2), 16) % adjectives.length]
    + animals[parseInt(hash.slice(2, 4), 16) % animals.length] + " " + hash.slice(4, 9).toUpperCase();
}

// These bounds mirror the board's score accounting. Server time is independent
// of the browser clock. Hydro can genuinely end early when the reservoir floods.
export function validFinish(game, score, stats, elapsed) {
  if (!Number.isInteger(score) || score < 0 || score > 5000 || !stats || stats.active_input !== true) return false;
  const {attempts, correct} = stats;
  if (!Number.isInteger(attempts) || attempts < 1 || attempts > 4096 ||
      !Number.isInteger(correct) || correct < 0 || correct > attempts) return false;
  const duration = game === "eco_commute" ? 60 : 30;
  if (elapsed < (game === "hydro_gate" ? 3 : duration - 3) || elapsed > scoreTicketLifetime) return false;
  switch (game) {
    case "solar_align": return score <= correct * 100 + (attempts - correct) * 30;
    case "wind_rhythm": return correct <= 2 && score <= attempts * 75;
    case "grid_balance": return attempts <= Math.ceil(duration / 4.2) && score <= 3000;
    case "standby_hunt": return score <= correct * 120;
    case "hydro_gate": return score <= Math.ceil(21 * 1000 / 3600 * 12 * Math.min(elapsed + 3, duration + 1));
    case "energy_sort": return score <= correct * 90;
    case "battery_relay": return correct <= attempts - correct && score <= correct * 80 + (attempts - correct) * 20;
    case "eco_commute": return score <= correct * 45 * 27;
    case "heat_leak": return correct <= 15 && score <= correct * 110;
    default: return false;
  }
}

async function digest(value) {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(bytes), b => b.toString(16).padStart(2, "0")).join("");
}

async function board(db, game, owner) {
  const rows = await db.prepare(
    "SELECT owner, score FROM arcade_bests WHERE game=?1 ORDER BY score DESC, owner LIMIT 10"
  ).bind(game).all();
  let rank = 0, previous = -1;
  const entries = rows.results.map(({owner: id, score}, idx) => {
    if (score !== previous) rank = idx + 1;
    previous = score;
    return {rank, alias: scoreAlias(id), score, mine: id === owner};
  });
  const personal = owner && await db.prepare(
    `SELECT b.score, 1+(SELECT COUNT(*) FROM arcade_bests h WHERE h.game=b.game AND h.score>b.score) AS rank
     FROM arcade_bests b WHERE b.game=?1 AND b.owner=?2`
  ).bind(game, owner).first();
  return {game_id: game, entries, personal_best: personal?.score || 0, has_personal_best: Boolean(personal), personal_rank: personal?.rank || 0};
}

// Both storage backends accept exactly the same public protocol and bounds.
export async function parseScoreRequest(request, parts) {
  const [,game, action, id] = parts;
  if (!games.has(game)) return {error: "unknown_game", status: 404};
  const header = request.headers.get("Authorization") || "";
  if (header && !/^Bearer [a-f0-9]{64}$/.test(header)) return {error: "identity", status: 401};
  const owner = header ? await digest(header.slice(7)) : "";
  if (request.method === "GET" && parts.length === 2) return {type: "board", game, owner};
  if (request.method !== "POST" || action !== "attempts" || ![3, 4].includes(parts.length)) return {error: "not_found", status: 404};
  if (!owner) return {error: "identity", status: 401};
  if (Number(request.headers.get("Content-Length")) > 1024) return {error: "too_large", status: 413};
  let body;
  try {
    const reader = request.body?.getReader();
    if (!reader) return {error: "invalid_body", status: 400};
    const bytes = new Uint8Array(1024);
    let length = 0;
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      if (length + chunk.value.byteLength > bytes.length) {
        await reader.cancel();
        return {error: "too_large", status: 413};
      }
      bytes.set(chunk.value, length);
      length += chunk.value.byteLength;
    }
    body = JSON.parse(new TextDecoder().decode(bytes.subarray(0, length)));
  } catch { return {error: "invalid_json", status: 400}; }
  if (!body || Array.isArray(body) || typeof body !== "object") return {error: "invalid_body", status: 400};
  const now = Math.floor(Date.now() / 1000);
  if (parts.length === 3) {
    if (typeof body.round_key !== "string" || !/^[a-f0-9]{32}$/.test(body.round_key)) return {error: "round_key", status: 400};
    const ip = request.headers.get("CF-Connecting-IP") || "local";
    const network = await digest(Math.floor(now / 86400) + "/" + ip);
    return {type: "start", game, owner, body, now, network};
  }
  if (!/^[a-f0-9]{32}$/.test(id)) return {error: "unknown_attempt", status: 404};
  return {type: "finish", game, owner, body, now, id};
}

export async function scoresRoute(request, db, parts, json) {
  const result = await parseScoreRequest(request, parts);
  if (result.error) return json({error: result.error}, result.status);
  const {type, game, owner, body, now, network, id} = result;
  if (type === "board") return json(await board(db, game, owner));
  if (type === "start") {
    const attempt = crypto.randomUUID().replaceAll("-", "");
    await db.prepare("DELETE FROM score_attempts WHERE started < ?1").bind(now - 86400).run();
    await db.prepare(
      `INSERT OR IGNORE INTO score_attempts(id,owner,game,round_key,started,network)
       SELECT ?1,?2,?3,?4,?5,?6 WHERE
       (SELECT COUNT(*) FROM score_attempts WHERE owner=?2 AND started>?7)<5 AND
       (SELECT COUNT(*) FROM score_attempts WHERE network=?6 AND started>?7)<120`
    ).bind(attempt, owner, game, body.round_key, now, network, now - 60).run();
    const row = await db.prepare(`SELECT id,game,started,score,EXISTS(SELECT 1 FROM score_attempts n WHERE n.owner=a.owner AND n.rowid>a.rowid) AS superseded
      FROM score_attempts a WHERE owner=?1 AND round_key=?2`).bind(owner, body.round_key).first();
    if (!row) return json({error: "too_many_starts"}, 429);
    if (row.game !== game || now - row.started > scoreTicketLifetime || (row.superseded && row.score === null)) return json({error: "stale_round"}, 409);
    return json({attempt_id: row.id, expires_at: row.started + scoreTicketLifetime}, row.id === attempt ? 201 : 200);
  }
  const row = await db.prepare("SELECT score,started FROM score_attempts WHERE id=?1 AND owner=?2 AND game=?3").bind(id, owner, game).first();
  if (!row) return json({error: "unknown_attempt"}, 404);
  if (row.score !== null) return row.score === body.score ? json(await board(db, game, owner)) : json({error: "already_finished"}, 409);
  if (now - row.started > scoreTicketLifetime) return json({error: "expired"}, 410);
  if (!validFinish(game, body.score, body.stats, now - row.started)) return json({error: "invalid_record"}, 422);
  // Both statements share one D1 transaction. A retry may only promote the
  // score that actually won the one-use attempt, including across Worker isolates.
  await db.batch([
    db.prepare(`UPDATE score_attempts SET score=?1 WHERE id=?2 AND score IS NULL AND NOT EXISTS
      (SELECT 1 FROM score_attempts n WHERE n.owner=score_attempts.owner AND n.rowid>score_attempts.rowid)`).bind(body.score, id),
    db.prepare(`INSERT INTO arcade_bests(game,owner,score) SELECT game,owner,score FROM score_attempts WHERE id=?1 AND score IS NOT NULL
       ON CONFLICT(game,owner) DO UPDATE SET score=MAX(arcade_bests.score,excluded.score)`).bind(id),
  ]);
  const saved = await db.prepare("SELECT score FROM score_attempts WHERE id=?1").bind(id).first();
  if (saved.score !== body.score) return json({error: "already_finished"}, 409);
  return json(await board(db, game, owner));
}
