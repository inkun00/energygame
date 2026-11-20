// src/scores.js
var games = /* @__PURE__ */ new Set([
  "solar_align",
  "wind_rhythm",
  "grid_balance",
  "standby_hunt",
  "hydro_gate",
  "energy_sort",
  "battery_relay",
  "eco_commute",
  "heat_leak"
]);
var adjectives = ["\uD587\uC0B4", "\uBC14\uB78C", "\uBB3C\uACB0", "\uC0C8\uC2F9", "\uCD08\uB85D", "\uBB34\uC9C0\uAC1C", "\uAD6C\uB984", "\uBCC4\uBE5B"];
var animals = ["\uC5EC\uC6B0", "\uD1A0\uB07C", "\uC218\uB2EC", "\uB2E4\uB78C\uC950", "\uACE0\uC2B4\uB3C4\uCE58", "\uB108\uAD6C\uB9AC", "\uACE0\uC591\uC774", "\uBD80\uC5C9\uC774"];
var scoreTicketLifetime = 15 * 60;
function scoreAlias(hash) {
  return adjectives[parseInt(hash.slice(0, 2), 16) % adjectives.length] + animals[parseInt(hash.slice(2, 4), 16) % animals.length] + " " + hash.slice(4, 9).toUpperCase();
}
function validFinish(game, score, stats, elapsed) {
  if (!Number.isInteger(score) || score < 0 || score > 5e3 || !stats || stats.active_input !== true) return false;
  const { attempts, correct } = stats;
  if (!Number.isInteger(attempts) || attempts < 1 || attempts > 4096 || !Number.isInteger(correct) || correct < 0 || correct > attempts) return false;
  const duration = game === "eco_commute" ? 60 : 30;
  if (elapsed < (game === "hydro_gate" ? 3 : duration - 3) || elapsed > scoreTicketLifetime) return false;
  switch (game) {
    case "solar_align":
      return score <= correct * 100 + (attempts - correct) * 30;
    case "wind_rhythm":
      return correct <= 2 && score <= attempts * 75;
    case "grid_balance":
      return attempts <= Math.ceil(duration / 4.2) && score <= 3e3;
    case "standby_hunt":
      return score <= correct * 120;
    case "hydro_gate":
      return score <= Math.ceil(21 * 1e3 / 3600 * 12 * Math.min(elapsed + 3, duration + 1));
    case "energy_sort":
      return score <= correct * 90;
    case "battery_relay":
      return correct <= attempts - correct && score <= correct * 80 + (attempts - correct) * 20;
    case "eco_commute":
      return score <= correct * 45 * 27;
    case "heat_leak":
      return correct <= 15 && score <= correct * 110;
    default:
      return false;
  }
}
async function digest(value) {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(bytes), (b) => b.toString(16).padStart(2, "0")).join("");
}
async function board(db, game, owner) {
  const rows = await db.prepare(
    "SELECT owner, score FROM arcade_bests WHERE game=?1 ORDER BY score DESC, owner LIMIT 10"
  ).bind(game).all();
  let rank = 0, previous = -1;
  const entries = rows.results.map(({ owner: id, score }, idx) => {
    if (score !== previous) rank = idx + 1;
    previous = score;
    return { rank, alias: scoreAlias(id), score, mine: id === owner };
  });
  const personal = owner && await db.prepare(
    `SELECT b.score, 1+(SELECT COUNT(*) FROM arcade_bests h WHERE h.game=b.game AND h.score>b.score) AS rank
     FROM arcade_bests b WHERE b.game=?1 AND b.owner=?2`
  ).bind(game, owner).first();
  return { game_id: game, entries, personal_best: personal?.score || 0, has_personal_best: Boolean(personal), personal_rank: personal?.rank || 0 };
}
async function parseScoreRequest(request, parts) {
  const [, game, action, id] = parts;
  if (!games.has(game)) return { error: "unknown_game", status: 404 };
  const header = request.headers.get("Authorization") || "";
  if (header && !/^Bearer [a-f0-9]{64}$/.test(header)) return { error: "identity", status: 401 };
  const owner = header ? await digest(header.slice(7)) : "";
  if (request.method === "GET" && parts.length === 2) return { type: "board", game, owner };
  if (request.method !== "POST" || action !== "attempts" || ![3, 4].includes(parts.length)) return { error: "not_found", status: 404 };
  if (!owner) return { error: "identity", status: 401 };
  if (Number(request.headers.get("Content-Length")) > 1024) return { error: "too_large", status: 413 };
  let body;
  try {
    const reader = request.body?.getReader();
    if (!reader) return { error: "invalid_body", status: 400 };
    const bytes = new Uint8Array(1024);
    let length = 0;
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      if (length + chunk.value.byteLength > bytes.length) {
        await reader.cancel();
        return { error: "too_large", status: 413 };
      }
      bytes.set(chunk.value, length);
      length += chunk.value.byteLength;
    }
    body = JSON.parse(new TextDecoder().decode(bytes.subarray(0, length)));
  } catch {
    return { error: "invalid_json", status: 400 };
  }
  if (!body || Array.isArray(body) || typeof body !== "object") return { error: "invalid_body", status: 400 };
  const now = Math.floor(Date.now() / 1e3);
  if (parts.length === 3) {
    if (typeof body.round_key !== "string" || !/^[a-f0-9]{32}$/.test(body.round_key)) return { error: "round_key", status: 400 };
    const ip = request.headers.get("CF-Connecting-IP") || "local";
    const network = await digest(Math.floor(now / 86400) + "/" + ip);
    return { type: "start", game, owner, body, now, network };
  }
  if (!/^[a-f0-9]{32}$/.test(id)) return { error: "unknown_attempt", status: 404 };
  return { type: "finish", game, owner, body, now, id };
}
async function scoresRoute(request, db, parts, json2) {
  const result = await parseScoreRequest(request, parts);
  if (result.error) return json2({ error: result.error }, result.status);
  const { type, game, owner, body, now, network, id } = result;
  if (type === "board") return json2(await board(db, game, owner));
  if (type === "start") {
    const attempt = crypto.randomUUID().replaceAll("-", "");
    await db.prepare("DELETE FROM score_attempts WHERE started < ?1").bind(now - 86400).run();
    await db.prepare(
      `INSERT OR IGNORE INTO score_attempts(id,owner,game,round_key,started,network)
       SELECT ?1,?2,?3,?4,?5,?6 WHERE
       (SELECT COUNT(*) FROM score_attempts WHERE owner=?2 AND started>?7)<5 AND
       (SELECT COUNT(*) FROM score_attempts WHERE network=?6 AND started>?7)<120`
    ).bind(attempt, owner, game, body.round_key, now, network, now - 60).run();
    const row2 = await db.prepare(`SELECT id,game,started,score,EXISTS(SELECT 1 FROM score_attempts n WHERE n.owner=a.owner AND n.rowid>a.rowid) AS superseded
      FROM score_attempts a WHERE owner=?1 AND round_key=?2`).bind(owner, body.round_key).first();
    if (!row2) return json2({ error: "too_many_starts" }, 429);
    if (row2.game !== game || now - row2.started > scoreTicketLifetime || row2.superseded && row2.score === null) return json2({ error: "stale_round" }, 409);
    return json2({ attempt_id: row2.id, expires_at: row2.started + scoreTicketLifetime }, row2.id === attempt ? 201 : 200);
  }
  const row = await db.prepare("SELECT score,started FROM score_attempts WHERE id=?1 AND owner=?2 AND game=?3").bind(id, owner, game).first();
  if (!row) return json2({ error: "unknown_attempt" }, 404);
  if (row.score !== null) return row.score === body.score ? json2(await board(db, game, owner)) : json2({ error: "already_finished" }, 409);
  if (now - row.started > scoreTicketLifetime) return json2({ error: "expired" }, 410);
  if (!validFinish(game, body.score, body.stats, now - row.started)) return json2({ error: "invalid_record" }, 422);
  await db.batch([
    db.prepare(`UPDATE score_attempts SET score=?1 WHERE id=?2 AND score IS NULL AND NOT EXISTS
      (SELECT 1 FROM score_attempts n WHERE n.owner=score_attempts.owner AND n.rowid>score_attempts.rowid)`).bind(body.score, id),
    db.prepare(`INSERT INTO arcade_bests(game,owner,score) SELECT game,owner,score FROM score_attempts WHERE id=?1 AND score IS NOT NULL
       ON CONFLICT(game,owner) DO UPDATE SET score=MAX(arcade_bests.score,excluded.score)`).bind(id)
  ]);
  const saved = await db.prepare("SELECT score FROM score_attempts WHERE id=?1").bind(id).first();
  if (saved.score !== body.score) return json2({ error: "already_finished" }, 409);
  return json2(await board(db, game, owner));
}

