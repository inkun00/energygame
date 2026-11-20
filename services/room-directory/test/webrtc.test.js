import test from "node:test";
import assert from "node:assert/strict";
import { SqliteD1 } from "../src/sqlite-d1.js";
import worker from "../src/index.js";

const host = "h".repeat(48), guest = "g".repeat(48);
function client(env) {
  return async (path, method = "GET", body, token) => worker.fetch(new Request(`https://test.local/webrtc/rooms${path}`, {
    method, headers: {"Content-Type": "application/json", ...(token ? {Authorization: `Bearer ${token}`} : {})},
    body: body ? JSON.stringify(body) : undefined
  }), env);
}

test("only admitted WebRTC seats receive per-seat TURN credentials and retries reuse them", async t => {
  const env = { DB: new SqliteD1(), TURN_KEY_ID: "test-id", TURN_KEY_API_TOKEN: "provider-only" };
  const req = client(env);
  const tls = "turns:turn.cloudflare.com:443?transport=tcp";
  const tlsPrimary = "turns:turn.cloudflare.com:5349?transport=tcp";
  const udp = "turn:turn.cloudflare.com:3478?transport=udp";
  const stun = "stun:stun.cloudflare.com:3478";
  const mint = t.mock.method(globalThis, "fetch", async () => {
    const name = crypto.randomUUID();
    return Response.json({ iceServers: [
      { urls: stun }, { urls: [tlsPrimary, udp, "turn:turn.cloudflare.com:53?transport=udp", "https://invalid.test"],
        username: name, credential: "temporary" }, { urls: tls }, { urls: [stun], internal: "provider-only" },
    ] }, { status: 201 });
  });
  const created = await req("", "POST", { code: "345678", host_token: host, password: "private", max_players: 2 });
  assert.equal(created.status, 201);
  const room = await created.json();
  const relay = room.ice_servers.find(server => server.credential);
  assert.deepEqual(relay.urls, [tlsPrimary, udp, tls]);
  assert.ok(!Object.hasOwn(room, "relay_status"));
  assert.equal(relay.credential, "temporary");
  assert.ok(!JSON.stringify(room).includes(env.TURN_KEY_API_TOKEN));
  const [url, options] = mint.mock.calls[0].arguments;
  assert.equal(url, "https://rtc.live.cloudflare.com/v1/turn/keys/test-id/credentials/generate-ice-servers");
  assert.equal(options.method, "POST");
  assert.equal(options.headers.Authorization, "Bearer " + env.TURN_KEY_API_TOKEN);
  assert.equal(JSON.parse(options.body).ttl, 7200);
  assert.ok(options.signal instanceof AbortSignal);
  assert.equal(options.redirect, "manual");

  const join = (peer_token, password = "private") => req("/345678/join", "POST", { peer_token, password });
  const denied = await join(guest, "wrong");
  assert.equal(denied.status, 403);
  assert.ok(!Object.hasOwn(await denied.json(), "relay_status"));
  assert.equal((await req("", "POST", { code: "345678", host_token: host })).status, 409);
  const list = await (await req("")).json();
  assert.ok(!JSON.stringify(list).includes("ice_servers"));
  assert.ok(!JSON.stringify(list).includes("relay_status"));
  const signals = await (await req("/345678/signals?ack=0", "GET", undefined, host)).json();
  assert.ok(!Object.hasOwn(signals, "ice_servers"));
  assert.ok(!Object.hasOwn(signals, "relay_status"));
  assert.equal(mint.mock.callCount(), 1);

  const admissions = await Promise.all([join(guest), join(guest)]);
  const [one, retry] = await Promise.all(admissions.map(response => response.json()));
  assert.deepEqual(one.ice_servers, retry.ice_servers);
  assert.notEqual(one.ice_servers.find(s => s.credential).username, relay.username);
  assert.deepEqual((await (await join(guest)).json()).ice_servers, one.ice_servers);
  assert.equal((await join("w".repeat(48))).status, 409);
  assert.equal(mint.mock.callCount(), 2);
  env.DB.db.prepare("UPDATE webrtc_turn_grants SET usable_until = 0 WHERE peer_id = 2").run();
  assert.notDeepEqual((await (await join(guest)).json()).ice_servers, one.ice_servers);
  assert.equal(mint.mock.callCount(), 3);
  await req("/345678/leave", "POST", {}, guest);
  assert.equal(env.DB.db.prepare("SELECT COUNT(*) AS n FROM webrtc_turn_grants").get().n, 1);
  await req("/345678", "DELETE", undefined, host);
  assert.equal(env.DB.db.prepare("SELECT COUNT(*) AS n FROM webrtc_turn_grants").get().n, 0);
});

