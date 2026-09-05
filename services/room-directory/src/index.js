const ROOM_TTL_SECONDS = 90;
const WEBRTC_ROOM_TTL_SECONDS = 120;
const WEBRTC_MAX_PLAYERS = 4;
const WEBRTC_SIGNAL_TYPES = new Set(["offer", "answer", "candidate"]);
const schemaReady = new WeakSet();
const JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
};

export function isValidRoomCode(value) {
  return typeof value === "string" && /^[1-9][0-9]{5}$/.test(value);
}

export function isValidPort(value) {
  return Number.isInteger(value) && value >= 1024 && value <= 65535;
}

export function isValidIpv4(value) {
  if (typeof value !== "string" || !/^\d{1,3}(\.\d{1,3}){3}$/.test(value)) return false;
  const parts = value.split(".").map(Number);
  return parts.every((part) => part >= 0 && part <= 255) && value !== "0.0.0.0";
}

export async function sha256Hex(value) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
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
    "CREATE INDEX IF NOT EXISTS idx_webrtc_signals_recipient ON webrtc_signals (code, to_peer, id)",
  ];
  for (const sql of statements) await env.DB.prepare(sql).run();
  await env.DB.prepare(`CREATE TABLE IF NOT EXISTS webrtc_room_settings (
    code TEXT PRIMARY KEY REFERENCES webrtc_rooms(code) ON DELETE CASCADE,
    title TEXT NOT NULL, host_name TEXT NOT NULL,
    max_players INTEGER NOT NULL CHECK (max_players BETWEEN 2 AND 4),
    password_hash TEXT NOT NULL DEFAULT '', password_salt TEXT NOT NULL DEFAULT ''
  )`).run();
  schemaReady.add(env.DB);
}

export async function passwordHash(password, salt) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({name: "PBKDF2", salt: new TextEncoder().encode(salt), iterations: 100000, hash: "SHA-256"}, key, 256);
  return [...new Uint8Array(bits)].map(b => b.toString(16).padStart(2, "0")).join("");
}

async function listWebRtcRooms(env) {
  const now = Math.floor(Date.now() / 1000);
  const result = await env.DB.prepare(`SELECT r.code, s.title, s.host_name, s.max_players,
    (s.password_hash != '') AS password_required,
    (SELECT COUNT(*) FROM webrtc_peers p WHERE p.code = r.code AND p.expires_at > ?1) AS player_count
    FROM webrtc_rooms r JOIN webrtc_room_settings s ON s.code = r.code
    WHERE r.expires_at > ?1 ORDER BY r.code LIMIT 100`).bind(now).all();
  return json({rooms: result.results || []});
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
  if (!room || Number(room.expires_at) <= Math.floor(Date.now() / 1000)) return "missing";
  return room.token_hash === tokenHash ? "authorized" : "unauthorized";
}

async function createRoom(request, env) {
  const payload = await requestJson(request);
  if (!payload || !isValidRoomCode(payload.code) || !isValidPort(payload.port)) {
    return json({ error: "방 코드 또는 포트 형식이 올바르지 않습니다." }, 400);
  }
  if (typeof payload.host_token !== "string" || payload.host_token.length < 32) {
    return json({ error: "방장 인증 토큰이 올바르지 않습니다." }, 400);
  }
  const connectingIp = (request.headers.get("CF-Connecting-IP") || "").trim();
  const suppliedIp = typeof payload.public_ip === "string" ? payload.public_ip.trim() : "";
  if (isValidIpv4(connectingIp) && isValidIpv4(suppliedIp) && connectingIp !== suppliedIp) {
    return json({ error: "공유기 외부 주소와 인터넷 공인 주소가 다릅니다. CGNAT 환경에서는 직접 연결할 수 없습니다." }, 400);
  }
  const hostIp = requestIpv4(request, suppliedIp);
  if (!hostIp) return json({ error: "방장의 공인 IPv4 주소를 확인할 수 없습니다." }, 400);

  const now = Math.floor(Date.now() / 1000);
  await env.DB.prepare("DELETE FROM rooms WHERE code = ?1 AND expires_at <= ?2").bind(payload.code, now).run();
  const existing = await env.DB.prepare("SELECT code FROM rooms WHERE code = ?1").bind(payload.code).first();
  if (existing) return json({ error: "이미 사용 중인 방 코드입니다." }, 409);

  const tokenHash = await sha256Hex(payload.host_token);
  try {
    await env.DB.prepare(
      "INSERT INTO rooms (code, host_ip, port, token_hash, expires_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)"
    ).bind(payload.code, hostIp, payload.port, tokenHash, now + ROOM_TTL_SECONDS, now).run();
  } catch {
    return json({ error: "이미 사용 중인 방 코드입니다." }, 409);
  }
  return json({ code: payload.code, expires_at: now + ROOM_TTL_SECONDS }, 201);
}

