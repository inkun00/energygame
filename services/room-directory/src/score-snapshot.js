import {randomUUID} from "node:crypto";
import {readFile, rm, writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {setTimeout as wait} from "node:timers/promises";
import {scoresRoute} from "./scores.js";
import {SqliteD1} from "./sqlite-d1.js";

// Reuse the Worker SQL and scoring rules. A write becomes visible only after
// the private store accepts the ETag of the exact database image we read.
export async function routeSnapshot(makeRequest, parts, schema, store) {
  for (let attempt = 0; attempt < 8; attempt++) {
    const snapshot = await store.read();
    const file = join(tmpdir(), `energygame-${randomUUID()}.sqlite`);
    let db;
    try {
      if (snapshot) await writeFile(file, snapshot.bytes, {mode: 0o600});
      db = new SqliteD1(file);
      if (!snapshot) db.db.exec(schema);
      const response = await scoresRoute(makeRequest(), db, parts,
        (value, status = 200) => Response.json(value, {status}));
      const changed = db.db.prepare("SELECT total_changes() AS n").get().n > 0;
      db.db.close();
      db = null;
      if (!changed || !response.ok) return response;
      if (await store.save(await readFile(file), snapshot?.etag)) return response;
    } finally {
      db?.db.close();
      await rm(file, {force: true});
    }
    await wait(30 + Math.random() * (attempt + 1) * 80);
  }
  return Response.json({error: "server_busy"}, {status: 503});
}
