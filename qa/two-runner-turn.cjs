const fs = require("node:fs/promises");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const { randomInt, randomBytes, generateKeyPairSync, diffieHellman, createPublicKey, createCipheriv, createDecipheriv } = require("node:crypto");
const { setTimeout: sleep } = require("node:timers/promises");
const deps = path.join(process.env.RUNNER_TEMP, "rtc-deps", "node_modules");
const { chromium } = require(path.join(deps, "playwright-core"));
const { DefaultArtifactClient } = require(path.join(deps, "@actions/artifact"));

module.exports = async ({ github, context }) => {
  if (process.env.LIVE_RELAY_CHECK !== "approved" || context.ref !== "refs/heads/qa/two-runner-turn-20261120") throw new Error("Live verification not enabled");
  const role = process.env.ROLE;
  if (!["guest", "host"].includes(role)) throw new Error("Unknown diagnostic role");
  const other = role === "host" ? "guest" : "host";
  const folder = await fs.mkdtemp(path.join(process.env.RUNNER_TEMP, "rtc-peer-"));
  const artifacts = new DefaultArtifactClient();
  const repo = context.repo;

  async function publish(name, data) {
    name = String(process.env.GITHUB_RUN_ATTEMPT) + "-" + name;
    const file = path.join(folder, name + ".bin");
    await fs.writeFile(file, data);
    await artifacts.uploadArtifact(name, [file], folder, { retentionDays: 1 });
  }
  async function receive(name) {
    name = String(process.env.GITHUB_RUN_ATTEMPT) + "-" + name;
    const deadline = Date.now() + 90000;
    while (Date.now() < deadline) {
      const result = await github.rest.actions.listWorkflowRunArtifacts({ ...repo, run_id: context.runId, per_page: 50 });
      const artifact = result.data.artifacts.find(item => item.name === name && !item.expired);
      if (artifact) {
        let archive;
        try { archive = await github.rest.actions.downloadArtifact({ ...repo, artifact_id: artifact.id, archive_format: "zip" }); }
        catch (err) { if (![404, 502, 503, 504].includes(err.status)) throw err; await sleep(1000); continue; }
        const zip = path.join(folder, name + ".zip");
        await fs.writeFile(zip, Buffer.from(archive.data));
        return execFileSync("unzip", ["-p", zip, name + ".bin"]);
      }
      await sleep(2500);
    }
    throw new Error("Paired runner did not publish " + name);
  }
  const keys = generateKeyPairSync("x25519");
  await publish(role + "-public-key", keys.publicKey.export({ type: "spki", format: "pem" }));
  const shared = diffieHellman({ privateKey: keys.privateKey, publicKey: createPublicKey(await receive(other + "-public-key")) });
  const base = "https://energygame-room-directory.energygame-room-directory.workers.dev/webrtc/rooms";
  const token = randomBytes(32).toString("hex");
  let code;
  let ownsRoom = false;
  let possiblyOwnedRoom = false;
  let admittedGuest = false;
  let page;
  let browser;
  function encrypt(data) {
    const iv = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", shared, iv);
    const encrypted = Buffer.concat([cipher.update(JSON.stringify(data)), cipher.final()]);
    return Buffer.concat([iv, cipher.getAuthTag(), encrypted]);
  }
  function decrypt(data) {
    const cipher = createDecipheriv("aes-256-gcm", shared, data.subarray(0, 12));
    cipher.setAuthTag(data.subarray(12, 28));
    return JSON.parse(Buffer.concat([cipher.update(data.subarray(28)), cipher.final()]));
  }
  async function request(method, suffix, body, authenticated = true, allowed = [200, 201, 202]) {
    const response = await fetch(base + suffix, {
      method, redirect: "error", signal: AbortSignal.timeout(9000),
      headers: { "Content-Type": "application/json", ...(authenticated ? { Authorization: "Bearer " + token } : {}) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) })
    });
    if (!allowed.includes(response.status)) throw new Error("Room service returned HTTP " + response.status);
    return { status: response.status, data: await response.json() };
  }
  function permittedRelayServers(data) {
    const results = [];
    for (const server of data.ice_servers || []) {
      if (!Array.isArray(server.urls) || !server.username || !server.credential) continue;
      const urls = server.urls.filter(url => url === "turns:turn.cloudflare.com:443?transport=tcp");
      if (urls.length) results.push({ urls, username: server.username, credential: server.credential });
    }
    const status = data.relay_status;
    if (status && typeof status === "object") {
      const known = new Set(["storage_claim", "storage_save", "bindings_absent", "upstream_http", "upstream_timeout", "upstream_fetch", "upstream_shape", "save_or_empty", "issued"]);
      const stage = known.has(status.stage) ? status.stage : "unrecognized";
      const code = Number(status.code);
      const summary = { stage };
      if (Number.isInteger(code) && code >= 100 && code <= 599) summary.code = code;
      if (typeof status.id32 === "boolean") summary.id32 = status.id32;
      if (typeof status.token64 === "boolean") summary.token64 = status.token64;
      console.log("ISSUER_STATUS", role, JSON.stringify(summary));
    }
    console.log("ADMISSION_ICE_SHAPE", role, JSON.stringify({ field: Array.isArray(data.ice_servers) ? "array" : typeof data.ice_servers, tls443: results.length, entries: (Array.isArray(data.ice_servers) ? data.ice_servers : []).map(server => ({ turnUris: (Array.isArray(server?.urls) ? server.urls : []).filter(url => typeof url === "string" && /^turns?:/.test(url)).length, username: typeof server?.username === "string", credential: typeof server?.credential === "string" })) }));
    return results;
  }
  async function reserve() {
    if (role === "host") {
      const password = randomBytes(24).toString("base64url");
      for (let attempt = 0; attempt < 4; attempt++) {
        code = String(randomInt(100000, 1000000));
        possiblyOwnedRoom = true;
        const r = await request("POST", "", { code, password, host_token: token, title: "QA Relay Check", host_name: "QA", max_players: 2 }, false, [201, 409]);
        if (r.status === 409) { possiblyOwnedRoom = false; continue; }
        ownsRoom = true;
        const ice = permittedRelayServers(r.data);
        await publish("private-invitation", encrypt({ code, password }));
        if (!ice.length) {
          await receive("guest-admission-checked");
          throw new Error("Production host admission did not include a usable TLS 443 grant");
        }
        return ice;
      }
      throw new Error("Temporary private room code unavailable");
    }
    const invitation = decrypt(await receive("private-invitation"));
    code = invitation.code;
    if (!/^\d{6}$/.test(code)) throw new Error("Invalid diagnostic invitation");
    admittedGuest = true;
    const r = await request("POST", "/" + code + "/join", { password: invitation.password, peer_token: token }, false);
    if (r.data.peer_id !== 2) throw new Error("Unexpected private room seat");
    const ice = permittedRelayServers(r.data);
    await publish("guest-admission-checked", Buffer.from("checked"));
    if (!ice.length) throw new Error("Production guest admission did not include a usable TLS 443 grant");
    return ice;
  }
  async function pollDescription(type) {
    const until = Date.now() + 65000;
    while (Date.now() < until) {
      const r = await request("GET", "/" + code + "/signals?ack=0");
      const row = r.data.signals.find(x => x.from_peer === (role === "host" ? 2 : 1) && x.type === type);
      if (row) {
        await page.evaluate(desc => pc.setRemoteDescription(desc), { type, sdp: row.data.sdp });
        await request("GET", "/" + code + "/signals?ack=" + encodeURIComponent(row.id));
        return;
      }
      await sleep(1000);
    }
    throw new Error("Did not receive paired room SDP");
  }
  async function sendDescription(type) {
    await page.evaluate(async type => {
      await pc.setLocalDescription(type === "offer" ? await pc.createOffer() : await pc.createAnswer());
    }, type);
    await page.waitForFunction(() => window.hasRelay, undefined, { timeout: 18000 });
    const desc = await page.evaluate(() => pc.localDescription.toJSON());
    if (!desc.sdp.includes(" typ relay")) throw new Error("Relay ICE candidate absent from local SDP");
    await request("POST", "/" + code + "/signals", { to_peer: role === "host" ? 2 : 1, type, data: { sdp: desc.sdp } });
  }
  try {
    browser = await chromium.launch({ executablePath: "/usr/bin/google-chrome", headless: true });
    page = await browser.newPage();
    await page.route("https://rtc-check.invalid/", route => route.fulfill({ contentType: "text/html", body: "<title>Private TURN test</title>" }));
    await page.goto("https://rtc-check.invalid/");
    await page.evaluate(({ role, iceServers }) => {
      window.pc = new RTCPeerConnection({ iceTransportPolicy: "relay", iceServers });
      window.hasRelay = false; window.complete = false;
      window.started = performance.now(); window.echoMs = null;
      window.appBytes = { sent: 0, received: 0 };
      const count = text => new TextEncoder().encode(text).length;
      const send = text => { dc.send(text); window.appBytes.sent += count(text); };
      pc.onicecandidate = e => { if (e.candidate?.type === "relay") window.hasRelay = true; };
      window.dc = pc.createDataChannel("reliable", { negotiated: true, ordered: true, id: 1 });
      dc.onopen = () => { if (role === "guest") send("energygame-ping"); };
      dc.onmessage = e => {
        window.appBytes.received += count(e.data);
        if (role === "host" && e.data === "energygame-ping") send("energygame-echo");
        if (role === "guest" && e.data === "energygame-echo") { send("complete"); window.complete = true; window.echoMs = performance.now() - window.started; }
        if (role === "host" && e.data === "complete") { window.complete = true; window.echoMs = performance.now() - window.started; }
      };
    }, { role, iceServers: await reserve() });
    if (role === "guest") { await sendDescription("offer"); await pollDescription("answer"); }
    else { await pollDescription("offer"); await request("POST", "/" + code + "/start", {}); await sendDescription("answer"); }
    await page.waitForFunction(() => window.complete, undefined, { timeout: 45000 });
    const pair = await page.evaluate(async () => {
      const stats = await pc.getStats();
      const transport = [...stats.values()].find(e => e.type === "transport" && e.selectedCandidatePairId);
      const selected = transport ? stats.get(transport.selectedCandidatePairId) :
        [...stats.values()].find(e => e.type === "candidate-pair" && e.nominated && e.state === "succeeded");
      if (!selected) return null;
      const local = stats.get(selected.localCandidateId), remote = stats.get(selected.remoteCandidateId);
      return { local: local?.candidateType, remote: remote?.candidateType, relayProtocol: local?.relayProtocol || "unreported", appBytes: window.appBytes, echoMs: Math.round(window.echoMs) };
    });
    if (pair?.local !== "relay" || pair?.remote !== "relay") throw new Error("Data echo lacked a selected relay pair");
    console.log("TLS_443_BIDIRECTIONAL_ECHO_OK role=" + role + " selected=" + JSON.stringify(pair));
    await sleep(role === "host" ? 2200 : 500);
  } catch (error) {
    if (page) console.log("Transport state:", await page.evaluate(() => [window.pc?.connectionState, window.pc?.iceConnectionState, window.dc?.readyState]).catch(() => []));
    throw new Error(String(error.message).split("\n")[0].slice(0, 160));
  } finally {
    if (browser) await browser.close().catch(() => {});
    if (admittedGuest) await request("POST", "/" + code + "/leave", {}, true, [200, 401, 404]);
    if (ownsRoom || possiblyOwnedRoom) { const removed = await request("DELETE", "/" + code, undefined, true, ownsRoom ? [200] : [200, 401, 404]); console.log("ROOM_CLEANUP_HTTP=" + removed.status); }
  }
};
