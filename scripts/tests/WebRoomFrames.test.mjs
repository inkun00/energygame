import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { runInNewContext } from "node:vm";

const shell = readFileSync(new URL("../../web/loading.html", import.meta.url), "utf8");
const scheduler = shell.match(/<script id="online-room-frames">([\s\S]*?)<\/script>/)[1];

function createBrowser() {
  const frames = new Map();
  const timers = new Map();
  const document = new EventTarget();
  document.hidden = false;
  let nextId = 0;
  let now = 0;
  const window = {
    requestAnimationFrame(callback) {
      frames.set(++nextId, callback);
      return nextId;
    },
    cancelAnimationFrame(id) { frames.delete(id); },
  };
  runInNewContext(scheduler, {
    window, document, performance: { now: () => now },
    setTimeout(callback, delay) {
      timers.set(++nextId, { callback, delay });
      return nextId;
    },
    clearTimeout(id) { timers.delete(id); },
  });
  return {
    window, frames, timers,
    hide(hidden) {
      document.hidden = hidden;
      document.dispatchEvent(new Event("visibilitychange"));
    },
    paint(id, timestamp) {
      const callback = frames.get(id);
      assert.ok(callback);
      frames.delete(id);
      callback(timestamp);
    },
    tickTimer() {
      assert.equal(timers.size, 1);
      const [id, { callback, delay }] = timers.entries().next().value;
      timers.delete(id);
      assert.ok(delay >= 250 && delay <= 500);
      now += delay;
      callback();
    },
  };
}

test("a hidden room host keeps polling from an already queued frame", () => {
  const { window, frames, timers, hide, paint, tickTimer } = createBrowser();
  const ticks = [];
  const poll = timestamp => {
    ticks.push(timestamp);
    window.requestAnimationFrame(poll);
  };
  const firstId = window.requestAnimationFrame(poll);
  const lateNativeFrame = frames.get(firstId);
  hide(true);
  assert.equal(timers.size, 0);
  window.setEnergyGameOnlineFrames(true);
  window.setEnergyGameOnlineFrames(true);
  tickTimer();
  tickTimer();
  lateNativeFrame(999);
  assert.equal(ticks.length, 2);
  assert.ok(ticks[1] > ticks[0]);
  hide(false);
  assert.equal(timers.size, 0);
  assert.equal(frames.size, 1);
  paint(frames.keys().next().value, 1050);
  assert.equal(ticks.length, 3);
  assert.equal(ticks.at(-1), 1050);
  assert.equal(timers.size, 0);
});

test("leaving, becoming visible, and cancellation preserve native frame behavior", () => {
  const { window, frames, timers, hide, paint } = createBrowser();
  const ticks = [];
  window.setEnergyGameOnlineFrames(true);
  const id = window.requestAnimationFrame(timestamp => ticks.push(timestamp));
  assert.equal(timers.size, 0);
  hide(true);
  const staleTimer = timers.values().next().value.callback;
  hide(false);
  staleTimer();
  assert.deepEqual(ticks, []);
  hide(true);
  window.setEnergyGameOnlineFrames(false);
  assert.equal(timers.size, 0);
  paint(id, 12);
  assert.deepEqual(ticks, [12]);
  const canceledId = window.requestAnimationFrame(timestamp => ticks.push(timestamp));
  assert.equal(timers.size, 0);
  window.setEnergyGameOnlineFrames(true);
  const canceledTimer = timers.values().next().value.callback;
  window.cancelAnimationFrame(canceledId);
  canceledTimer();
  assert.equal(timers.size, 0);
  assert.equal(frames.has(canceledId), false);
  assert.deepEqual(ticks, [12]);
});

test("a native frame that wins the race cancels its hidden-room timer", () => {
  const { window, timers, hide, paint } = createBrowser();
  const ticks = [];
  window.setEnergyGameOnlineFrames(true);
  hide(true);
  const id = window.requestAnimationFrame(timestamp => ticks.push(timestamp));
  const staleTimer = timers.values().next().value.callback;
  paint(id, 7);
  staleTimer();
  assert.equal(timers.size, 0);
  assert.deepEqual(ticks, [7]);
});
