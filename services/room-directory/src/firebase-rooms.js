import {isValidRoomCode, passwordHash, sha256Hex} from "./room-credentials.js";
import {CREDENTIAL_TTL_SECONDS, mintCredentials} from "./turn.js";

const collection = "energygameWebRooms";
const lifetime = 120;
const renewalInterval = 30;
const signalTypes = new Set(["offer", "answer", "candidate"]);
const nowSeconds = () => Math.floor(Date.now() / 1000);
const json = (body, status = 200) => Response.json(body, {status});
const error = (message, status) => json({error: message}, status);
const unauthorized = () => error("방이 만료되었거나 이 자리에 접속할 권한이 없습니다.", 401);
const validToken = value => typeof value === "string" && value.length >= 32 && value.length <= 512;

async function tokenHash(request) {
  const header = request.headers.get("Authorization") || "";
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  return validToken(token) ? sha256Hex(token) : null;
}

function activePeer(room, hash, now) {
  if (!room || room.expiresAt <= now) return undefined;
  return room.peers.find(peer => peer.hash === hash && peer.expiresAt > now);
}

function reserveRelay(peer, env, now, claim) {
  if (!env.TURN_KEY_ID || !env.TURN_KEY_API_TOKEN) return;
  if (peer.relay?.key === env.TURN_KEY_ID && peer.relay.until > now) return;
  peer.relay = {key: env.TURN_KEY_ID, claim, until: now + 5};
}

// Mint once per admitted seat. A retry can only see its own seat's grant.
async function admissionResponse(ref, admitted, claim, env) {
  if (admitted instanceof Response) return admitted;
  const {peer, body} = admitted;
  if (!peer.relay || !env.TURN_KEY_ID || !env.TURN_KEY_API_TOKEN) return json(body, 201);
  try {
    let relay = peer.relay;
    if (relay.claim === claim) {
      const {ice_servers = []} = await mintCredentials(env);
      const saved = await ref.firestore.runTransaction(async tx => {
        const room = (await tx.get(ref)).data();
        const current = activePeer(room, peer.hash, nowSeconds());
        if (current?.relay?.claim !== claim) return false;
        current.relay.servers = JSON.stringify(ice_servers);
        current.relay.until = nowSeconds() + (ice_servers.length ? CREDENTIAL_TTL_SECONDS - 60 : 10);
        tx.update(ref, {peers: room.peers});
        return true;
      });
      if (saved && ice_servers.length) body.ice_servers = ice_servers;
    } else {
      for (const delay of [150, 350, 650, 950]) {
        if (relay?.servers !== undefined || !relay) break;
        await new Promise(resolve => setTimeout(resolve, delay));
        relay = activePeer((await ref.get()).data(), peer.hash, nowSeconds())?.relay;
      }
      if (relay?.servers && relay.key === env.TURN_KEY_ID) {
        const servers = JSON.parse(relay.servers);
        if (servers.length) body.ice_servers = servers;
      }
    }
  } catch {
    // Relay provisioning is optional. The game can still negotiate direct ICE.
  }
  return json(body, 201);
}

async function createRoom(db, data, env) {
  if (!isValidRoomCode(data?.code) || !validToken(data.host_token)) {
    return error("방 코드 또는 방장 인증값을 확인해 주세요.", 400);
  }
  const {title = "함께하는 에너지 모험", max_players: capacity = 4, password = ""} = data;
  if (typeof title !== "string" || !title.trim() || [...title].length > 15 ||
      !Number.isInteger(capacity) || capacity < 2 || capacity > 4 ||
      typeof password !== "string" || password.length > 64) {
    return error("방 제목(1~15자), 정원(2~4명), 비밀번호(최대 64자)를 확인하세요.", 400);
  }
  const hostName = typeof data.host_name === "string" ? [...data.host_name].slice(0, 6).join("") : "방장";
  const salt = password ? crypto.randomUUID() : "";
  const digest = password ? await passwordHash(password, salt) : "";
  const hash = await sha256Hex(data.host_token);
  const claim = crypto.randomUUID();
  const rooms = db.collection(collection);
  const ref = rooms.doc(data.code);
  const admitted = await db.runTransaction(async tx => {
    const snapshot = await tx.get(ref);
    const now = nowSeconds();
    if (snapshot.exists && snapshot.get("expiresAt") > now) return error("이미 사용 중인 방 코드입니다.", 409);
    const expiresAt = now + lifetime;
    const peer = {id: 1, hash, expiresAt};
    reserveRelay(peer, env, now, claim);
    tx.set(ref, {title: title.trim(), hostName, capacity, salt, digest, passwordRequired: Boolean(password),
      expiresAt, listedUntil: expiresAt, started: false, peers: [peer], signals: [], nextSignalId: 1});
    return {peer, body: {code: data.code, peer_id: 1, expires_at: expiresAt}};
  });
  if (!(admitted instanceof Response)) {
    // A closed browser cannot delete its room. Reclaim a bounded number of abandoned
    // rooms on admission, using the snapshot version to protect concurrently reused codes.
    try {
      const expired = await rooms.where("expiresAt", "<=", nowSeconds()).limit(4).select().get();
      await Promise.allSettled(expired.docs.map(doc => doc.ref.delete({lastUpdateTime: doc.updateTime})));
    } catch { /* Later admissions retry cleanup. */ }
  }
  return admissionResponse(ref, admitted, claim, env);
}