async function findRoom(env, code) {
  if (!isValidRoomCode(code)) return json({ error: "방 코드 형식이 올바르지 않습니다." }, 400);
  const now = Math.floor(Date.now() / 1000);
  const room = await env.DB.prepare(
    "SELECT code, host_ip, port, expires_at FROM rooms WHERE code = ?1 AND expires_at > ?2"
  ).bind(code, now).first();
  if (!room) return json({ error: "방을 찾을 수 없거나 대기 시간이 끝났습니다." }, 404);
  return json({ code: room.code, host: room.host_ip, port: room.port, expires_at: room.expires_at });
}

async function heartbeatRoom(request, env, code) {
  if (!isValidRoomCode(code)) return json({ error: "방 코드 형식이 올바르지 않습니다." }, 400);
  const authorization = await authorizeRoom(request, env, code);
  if (authorization === "missing") return json({ error: "방 등록이 만료되었습니다." }, 404);
  if (authorization !== "authorized") return json({ error: "방장 인증에 실패했습니다." }, 401);
  const now = Math.floor(Date.now() / 1000);
  await env.DB.prepare(
    "UPDATE rooms SET expires_at = ?1, updated_at = ?2 WHERE code = ?3"
  ).bind(now + ROOM_TTL_SECONDS, now, code).run();
  return json({ code, expires_at: now + ROOM_TTL_SECONDS });
}

async function deleteRoom(request, env, code) {
  if (!isValidRoomCode(code)) return json({ error: "방 코드 형식이 올바르지 않습니다." }, 400);
  const authorization = await authorizeRoom(request, env, code);
  if (authorization === "missing") return json({ deleted: true });
  if (authorization !== "authorized") return json({ error: "방장 인증에 실패했습니다." }, 401);
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
  const now = Math.floor(Date.now() / 1000);
  const tokenHash = await sha256Hex(token);
  const peer = await env.DB.prepare(
    "SELECT peer_id FROM webrtc_peers WHERE code = ?1 AND token_hash = ?2 AND expires_at > ?3"
  ).bind(code, tokenHash, now).first();
  return peer ? { peerId: Number(peer.peer_id), now } : null;
}

async function createWebRtcRoom(request, env) {
  const payload = await requestJson(request);
  if (!payload || !isValidRoomCode(payload.code)) {
    return json({ error: "방 코드 형식이 올바르지 않습니다." }, 400);
  }
  if (typeof payload.host_token !== "string" || payload.host_token.length < 32) {
    return json({ error: "방장 인증 토큰이 올바르지 않습니다." }, 400);
  }
  const title = payload.title === undefined ? "함께하는 에너지 모험" : payload.title;
  const capacity = payload.max_players === undefined ? 4 : payload.max_players;
  const password = payload.password === undefined ? "" : payload.password;
  if (typeof title !== "string" || !title.trim() || title.length > 40 ||
      !Number.isInteger(capacity) || capacity < 2 || capacity > 4 ||
      typeof password !== "string" || password.length > 64) {
    return json({error: "방 제목(1~40자), 정원(2~4명), 비밀번호(최대 64자)를 확인하세요."}, 400);
  }
  const salt = password ? crypto.randomUUID() : "";
  const passwordDigest = password ? await passwordHash(password, salt) : "";
  const hostName = typeof payload.host_name === "string" ? payload.host_name.slice(0, 24) : "방장";
  const now = Math.floor(Date.now() / 1000);
  await cleanupExpiredWebRtcRoom(env, payload.code, now);
  const existing = await env.DB.prepare(
    "SELECT code FROM webrtc_rooms WHERE code = ?1"
  ).bind(payload.code).first();
  if (existing) return json({ error: "이미 사용 중인 방 코드입니다." }, 409);

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
    return json({ error: "이미 사용 중인 방 코드입니다." }, 409);
  }
  return json({ code: payload.code, peer_id: 1, expires_at: expiresAt }, 201);
}

