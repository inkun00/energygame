const ROOM_TTL_SECONDS = 90;
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

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: JSON_HEADERS });
    if (!env.DB) return json({ error: "D1 데이터베이스가 연결되지 않았습니다." }, 503);

    const url = new URL(request.url);
    const parts = url.pathname.split("/").filter(Boolean);
    if (request.method === "POST" && parts.length === 1 && parts[0] === "rooms") {
      return createRoom(request, env);
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
