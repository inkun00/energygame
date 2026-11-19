import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import worker from "../src/index.js";
import {validFinish} from "../src/scores.js";
import {SqliteD1} from "../src/sqlite-d1.js";

function fixture() {
  const db = new SqliteD1();
  db.db.exec(readFileSync(new URL("../schema.sql", import.meta.url), "utf8"));
  const call = async (path, token, body) => worker.fetch(new Request("http://test/scores/" + path, {
    method: body === undefined ? "GET" : "POST",
    headers: token ? {Authorization: "Bearer " + token} : {},
    body: body === undefined ? undefined : JSON.stringify(body),
  }), {DB: db});
  const start = (token, key, game = "solar_align") =>
    call(game + "/attempts", token, {round_key: key.toString(16).padStart(32, "0")});
  const input = score => ({score, stats: {attempts: 4, correct: 4, active_input: true}});
  const send = (id, token, score) => call("solar_align/attempts/" + id, token, input(score));
  const age = (id, delta = 30) => db.db.prepare("UPDATE score_attempts SET started=started-? WHERE id=?").run(delta,id);
  return {db, call, start, send, age, input};
}
const owner = "e".repeat(64), other = "d".repeat(64);

test("persistent per-sport bests, aliases, tied ranks and a personal rank outside the top ten", async () => {
  const {call,start,send,age} = fixture();
  for (let i = 0; i < 12; i++) {
    const token = (i + 10).toString(16).padStart(64,"0");
    const {attempt_id:id} = await (await start(token, 1)).json();
    age(id);
    assert.equal((await send(id, token, i < 2 ? 400 : 390 - i)).status, 200);
  }
  const top = await (await call("solar_align","a".padStart(64,"0"))).json();
  assert.equal(top.entries.length,10);
  assert.deepEqual(top.entries.slice(0,3).map(x=>x.rank),[1,1,3]);
  assert.equal(top.personal_best,400);
  assert.equal(top.entries.filter(x=>x.mine).length,1);
  assert.ok(top.entries.every(x=>!x.owner && /^[가-힣]+ [A-F0-9]{5}$/.test(x.alias)));
  const out = await (await call("solar_align","15".padStart(64,"0"))).json();
  assert.equal(out.personal_rank,12);
  assert.equal(out.entries.some(x=>x.mine),false);
  assert.deepEqual((await (await call("hydro_gate",owner)).json()).entries,[]);
  assert.equal((await call("made_up")).status,404);
  assert.equal((await call("solar_align","real name")).status,401);
});

test("server tickets bind one pupil, sport and round, and reject stale or conflicting finishes", async () => {
  const {call,start,send,age} = fixture();
  assert.equal((await start("", 1)).status,401);
  const issued = await start(owner, 1);
  assert.equal(issued.status,201);
  const {attempt_id:id} = await issued.json();
  assert.equal((await (await start(owner,1)).json()).attempt_id,id);
  assert.equal((await start(owner,1,"heat_leak")).status,409);
  assert.equal((await send(id,owner,300)).status,422);
  age(id);
  assert.equal((await send(id,other,300)).status,404);
  assert.equal((await send(id,owner,4999)).status,422);
  const concurrent = await Promise.all([send(id,owner,300), send(id,owner,350)]);
  assert.deepEqual(concurrent.map(r=>r.status).sort(),[200,409]);
  const best = (await (await call("solar_align",owner)).json()).personal_best;
  assert.equal((await send(id,owner,best)).status,200);
  const a = (await (await start(owner,2)).json()).attempt_id;
  age(a);
  const b = (await (await start(owner,3)).json()).attempt_id;
  assert.equal((await send(a,owner,100)).status,409);
  age(b,1000);
  assert.equal((await send(b,owner,100)).status,410);
});

test("a played zero is ranked, an idle zero is discarded, and a lower run cannot erase a personal best", async () => {
  const {call,start,send,age} = fixture();
  let id = (await (await start(owner,1)).json()).attempt_id;
  age(id);
  assert.equal((await call("solar_align/attempts/"+id, owner, {score:0, stats:{attempts:0,correct:0,active_input:false}})).status,422);
  const zero = await (await send(id,owner,0)).json();
  assert.equal(zero.has_personal_best,true);
  assert.equal(zero.personal_rank,1);
  for (const [k,score] of [[2,300],[3,45]]) {
    id = (await (await start(owner,k)).json()).attempt_id;
    age(id);
    assert.equal((await (await send(id,owner,score)).json()).personal_best,300);
  }
  const empty = await (await call("solar_align", other)).json();
  assert.equal(empty.has_personal_best,false);
});

test("admission limits launches, accepts legitimate scoring ranges for all nine sports", async () => {
  const {start} = fixture();
  for (let i=0;i<5;i++) assert.equal((await start(owner,i)).status,201);
  assert.equal((await start(owner,6)).status,429);
  assert.equal((await start(owner,0)).status,409);
  for (const game of ["solar_align","wind_rhythm","grid_balance","standby_hunt","hydro_gate","energy_sort","battery_relay","eco_commute","heat_leak"]) {
    const stats = {attempts:4,correct:2,active_input:true};
    assert.equal(validFinish(game,120,stats,60),true,game);
    assert.equal(validFinish(game,5001,stats,60),false,game);
    assert.equal(validFinish(game,0,{...stats,active_input:false},60),false,game);
  }
});