// src/turn.js
var CREDENTIAL_TTL_SECONDS = 2 * 60 * 60;
var PROVIDER_TIMEOUT_MS = 1800;
var stunUrl = /^stun:stun\.cloudflare\.com:3478$/;
var turnUrl = /^(?:turn:turn\.cloudflare\.com:(?:3478\?transport=(?:udp|tcp)|443\?transport=udp|80\?transport=tcp)|turns:turn\.cloudflare\.com:(?:443|5349)\?transport=tcp)$/;
var tlsPrimary = "turns:turn.cloudflare.com:5349?transport=tcp";
var tlsAlternate = "turns:turn.cloudflare.com:443?transport=tcp";
var fetchErrorNames = /* @__PURE__ */ new Set(["TypeError", "NetworkError", "AbortError", "TimeoutError"]);
function browserIceServers(entries) {
  if (!Array.isArray(entries)) return [];
  const servers = [];
  for (const entry of entries.slice(0, 8)) {
    if (!entry || typeof entry !== "object") continue;
    const urls = (Array.isArray(entry.urls) ? entry.urls : [entry.urls]).slice(0, 16).filter((url) => typeof url === "string" && url.length < 160);
    const stun = urls.filter((url) => stunUrl.test(url));
    const turn = urls.filter((url) => turnUrl.test(url));
    if (stun.length) servers.push({ urls: stun });
    if (turn.length && [entry.username, entry.credential].every((value) => typeof value === "string" && value.length > 0 && value.length <= 512)) {
      if (turn.includes(tlsPrimary) && !turn.includes(tlsAlternate)) turn.push(tlsAlternate);
      servers.push({ urls: turn, username: entry.username, credential: entry.credential });
    }
  }
  return servers.some((server) => server.credential) ? servers : [];
}
function unavailable(env, stage, details = {}) {
  return { relay_status: {
    stage,
    id32: env.TURN_KEY_ID?.length === 32,
    token64: env.TURN_KEY_API_TOKEN?.length === 64,
    ...details
  } };
}
async function mintCredentials(env) {
  const url = `https://rtc.live.cloudflare.com/v1/turn/keys/${encodeURIComponent(env.TURN_KEY_ID)}/credentials/generate-ice-servers`;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), PROVIDER_TIMEOUT_MS);
  let receivedHeaders = false;
  try {
    const response = await fetch(url, {
      method: "POST",
      redirect: "manual",
      signal: controller.signal,
      headers: { Authorization: `Bearer ${env.TURN_KEY_API_TOKEN}`, "Content-Type": "application/json" },
      body: JSON.stringify({ ttl: CREDENTIAL_TTL_SECONDS })
    });
    receivedHeaders = true;
    if (!response.ok) return unavailable(env, "upstream_http", { code: response.status });
    const servers = browserIceServers((await response.json())?.iceServers);
    return servers.length ? { ice_servers: servers } : unavailable(env, "upstream_shape");
  } catch (error) {
    if (controller.signal.aborted || error?.name === "TimeoutError") return unavailable(env, "upstream_timeout");
    if (receivedHeaders) return unavailable(env, "upstream_shape");
    const error_name = fetchErrorNames.has(error?.name) ? error.name : "Other";
    return unavailable(env, "upstream_fetch", { error_name });
  } finally {
    clearTimeout(timeout);
  }
}
async function admissionIceServers(env, code, peerId, tokenHash) {
  if (!env.TURN_KEY_ID || !env.TURN_KEY_API_TOKEN) return unavailable(env, "bindings_absent");
  let stage = "storage_claim";
  try {
    const now = Math.floor(Date.now() / 1e3);
    const claim = crypto.randomUUID();
    const owner = await env.DB.prepare(`INSERT INTO webrtc_turn_grants
      (code, peer_id, token_hash, key_id, claim, usable_until, servers)
      SELECT code, peer_id, token_hash, ?4, ?5, ?6, NULL FROM webrtc_peers
        WHERE code=?1 AND peer_id=?2 AND token_hash=?3 AND expires_at>?7
      ON CONFLICT(code, peer_id) DO UPDATE SET token_hash=excluded.token_hash,
        key_id=excluded.key_id, claim=excluded.claim, usable_until=excluded.usable_until, servers=NULL
      WHERE token_hash != ?3 OR key_id != ?4 OR usable_until <= ?7
      RETURNING claim`).bind(code, peerId, tokenHash, env.TURN_KEY_ID, claim, now + 5, now).first();
    if (!owner) {
      stage = "storage_read";
      for (const delay of [0, 150, 350, 650, 950]) {
        if (delay) await new Promise((resolve) => setTimeout(resolve, delay));
        const row = await env.DB.prepare(`SELECT servers FROM webrtc_turn_grants
          WHERE code=?1 AND peer_id=?2 AND token_hash=?3 AND key_id=?4`).bind(code, peerId, tokenHash, env.TURN_KEY_ID).first();
        if (!row) return unavailable(env, "claim_stale");
        if (row.servers !== null) {
          const servers2 = browserIceServers(JSON.parse(row.servers));
          return servers2.length ? { ice_servers: servers2 } : unavailable(env, "cached_unavailable");
        }
      }
      return unavailable(env, "grant_pending");
    }
    const result = await mintCredentials(env);
    const servers = result.ice_servers || [];
    const usableUntil = now + (servers.length ? CREDENTIAL_TTL_SECONDS - 60 : 10);
    stage = "storage_save";
    const current = await env.DB.prepare(`UPDATE webrtc_turn_grants SET servers=?1, usable_until=?2
      WHERE code=?3 AND peer_id=?4 AND claim=?5 RETURNING claim`).bind(JSON.stringify(servers), usableUntil, code, peerId, claim).first();
    return current ? result : unavailable(env, "claim_stale");
  } catch {
    return unavailable(env, stage);
  }
}

