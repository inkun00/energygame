import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {routeSnapshot} from "../src/score-snapshot.js";

test("simultaneous starts survive a stale snapshot and each player can retry their own ticket", async () => {
  const schema = readFileSync(new URL("../schema.sql", import.meta.url), "utf8");
  let latest = null;
  let revision = 0;
  let conflicts = 0;
  const store = {
    async read() { return latest; },
    async save(bytes, etag) {
      if (etag !== latest?.etag) { conflicts++; return false; }
      latest = {bytes, etag: String(++revision)};
      return true;
    }
  };
  const enter = (who) => routeSnapshot(() => new Request("https://example.org/scores/wind_rhythm/attempts", {
    method: "POST", headers: {Authorization: "Bearer " + who.repeat(64)},
    body: JSON.stringify({round_key: who.repeat(32)})
  }), ["scores", "wind_rhythm", "attempts"], schema, store);
  const results = await Promise.all([enter("a"), enter("b")]);
  assert.deepEqual(results.map(r => r.status), [201, 201]);
  const tickets = await Promise.all(results.map(r => r.json()));
  assert.notEqual(tickets[0].attempt_id, tickets[1].attempt_id);
  assert.ok(conflicts >= 1);
  const retry = await Promise.all([enter("a"), enter("b")]);
  assert.deepEqual(retry.map(r => r.status), [200, 200]);
  const repeated = await Promise.all(retry.map(r => r.json()));
  assert.deepEqual(repeated.map(t => t.attempt_id), tickets.map(t => t.attempt_id));
});
