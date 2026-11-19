import assert from "node:assert/strict";
import {mkdtempSync, readFileSync, rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {DatabaseSync} from "node:sqlite";
import test from "node:test";
import {firebaseScorePaths as paths} from "../src/firebase-scores.js";
import {readScores, syncScores} from "../tools/migrate-scores.mjs";

test("SQLite import keeps zeroes, tie order, ticket retries and concurrent Firebase progress on replay", async t => {
  const root = mkdtempSync(join(tmpdir(), "score-migration-"));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const file = join(root, "source.sqlite");
  const sql = new DatabaseSync(file);
  sql.exec(readFileSync(new URL("../schema.sql", import.meta.url), "utf8"));
  const game = "solar_align", owner = "a".repeat(64), network = "f".repeat(64);
  const other = "b".repeat(64), older = "1".repeat(32), newer = "2".repeat(32), now = 250000;
  const start = sql.prepare("INSERT INTO score_attempts(id,owner,game,round_key,started,network,score) VALUES(?,?,?,?,?,?,?)");
  start.run("0".repeat(32), owner, game, "0".repeat(32), now - 86401, network, null);
  start.run(older, owner, game, older, now - 10, network, 0);
  start.run(newer, owner, game, newer, now - 10, network, null);
  for (const [player, score] of [[owner, 0], [other, 200]]) {
    sql.prepare("INSERT INTO arcade_bests(game,owner,score) VALUES(?,?,?)").run(game, player, score);
  }
  sql.close();
  const source = readScores(file, now);
  assert.equal(source.bests.length, 2);
  assert.equal(source.attempts.length, 2);
  const docs = new Map();
  const ref = path => ({path, get: () => ({data: () => docs.get(path)})});
  const db = {
    doc: ref,
    getAll: (...refs) => refs.map(r => r.get()),
    runTransaction: fn => fn({
      get: r => r.get(), getAll: (...refs) => refs.map(r => r.get()),
      set: (r, value) => docs.set(r.path, value)
    })
  };
  const sync = verify => syncScores(db, source, verify, () => now);
  await assert.rejects(sync(true), /best is missing/);
  assert.equal((await sync(false)).attemptChanges, 2);
  await sync(true);
  assert.equal(docs.get(paths.best(game, owner)).score, 0);
  assert.equal(docs.get(paths.player(owner)).latestId, newer);
  assert.deepEqual(docs.get(paths.network(network, 0)).starts, [now - 10]);
  assert.deepEqual(docs.get(paths.network(network, 1)).starts, [now - 10]);
  assert.deepEqual(docs.get(paths.round(owner, newer)), {attemptId: newer, expiresAt: now - 10 + 86400});
  assert.equal(docs.get(paths.attempt(older)).round, owner + ":" + older);
  assert.equal((await sync(false)).attemptChanges, 0);
  assert.equal((await sync(false)).bestChanges, 0);
  // Firebase completed the imported pending round and accepted a subsequent
  // launch in the same second. Replaying the snapshot must retain both.
  docs.get(paths.best(game, owner)).score = 320;
  docs.get(paths.best(game, owner)).sortScore = -320;
  docs.get(paths.attempt(newer)).score = 320;
  docs.get(paths.player(owner)).latestId = "3".repeat(32);
  assert.equal((await sync(false)).attemptChanges, 0);
  assert.equal((await sync(false)).bestChanges, 0);
  assert.equal(docs.get(paths.attempt(newer)).score, 320);
  assert.equal(docs.get(paths.player(owner)).latestId, "3".repeat(32));
  await sync(true);
});