test("absent, timed-out or unusable TURN provisioning leaves admission available", async t => {
  const env = { DB: new SqliteD1(), TURN_KEY_ID: "test-id" };
  const req = client(env);
  const failureResponses = [
    () => { throw new DOMException("test timeout", "TimeoutError"); },
    () => new Response("provider error", { status: 503 }),
    () => Response.json({ iceServers: [{ urls: "turns:turn.cloudflare.com:443?transport=tcp" }] }),
    () => { throw new TypeError("private-upstream-error-detail"); },
    () => new Response("private-invalid-json"),
    () => Response.redirect("https://example.invalid/never-follow", 302),
  ];
  const provider = t.mock.method(globalThis, "fetch", () => failureResponses.shift()());
  const create = code => req("", "POST", { code, host_token: host });
  const disabled = await create("345678");
  assert.equal(disabled.status, 201);
  const absent = await disabled.json();
  assert.ok(!Object.hasOwn(absent, "ice_servers"));
  assert.deepEqual(absent.relay_status, { stage: "bindings_absent", id32: false, token64: false });
  assert.equal(provider.mock.callCount(), 0);
  env.TURN_KEY_API_TOKEN = "provider-only";
  for (const [code, expected] of [
    ["345679", { stage: "upstream_timeout" }], ["345680", { stage: "upstream_http", code: 503 }],
    ["345681", { stage: "upstream_shape" }], ["345682", { stage: "upstream_fetch", error_name: "TypeError" }],
    ["345683", { stage: "upstream_shape" }], ["345684", { stage: "upstream_http", code: 302 }],
  ]) {
    const response = await create(code);
    assert.equal(response.status, 201);
    const result = await response.json();
    assert.ok(!Object.hasOwn(result, "ice_servers"));
    assert.deepEqual(result.relay_status, { ...expected, id32: false, token64: false });
    assert.ok(!JSON.stringify(result).includes("private-"));
  }
  assert.equal(provider.mock.callCount(), 6);
  env.DB.db.exec("DROP TABLE webrtc_turn_grants");
  const join = await req("/345678/join", "POST", { peer_token: guest });
  assert.equal(join.status, 201);
  assert.deepEqual((await join.json()).relay_status, { stage: "storage_claim", id32: false, token64: false });
  assert.equal(provider.mock.callCount(), 6);
});

test("a lost poll is replayed until acknowledged while legacy peers consume their own inbox once", async () => {
  const env = { DB: new SqliteD1() }, req = client(env);
  await req("", "POST", {code: "345678", host_token: host});
  await req("/345678/join", "POST", {peer_token: guest});
  const path = "/345678/signals";
  for (const type of ["offer", "candidate"]) {
    assert.equal((await req(path, "POST", {to_peer: 1, type, data: {attempt: "first"}}, guest)).status, 202);
  }
  await req(path, "POST", {to_peer: 2, type: "answer", data: {attempt: "first"}}, host);
  const poll = async (query, token) => (await (await req(path + query, "GET", undefined, token)).json()).signals;
  const lost = await poll("?ack=0", host);
  assert.deepEqual(lost.map(signal => signal.type), ["offer", "candidate"]);
  assert.deepEqual(await poll("?ack=0", host), lost);
  for (const ack of ["-1", "1.5", "", "9007199254740992"]) {
    assert.equal((await req(path + "?ack=" + ack, "GET", undefined, host)).status, 400);
  }
  assert.deepEqual(await poll("?ack=" + lost[0].id, host), [lost[1]]);
  assert.deepEqual(await poll("?ack=" + lost[1].id, host), []);
  assert.deepEqual(await poll("?ack=" + lost[0].id, host), []);
  assert.deepEqual((await poll("", guest)).map(signal => signal.type), ["answer"]);
  assert.deepEqual(await poll("", guest), []);
});