async function joinWebRtcRoom(request, env, code) {
  if (!isValidRoomCode(code)) return json({ error: "방 코드 형식이 올바르지 않습니다." }, 400);
  const payload = await requestJson(request);
  if (!payload || typeof payload.peer_token !== "string" || payload.peer_token.length < 32) {
    return json({ error: "참가자 인증 토큰이 올바르지 않습니다." }, 400);
  }
  const now = Math.floor(Date.now() / 1000);
  const room = await cleanupExpiredWebRtcRoom(env, code, now);
  if (!room) return json({ error: "방을 찾을 수 없거나 대기 시간이 끝났습니다." }, 404);

  const settings = await env.DB.prepare("SELECT * FROM webrtc_room_settings WHERE code = ?1").bind(code).first();
  if (settings?.password_hash) {
    if (typeof payload.password !== "string" || payload.password.length > 64 ||
        await passwordHash(payload.password, settings.password_salt) !== settings.password_hash) {
      return json({error: "비밀번호가 올바르지 않습니다."}, 403);
    }
  }
  await env.DB.prepare("DELETE FROM webrtc_peers WHERE code = ?1 AND expires_at <= ?2 AND peer_id != 1").bind(code, now).run();

  const result = await env.DB.prepare(
    "SELECT peer_id FROM webrtc_peers WHERE code = ?1 AND expires_at > ?2 ORDER BY peer_id"
  ).bind(code, now).all();
  const used = new Set((result.results || []).map((peer) => Number(peer.peer_id)));
  let peerId = 0;
  for (let candidate = 2; candidate <= (settings?.max_players || 4); candidate += 1) {
    if (!used.has(candidate)) {
      peerId = candidate;
      break;
    }
  }
  if (!peerId) return json({ error: "게임방 인원이 가득 찼습니다." }, 409);

  const tokenHash = await sha256Hex(payload.peer_token);
  const expiresAt = now + WEBRTC_ROOM_TTL_SECONDS;
  try {
    await env.DB.prepare(
      "INSERT INTO webrtc_peers (code, peer_id, token_hash, expires_at) VALUES (?1, ?2, ?3, ?4)"
    ).bind(code, peerId, tokenHash, expiresAt).run();
  } catch {
    return json({ error: "참가자 번호를 배정하지 못했습니다. 다시 시도해 주세요." }, 409);
  }
  return json({ code, peer_id: peerId, host_peer_id: 1, expires_at: expiresAt,
    title: settings?.title || "에너지 모험", max_players: settings?.max_players || 4 }, 201);
}

async function leaveWebRtcRoom(request, env, code) {
  const peer = await authorizeWebRtcPeer(request, env, code);
  if (!peer || peer.peerId === 1) return json({error: "참가자 인증에 실패했습니다."}, 401);
  await env.DB.batch([
    env.DB.prepare("DELETE FROM webrtc_signals WHERE code = ?1 AND (from_peer = ?2 OR to_peer = ?2)").bind(code, peer.peerId),
    env.DB.prepare("DELETE FROM webrtc_peers WHERE code = ?1 AND peer_id = ?2").bind(code, peer.peerId)
  ]);
  return json({left: true});
}

