// Four isolated browser sessions, real WebRTC and actual game UI controls.
// Fixtures only select scenario boundaries/materials; competitive clocks/scores are real.
// Run export_four_player_web.cjs first. Node 22+ and Playwright required.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { DatabaseSync } = require('node:sqlite');
const { pathToFileURL } = require('node:url');
let playwright;
try { playwright = require('playwright'); }
catch (error) {
  const fallback = process.env.PLAYWRIGHT_MODULE_PATH || path.join(process.env.USERPROFILE || '', '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
  if (!fs.existsSync(fallback)) throw error;
  playwright = require(fallback);
}
class SqliteD1 {
  constructor() { this.db = new DatabaseSync(':memory:'); this.db.exec('PRAGMA foreign_keys = ON'); }
  prepare(sql) {
    let args = {};
    const statement = {
      bind(...values) { args = Object.fromEntries(values.map((value, i) => [`p${i + 1}`, value])); return statement; },
      first: async () => this.db.prepare(sql.replace(/\?(\d+)/g, ':p$1')).get(args) || null,
      all: async () => ({ results: this.db.prepare(sql.replace(/\?(\d+)/g, ':p$1')).all(args) }),
      run: async () => this.db.prepare(sql.replace(/\?(\d+)/g, ':p$1')).run(args),
    };
    return statement;
  }
  async batch(statements) {
    this.db.exec('BEGIN');
    try { const result = []; for (const statement of statements) result.push(await statement.run()); this.db.exec('COMMIT'); return result; }
    catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }
}
const repo = path.resolve(__dirname, '../..');
const webRoot = path.join(repo, '.godot/four-player-web');
const output = path.join(webRoot, 'evidence');
const origin = 'http://127.0.0.1:19395';
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const games = ['solar_align', 'wind_rhythm', 'grid_balance', 'standby_hunt', 'hydro_gate', 'energy_sort', 'battery_relay', 'eco_commute', 'heat_leak'];
let pages = [], errors = [], steps = [], commands = [0, 0, 0, 0], hostHasLeft = false;
async function states() { return Promise.all(pages.map(page => page.evaluate(() => window.fourPlayerState))); }
async function waitFor(predicate, label, timeout = 60000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) {
    const snapshot = await states();
    if (snapshot.some(state => state?.error)) throw new Error(`${label}: ${JSON.stringify(snapshot.map(state => state?.error))}`);
    if (predicate(snapshot)) return snapshot;
    await delay(350);
  }
  throw new Error(`Timeout: ${label}\n${JSON.stringify(await states())}`);
}
async function command(index, action, extra = {}) {
  const sequence = ++commands[index];
  await pages[index].evaluate(value => window.fourPlayerCommand = value, { sequence, action, ...extra });
  await waitFor(ss => ss[index]?.sequence === sequence, `command ${index} ${action}`);
}
async function click(index, name) {
  const ss = await waitFor(all => all[index]?.buttons[name]?.x !== undefined && !all[index].buttons[name].disabled, `button ${index} ${name}`);
  const target = ss[index].buttons[name];
  // Godot canvas logical coordinates are 1280x720 at this fixed viewport.
  await pages[index].mouse.click(target.x, target.y, { delay: 100 });
}
async function capture(label) {
  await Promise.all(pages.map((page, i) => page.screenshot({ path: path.join(output, `${label}-player${i + 1}.png`) })));
}
function equalAll(snapshot, select, label) {
  const expected = select(snapshot[0]);
  for (let i = 1; i < 4; i++) assert.deepEqual(select(snapshot[i]), expected, `${label}: player ${i + 1}`);
}
function passed(label, extra = {}) { steps.push({ label, ...extra }); console.log(`[PASS] ${label}`, JSON.stringify(extra)); }
async function releaseKeys() {
  await Promise.all(pages.map(async page => { for (const key of ['a', 'd', 'w', 's', 'e', 'Space']) await page.keyboard.up(key); }));
}
async function playRound(id, round) {
  await command(0, 'minigame_fixture', { id });
  let ss = await waitFor(all => all.every(s => s?.mini?.id === id && s.mini.phase === 'ready'), `${id} guide`);
  equalAll(ss, s => [s.mini.seed, s.mini.round_id, s.mini.duration], `${id} shared conditions`);
  // A participant may practice while peers ready; shared start must interrupt safely.
  if (id === 'grid_balance') {
    await click(3, 'practice');
    await waitFor(all => all[3].practice, 'remote practice started');
    await pages[3].keyboard.press('Escape', { delay: 160 });
    await waitFor(all => !all[3].practice, 'remote practice exited');
  }
  await Promise.all(pages.map((_, i) => click(i, 'mini_ready')));
  await waitFor(all => all.every(s => s.mini?.phase === 'playing' && s.playing && !s.practice), `${id} simultaneous start`);
  const started = Date.now();
  const duration = id === 'eco_commute' ? 60 : 30;
  let tick = 0, recovered = false, captured = false;
  while (Date.now() - started < (duration + 25) * 1000) {
    ss = await states();
    if (ss.every(s => s.mini?.phase === 'results')) break;
    if (id === 'grid_balance' && tick === 6) {
      const before = ss[2];
      await command(2, 'drop');
      const paused = await waitFor(all => all.every(s => s.paused), 'all four pause for reconnect');
      await delay(650);
      const stillPaused = await states();
      assert(stillPaused.every(s => s.paused), 'recovery pause observation interval');
      assert.deepEqual(stillPaused.map(s => s.local_claim.elapsed), paused.map(s => s.local_claim.elapsed), 'all four actual UI clocks freeze during recovery');
      await capture('reconnect-paused');
      await waitFor(all => all.every(s => !s.paused) && all[2].restored > before.restored, 'guest restored');
      ss = await states();
      assert.equal(ss[2].local, before.local, 'reconnected guest retains own seat');
      assert.equal(ss[2].mini.seed, before.mini.seed, 'reconnect retains round seed');
      recovered = true;
    }
    await Promise.all(pages.map(async (page, i) => {
      if (ss[i].mini?.phase !== 'playing' || ss[i].submitted) return;
      const horizontal = ((tick + i) % 8 < 4) ? 'd' : 'a';
      const vertical = ((tick + i) % 6 < 3) ? 'w' : 's';
      const keys = {
        solar_align: [horizontal, tick % 3 === 0 ? 'Space' : null],
        wind_rhythm: [horizontal, tick % 4 === 0 ? 'Space' : null],
        grid_balance: [vertical], standby_hunt: [horizontal, tick % 2 ? 'Space' : 'e'],
        hydro_gate: [tick % 3 === 0 ? 'w' : null, 'Space'], energy_sort: [horizontal],
        battery_relay: [horizontal], eco_commute: [tick % 12 < 8 ? 'd' : 's'],
        heat_leak: [horizontal, tick % 2 ? 'Space' : 'e'],
      }[id].filter(Boolean);
      for (const key of ['a', 'd', 'w', 's']) {
        if (keys.includes(key)) await page.keyboard.down(key); else await page.keyboard.up(key);
      }
      for (const key of keys.filter(key => ['Space', 'e'].includes(key))) await page.keyboard.press(key, { delay: 100 });
    }));
    if (!captured && tick > 4) { await capture(`${round}-${id}-playing`); captured = true; }
    tick++;
    await delay(600);
  }
  await releaseKeys();
  ss = await waitFor(all => all.every(s => s.mini?.phase === 'results' && s.results.length === 4), `${id} four results`, 20000);
  fs.writeFileSync(path.join(output, `${id}-results.json`), JSON.stringify(ss, null, 2));
  equalAll(ss, s => s.results, `${id} result agreement`);
  assert(ss[0].results.every(result => !result.stats?.timed_out), `${id}: every real UI score reaches the host`);
  equalAll(ss, s => s.players.map(p => p.energy), `${id} energy agreement`);
  assert(ss.every(s => s.completed.includes(id)), `${id} marked completed everywhere`);
  assert.equal(ss[0].mini.duration, duration);
  if (id === 'grid_balance') assert(recovered, 'reconnect scenario ran');
  await capture(`${round}-${id}-results`);
  passed(`Four-browser ${id}`, { duration, elapsedSeconds: Math.round((Date.now() - started) / 1000), scores: ss[0].results.map(r => r.score), rewards: ss[0].results.map(r => r.reward), recovered });
  await waitFor(all => all.every(s => !s.mini?.id && !s.mini_visible), `${id} return to board`, 25000);
}
async function main() {
  fs.mkdirSync(output, { recursive: true });
  fs.writeFileSync(path.join(output, 'network.log'), '');
  const { default: worker } = await import(pathToFileURL(path.join(repo, 'services/room-directory/src/index.js')));
  const env = { DB: new SqliteD1() };
  const server = http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url, origin);
      if (url.pathname.startsWith('/webrtc/')) {
        const chunks = []; for await (const chunk of req) chunks.push(chunk);
        const response = await worker.fetch(new Request(url, { method: req.method, headers: req.headers, body: ['GET', 'HEAD'].includes(req.method) ? undefined : Buffer.concat(chunks) }), env);
        res.writeHead(response.status, Object.fromEntries(response.headers)); res.end(Buffer.from(await response.arrayBuffer())); return;
      }
      if (url.pathname === '/favicon.ico') { res.writeHead(204); res.end(); return; }
      const file = path.resolve(webRoot, '.' + (url.pathname === '/' ? '/index.html' : decodeURIComponent(url.pathname)));
      if (!file.startsWith(webRoot + path.sep) || !fs.existsSync(file)) { res.writeHead(404); res.end(); return; }
      const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png', '.pck': 'application/octet-stream' };
      res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream', 'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp' });
      fs.createReadStream(file).pipe(res);
    } catch (error) { errors.push(String(error)); res.writeHead(500); res.end(); }
  });
  await new Promise(resolve => server.listen(19395, '127.0.0.1', resolve));
  let browser;
  try {
    browser = await playwright.chromium.launch({ headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH || undefined,
      args: [...(process.platform === 'win32' ? ['--use-angle=d3d11', '--ignore-gpu-blocklist'] : ['--enable-unsafe-swiftshader']), '--disable-background-timer-throttling', '--disable-renderer-backgrounding'] });
    for (let i = 0; i < 4; i++) {
      const context = await browser.newContext({ viewport: { width: 1280, height: 720 } });
      const page = await context.newPage(); pages.push(page);
      page.on('console', message => {
        if (message.text().includes('[Network]')) fs.appendFileSync(path.join(output, 'network.log'), `player${i + 1}: ${message.text()}\n`);
        // Deleting the host's room intentionally revokes guests' signaling credentials.
        if (hostHasLeft && message.text().includes('401 (Unauthorized)')) return;
        if (message.type() === 'error' || /SCRIPT ERROR|Parse Error/.test(message.text())) { const error = `player${i + 1}: ${message.text()}`; errors.push(error); console.error(error); }
      });
      page.on('pageerror', error => { errors.push(`player${i + 1}: ${error.message}`); console.error(error); });
    }
    // Load sequentially to avoid four simultaneous shader compilation spikes.
    for (const [index, page] of pages.entries()) {
      console.log(`[LOAD] player ${index + 1}`);
      await page.goto(origin);
      await page.waitForFunction(() => window.fourPlayerState && !document.getElementById('loading'), null, { timeout: 90000 });
      console.log(`[READY] player ${index + 1}`);
    }
    await command(0, 'create', { name: '검증1', character: 0 });
    let ss = await waitFor(all => all[0]?.code?.length === 6 && all[0].peers === 1, 'host code');
    const code = ss[0].code;
    await Promise.all([1, 2, 3].map(i => command(i, 'join', { code, name: `검증${i + 1}`, character: i })));
    ss = await waitFor(all => all.every(s => s.peers === 4), 'three simultaneous joins');
    await capture('01-lobby'); passed('Three concurrent joins, four registered participants');
    await click(0, 'start');
    ss = await waitFor(all => all.every(s => s.session && s.preparation && s.players.length === 4), 'all four preparation screens');
    assert.equal(new Set(ss.map(s => s.local)).size, 4, 'four unique seats after game start');
    await capture('02-preparation');
    await Promise.all(pages.map((_, i) => click(i, 'ready')));
    ss = await waitFor(all => all.every(s => !s.preparation) && all.some(s => s.buttons.dice?.x !== undefined && !s.buttons.dice.disabled), 'all four ready');
    assert(ss.every(s => s.players.every(p => !p.ai)), 'all four remain human');
    assert.equal(ss.filter(s => s.buttons.dice?.x !== undefined && !s.buttons.dice.disabled).length, 1, 'only current player can roll');
    const actor = ss.findIndex(s => s.buttons.dice?.x !== undefined && !s.buttons.dice.disabled);
    await click(actor, 'dice');
    await waitFor(all => all.some(s => s.state !== 0 || s.turns > 0), 'real dice action');
    // Let movement/quiz resolve using visible choices before scenario-selected rounds.
    const turnDeadline = Date.now() + 45000;
    while (Date.now() < turnDeadline) {
      ss = await states();
      await Promise.all(pages.map(async (page, i) => {
        if (ss[i].quiz.active) {
          const choice = ss[i].choices.find(c => c.x !== undefined && !c.disabled && c.answer === ss[i].quiz.answer);
          if (choice) await page.mouse.click(choice.x, choice.y, { delay: 100 });
        } else if (ss[i].buttons.quiz_next?.x !== undefined && !ss[i].buttons.quiz_next.disabled) {
          await click(i, 'quiz_next');
        }
      }));
      if (ss.every(s => s.turns > 0 && !s.quiz.visible && s.state === 0)) break;
      if (ss.some(s => s.mini?.id)) throw new Error('Dice unexpectedly reached a minigame; re-run with controlled seed');
      await delay(500);
    }
    await capture('03-board-turn'); passed('Actual dice/board controls and local turn authority');
    const selectedGames = process.env.FOUR_PLAYER_GAMES ? process.env.FOUR_PLAYER_GAMES.split(',') : games;
    for (let i = 0; i < selectedGames.length; i++) await playRound(selectedGames[i], i + 4);
    await command(0, 'market_fixture');
    await waitFor(all => all.every(s => s.market.active), 'open market');
    await capture('20-market');
    await Promise.all(pages.map((_, i) => click(i, 'market_confirm')));
    await waitFor(all => all.every(s => s.construction), 'all four market submissions -> construction');
    ss = await states(); equalAll(ss, s => s.players.map(p => p.inventory), 'shared inventories');
    await capture('21-construction');
    const card = ss[1].cards.find(c => c.x !== undefined && !c.disabled);
    assert(card, 'remote player has buildable card');
    await pages[1].mouse.click(card.x, card.y, { delay: 100 });
    await pages[1].keyboard.press('Enter', { delay: 180 });
    ss = await waitFor(all => all.every(s => s.built.length > 0), 'remote keyboard construction');
    equalAll(ss, s => [s.built, s.placements], 'authoritative shared buildings');
    await capture('22-built'); passed('Four market confirmations and remote keyboard building');
    await Promise.all(pages.map((_, i) => click(i, 'finish')));
    ss = await waitFor(all => all.every(s => s.endings === 1 && s.ending_visible), 'four ending cinematics');
    await capture('23-ending'); equalAll(ss, s => [s.players, s.built, s.placements], 'final state');
    await waitFor(all => all.every(s => !s.ending_visible && s.buttons.return?.x !== undefined), 'final results', 45000);
    await capture('24-final-results'); passed('Exactly one ending and matching final state on four screens');
    hostHasLeft = true;
    await command(0, 'host_leave');
    await waitFor(all => all.slice(1).every(s => s.paused && s.buttons.recovery_leave?.x !== undefined), 'host loss recovery overlay');
    await capture('25-host-lost');
    await Promise.all([1, 2, 3].map(i => click(i, 'recovery_leave')));
    await waitFor(all => all.every(s => s.lobby && !s.online && !s.session), 'host leave returns everyone to lobby');
    await capture('26-host-left'); passed('Host loss shows recovery and safe lobby exit on all clients');
    assert.equal(errors.length, 0, errors.join('\n'));
    console.log('[PASS] Four-browser complete online scenario');
  } catch (error) {
    if (pages.length) {
      await capture('failure').catch(() => {});
      fs.writeFileSync(path.join(output, 'failure-state.json'), JSON.stringify(await states().catch(() => []), null, 2));
    }
    throw error;
  } finally {
    fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify({ steps, errors }, null, 2));
    if (browser) await browser.close();
    await new Promise(resolve => server.close(resolve)); env.DB.db.close();
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