test("a full legacy ICE signaling inbox fits within the D1 query budget", async () => {
  const env = { DB: new SqliteD1() }, req = client(env);
  await req("", "POST", {code: "345678", host_token: host});
  await req("/345678/join", "POST", {peer_token: guest});
  const insert = env.DB.db.prepare(`INSERT INTO webrtc_signals (code, from_peer, to_peer, signal_type, payload, created_at)
    VALUES ('345678', 2, 1, 'candidate', '{}', 1)`);
  for (let i = 0; i < 65; i++) insert.run();
  let queryCount = 0;
  const prepare = env.DB.prepare.bind(env.DB);
  env.DB.prepare = sql => { queryCount++; return prepare(sql); };
  const first = await (await req("/345678/signals", "GET", undefined, host)).json();
  assert.equal(first.signals.length, 64);
  assert.ok(queryCount < 10, `used ${queryCount} queries for one poll`);
  const second = await (await req("/345678/signals", "GET", undefined, host)).json();
  assert.deepEqual(second.signals.map(signal => signal.id), [first.signals[63].id + 1]);
});

test("empty polls renew host and guest leases only every 30 seconds and return the stored expiry", async t => {
  const start = 1_793_824_800;
  let now = start;
  t.mock.method(Date, "now", () => now * 1000);
  const env = { DB: new SqliteD1() }, req = client(env);
  const code = "345678";
  assert.equal((await req("", "POST", { code, host_token: host })).status, 201);
  assert.equal((await req("/345678/join", "POST", { peer_token: guest })).status, 201);
  const poll = token => req("/345678/signals?ack=0", "GET", undefined, token);
  const changes = () => env.DB.db.prepare("SELECT total_changes() AS n").get().n;
  const roomExpiry = () => env.DB.db.prepare("SELECT expires_at FROM webrtc_rooms WHERE code = ?").get(code).expires_at;
  const checkPoll = async (token, peerId, expectedExpiry, expectedChanges) => {
    const before = changes();
    const response = await poll(token);
    assert.equal(response.status, 200);
    assert.equal(changes() - before, expectedChanges);
    const stored = env.DB.db.prepare("SELECT expires_at FROM webrtc_peers WHERE code = ? AND peer_id = ?").get(code, peerId);
    assert.equal(stored.expires_at, expectedExpiry);
    assert.deepEqual(await response.json(), { signals: [], expires_at: stored.expires_at });
  };

  for (const offset of [0, 1, 29]) {
    now = start + offset;
    await checkPoll(host, 1, start + 120, 0);
    await checkPoll(guest, 2, start + 120, 0);
  }
  now = start + 30;
  await checkPoll(guest, 2, start + 150, 1);
  assert.equal(roomExpiry(), start + 120);
  await checkPoll(host, 1, start + 150, 2);
  assert.equal(roomExpiry(), start + 150);
  now = start + 59;
  await checkPoll(guest, 2, start + 150, 0);
  await checkPoll(host, 1, start + 150, 0);

  now = start + 149;
  await checkPoll(host, 1, now + 120, 2);
  now = start + 150;
  const before = changes();
  assert.equal((await poll(guest)).status, 401);
  assert.equal(changes(), before);
  const rejoined = await req("/345678/join", "POST", { peer_token: guest });
  assert.equal(rejoined.status, 201);
  assert.equal((await rejoined.json()).expires_at, now + 120);
  await checkPoll(guest, 2, now + 120, 0);
});

