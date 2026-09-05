import test from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import worker from "../src/index.js";

class SqliteD1 {
  constructor() {
    this.db = new DatabaseSync(":memory:");
    this.db.exec("PRAGMA foreign_keys = ON");
  }
  prepare(sql) {
    const db = this.db;
    let params = {};
    const statement = {
      bind(...args) { params = Object.fromEntries(args.map((v, i) => [`p${i + 1}`, v])); return statement; },
      async first() { return db.prepare(sql.replace(/\?(\d+)/g, ":p$1")).get(params) || null; },
      async all() { return { results: db.prepare(sql.replace(/\?(\d+)/g, ":p$1")).all(params) }; },
      async run() { return db.prepare(sql.replace(/\?(\d+)/g, ":p$1")).run(params); }
    };
    return statement;
  }
  async batch(statements) {
    this.db.exec("BEGIN");
    try { const values = []; for (const s of statements) values.push(await s.run()); this.db.exec("COMMIT"); return values; }
    catch (e) { this.db.exec("ROLLBACK"); throw e; }
  }
}
const host = "h".repeat(48), guest = "g".repeat(48);
function client(env) {
  return async (path, method = "GET", body, token) => worker.fetch(new Request(`https://test.local/webrtc/rooms${path}`, {
    method, headers: {"Content-Type": "application/json", ...(token ? {Authorization: `Bearer ${token}`} : {})},
    body: body ? JSON.stringify(body) : undefined
  }), env);
}

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