// src/index.js
var ROOM_TTL_SECONDS = 90;
var WEBRTC_ROOM_TTL_SECONDS = 120;
var WEBRTC_MAX_PLAYERS = 4;
var WEBRTC_SIGNAL_TYPES = /* @__PURE__ */ new Set(["offer", "answer", "candidate"]);
var schemaReady = /* @__PURE__ */ new WeakSet();
var JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS"
};
function isValidRoomCode(value) {
  return typeof value === "string" && /^[1-9][0-9]{5}$/.test(value);
}
function isValidPort(value) {
  return Number.isInteger(value) && value >= 1024 && value <= 65535;
}
function isValidIpv4(value) {
  if (typeof value !== "string" || !/^\d{1,3}(\.\d{1,3}){3}$/.test(value)) return false;
  const parts = value.split(".").map(Number);
  return parts.every((part) => part >= 0 && part <= 255) && value !== "0.0.0.0";
}
async function sha256Hex(value) {
  const bytes = new TextEncoder().encode(value);
  const digest2 = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest2)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: JSON_HEADERS });
}
function bearerToken(request) {
  const header = request.headers.get("Authorization") || "";
  return header.startsWith("Bearer ") ? header.slice(7).trim() : "";
}
async function ensureWebRtcSchema(env) {
  if (schemaReady.has(env.DB)) return;
  const statements = [
    `CREATE TABLE IF NOT EXISTS webrtc_rooms (
      code TEXT PRIMARY KEY,
      host_token_hash TEXT NOT NULL,
      expires_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS webrtc_peers (
      code TEXT NOT NULL,
      peer_id INTEGER NOT NULL CHECK (peer_id BETWEEN 1 AND 4),
      token_hash TEXT NOT NULL,
      expires_at INTEGER NOT NULL,
      PRIMARY KEY (code, peer_id),
      FOREIGN KEY (code) REFERENCES webrtc_rooms(code) ON DELETE CASCADE
    )`,
    `CREATE TABLE IF NOT EXISTS webrtc_signals (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      code TEXT NOT NULL,
      from_peer INTEGER NOT NULL,
      to_peer INTEGER NOT NULL,
      signal_type TEXT NOT NULL,
      payload TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (code) REFERENCES webrtc_rooms(code) ON DELETE CASCADE
    )`,
    "CREATE INDEX IF NOT EXISTS idx_webrtc_rooms_expires_at ON webrtc_rooms (expires_at)",
    "CREATE INDEX IF NOT EXISTS idx_webrtc_peers_expiry ON webrtc_peers (code, expires_at)",
    "CREATE INDEX IF NOT EXISTS idx_webrtc_signals_recipient ON webrtc_signals (code, to_peer, id)"
  ];
  for (const sql of statements) await env.DB.prepare(sql).run();
  await env.DB.prepare(`CREATE TABLE IF NOT EXISTS webrtc_room_settings (
    code TEXT PRIMARY KEY REFERENCES webrtc_rooms(code) ON DELETE CASCADE,
    title TEXT NOT NULL, host_name TEXT NOT NULL,
    max_players INTEGER NOT NULL CHECK (max_players BETWEEN 2 AND 4),
    password_hash TEXT NOT NULL DEFAULT '', password_salt TEXT NOT NULL DEFAULT ''
  )`).run();
  await env.DB.prepare(`CREATE TABLE IF NOT EXISTS webrtc_started_rooms (
    code TEXT PRIMARY KEY REFERENCES webrtc_rooms(code) ON DELETE CASCADE
  )`).run();
  await env.DB.prepare(`CREATE TABLE IF NOT EXISTS webrtc_turn_grants (
    code TEXT NOT NULL, peer_id INTEGER NOT NULL, token_hash TEXT NOT NULL,
    key_id TEXT NOT NULL, claim TEXT NOT NULL, usable_until INTEGER NOT NULL, servers TEXT,
    PRIMARY KEY (code, peer_id),
    FOREIGN KEY (code, peer_id) REFERENCES webrtc_peers(code, peer_id) ON DELETE CASCADE
  )`).run();
  schemaReady.add(env.DB);
}
async function passwordHash(password, salt) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", salt: new TextEncoder().encode(salt), iterations: 1e5, hash: "SHA-256" }, key, 256);
  return [...new Uint8Array(bits)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
async function listWebRtcRooms(env) {
  const now = Math.floor(Date.now() / 1e3);
  const result = await env.DB.prepare(`SELECT r.code, s.title, s.host_name, s.max_players,
    (s.password_hash != '') AS password_required,
    (SELECT COUNT(*) FROM webrtc_peers p WHERE p.code = r.code AND p.expires_at > ?1) AS player_count
    FROM webrtc_rooms r JOIN webrtc_room_settings s ON s.code = r.code
    WHERE r.expires_at > ?1
    AND NOT EXISTS (SELECT 1 FROM webrtc_started_rooms started WHERE started.code = r.code)
    ORDER BY r.code LIMIT 100`).bind(now).all();
  return json({ rooms: result.results || [] });
}
async function requestJson(request) {
  try {
    return await request.json();
  } catch {
    return null;
  }
}
function requestIpv4(request, suppliedIp) {
  const connectingIp = (request.headers.get("CF-Connecting-IP") || "").trim();
  if (isValidIpv4(connectingIp)) return connectingIp;
  return isValidIpv4(suppliedIp) ? suppliedIp : "";
}
async function authorizeRoom(request, env, code) {
  const token = bearerToken(request);
  if (token.length < 32) return "unauthorized";
  const tokenHash = await sha256Hex(token);
  const room = await env.DB.prepare(
    "SELECT token_hash, expires_at FROM rooms WHERE code = ?1"
  ).bind(code).first();
  if (!room || Number(room.expires_at) <= Math.floor(Date.now() / 1e3)) return "missing";
  return room.token_hash === tokenHash ? "authorized" : "unauthorized";
}
async function createRoom(request, env) {
  const payload = await requestJson(request);
  if (!payload || !isValidRoomCode(payload.code) || !isValidPort(payload.port)) {
    return json({ error: "\uBC29 \uCF54\uB4DC \uB610\uB294 \uD3EC\uD2B8 \uD615\uC2DD\uC774 \uC62C\uBC14\uB974\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4." }, 400);
  }
  if (typeof payload.host_token !== "string" || payload.host_token.length < 32) {
    return json({ error: "\uBC29\uC7A5 \uC778\uC99D \uD1A0\uD070\uC774 \uC62C\uBC14\uB974\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4." }, 400);
  }
  const connectingIp = (request.headers.get("CF-Connecting-IP") || "").trim();
  const suppliedIp = typeof payload.public_ip === "string" ? payload.public_ip.trim() : "";
  if (isValidIpv4(connectingIp) && isValidIpv4(suppliedIp) && connectingIp !== suppliedIp) {
    return json({ error: "\uACF5\uC720\uAE30 \uC678\uBD80 \uC8FC\uC18C\uC640 \uC778\uD130\uB137 \uACF5\uC778 \uC8FC\uC18C\uAC00 \uB2E4\uB985\uB2C8\uB2E4. CGNAT \uD658\uACBD\uC5D0\uC11C\uB294 \uC9C1\uC811 \uC5F0\uACB0\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4." }, 400);
  }
  const hostIp = requestIpv4(request, suppliedIp);
  if (!hostIp) return json({ error: "\uBC29\uC7A5\uC758 \uACF5\uC778 IPv4 \uC8FC\uC18C\uB97C \uD655\uC778\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4." }, 400);
  const now = Math.floor(Date.now() / 1e3);
  await env.DB.prepare("DELETE FROM rooms WHERE code = ?1 AND expires_at <= ?2").bind(payload.code, now).run();
  const existing = await env.DB.prepare("SELECT code FROM rooms WHERE code = ?1").bind(payload.code).first();
  if (existing) return json({ error: "\uC774\uBBF8 \uC0AC\uC6A9 \uC911\uC778 \uBC29 \uCF54\uB4DC\uC785\uB2C8\uB2E4." }, 409);
  const tokenHash = await sha256Hex(payload.host_token);
  try {
    await env.DB.prepare(
      "INSERT INTO rooms (code, host_ip, port, token_hash, expires_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)"
    ).bind(payload.code, hostIp, payload.port, tokenHash, now + ROOM_TTL_SECONDS, now).run();
  } catch {
    return json({ error: "\uC774\uBBF8 \uC0AC\uC6A9 \uC911\uC778 \uBC29 \uCF54\uB4DC\uC785\uB2C8\uB2E4." }, 409);
  }
  return json({ code: payload.code, expires_at: now + ROOM_TTL_SECONDS }, 201);
}
async function findRoom(env, code) {
  if (!isValidRoomCode(code)) return json({ error: "\uBC29 \uCF54\uB4DC \uD615\uC2DD\uC774 \uC62C\uBC14\uB974\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4." }, 400);
  const now = Math.floor(Date.now() / 1e3);
  const room = await env.DB.prepare(
    "SELECT code, host_ip, port, expires_at FROM rooms WHERE code = ?1 AND expires_at > ?2"
  ).bind(code, now).first();
  if (!room) return json({ error: "\uBC29\uC744 \uCC3E\uC744 \uC218 \uC5C6\uAC70\uB098 \uB300\uAE30 \uC2DC\uAC04\uC774 \uB05D\uB0AC\uC2B5\uB2C8\uB2E4." }, 404);
  return json({ code: room.code, host: room.host_ip, port: room.port, expires_at: room.expires_at });
}
async function heartbeatRoom(request, env, code) {
  if (!isValidRoomCode(code)) return json({ error: "\uBC29 \uCF54\uB4DC \uD615\uC2DD\uC774 \uC62C\uBC14\uB974\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4." }, 400);
  const authorization = await authorizeRoom(request, env, code);
  if (authorization === "missing") return json({ error: "\uBC29 \uB4F1\uB85D\uC774 \uB9CC\uB8CC\uB418\uC5C8\uC2B5\uB2C8\uB2E4." }, 404);
  if (authorization !== "authorized") return json({ error: "\uBC29\uC7A5 \uC778\uC99D\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4." }, 401);
  const now = Math.floor(Date.now() / 1e3);
  await env.DB.prepare(
    "UPDATE rooms SET expires_at = ?1, updated_at = ?2 WHERE code = ?3"
  ).bind(now + ROOM_TTL_SECONDS, now, code).run();
  return json({ code, expires_at: now + ROOM_TTL_SECONDS });
}
async function deleteRoom(request, env, code) {
  if (!isValidRoomCode(code)) return json({ error: "\uBC29 \uCF54\uB4DC \uD615\uC2DD\uC774 \uC62C\uBC14\uB974\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4." }, 400);
  const authorization = await authorizeRoom(request, env, code);
  if (authorization === "missing") return json({ deleted: true });
  if (authorization !== "authorized") return json({ error: "\uBC29\uC7A5 \uC778\uC99D\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4." }, 401);
  await env.DB.prepare("DELETE FROM rooms WHERE code = ?1").bind(code).run();
  return json({ deleted: true });
}
async function cleanupExpiredWebRtcRoom(env, code, now) {
  const room = await env.DB.prepare(
    "SELECT expires_at FROM webrtc_rooms WHERE code = ?1"
  ).bind(code).first();
  if (!room || Number(room.expires_at) > now) return room;
  await env.DB.prepare("DELETE FROM webrtc_signals WHERE code = ?1").bind(code).run();
  await env.DB.prepare("DELETE FROM webrtc_peers WHERE code = ?1").bind(code).run();
  await env.DB.prepare("DELETE FROM webrtc_rooms WHERE code = ?1").bind(code).run();
  return null;
}
async function authorizeWebRtcPeer(request, env, code) {
  const token = bearerToken(request);
  if (token.length < 32) return null;
  const now = Math.floor(Date.now() / 1e3);
  const tokenHash = await sha256Hex(token);
  const peer = await env.DB.prepare(
    "SELECT peer_id FROM webrtc_peers WHERE code = ?1 AND token_hash = ?2 AND expires_at > ?3"
  ).bind(code, tokenHash, now).first();
  return peer ? { peerId: Number(peer.peer_id), now, tokenHash } : null;
}
async function createWebRtcRoom(request, env) {
  const payload = await requestJson(request);
  if (!payload || !isValidRoomCode(payload.code)) {
    return json({ error: "\uBC29 \uCF54\uB4DC \uD615\uC2DD\uC774 \uC62C\uBC14\uB974\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4." }, 400);
  }
  if (typeof payload.host_token !== "string" || payload.host_token.length < 32) {
    return json({ error: "\uBC29\uC7A5 \uC778\uC99D \uD1A0\uD070\uC774 \uC62C\uBC14\uB974\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4." }, 400);
  }
  const title = payload.title === void 0 ? "\uD568\uAED8\uD558\uB294 \uC5D0\uB108\uC9C0 \uBAA8\uD5D8" : payload.title;
  const capacity = payload.max_players === void 0 ? 4 : payload.max_players;
  const password = payload.password === void 0 ? "" : payload.password;
  if (typeof title !== "string" || !title.trim() || [...title].length > 15 || !Number.isInteger(capacity) || capacity < 2 || capacity > 4 || typeof password !== "string" || password.length > 64) {
    return json({ error: "\uBC29 \uC81C\uBAA9(1~15\uC790), \uC815\uC6D0(2~4\uBA85), \uBE44\uBC00\uBC88\uD638(\uCD5C\uB300 64\uC790)\uB97C \uD655\uC778\uD558\uC138\uC694." }, 400);
  }
  const salt = password ? crypto.randomUUID() : "";
  const passwordDigest = password ? await passwordHash(password, salt) : "";
  const hostName = typeof payload.host_name === "string" ? [...payload.host_name].slice(0, 6).join("") : "\uBC29\uC7A5";
  const now = Math.floor(Date.now() / 1e3);
  await cleanupExpiredWebRtcRoom(env, payload.code, now);
  const existing = await env.DB.prepare(
    "SELECT code FROM webrtc_rooms WHERE code = ?1"
  ).bind(payload.code).first();
  if (existing) return json({ error: "\uC774\uBBF8 \uC0AC\uC6A9 \uC911\uC778 \uBC29 \uCF54\uB4DC\uC785\uB2C8\uB2E4." }, 409);
  const tokenHash = await sha256Hex(payload.host_token);
  const expiresAt = now + WEBRTC_ROOM_TTL_SECONDS;
  try {
    await env.DB.batch([env.DB.prepare(
      "INSERT INTO webrtc_rooms (code, host_token_hash, expires_at, updated_at) VALUES (?1, ?2, ?3, ?4)"
    ).bind(payload.code, tokenHash, expiresAt, now), env.DB.prepare(
      "INSERT INTO webrtc_peers (code, peer_id, token_hash, expires_at) VALUES (?1, 1, ?2, ?3)"
    ).bind(payload.code, tokenHash, expiresAt), env.DB.prepare(
      "INSERT INTO webrtc_room_settings (code, title, host_name, max_players, password_hash, password_salt) VALUES (?1, ?2, ?3, ?4, ?5, ?6)"
    ).bind(payload.code, title.trim(), hostName, capacity, passwordDigest, salt)]);
  } catch {
    return json({ error: "\uC774\uBBF8 \uC0AC\uC6A9 \uC911\uC778 \uBC29 \uCF54\uB4DC\uC785\uB2C8\uB2E4." }, 409);
  }
  const ice = await admissionIceServers(env, payload.code, 1, tokenHash);
  return json({ code: payload.code, peer_id: 1, expires_at: expiresAt, ...ice }, 201);
}
async function joinWebRtcRoom(request, env, code) {
  if (!isValidRoomCode(code)) return json({ error: "\uBC29 \uCF54\uB4DC \uD615\uC2DD\uC774 \uC62C\uBC14\uB974\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4." }, 400);
  const payload = await requestJson(request);
  if (!payload || typeof payload.peer_token !== "string" || payload.peer_token.length < 32) {
    return json({ error: "\uCC38\uAC00\uC790 \uC778\uC99D \uD1A0\uD070\uC774 \uC62C\uBC14\uB974\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4." }, 400);
  }
  const now = Math.floor(Date.now() / 1e3);
  const room = await cleanupExpiredWebRtcRoom(env, code, now);
  if (!room) return json({ error: "\uBC29\uC744 \uCC3E\uC744 \uC218 \uC5C6\uAC70\uB098 \uB300\uAE30 \uC2DC\uAC04\uC774 \uB05D\uB0AC\uC2B5\uB2C8\uB2E4." }, 404);
  const started = await env.DB.prepare("SELECT code FROM webrtc_started_rooms WHERE code = ?1").bind(code).first();
  if (started) return json({ error: "\uC774\uBBF8 \uC9C4\uD589 \uC911\uC778 \uAC8C\uC784\uC785\uB2C8\uB2E4. \uAE30\uC874 \uCC38\uAC00\uC790\uB9CC \uC7AC\uC811\uC18D\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4." }, 409);
  const settings = await env.DB.prepare("SELECT * FROM webrtc_room_settings WHERE code = ?1").bind(code).first();
  if (settings?.password_hash) {
    if (typeof payload.password !== "string" || payload.password.length > 64 || await passwordHash(payload.password, settings.password_salt) !== settings.password_hash) {
      return json({ error: "\uBE44\uBC00\uBC88\uD638\uAC00 \uC62C\uBC14\uB974\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4." }, 403);
    }
  }
  await env.DB.prepare(`DELETE FROM webrtc_signals WHERE code = ?1 AND (
    from_peer IN (SELECT peer_id FROM webrtc_peers WHERE code = ?1 AND expires_at <= ?2 AND peer_id != 1)
    OR to_peer IN (SELECT peer_id FROM webrtc_peers WHERE code = ?1 AND expires_at <= ?2 AND peer_id != 1)
  )`).bind(code, now).run();
  await env.DB.prepare("DELETE FROM webrtc_peers WHERE code = ?1 AND expires_at <= ?2 AND peer_id != 1").bind(code, now).run();
  const tokenHash = await sha256Hex(payload.peer_token);
  const expiresAt = now + WEBRTC_ROOM_TTL_SECONDS;
  try {
    await env.DB.prepare(
      `INSERT INTO webrtc_peers (code, peer_id, token_hash, expires_at)
      SELECT ?1, seats.peer_id, ?2, ?3
      FROM (SELECT 2 AS peer_id UNION ALL SELECT 3 UNION ALL SELECT 4) seats
      WHERE seats.peer_id <= ?4
        AND NOT EXISTS (SELECT 1 FROM webrtc_peers p WHERE p.code = ?1 AND p.peer_id = seats.peer_id)
        AND NOT EXISTS (SELECT 1 FROM webrtc_peers p WHERE p.code = ?1 AND p.token_hash = ?2)
        AND NOT EXISTS (SELECT 1 FROM webrtc_started_rooms s WHERE s.code = ?1)
        AND EXISTS (SELECT 1 FROM webrtc_rooms r WHERE r.code = ?1 AND r.expires_at > ?5)
      ORDER BY seats.peer_id LIMIT 1`
    ).bind(code, tokenHash, expiresAt, settings?.max_players || 4, now).run();
  } catch {
    return json({ error: "\uCC38\uAC00\uC790 \uBC88\uD638\uB97C \uBC30\uC815\uD558\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4. \uB2E4\uC2DC \uC2DC\uB3C4\uD574 \uC8FC\uC138\uC694." }, 409);
  }
  const assigned = await env.DB.prepare(
    "SELECT peer_id FROM webrtc_peers WHERE code = ?1 AND token_hash = ?2 AND peer_id != 1 AND expires_at > ?3"
  ).bind(code, tokenHash, now).first();
  if (!assigned) return json({ error: "\uAC8C\uC784\uBC29\uC774 \uAC00\uB4DD \uCC3C\uAC70\uB098 \uC774\uBBF8 \uC2DC\uC791\uB418\uC5C8\uC2B5\uB2C8\uB2E4." }, 409);
  const peerId = Number(assigned.peer_id);
  await env.DB.prepare(
    "UPDATE webrtc_peers SET expires_at = MAX(expires_at, ?1) WHERE code = ?2 AND peer_id = ?3 AND token_hash = ?4"
  ).bind(expiresAt, code, peerId, tokenHash).run();
  const ice = await admissionIceServers(env, code, peerId, tokenHash);
  return json({
    code,
    peer_id: peerId,
    host_peer_id: 1,
    expires_at: expiresAt,
    ...ice,
    title: settings?.title || "\uC5D0\uB108\uC9C0 \uBAA8\uD5D8",
    max_players: settings?.max_players || 4
  }, 201);
}
async function startWebRtcRoom(request, env, code) {
  const peer = await authorizeWebRtcPeer(request, env, code);
  if (!peer || peer.peerId !== 1) return json({ error: "\uBC29\uC7A5 \uC778\uC99D\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4." }, 401);
  await env.DB.prepare("INSERT OR IGNORE INTO webrtc_started_rooms (code) VALUES (?1)").bind(code).run();
  return json({ started: true });
}
async function leaveWebRtcRoom(request, env, code) {
  const peer = await authorizeWebRtcPeer(request, env, code);
  if (!peer || peer.peerId === 1) return json({ error: "\uCC38\uAC00\uC790 \uC778\uC99D\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4." }, 401);
  await env.DB.batch([
    env.DB.prepare("DELETE FROM webrtc_signals WHERE code = ?1 AND (from_peer = ?2 OR to_peer = ?2)").bind(code, peer.peerId),
    env.DB.prepare("DELETE FROM webrtc_peers WHERE code = ?1 AND peer_id = ?2").bind(code, peer.peerId)
  ]);
  return json({ left: true });
}
async function postWebRtcSignal(request, env, code) {
  if (!isValidRoomCode(code)) return json({ error: "\uBC29 \uCF54\uB4DC \uD615\uC2DD\uC774 \uC62C\uBC14\uB974\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4." }, 400);
  const sender = await authorizeWebRtcPeer(request, env, code);
  if (!sender) return json({ error: "\uC2E0\uD638 \uC804\uC1A1 \uAD8C\uD55C\uC774 \uC5C6\uC2B5\uB2C8\uB2E4." }, 401);
  const payload = await requestJson(request);
  const toPeer = Number(payload?.to_peer);
  const signalType = payload?.type;
  if (!Number.isInteger(toPeer) || toPeer < 1 || toPeer > WEBRTC_MAX_PLAYERS || !WEBRTC_SIGNAL_TYPES.has(signalType) || typeof payload?.data !== "object" || payload.data === null) {
    return json({ error: "WebRTC \uC2E0\uD638 \uD615\uC2DD\uC774 \uC62C\uBC14\uB974\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4." }, 400);
  }
  const encodedPayload = JSON.stringify(payload.data);
  if (encodedPayload.length > 65536) return json({ error: "WebRTC \uC2E0\uD638\uAC00 \uB108\uBB34 \uD07D\uB2C8\uB2E4." }, 413);
  const target = await env.DB.prepare(
    "SELECT peer_id FROM webrtc_peers WHERE code = ?1 AND peer_id = ?2 AND expires_at > ?3"
  ).bind(code, toPeer, sender.now).first();
  if (!target) return json({ error: "\uC5F0\uACB0 \uB300\uC0C1\uC774 \uBC29\uC5D0 \uC5C6\uC2B5\uB2C8\uB2E4." }, 404);
  await env.DB.prepare(
    "INSERT INTO webrtc_signals (code, from_peer, to_peer, signal_type, payload, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)"
  ).bind(code, sender.peerId, toPeer, signalType, encodedPayload, sender.now).run();
  return json({ accepted: true }, 202);
}
async function pollWebRtcSignals(request, env, code) {
  if (!isValidRoomCode(code)) return json({ error: "\uBC29 \uCF54\uB4DC \uD615\uC2DD\uC774 \uC62C\uBC14\uB974\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4." }, 400);
  const peer = await authorizeWebRtcPeer(request, env, code);
  if (!peer) return json({ error: "\uC2E0\uD638 \uC218\uC2E0 \uAD8C\uD55C\uC774 \uC5C6\uAC70\uB098 \uBC29\uC774 \uB9CC\uB8CC\uB418\uC5C8\uC2B5\uB2C8\uB2E4." }, 401);
  const cursor = new URL(request.url).searchParams.get("ack");
  if (cursor !== null && (!/^(0|[1-9]\d*)$/.test(cursor) || !Number.isSafeInteger(Number(cursor)))) {
    return json({ error: "\uC2E0\uD638 \uC218\uC2E0 \uBC88\uD638\uAC00 \uC62C\uBC14\uB974\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4." }, 400);
  }
  const expiresAt = peer.now + WEBRTC_ROOM_TTL_SECONDS;
  await env.DB.prepare(
    "UPDATE webrtc_peers SET expires_at = MAX(expires_at, ?1) WHERE code = ?2 AND peer_id = ?3 AND token_hash = ?4"
  ).bind(expiresAt, code, peer.peerId, peer.tokenHash).run();
  if (peer.peerId === 1) {
    await env.DB.prepare(
      "UPDATE webrtc_rooms SET expires_at = MAX(expires_at, ?1), updated_at = MAX(updated_at, ?2) WHERE code = ?3 AND host_token_hash = ?4"
    ).bind(expiresAt, peer.now, code, peer.tokenHash).run();
  }
  const recipient = `code = ?1 AND to_peer = ?2 AND EXISTS (
    SELECT 1 FROM webrtc_peers WHERE code = ?1 AND peer_id = ?2 AND token_hash = ?3)`;
  const credentials = [code, peer.peerId, peer.tokenHash];
  const discardThrough = (id) => env.DB.prepare(`DELETE FROM webrtc_signals WHERE id IN (
    SELECT id FROM webrtc_signals WHERE ${recipient} AND id <= ?4 ORDER BY id LIMIT 64)`).bind(...credentials, id).run();
  if (Number(cursor) > 0) await discardThrough(Number(cursor));
  const result = await env.DB.prepare(
    `
    SELECT id, from_peer, signal_type, payload FROM webrtc_signals WHERE ${recipient} ORDER BY id LIMIT 64`
  ).bind(...credentials).all();
  const rows = result.results || [];
  if (cursor === null && rows.length) await discardThrough(rows[rows.length - 1].id);
  const signals = [];
  for (const row of rows) {
    let data = {};
    try {
      data = JSON.parse(row.payload);
    } catch {
      data = {};
    }
    signals.push({ id: Number(row.id), from_peer: Number(row.from_peer), type: row.signal_type, data });
  }
  return json({ signals, expires_at: expiresAt });
}
async function deleteWebRtcRoom(request, env, code) {
  const peer = await authorizeWebRtcPeer(request, env, code);
  if (!peer || peer.peerId !== 1) return json({ error: "\uBC29\uC7A5 \uC778\uC99D\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4." }, 401);
  await env.DB.prepare("DELETE FROM webrtc_signals WHERE code = ?1").bind(code).run();
  await env.DB.prepare("DELETE FROM webrtc_peers WHERE code = ?1").bind(code).run();
  await env.DB.prepare("DELETE FROM webrtc_rooms WHERE code = ?1").bind(code).run();
  return json({ deleted: true });
}
var src_default = {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: JSON_HEADERS });
    if (!env.DB) return json({ error: "D1 \uB370\uC774\uD130\uBCA0\uC774\uC2A4\uAC00 \uC5F0\uACB0\uB418\uC9C0 \uC54A\uC558\uC2B5\uB2C8\uB2E4." }, 503);
    const url = new URL(request.url);
    const parts = url.pathname.split("/").filter(Boolean);
    if (parts[0] === "scores") return scoresRoute(request, env.DB, parts, json);
    if (parts[0] === "webrtc") await ensureWebRtcSchema(env);
    if (parts[0] === "webrtc" && parts[1] === "rooms" && parts.length === 2 && request.method === "GET") return listWebRtcRooms(env);
    if (parts[0] === "webrtc" && parts[1] === "rooms" && parts.length === 4 && parts[3] === "leave" && request.method === "POST") return leaveWebRtcRoom(request, env, parts[2]);
    if (parts[0] === "webrtc" && parts[1] === "rooms" && parts.length === 4 && parts[3] === "start" && request.method === "POST") return startWebRtcRoom(request, env, parts[2]);
    if (request.method === "POST" && parts.length === 1 && parts[0] === "rooms") {
      return createRoom(request, env);
    }
    if (request.method === "POST" && parts.length === 2 && parts[0] === "webrtc" && parts[1] === "rooms") {
      return createWebRtcRoom(request, env);
    }
    if (parts[0] === "webrtc" && parts[1] === "rooms" && parts.length === 4 && parts[3] === "join" && request.method === "POST") {
      return joinWebRtcRoom(request, env, parts[2]);
    }
    if (parts[0] === "webrtc" && parts[1] === "rooms" && parts.length === 4 && parts[3] === "signals") {
      if (request.method === "POST") return postWebRtcSignal(request, env, parts[2]);
      if (request.method === "GET") return pollWebRtcSignals(request, env, parts[2]);
    }
    if (parts[0] === "webrtc" && parts[1] === "rooms" && parts.length === 3 && request.method === "DELETE") {
      return deleteWebRtcRoom(request, env, parts[2]);
    }
    if (parts[0] === "rooms" && parts.length === 2 && request.method === "GET") {
      return findRoom(env, parts[1]);
    }
    if (parts[0] === "rooms" && parts.length === 3 && parts[2] === "heartbeat" && request.method === "PUT") {
      return heartbeatRoom(request, env, parts[1]);
    }
    if (parts[0] === "rooms" && parts.length === 2 && request.method === "DELETE") {
      return deleteRoom(request, env, parts[1]);
    }
    return json({ error: "\uC9C0\uC6D0\uD558\uC9C0 \uC54A\uB294 \uC694\uCCAD\uC785\uB2C8\uB2E4." }, 404);
  }
};
export {
  src_default as default
};