test("a host poll renews only the due lease when the room and host expiries differ", async t => {
  let now = 1_793_824_800;
  t.mock.method(Date, "now", () => now * 1000);
  const env = { DB: new SqliteD1() }, req = client(env);
  const code = "345678";
  await req("", "POST", { code, host_token: host });
  const changes = () => env.DB.db.prepare("SELECT total_changes() AS n").get().n;
  const checkHost = async (expectedSeat, expectedRoom) => {
    const before = changes();
    const response = await req("/345678/signals?ack=0", "GET", undefined, host);
    assert.equal(response.status, 200);
    assert.equal((await response.json()).expires_at, expectedSeat);
    assert.equal(changes() - before, 1);
    assert.equal(env.DB.db.prepare("SELECT expires_at FROM webrtc_peers WHERE code = ? AND peer_id = 1").get(code).expires_at, expectedSeat);
    assert.equal(env.DB.db.prepare("SELECT expires_at FROM webrtc_rooms WHERE code = ?").get(code).expires_at, expectedRoom);
  };

  // Earlier builds updated the two rows separately, so their leases can be out of sync.
  env.DB.db.prepare("UPDATE webrtc_rooms SET expires_at = ? WHERE code = ?").run(now + 110, code);
  now += 20;
  await checkHost(now + 100, now + 120);
  now += 10;
  await checkHost(now + 120, now + 110);
});

test("a poll whose seat changed hands cannot acknowledge or see the replacement's inbox", async () => {
  const env = { DB: new SqliteD1() }, req = client(env);
  await req("", "POST", {code: "345678", host_token: host});
  await req("/345678/join", "POST", {peer_token: guest});
  const prepare = env.DB.prepare.bind(env.DB);
  let changed = false;
  env.DB.prepare = sql => {
    if (!changed && sql.startsWith("DELETE FROM webrtc_signals")) {
      changed = true;
      env.DB.db.exec(`UPDATE webrtc_peers SET token_hash = 'replacement' WHERE peer_id = 2;
        INSERT INTO webrtc_signals (code, from_peer, to_peer, signal_type, payload, created_at)
        VALUES ('345678', 1, 2, 'answer', '{}', 1);`);
    }
    return prepare(sql);
  };
  const stale = await (await req("/345678/signals?ack=123", "GET", undefined, guest)).json();
  assert.ok(changed);
  assert.deepEqual(stale.signals, []);
  assert.equal(env.DB.db.prepare("SELECT COUNT(*) AS count FROM webrtc_signals").get().count, 1);
});

test("private room list hides secrets, enforces password and capacity, and frees departed seats", async () => {
  const env = { DB: new SqliteD1() }, req = client(env);
  assert.equal((await req("", "POST", {code: "654321", host_token: host, title: "친구들의 모험", host_name: "로코코", max_players: 2, password: "secret-test"})).status, 201);
  const listed = await (await req("")).json();
  assert.equal(listed.rooms[0].player_count, 1);
  assert.equal(listed.rooms[0].max_players, 2);
  assert.equal(listed.rooms[0].password_required, 1);
  assert.equal(JSON.stringify(listed).includes("secret-test"), false);
  assert.equal(JSON.stringify(listed).includes("password_hash"), false);
  assert.equal((await req("/654321/join", "POST", {peer_token: guest})).status, 403);
  assert.equal((await req("/654321/join", "POST", {peer_token: guest, password: "wrong"})).status, 403);
  assert.equal((await req("/654321/join", "POST", {peer_token: guest, password: "secret-test"})).status, 201);
  assert.equal((await req("/654321/join", "POST", {peer_token: "x".repeat(48), password: "secret-test"})).status, 409);
  assert.equal((await req("/654321/leave", "POST", {}, guest)).status, 200);
  assert.equal((await req("/654321/join", "POST", {peer_token: guest, password: "secret-test"})).status, 201);
  assert.equal((await req("/654321", "DELETE", undefined, guest)).status, 401);
  assert.equal((await req("/654321", "DELETE", undefined, host)).status, 200);
  assert.equal((await (await req("")).json()).rooms.length, 0);
});