async function listRooms(db) {
  const now = nowSeconds();
  const snapshot = await db.collection(collection).where("listedUntil", ">", now).limit(100)
    .select("title", "hostName", "capacity", "passwordRequired", "peers").get();
  const rooms = snapshot.docs.map(doc => {
    const room = doc.data();
    return {code: doc.id, title: room.title, host_name: room.hostName, max_players: room.capacity,
      password_required: Number(room.passwordRequired), player_count: room.peers.filter(peer => peer.expiresAt > now).length};
  });
  rooms.sort((a, b) => a.code.localeCompare(b.code));
  return json({rooms});
}

async function joinRoom(ref, data, env) {
  if (!validToken(data?.peer_token)) return error("참가자 인증값을 확인해 주세요.", 400);
  const hash = await sha256Hex(data.peer_token);
  const claim = crypto.randomUUID();
  const admitted = await ref.firestore.runTransaction(async tx => {
    const room = (await tx.get(ref)).data();
    const now = nowSeconds();
    if (!room || room.expiresAt <= now) return error("방을 찾을 수 없거나 대기 시간이 끝났습니다.", 404);
    if (room.started) return error("이미 진행 중인 게임입니다.", 409);
    if (room.digest && (typeof data.password !== "string" || data.password.length > 64 ||
        await passwordHash(data.password, room.salt) !== room.digest)) return error("비밀번호가 올바르지 않습니다.", 403);
    const peers = room.peers.filter(peer => peer.expiresAt > now);
    let peer = peers.find(seat => seat.hash === hash);
    if (peer?.id === 1) return error("방장 자리는 참가자로 사용할 수 없습니다.", 409);
    // Discard signals in both directions before an expired seat changes hands.
    const activeIds = new Set(peers.map(seat => seat.id));
    const signals = room.signals.filter(signal => activeIds.has(signal.from) && activeIds.has(signal.to));
    if (!peer) {
      let id = 2;
      while (id <= room.capacity && activeIds.has(id)) id++;
      if (id > room.capacity) return error("게임방이 가득 찼습니다.", 409);
      peer = {id, hash};
      peers.push(peer);
    }
    peer.expiresAt = Math.max(peer.expiresAt || 0, now + lifetime);
    reserveRelay(peer, env, now, claim);
    tx.update(ref, {peers, signals});
    return {peer, body: {code: ref.id, peer_id: peer.id, host_peer_id: 1, expires_at: peer.expiresAt,
      title: room.title, max_players: room.capacity}};
  });
  return admissionResponse(ref, admitted, claim, env);
}

function inspectPost(room, hash, data) {
  const now = nowSeconds();
  const peer = activePeer(room, hash, now);
  if (!peer) return {response: unauthorized()};
  const to = Number(data?.to_peer);
  if (!Number.isInteger(to) || to < 1 || to > 4 || !signalTypes.has(data?.type) ||
      !data.data || typeof data.data !== "object") return {response: error("WebRTC 신호 형식이 올바르지 않습니다.", 400)};
  if (!room.peers.some(seat => seat.id === to && seat.expiresAt > now)) return {response: error("연결 대상이 방에 없습니다.", 404)};
  const body = JSON.stringify(data.data);
  const bytes = Buffer.byteLength(body, "utf8");
  if (bytes > 65536) return {response: error("WebRTC 신호가 너무 큽니다.", 413)};
  // Keep the entire room well below Firestore's single-document limit, even if
  // a recipient goes offline. Normal exchanges drain the queue as they connect.
  if (room.signals.length >= 256 || room.signals.reduce((n, signal) => n + signal.bytes, bytes) > 512 * 1024) {
    return {response: error("신호가 쌓여 있습니다. 잠시 후 다시 시도해 주세요.", 429)};
  }
  const id = room.nextSignalId;
  room.signals.push({id, from: peer.id, to, type: data.type, body, bytes});
  return {patch: {signals: room.signals, nextSignalId: id + 1}, response: json({accepted: true}, 202)};
}

