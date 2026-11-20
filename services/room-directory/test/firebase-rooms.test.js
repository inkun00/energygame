import assert from "node:assert/strict";
import {randomBytes} from "node:crypto";
import test from "node:test";
import {Firestore} from "@google-cloud/firestore";
import {firebaseRoomsRoute} from "../src/firebase-rooms.js";

const emulator = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
const code = "456789";
const newToken = () => randomBytes(24).toString("hex");

function fixture(t) {
  const db = new Firestore({projectId: "demo-rooms-" + randomBytes(5).toString("hex")});
  t.after(() => db.terminate());
  const host = newToken();
  async function call(path, method = "GET", token, body) {
    const url = new URL("/api/webrtc/rooms" + path, "http://localhost");
    const request = new Request(url, {
      method, headers: token ? {Authorization: "Bearer " + token} : {},
      body: body === undefined ? undefined : JSON.stringify(body)
    });
    return firebaseRoomsRoute(request, db, url.pathname.split("/").slice(2));
  }
  return {
    host, doc: db.doc("energygameWebRooms/" + code),
    create: (settings = {}) => call("", "POST", null, {code, host_token: host, ...settings}),
    join: (peer_token, password = "") => call("/" + code + "/join", "POST", null, {peer_token, password}),
    poll: (token, ack = 0) => call("/" + code + "/signals?ack=" + ack, "GET", token),
    send: (token, to_peer) => call("/" + code + "/signals", "POST", token, {to_peer, type: "offer", data: {sdp: "test"}}),
    action: (path, token, method = "POST") => call("/" + code + path, method, token, method === "POST" ? {} : undefined)
  };
}

test("a code admits four seats without listing and preserves ownership across retries, replacement and start", emulator, async t => {
  const f = fixture(t);
  assert.equal((await f.create({password: "5678"})).status, 201);
  const denied = newToken();
  assert.equal((await f.join(denied, "incorrect")).status, 403);
  const guests = [newToken(), newToken(), newToken()];
  const joined = await Promise.all(guests.map(token => f.join(token, "5678")));
  assert.ok(joined.every(res => res.status === 201));
  const seats = await Promise.all(joined.map(res => res.json()));
  assert.deepEqual(seats.map(s => s.peer_id).sort(), [2, 3, 4]);
  assert.equal((await (await f.join(guests[0], "5678")).json()).peer_id, seats[0].peer_id);
  assert.equal((await f.join(denied, "5678")).status, 409);
  assert.equal((await f.send(denied, 1)).status, 401);
  assert.equal((await f.action("/start", guests[0])).status, 401);

  assert.equal((await f.send(guests[0], 1)).status, 202);
  const received = (await (await f.poll(f.host)).json()).signals;
  assert.deepEqual(received.map(signal => [signal.from_peer, signal.type, signal.data.sdp]), [[seats[0].peer_id, "offer", "test"]]);
  assert.deepEqual((await (await f.poll(f.host)).json()).signals, received);
  assert.deepEqual((await (await f.poll(f.host, received[0].id)).json()).signals, []);
  const acked = (await f.doc.get()).updateTime;
  assert.deepEqual((await (await f.poll(f.host, received[0].id)).json()).signals, []);
  assert.ok(acked.isEqual((await f.doc.get()).updateTime), "repeating the acknowledgement is read-only");

  assert.equal((await f.send(f.host, seats[0].peer_id)).status, 202);
  assert.equal((await f.action("/leave", guests[0])).status, 200);
  assert.equal((await f.poll(guests[0])).status, 401);
  assert.equal((await (await f.join(denied, "5678")).json()).peer_id, seats[0].peer_id);
  assert.deepEqual((await (await f.poll(denied)).json()).signals, []);
  assert.equal((await f.action("/start", f.host)).status, 200);
  assert.equal((await f.join(newToken(), "5678")).status, 409);
  assert.equal((await f.send(denied, 1)).status, 202);
  assert.equal((await f.action("", denied, "DELETE")).status, 401);
  assert.equal((await f.action("", f.host, "DELETE")).status, 200);
  assert.equal((await f.join(newToken(), "5678")).status, 404);
});

test("empty code-room polling is read-only before renewal and idle seats expire", emulator, async t => {
  const f = fixture(t);
  const guest = newToken();
  assert.equal((await f.create()).status, 201);
  assert.equal((await f.join(guest)).status, 201);
  const version = (await f.doc.get()).updateTime;
  for (let i = 0; i < 3; i++) {
    for (const token of [f.host, guest]) {
      const result = await f.poll(token);
      assert.equal(result.status, 200);
      assert.deepEqual((await result.json()).signals, []);
    }
  }
  assert.ok(version.isEqual((await f.doc.get()).updateTime), "zero Firestore writes on empty polls");
  const now = Math.floor(Date.now() / 1000);
  const before = (await f.doc.get()).data();
  before.peers.find(peer => peer.id === 1).expiresAt = now + 60;
  before.peers.find(peer => peer.id === 2).expiresAt = now - 1;
  await f.doc.update({peers: before.peers, expiresAt: now + 60});
  const refreshed = await f.poll(f.host);
  assert.equal(refreshed.status, 200);
  const stored = (await f.doc.get()).data();
  assert.ok(stored.expiresAt >= now + 120);
  assert.equal((await refreshed.json()).expires_at, stored.expiresAt);
  assert.equal((await f.poll(guest)).status, 401);
  assert.equal((await f.poll(f.host)).status, 200);
  assert.equal((await f.join(newToken())).status, 201);
});

test("three guests can send a simultaneous signaling burst without dropping messages", emulator, async t => {
  const f = fixture(t);
  assert.equal((await f.create()).status, 201);
  const guests = [newToken(), newToken(), newToken()];
  const seats = await Promise.all(guests.map(token => f.join(token)));
  assert.ok(seats.every(res => res.status === 201));
  const sent = await Promise.all(guests.flatMap(token => Array.from({length: 6}, () => f.send(token, 1))));
  assert.ok(sent.every(res => res.status === 202));
  const {signals} = await (await f.poll(f.host)).json();
  assert.equal(signals.length, sent.length);
  assert.equal(new Set(signals.map(s => s.id)).size, sent.length);
  for (const id of [2, 3, 4]) assert.equal(signals.filter(s => s.from_peer === id).length, 6);
  assert.deepEqual((await (await f.poll(f.host, signals.at(-1).id)).json()).signals, []);
});