test("public rooms, input validation, expiration and simultaneous last-seat joins", async () => {
  const env = { DB: new SqliteD1() }, req = client(env);
  for (const max_players of [1, 5, 2.5]) {
    assert.equal((await req("", "POST", {code: "123456", host_token: host, max_players})).status, 400);
  }
  assert.equal((await req("", "POST", {code: "123456", host_token: host, title: " "})).status, 400);
  assert.equal((await req("", "POST", {code: "123456", host_token: host, title: "가".repeat(16)})).status, 400);
  assert.equal((await req("", "POST", {code: "222222", host_token: host, title: "가".repeat(15), host_name: "가나다라마바사"})).status, 201);
  const boundaryRoom = (await (await req("")).json()).rooms.find(room => room.code === "222222");
  assert.equal(boundaryRoom.title.length, 15);
  assert.equal(boundaryRoom.host_name, "가나다라마바");
  await req("/222222", "DELETE", undefined, host);
  assert.equal((await req("", "POST", {code: "123456", host_token: host, max_players: 2})).status, 201);
  const responses = await Promise.all([guest, "a".repeat(48)].map(peer_token => req("/123456/join", "POST", {peer_token})));
  assert.deepEqual(responses.map(r => r.status).sort(), [201, 409]);
  assert.equal((await (await req("")).json()).rooms[0].player_count, 2);
  env.DB.db.exec("UPDATE webrtc_rooms SET expires_at = 0");
  assert.equal((await (await req("")).json()).rooms.length, 0);
  assert.equal((await req("/123456/join", "POST", {peer_token: guest})).status, 404);
  assert.equal((await req("", "POST", {code: "123456", host_token: host, max_players: 3})).status, 201);
});

test("started rooms stay available for authenticated signaling but reject new arrivals", async () => {
  const env = { DB: new SqliteD1() }, req = client(env);
  await req("", "POST", {code: "123456", host_token: host, max_players: 4});
  await req("/123456/join", "POST", {peer_token: guest});
  assert.equal((await req("/123456/start", "POST", {}, guest)).status, 401);
  assert.equal((await req("/123456/start", "POST", {}, host)).status, 200);
  assert.equal((await req("/123456/start", "POST", {}, host)).status, 200);
  assert.equal((await (await req("")).json()).rooms.length, 0);
  assert.equal((await req("/123456/join", "POST", {peer_token: "x".repeat(48)})).status, 409);
  assert.equal((await req("/123456/signals", "POST", {to_peer: 1, type: "offer", data: {sdp: "resume", attempt: "attempt-2"}}, guest)).status, 202);
  const polled = await (await req("/123456/signals", "GET", undefined, host)).json();
  assert.equal(polled.signals[0].from_peer, 2);
  assert.equal(polled.signals[0].data.attempt, "attempt-2");
  assert.equal((await req("/123456/signals", "GET", undefined, "x".repeat(48))).status, 401);
  await req("/123456", "DELETE", undefined, host);
  assert.equal(env.DB.db.prepare("SELECT COUNT(*) AS count FROM webrtc_started_rooms").get().count, 0);
});

test("three classmates can join together without competing for the same empty seat", async () => {
  const env = { DB: new SqliteD1() }, req = client(env);
  await req("", "POST", {code: "345678", host_token: host, max_players: 4});
  const responses = await Promise.all(["a", "b", "c"].map(letter =>
    req("/345678/join", "POST", {peer_token: letter.repeat(48)})));
  assert.deepEqual(responses.map(response => response.status), [201, 201, 201]);
  const peers = await Promise.all(responses.map(response => response.json()));
  assert.deepEqual(peers.map(peer => peer.peer_id).sort(), [2, 3, 4]);
  assert.equal((await (await req("")).json()).rooms[0].player_count, 4);
});