function inspectPoll(room, hash, cursor) {
  const now = nowSeconds();
  const peer = activePeer(room, hash, now);
  if (!peer) return {response: unauthorized()};
  const patch = {};
  const newExpiry = now + lifetime;
  if (peer.expiresAt <= newExpiry - renewalInterval) {
    peer.expiresAt = newExpiry;
    patch.peers = room.peers;
    if (peer.id === 1) {
      patch.expiresAt = newExpiry;
      if (!room.started) patch.listedUntil = newExpiry;
    }
  }
  const messages = room.signals.filter(entry => entry.to === peer.id && entry.id > Number(cursor)).slice(0, 64);
  const through = cursor === null ? messages.at(-1)?.id : Number(cursor);
  if (through > 0 && room.signals.some(entry => entry.to === peer.id && entry.id <= through)) {
    patch.signals = room.signals.filter(entry => entry.to !== peer.id || entry.id > through);
  }
  const signals = messages.map(row => ({id: row.id, from_peer: row.from, type: row.type, data: JSON.parse(row.body)}));
  return {patch: Object.keys(patch).length ? patch : null, response: json({signals, expires_at: peer.expiresAt})};
}

// ICE candidates arrive in bursts. A version-checked write avoids queuing all
// those requests on a document lock. Retry against fresh seat ownership, ids,
// acknowledgements and expiry each time another request wins the race.
async function exchangeSignals(ref, inspect) {
  for (let attempt = 0; attempt < 10; attempt++) {
    const snapshot = await ref.get();
    const {response, patch} = inspect(snapshot.data());
    if (!patch) return response;
    try {
      await ref.update(patch, {lastUpdateTime: snapshot.updateTime});
      return response;
    } catch (failure) {
      if (![5, 9, 10].includes(failure.code)) throw failure;
      const delay = Math.floor(Math.random() * Math.min(100, 8 * (attempt + 1)));
      await new Promise(resolve => setTimeout(resolve, delay));
    }
  }
  return ref.firestore.runTransaction(async tx => {
    const {response, patch} = inspect((await tx.get(ref)).data());
    if (patch) tx.update(ref, patch);
    return response;
  });
}

async function pollSignals(ref, hash, request) {
  const cursor = new URL(request.url).searchParams.get("ack");
  if (cursor !== null && (!/^(0|[1-9]\d*)$/.test(cursor) || !Number.isSafeInteger(Number(cursor)))) {
    return error("신호 수신 번호가 올바르지 않습니다.", 400);
  }
  return exchangeSignals(ref, room => inspectPoll(room, hash, cursor));
}

export async function firebaseRoomsRoute(request, db, parts, env = {}) {
  const [namespace, route, code, action] = parts;
  const method = request.method;
  if (namespace !== "webrtc" || route !== "rooms" || parts.length > 4) return error("지원하지 않는 요청입니다.", 404);
  const data = method === "POST" ? await request.json().catch(() => null) : null;
  if (parts.length === 2 && method === "GET") return listRooms(db);
  if (parts.length === 2 && method === "POST") return createRoom(db, data, env);
  if (!isValidRoomCode(code)) return error("방 코드 형식이 올바르지 않습니다.", 400);
  const ref = db.collection(collection).doc(code);
  if (action === "join" && method === "POST") return joinRoom(ref, data, env);
  const hash = await tokenHash(request);
  if (!hash) return unauthorized();
  if (action === "signals" && method === "GET") return pollSignals(ref, hash, request);
  if (action === "signals" && method === "POST") return exchangeSignals(ref, room => inspectPost(room, hash, data));
  return db.runTransaction(async tx => {
    const room = (await tx.get(ref)).data();
    const now = nowSeconds();
    const peer = activePeer(room, hash, now);
    if (!peer) return unauthorized();
    if (action === "start" && method === "POST" && peer.id === 1) {
      if (!room.started) tx.update(ref, {started: true, listedUntil: 0});
      return json({started: true});
    }
    if (action === "leave" && method === "POST" && peer.id !== 1) {
      tx.update(ref, {peers: room.peers.filter(seat => seat.id !== peer.id),
        signals: room.signals.filter(signal => signal.from !== peer.id && signal.to !== peer.id)});
      return json({left: true});
    }
    if (parts.length === 3 && method === "DELETE" && peer.id === 1) {
      tx.delete(ref);
      return json({deleted: true});
    }
    return unauthorized();
  });
}