async function postWebRtcSignal(request, env, code) {
  if (!isValidRoomCode(code)) return json({ error: "방 코드 형식이 올바르지 않습니다." }, 400);
  const sender = await authorizeWebRtcPeer(request, env, code);
  if (!sender) return json({ error: "신호 전송 권한이 없습니다." }, 401);
  const payload = await requestJson(request);
  const toPeer = Number(payload?.to_peer);
  const signalType = payload?.type;
  if (!Number.isInteger(toPeer) || toPeer < 1 || toPeer > WEBRTC_MAX_PLAYERS ||
      !WEBRTC_SIGNAL_TYPES.has(signalType) || typeof payload?.data !== "object" || payload.data === null) {
    return json({ error: "WebRTC 신호 형식이 올바르지 않습니다." }, 400);
  }
  const encodedPayload = JSON.stringify(payload.data);
  if (encodedPayload.length > 65536) return json({ error: "WebRTC 신호가 너무 큽니다." }, 413);
  const target = await env.DB.prepare(
    "SELECT peer_id FROM webrtc_peers WHERE code = ?1 AND peer_id = ?2 AND expires_at > ?3"
  ).bind(code, toPeer, sender.now).first();
  if (!target) return json({ error: "연결 대상이 방에 없습니다." }, 404);
  await env.DB.prepare(
    "INSERT INTO webrtc_signals (code, from_peer, to_peer, signal_type, payload, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)"
  ).bind(code, sender.peerId, toPeer, signalType, encodedPayload, sender.now).run();
  return json({ accepted: true }, 202);
}

async function pollWebRtcSignals(request, env, code) {
  if (!isValidRoomCode(code)) return json({ error: "방 코드 형식이 올바르지 않습니다." }, 400);
  const peer = await authorizeWebRtcPeer(request, env, code);
  if (!peer) return json({ error: "신호 수신 권한이 없거나 방이 만료되었습니다." }, 401);
  const expiresAt = peer.now + WEBRTC_ROOM_TTL_SECONDS;
  await env.DB.prepare(
    "UPDATE webrtc_peers SET expires_at = ?1 WHERE code = ?2 AND peer_id = ?3"
  ).bind(expiresAt, code, peer.peerId).run();
  if (peer.peerId === 1) {
    await env.DB.prepare(
      "UPDATE webrtc_rooms SET expires_at = ?1, updated_at = ?2 WHERE code = ?3"
    ).bind(expiresAt, peer.now, code).run();
  }

  const result = await env.DB.prepare(
    "SELECT id, from_peer, signal_type, payload FROM webrtc_signals WHERE code = ?1 AND to_peer = ?2 ORDER BY id LIMIT 64"
  ).bind(code, peer.peerId).all();
  const rows = result.results || [];
  const signals = [];
  for (const row of rows) {
    let data = {};
    try { data = JSON.parse(row.payload); } catch { data = {}; }
    signals.push({ id: Number(row.id), from_peer: Number(row.from_peer), type: row.signal_type, data });
    await env.DB.prepare("DELETE FROM webrtc_signals WHERE id = ?1").bind(row.id).run();
  }
  return json({ signals, expires_at: expiresAt });
}

async function deleteWebRtcRoom(request, env, code) {
  const peer = await authorizeWebRtcPeer(request, env, code);
  if (!peer || peer.peerId !== 1) return json({ error: "방장 인증에 실패했습니다." }, 401);
  await env.DB.prepare("DELETE FROM webrtc_signals WHERE code = ?1").bind(code).run();
  await env.DB.prepare("DELETE FROM webrtc_peers WHERE code = ?1").bind(code).run();
  await env.DB.prepare("DELETE FROM webrtc_rooms WHERE code = ?1").bind(code).run();
  return json({ deleted: true });
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: JSON_HEADERS });
    if (!env.DB) return json({ error: "D1 데이터베이스가 연결되지 않았습니다." }, 503);

    const url = new URL(request.url);
    const parts = url.pathname.split("/").filter(Boolean);
    if (parts[0] === "webrtc") await ensureWebRtcSchema(env);
    if (parts[0] === "webrtc" && parts[1] === "rooms" && parts.length === 2 && request.method === "GET") return listWebRtcRooms(env);
    if (parts[0] === "webrtc" && parts[1] === "rooms" && parts.length === 4 && parts[3] === "leave" && request.method === "POST") return leaveWebRtcRoom(request, env, parts[2]);
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
    return json({ error: "지원하지 않는 요청입니다." }, 404);
  },
};