test("retried join requests reserve only one seat per participant credential", async () => {
  const env = { DB: new SqliteD1() }, req = client(env);
  await req("", "POST", {code: "345678", host_token: host, max_players: 4});
  const responses = await Promise.all(Array.from({length: 3}, () =>
    req("/345678/join", "POST", {peer_token: guest})));
  assert.deepEqual(responses.map(response => response.status), [201, 201, 201]);
  const peers = await Promise.all(responses.map(response => response.json()));
  assert.deepEqual(peers.map(peer => peer.peer_id), [2, 2, 2]);
  assert.equal((await (await req("/345678/join", "POST", {peer_token: guest})).json()).peer_id, 2);
  assert.equal((await (await req("")).json()).rooms[0].player_count, 2);
});

test("retrying a join near expiration renews the stored seat until the advertised deadline", async t => {
  let now = 1_793_824_800_000;
  t.mock.method(Date, "now", () => now);
  const env = { DB: new SqliteD1() }, req = client(env);
  await req("", "POST", {code: "345678", host_token: host, max_players: 4});
  const original = await (await req("/345678/join", "POST", {peer_token: guest})).json();
  now += 119_000;
  assert.equal((await req("/345678/signals", "GET", undefined, host)).status, 200);
  const retried = await (await req("/345678/join", "POST", {peer_token: guest})).json();
  assert.equal(retried.peer_id, original.peer_id);
  assert.equal(retried.expires_at, Math.floor(now / 1000) + 120);
  const stored = env.DB.db.prepare("SELECT expires_at FROM webrtc_peers WHERE code = '345678' AND peer_id = 2").get();
  assert.equal(stored.expires_at, retried.expires_at);
  now += 2_000;
  assert.ok(Math.floor(now / 1000) > original.expires_at);
  assert.equal((await req("/345678/signals", "GET", undefined, guest)).status, 200);
  assert.equal((await (await req("")).json()).rooms[0].player_count, 2);
});

test("reusing an expired seat cannot deliver the previous participant's queued signaling", async () => {
  const env = { DB: new SqliteD1() }, req = client(env);
  await req("", "POST", {code: "345678", host_token: host, max_players: 4});
  await req("/345678/join", "POST", {peer_token: guest});
  await req("/345678/signals", "POST", {to_peer: 1, type: "offer", data: {sdp: "old-offer"}}, guest);
  await req("/345678/signals", "POST", {to_peer: 2, type: "answer", data: {sdp: "old-answer"}}, host);
  env.DB.db.exec("UPDATE webrtc_peers SET expires_at = 0 WHERE peer_id = 2");
  const replacement = "r".repeat(48);
  assert.equal((await (await req("/345678/join", "POST", {peer_token: replacement})).json()).peer_id, 2);
  assert.deepEqual((await (await req("/345678/signals", "GET", undefined, replacement)).json()).signals, []);
  assert.deepEqual((await (await req("/345678/signals", "GET", undefined, host)).json()).signals, []);
  assert.equal((await req("/345678/signals", "GET", undefined, guest)).status, 401);
});

test("a game starting while a join is being prepared cannot admit an extra participant", async () => {
  const env = { DB: new SqliteD1() }, req = client(env);
  await req("", "POST", {code: "345678", host_token: host, max_players: 4});
  const prepare = env.DB.prepare.bind(env.DB);
  env.DB.prepare = sql => {
    const statement = prepare(sql);
    if (sql.startsWith("INSERT INTO webrtc_peers")) {
      const run = statement.run.bind(statement);
      statement.run = async () => {
        env.DB.db.exec("INSERT INTO webrtc_started_rooms (code) VALUES ('345678')");
        return run();
      };
    }
    return statement;
  };
  assert.equal((await req("/345678/join", "POST", {peer_token: guest})).status, 409);
  assert.equal(env.DB.db.prepare("SELECT COUNT(*) AS count FROM webrtc_peers").get().count, 1);
});
