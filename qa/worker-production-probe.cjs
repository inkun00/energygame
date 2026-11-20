const {randomBytes, randomInt} = require("node:crypto");
const assert = require("node:assert/strict");

const base = "https://energygame-room-directory.energygame-room-directory.workers.dev/webrtc/rooms";
const token = () => randomBytes(24).toString("hex");
const host = token(), guests = [token(), token(), token()], password = token();
let room = "", created = false;

async function request(suffix, method, credential, body) {
  const headers = {"Accept": "application/json"};
  if (credential) headers.Authorization = "Bearer " + credential;
  if (body) headers["Content-Type"] = "application/json";
  try {
    const response = await fetch(base + suffix, {
      method, headers, body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(15000), redirect: "error"
    });
    const data = await response.json().catch(() => null);
    return {status: response.status, data};
  } catch { throw new Error("room service network error"); }
}
async function deleteOwnRoom() {
  // Even when the create response is lost, only our independently generated
  // host credential can authorize deletion of this specific test room.
  const suffix = "/" + room;
  for (let i = 0; i < 3; i++) {
    try {
      const deleted = await request(suffix, "DELETE", host);
      if (deleted.status === 200 || (deleted.status === 401 && !created)) {
        const gone = await request(suffix + "/signals?ack=0", "GET", host);
        if (gone.status === 401 || gone.status === 404) return;
      }
      if (i > 0 && deleted.status === 401) {
        const gone = await request(suffix + "/signals?ack=0", "GET", host);
        if (gone.status === 401 || gone.status === 404) return;
      }
    } catch {}
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
  throw new Error("test-room deletion could not be verified");
}
async function main() {
  try {
    for (let i = 0; i < 3; i++) {
      room = String(randomInt(100000, 1000000));
      const response = await request("", "POST", null, {
        code: room, host_token: host, password, title: "접속 점검", host_name: "점검", max_players: 4
      });
      if (response.status === 409) { room = ""; continue; }
      assert.equal(response.status, 201, "create private room");
      created = true;
      break;
    }
    assert.ok(created, "private room created");
    const suffix = "/" + room;
    const joined = await Promise.all(guests.map(peer_token =>
      request(suffix + "/join", "POST", null, {peer_token, password})));
    assert.deepEqual(joined.map(r => r.status), [201,201,201], "three admitted peers");
    assert.deepEqual(joined.map(r => r.data.peer_id).sort(), [2,3,4], "unique reserved seats");
    console.log("PASS: private host and three simultaneous guests, distinct seats 1/2/3/4");
    const locked = await request(suffix + "/start", "POST", host, {});
    assert.equal(locked.status, 200, "lock room before test signaling");
    const marker = token();
    const posted = await request(suffix + "/signals", "POST", guests[0], {
      to_peer: 1, type: "candidate", data: {attempt: marker, sdp: "QA signaling replay"}
    });
    assert.equal(posted.status, 202, "submit probe in own locked room");
    const poll = async cursor => {
      const response = await request(suffix + "/signals?ack=" + cursor, "GET", host);
      assert.equal(response.status, 200, "poll authenticated inbox");
      assert.ok(Array.isArray(response.data?.signals), "valid signal envelope");
      return response.data.signals.filter(signal => signal.data?.attempt === marker);
    };
    const first = await poll(0);
    assert.equal(first.length, 1, "first delivery");
    assert.equal(first[0].from_peer, joined[0].data.peer_id);
    const replay = await poll(0);
    const mode = replay.length === 1 && replay[0].id === first[0].id ? "ACK_CAPABLE"
      : replay.length === 0 ? "LEGACY_EAGER" : "UNEXPECTED";
    assert.notEqual(mode, "UNEXPECTED", "unexpected signaling behavior");
    assert.equal((await poll(first[0].id)).length, 0, "inbox clear after acknowledgment");
    console.log("Production room-worker fingerprint: " + mode);
    if (process.env.REQUIRE_WORKER_ACK === "1") assert.equal(mode, "ACK_CAPABLE");
  } finally {
    if (room) {
      await deleteOwnRoom();
      console.log("PASS: test room deleted and its host credential no longer accepted");
    }
  }
}
main().catch(error => {
  console.error(error.message.split("\n")[0]);
  process.exitCode = 1;
});