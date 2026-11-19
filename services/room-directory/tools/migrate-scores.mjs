import {parseArgs} from "node:util";
import {DatabaseSync} from "node:sqlite";
import {pathToFileURL} from "node:url";
import {firebaseScorePaths as paths, scoreNetworkShardCount, scoreNetworkShardCapacity} from "../src/firebase-scores.js";

const day = 86400;
const epoch = () => Math.floor(Date.now() / 1000);

export function readScores(file, now = epoch()) {
  const db = new DatabaseSync(file, {readOnly: true});
  try {
    db.exec("BEGIN");
    if (db.prepare("PRAGMA quick_check").get().quick_check !== "ok") throw new Error("SQLite integrity check failed");
    const bests = db.prepare("SELECT game,owner,score FROM arcade_bests ORDER BY game,owner").all();
    // SQLite rowid, including when two starts share a second, decides which ticket is latest.
    const attempts = db.prepare("SELECT rowid AS sequence,id,owner,game,round_key,started,network,score FROM score_attempts WHERE started>=? ORDER BY rowid").all(now - day);
    const order = new Map(attempts.map(row => [row.id, row.sequence]));
    return {bests, attempts, order};
  } finally {
    db.close();
  }
}

function fail(message) {
  throw new Error(message);
}

// Comparing with the current snapshot allows replaying an older cutover snapshot
// after players have started new rounds or posted better scores in Firestore.
function isLater(row, player, order) {
  if (!player) return true;
  const existing = order.get(player.latestId);
  if (existing !== undefined) return row.sequence > existing;
  return row.started + day > player.expiresAt;
}

function lastMinute(doc, now) {
  return (doc?.starts ?? []).filter(t => t > now - 60);
}

async function syncBest(db, row, verify) {
  const ref = db.doc(paths.best(row.game, row.owner));
  return db.runTransaction(async tx => {
    const old = (await tx.get(ref)).data();
    if (old && old.score >= row.score && old.sortScore === -old.score) return false;
    if (verify) fail("Firebase best is missing, lower than the source, or has an invalid ranking key");
    const score = Math.max(old?.score ?? 0, row.score);
    tx.set(ref, {score, sortScore: -score});
    return true;
  });
}

async function networkCounter(tx, db, row, first, now) {
  let preferred;
  for (let offset = 0; offset < scoreNetworkShardCount; offset++) {
    const shard = (first + offset) % scoreNetworkShardCount;
    const ref = db.doc(paths.network(row.network, shard));
    const starts = lastMinute((await tx.get(ref)).data(), now);
    if (!offset) preferred = {ref, starts};
    if (starts.length < scoreNetworkShardCapacity(shard)) return {ref, starts};
  }
  // If two live backends admitted more than 120 unique starts during cutover,
  // retain the actual accepted history. The new service blocks saturated shards.
  return preferred;
}

async function syncAttempt(db, row, order, verify, now, firstShard) {
  if (row.started < now - day) return false;
  const runtime = {
    owner: row.owner, game: row.game, round: row.owner + ":" + row.round_key,
    started: row.started, score: row.score, expiresAt: row.started + day
  };
  const ticketRef = db.doc(paths.attempt(row.id));
  const playerRef = db.doc(paths.player(row.owner));
  const roundRef = db.doc(paths.round(row.owner, row.round_key));
  return db.runTransaction(async tx => {
    const [ticket, player, key] = await tx.getAll(ticketRef, playerRef, roundRef);
    const old = ticket.data();
    const nonce = key.data();
    if (nonce && (nonce.attemptId !== row.id || nonce.expiresAt !== runtime.expiresAt)) fail("Existing round key points to a different attempt or expiry");
    if (old && (old.owner !== row.owner || old.game !== row.game || old.round !== runtime.round ||
        old.started !== row.started || old.expiresAt !== runtime.expiresAt)) fail("Attempt identity or timing conflict");
    if (old && old.score != null && row.score != null && old.score !== row.score) fail("Existing and imported finished attempts disagree");
    const ticketChanged = !old || (old.score === null && row.score !== null);
    const current = player.data();
    const promote = isLater(row, current, order);
    if (verify) {
      if (!nonce || ticketChanged || promote) fail("Firebase round key, attempt or latest ticket is missing or behind the source");
      return false;
    }
    const counted = !old && row.started > now - 60;
    // Inserting the ticket and adding its start to the rate counters in one transaction
    // lets repeat imports preserve two distinct starts in the same second exactly once.
    const counter = (!old || !nonce) && row.started > now - 60 ? await networkCounter(tx, db, row, firstShard, now) : null;
    if (ticketChanged) tx.set(ticketRef, runtime);
    if (!nonce) tx.set(roundRef, {attemptId: row.id, expiresAt: runtime.expiresAt});
    if (promote || counted) {
      const starts = lastMinute(current, now);
      if (counted) starts.push(row.started);
      tx.set(playerRef, {
        latestId: promote ? row.id : current.latestId, starts,
        expiresAt: promote ? runtime.expiresAt : current.expiresAt,
      });
    }
    if (counter) {
      const starts = [...counter.starts, row.started];
      tx.set(counter.ref, {starts, expiresAt: Math.max(...starts) + 60});
    }
    return Boolean(!nonce || ticketChanged || promote || counted);
  });
}

