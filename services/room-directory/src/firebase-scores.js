import {parseScoreRequest, scoreAlias, scoreTicketLifetime, validFinish} from "./scores.js";

const runtime = "energygameScoreRuntime";
const retention = 24 * 60 * 60;
const bests = game => `energygameLeaderboards/${game}/bests`;
export const scoreNetworkShardCount = 16;
export const scoreNetworkShardCapacity = shard => shard < 8 ? 8 : 7;
export const firebaseScorePaths = {
  best: (game, owner) => `${bests(game)}/${owner}`,
  attempt: id => `${runtime}/attempt_${id}`,
  round: (owner, key) => `${runtime}/round_${owner}_${key}`,
  player: owner => `${runtime}/player_${owner}`,
  network: (network, shard) => `${runtime}/network_${network}_${shard}`
};

async function readBoard(db, game, owner) {
  const scores = db.collection(bests(game));
  return db.runTransaction(async tx => {
    // The descending score is stored negated. A single ascending field index
    // then orders tied players by ascending document ID, as in the SQL board.
    const top = await tx.get(scores.orderBy("sortScore").limit(10));
    let rank = 0, previous = -1;
    const entries = top.docs.map((doc, index) => {
      const score = doc.get("score");
      if (score !== previous) rank = index + 1;
      previous = score;
      return {rank, alias: scoreAlias(doc.id), score, mine: doc.id === owner};
    });
    let mine = entries.find(entry => entry.mine);
    if (owner && !mine) {
      const self = await tx.get(scores.doc(owner));
      if (self.exists) {
        const score = self.get("score");
        const higher = await tx.get(scores.where("sortScore", "<", -score).count());
        mine = {score, rank: higher.data().count + 1};
      }
    }
    return {game_id: game, entries, personal_best: mine?.score ?? 0,
      has_personal_best: Boolean(mine), personal_rank: mine?.rank ?? 0};
  }, {readOnly: true});
}

async function startRound(db, {owner, network, now, game, body}) {
  const id = crypto.randomUUID().replaceAll("-", "");
  const attemptRef = db.doc(firebaseScorePaths.attempt(id));
  const playerRef = db.doc(firebaseScorePaths.player(owner));
  const round = owner + ":" + body.round_key;
  const roundRef = db.doc(firebaseScorePaths.round(owner, body.round_key));
  const result = await db.runTransaction(async tx => {
    const [player, key] = await tx.getAll(playerRef, roundRef);
    if (key.exists && key.get("expiresAt") >= now) {
      const savedId = key.get("attemptId");
      const prior = await tx.get(db.doc(firebaseScorePaths.attempt(savedId)));
      const started = prior.get("started");
      if (!prior.exists || prior.get("game") !== game || now - started > scoreTicketLifetime ||
          (prior.get("score") === null && player.get("latestId") !== savedId)) {
        return {status: 409, data: {error: "stale_round"}};
      }
      return {status: 200, data: {attempt_id: savedId, expires_at: started + scoreTicketLifetime}};
    }
    const ownerStarts = (player.get("starts") ?? []).filter(time => time > now - 60);
    if (ownerStarts.length >= 5) {
      return {status: 429, data: {error: "too_many_starts"}};
    }
    // A whole class can be behind one network address. Start at a random
    // shard and use a free slot, keeping the exact 120-start rolling limit.
    const first = parseInt(id[0], 16);
    let admitted = false;
    for (let offset = 0; offset < scoreNetworkShardCount; offset++) {
      const shard = (first + offset) % scoreNetworkShardCount;
      const counter = await tx.get(db.doc(firebaseScorePaths.network(network, shard)));
      const starts = (counter.get("starts") ?? []).filter(time => time > now - 60);
      if (starts.length >= scoreNetworkShardCapacity(shard)) continue;
      tx.set(counter.ref, {starts: [...starts, now], expiresAt: now + 60});
      admitted = true;
      break;
    }
    if (!admitted) return {status: 429, data: {error: "too_many_starts"}};
    tx.create(attemptRef, {owner, game, round, started: now, score: null, expiresAt: now + retention});
    tx.set(roundRef, {attemptId: id, expiresAt: now + retention});
    tx.set(playerRef, {latestId: id, starts: [...ownerStarts, now], expiresAt: now + retention});
    return {status: 201, data: {attempt_id: id, expires_at: now + scoreTicketLifetime}};
  });
  // Cleanup runs outside admission transactions so unrelated classrooms never
  // wait for a range lock. A concurrent renewal invalidates the deletion.
  if (result.status === 201 && id[1] === "0") {
    try {
      const expired = await db.collection(runtime).where("expiresAt", "<", now).limit(96).get();
      if (!expired.empty) {
        const batch = db.batch();
        for (const old of expired.docs) batch.delete(old.ref, {lastUpdateTime: old.updateTime});
        await batch.commit();
      }
    } catch (error) {
      // Missing or changed documents will be revisited on the next cleanup.
      if (error.code !== 5 && error.code !== 9) console.warn("Score ticket cleanup deferred", error.code);
    }
  }
  return result;
}

async function finishRound(db, {owner, now, game, id, body}) {
  const attemptRef = db.doc(firebaseScorePaths.attempt(id));
  const bestRef = db.doc(firebaseScorePaths.best(game, owner));
  const rejected = await db.runTransaction(async tx => {
    const ticket = await tx.get(attemptRef);
    if (!ticket.exists || ticket.get("owner") !== owner || ticket.get("game") !== game)
      return {error: "unknown_attempt", status: 404};
    const saved = ticket.get("score");
    if (saved !== null) return saved === body.score ? null : {error: "already_finished", status: 409};
    const elapsed = now - ticket.get("started");
    if (elapsed > scoreTicketLifetime) return {error: "expired", status: 410};
    if (!validFinish(game, body.score, body.stats, elapsed)) return {error: "invalid_record", status: 422};
    const [player, best] = await tx.getAll(db.doc(firebaseScorePaths.player(owner)), bestRef);
    if (player.get("latestId") !== id) return {error: "already_finished", status: 409};
    tx.update(attemptRef, {score: body.score});
    if (!best.exists || best.get("score") < body.score) tx.set(bestRef, {score: body.score, sortScore: -body.score});
    return null;
  });
  if (rejected) return {status: rejected.status, data: {error: rejected.error}};
  return {status: 200, data: await readBoard(db, game, owner)};
}

export async function firebaseScoresRoute(request, firestore, parts) {
  const round = await parseScoreRequest(request, parts);
  if (round.error) return Response.json({error: round.error}, {status: round.status});
  if (round.type === "board") return Response.json(await readBoard(firestore, round.game, round.owner));
  const {status, data} = round.type === "start" ? await startRound(firestore, round) : await finishRound(firestore, round);
  return Response.json(data, {status});
}
