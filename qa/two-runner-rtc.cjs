const fs = require("node:fs/promises");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const { randomBytes, generateKeyPairSync, diffieHellman, createPublicKey, createCipheriv, createDecipheriv } = require("node:crypto");
const { setTimeout: sleep } = require("node:timers/promises");
const deps = path.join(process.env.RUNNER_TEMP, "rtc-deps", "node_modules");
const { chromium } = require(path.join(deps, "playwright-core"));
const { DefaultArtifactClient } = require(path.join(deps, "@actions/artifact"));

module.exports = async ({ github, context }) => {
  const role = process.env.ROLE;
  const other = role === "host" ? "guest" : "host";
  const folder = await fs.mkdtemp(path.join(process.env.RUNNER_TEMP, "rtc-peer-"));
  const artifacts = new DefaultArtifactClient();
  const repo = context.repo;

  async function publish(name, data) {
    const file = path.join(folder, name + ".bin");
    await fs.writeFile(file, data);
    await artifacts.uploadArtifact(name, [file], folder, { retentionDays: 1 });
  }
  async function receive(name) {
    const deadline = Date.now() + 90000;
    while (Date.now() < deadline) {
      const result = await github.rest.actions.listWorkflowRunArtifacts({ ...repo, run_id: context.runId, per_page: 50 });
      const artifact = result.data.artifacts.find(item => item.name === name && !item.expired);
      if (artifact) {
        const archive = await github.rest.actions.downloadArtifact({ ...repo, artifact_id: artifact.id, archive_format: "zip" });
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
  const browser = await chromium.launch({ executablePath: "/usr/bin/google-chrome", headless: true });
  let page;
  try {
    page = await browser.newPage();
    await page.route("https://rtc-check.invalid/", route => route.fulfill({ contentType: "text/html", body: "<title>Owned WebRTC peers</title>" }));
    await page.goto("https://rtc-check.invalid/");
    await page.evaluate(role => {
      window.pc = new RTCPeerConnection({ iceServers: [
        { urls: "stun:stun.l.google.com:19302" }, { urls: "stun:stun1.l.google.com:19302" }, { urls: "stun:stun.cloudflare.com:3478" }
      ] });
      window.types = new Set();
      pc.onicecandidate = e => { if (e.candidate) window.types.add(e.candidate.type); };
      window.dc = pc.createDataChannel("reliable", { negotiated: true, ordered: true, id: 1 });
      window.complete = false;
      dc.onopen = () => { if (role === "host") dc.send("energygame-probe"); };
      dc.onmessage = e => {
        if (role === "guest" && e.data === "energygame-probe") dc.send("energygame-pong");
        if (role === "host" && e.data === "energygame-pong") { dc.send("received"); window.complete = true; }
        if (role === "guest" && e.data === "received") window.complete = true;
      };
    }, role);
    async function sendDescription(name) {
      await page.evaluate(async type => {
        await pc.setLocalDescription(type === "offer" ? await pc.createOffer() : await pc.createAnswer());
      }, name);
      await page.waitForFunction(() => pc.iceGatheringState === "complete", undefined, { timeout: 25000 }).catch(() => {});
      const desc = await page.evaluate(() => pc.localDescription.toJSON());
      const iv = randomBytes(12);
      const cipher = createCipheriv("aes-256-gcm", shared, iv);
      const encrypted = Buffer.concat([cipher.update(JSON.stringify(desc)), cipher.final()]);
      await publish(name, Buffer.concat([iv, cipher.getAuthTag(), encrypted]));
      console.log("Gathered candidate types on " + role + ":", await page.evaluate(() => Array.from(window.types).sort().join(",")));
    }
    async function receiveDescription(name) {
      const data = await receive(name);
      const decipher = createDecipheriv("aes-256-gcm", shared, data.subarray(0, 12));
      decipher.setAuthTag(data.subarray(12, 28));
      const remote = JSON.parse(Buffer.concat([decipher.update(data.subarray(28)), decipher.final()]));
      await page.evaluate(desc => pc.setRemoteDescription(desc), remote);
    }
    if (role === "host") { await sendDescription("offer"); await receiveDescription("answer"); }
    else { await receiveDescription("offer"); await sendDescription("answer"); }
    await page.waitForFunction(() => window.complete, undefined, { timeout: 45000 });
    const route = await page.evaluate(async () => {
      const stats = await pc.getStats();
      const pair = Array.from(stats.values()).find(s => s.type === "candidate-pair" && s.state === "succeeded" && s.nominated);
      return pair && [stats.get(pair.localCandidateId)?.candidateType, stats.get(pair.remoteCandidateId)?.candidateType, stats.get(pair.localCandidateId)?.protocol];
    });
    console.log("BIDIRECTIONAL_DATA_CHANNEL_OK role=" + role + " pair=" + JSON.stringify(route));
    await sleep(1200);
  } catch (error) {
    if (page) console.log("Transport state", await page.evaluate(() => ({ connection: window.pc?.connectionState, ice: window.pc?.iceConnectionState, channel: window.dc?.readyState, candidateTypes: [...(window.types || [])] })).catch(() => ({})));
    throw error;
  } finally { await browser.close(); }
};