async function verifyCounters(db, attempts, now) {
  const players = new Map(), networks = new Map();
  for (const row of attempts.filter(t => t.started > now - 60)) {
    for (const [map, key] of [[players, row.owner], [networks, row.network]]) {
      if (!map.has(key)) map.set(key, []);
      map.get(key).push(row.started);
    }
  }
  function check(starts, available) {
    const remaining = [...available];
    for (const timestamp of starts) {
      const index = remaining.indexOf(timestamp);
      if (index < 0) fail("Imported last-minute starts are missing from a Firebase rate counter");
      remaining.splice(index, 1);
    }
  }
  for (const [owner, starts] of players) check(starts, (await db.doc(paths.player(owner)).get()).data()?.starts ?? []);
  for (const [network, starts] of networks) {
    const refs = Array.from({length: scoreNetworkShardCount}, (_, shard) => db.doc(paths.network(network, shard)));
    const counters = await db.getAll(...refs);
    check(starts, counters.flatMap(counter => counter.data()?.starts ?? []));
  }
}

export async function syncScores(db, source, verify = false, clock = epoch) {
  let bestChanges = 0, attemptChanges = 0;
  for (const row of source.bests) {
    if (await syncBest(db, row, verify)) bestChanges++;
  }
  const networkOrdinals = new Map();
  for (const row of source.attempts) {
    const now = clock();
    const ordinal = networkOrdinals.get(row.network) ?? 0;
    if (row.started > now - 60) networkOrdinals.set(row.network, ordinal + 1);
    if (await syncAttempt(db, row, source.order, verify, now, ordinal % scoreNetworkShardCount)) attemptChanges++;
  }
  if (verify) await verifyCounters(db, source.attempts, clock());
  return {bests: source.bests.length, retainedAttempts: source.attempts.length, bestChanges, attemptChanges};
}

async function main() {
  const {values} = parseArgs({options: {
    sqlite: {type: "string"}, project: {type: "string"}, database: {type: "string", default: "(default)"},
    apply: {type: "boolean"}, verify: {type: "boolean"},
  }});
  if (!values.sqlite || (values.apply && values.verify) || ((values.apply || values.verify) && !values.project)) {
    fail("Usage: node tools/migrate-scores.mjs --sqlite FILE [--project PROJECT_ID [--database DATABASE_ID] (--apply|--verify)]");
  }
  const source = readScores(values.sqlite);
  if (!values.apply && !values.verify) {
    console.log(JSON.stringify({bests: source.bests.length, retainedAttempts: source.attempts.length}));
    return;
  }
  const {Firestore} = await import("@google-cloud/firestore");
  const db = new Firestore({
    projectId: values.project, databaseId: values.database, preferRest: !process.env.FIRESTORE_EMULATOR_HOST
  });
  try {
    const result = await syncScores(db, source, values.verify);
    if (values.apply) await syncScores(db, source, true);
    console.log(JSON.stringify({project: values.project, database: values.database, verified: true, ...result}));
  } finally {
    await db.terminate();
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
