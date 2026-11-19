import assert from "node:assert/strict";
import {randomBytes} from "node:crypto";
import test from "node:test";
import {firebaseScorePaths, firebaseScoresRoute} from "../src/firebase-scores.js";
import {parseScoreRequest, scoreAlias} from "../src/scores.js";

function request(parts, token, body) {
  return new Request("http://localhost/" + parts.join("/"), {
    method: body === undefined ? "GET" : "POST",
    headers: token ? {Authorization: "Bearer " + token} : {},
    body: body === undefined ? undefined : JSON.stringify(body)
  });
}

test("invalid public requests are rejected before any Firestore read", async () => {
  for (const [parts, token, body, status] of [
    [["scores", "unknown"], "", undefined, 404],
    [["scores", "solar_align"], "untrusted", undefined, 401],
    [["scores", "solar_align", "attempts"], "", {}, 401],
    [["scores", "solar_align", "attempts"], "a".repeat(64), {round_key: "bad"}, 400],
    [["scores", "solar_align", "attempts"], "a".repeat(64), {payload: "a".repeat(1200)}, 413]
  ]) {
    const response = await firebaseScoresRoute(request(parts, token, body), null, parts);
    assert.equal(response.status, status);
  }
});

test("Firestore preserves tickets, ranks and personal bests across retries", {
  skip: !process.env.FIRESTORE_EMULATOR_HOST
}, async () => {
  const {Firestore} = await import("@google-cloud/firestore");
  // Keep test data isolated from the application and from simultaneous runs.
  // This SDK call only targets the configured local Firestore emulator.
  const db = new Firestore({projectId: "demo-scores-" + randomBytes(5).toString("hex")});
  const game = "solar_align";
  const token = randomBytes(32).toString("hex");
  const rival = randomBytes(32).toString("hex");
  const parts = ["scores", game];
  const {owner} = await parseScoreRequest(request(parts, token), parts);
  const call = (parts, token, body) => firebaseScoresRoute(request(parts, token, body), db, parts);
  const start = (key, gameId = game) => call(["scores", gameId, "attempts"], token, {round_key: key.padStart(32, "0")});
  const finish = (id, score, who = token) => call([...parts, "attempts", id], who,
    {score, stats: {attempts: 4, correct: 4, active_input: true}});
  const makePlayable = (id, age = 30) => db.doc(firebaseScorePaths.attempt(id))
    .update({started: Math.floor(Date.now() / 1000) - age});

  try {
    const initial = await Promise.all([start("1"), start("1")]);
    assert.deepEqual(initial.map(r => r.status).sort(), [200, 201]);
    const [first, duplicate] = await Promise.all(initial.map(r => r.json()));
    assert.equal(first.attempt_id, duplicate.attempt_id);
    assert.equal((await start("1", "heat_leak")).status, 409);
    assert.equal((await finish(first.attempt_id, 120)).status, 422);
    assert.equal((await finish(first.attempt_id, 120, rival)).status, 404);
    await makePlayable(first.attempt_id);
    const simultaneous = await Promise.all([finish(first.attempt_id, 120), finish(first.attempt_id, 225)]);
    assert.deepEqual(simultaneous.map(r => r.status).sort(), [200, 409]);
    const winningScore = (await simultaneous.find(r => r.ok).json()).personal_best;
    assert.equal((await finish(first.attempt_id, winningScore)).status, 200);
    const second = await (await start("2")).json();
    await makePlayable(second.attempt_id);
    assert.equal((await (await finish(second.attempt_id, 50)).json()).personal_best, winningScore);
    // Seed ties and enough players to force the out-of-top-ten count query.
    const batch = db.batch();
    for (let i = 1; i <= 12; i++) {
      const score = i < 3 ? 490 : 490 - i;
      batch.set(db.doc(firebaseScorePaths.best(game, String(i).padStart(64, "0"))), {score, sortScore: -score});
    }
    await batch.commit();
    const board = await (await call(parts, token)).json();
    assert.equal(board.personal_rank, 13);
    assert.equal(board.entries.length, 10);
    assert.deepEqual(board.entries.slice(0, 3).map(e => e.rank), [1, 1, 3]);
    assert.equal(board.entries[0].alias, scoreAlias("1".padStart(64, "0")));
    assert.equal(board.entries.some(e => e.mine || "owner" in e), false);
    assert.equal(board.has_personal_best, true);
    assert.equal((await (await call(["scores", "wind_rhythm"], token)).json()).has_personal_best, false);
    const stale = await (await start("3")).json();
    const expired = await (await start("4")).json();
    await makePlayable(stale.attempt_id);
    assert.equal((await finish(stale.attempt_id, 50)).status, 409);
    await makePlayable(expired.attempt_id, 950);
    assert.equal((await finish(expired.attempt_id, 50)).status, 410);
    assert.equal((await start("5")).status, 201);
    assert.equal((await start("6")).status, 429);
    assert.equal((await db.doc(firebaseScorePaths.best(game, owner)).get()).get("score"), winningScore);
  } finally {
    await db.terminate();
  }
});

test("students behind one school IP can start simultaneously within the 120-ticket budget", {
  skip: !process.env.FIRESTORE_EMULATOR_HOST
}, async () => {
  const {Firestore} = await import("@google-cloud/firestore");
  const db = new Firestore({projectId: "demo-class-" + randomBytes(5).toString("hex")});
  const parts = ["scores", "solar_align", "attempts"];
  const time = Math.floor(Date.now() / 1000);
  const networkKey = Math.floor(time / 86400) + "/local";
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(networkKey));
  const network = Buffer.from(hash).toString("hex");
  const group = Array.from({length: 30}, () => randomBytes(32).toString("hex"));
  const issue = token => firebaseScoresRoute(request(parts, token, {round_key: "0".repeat(32)}), db, parts);
  try {
    // Leave exactly thirty slots across sixteen shards.
    const batch = db.batch();
    for (let shard = 0; shard < 16; shard++) {
      const used = shard < 10 ? 6 : 5;
      batch.set(db.doc(firebaseScorePaths.network(network, shard)), {starts: Array(used).fill(time), expiresAt: time + 60});
    }
    await batch.commit();
    const calls = await Promise.all(group.map(issue));
    assert.ok(calls.every(r => r.status === 201));
    const retries = await Promise.all(group.map(issue));
    assert.ok(retries.every(r => r.status === 200));
    assert.equal((await issue(randomBytes(32).toString("hex"))).status, 429);
  } finally {
    await db.terminate();
  }
});
