import assert from "node:assert/strict";
import test from "node:test";
import worker from "../src/index.js";

class MemoryStatement {
  constructor(database, sql) {
    this.database = database;
    this.sql = sql;
    this.args = [];
  }

  bind(...args) {
    this.args = args;
    return this;
  }

  async first() {
    const room = this.database.rooms.get(this.args[0]) || null;
    if (!room) return null;
    if (this.sql.includes("expires_at >") && room.expires_at <= this.args[1]) return null;
    if (this.sql.includes("token_hash, expires_at")) {
      return { token_hash: room.token_hash, expires_at: room.expires_at };
    }
    return { ...room };
  }

  async run() {
    if (this.sql.startsWith("DELETE") && this.sql.includes("expires_at <=")) {
      const room = this.database.rooms.get(this.args[0]);
      if (room && room.expires_at <= this.args[1]) this.database.rooms.delete(this.args[0]);
    } else if (this.sql.startsWith("DELETE")) {
      this.database.rooms.delete(this.args[0]);
    } else if (this.sql.startsWith("INSERT")) {
      const [code, host_ip, port, token_hash, expires_at, updated_at] = this.args;
      if (this.database.rooms.has(code)) throw new Error("unique constraint");
      this.database.rooms.set(code, { code, host_ip, port, token_hash, expires_at, updated_at });
    } else if (this.sql.startsWith("UPDATE")) {
      const [expires_at, updated_at, code] = this.args;
      const room = this.database.rooms.get(code);
      if (room) Object.assign(room, { expires_at, updated_at });
    }
    return { success: true };
  }
}

class MemoryD1 {
  constructor() {
    this.rooms = new Map();
  }

  prepare(sql) {
    return new MemoryStatement(this, sql);
  }
}

const token = "1234567890abcdef1234567890abcdef1234567890abcdef";

function roomRequest(path, method, body, authorization = "") {
  const headers = { "CF-Connecting-IP": "203.0.113.42" };
  if (body) headers["Content-Type"] = "application/json";
  if (authorization) headers.Authorization = `Bearer ${authorization}`;
  return new Request(`https://rooms.example.test${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
}

test("room registration, lookup, heartbeat, and deletion form one complete lifecycle", async () => {
  const env = { DB: new MemoryD1() };
  const createResponse = await worker.fetch(roomRequest("/rooms", "POST", {
    code: "654321",
    port: 8910,
    host_token: token,
    public_ip: "203.0.113.42",
  }), env);
  assert.equal(createResponse.status, 201);

  const lookupResponse = await worker.fetch(roomRequest("/rooms/654321", "GET"), env);
  assert.equal(lookupResponse.status, 200);
  assert.deepEqual(await lookupResponse.json(), {
    code: "654321",
    host: "203.0.113.42",
    port: 8910,
    expires_at: env.DB.rooms.get("654321").expires_at,
  });

  const heartbeatResponse = await worker.fetch(roomRequest("/rooms/654321/heartbeat", "PUT", null, token), env);
  assert.equal(heartbeatResponse.status, 200);

  const deleteResponse = await worker.fetch(roomRequest("/rooms/654321", "DELETE", null, token), env);
  assert.equal(deleteResponse.status, 200);
  assert.equal((await worker.fetch(roomRequest("/rooms/654321", "GET"), env)).status, 404);
});

test("registration rejects a CGNAT-style public address mismatch", async () => {
  const env = { DB: new MemoryD1() };
  const response = await worker.fetch(roomRequest("/rooms", "POST", {
    code: "654321",
    port: 8910,
    host_token: token,
    public_ip: "100.64.0.10",
  }), env);
  assert.equal(response.status, 400);
});
