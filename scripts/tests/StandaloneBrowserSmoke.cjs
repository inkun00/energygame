// Run after exporting Web to .godot/qa-web/index.html.
// Requires Node 22+, Playwright, Sharp, and a local Chromium installation.
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');

const runtimeModules = path.join(os.homedir(), '.cache', 'codex-runtimes', 'codex-primary-runtime',
  'dependencies', 'node', 'node_modules');
function dependency(name) {
  try { return require(name); }
  catch (error) {
    if (error.code !== 'MODULE_NOT_FOUND') throw error;
    return require(path.join(runtimeModules, name));
  }
}
const {chromium} = dependency('playwright');
const sharp = dependency('sharp');

const repo = path.resolve(__dirname, '../..');
const webRoot = path.join(repo, '.godot', 'qa-web');
const screenshotRoot = path.join(webRoot, 'qa-screenshots');
const games = ['solar_align', 'wind_rhythm', 'grid_balance', 'standby_hunt', 'hydro_gate',
  'energy_sort', 'battery_relay', 'eco_commute', 'heat_leak'];
const requested = process.argv.slice(2).filter(arg => !arg.startsWith('--'));
const selectedGames = requested.length ? games.filter(id => requested.includes(id)) : games;
const verifyFlow = process.argv.includes('--flow');
const verifyFullResults = process.argv.includes('--full-results');
const sizeArgument = process.argv.slice(2).find(arg => arg.startsWith('--size='));
const sizeMatch = sizeArgument ? /^--size=(\d+)x(\d+)$/.exec(sizeArgument) : null;
if (sizeArgument && !sizeMatch) throw new Error('Use --size=WIDTHxHEIGHT');
const viewportSize = sizeMatch ? {width: Number(sizeMatch[1]), height: Number(sizeMatch[2])} : {width: 1366, height: 768};
const port = 19191;

function chromiumExecutable() {
  if (process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH) return process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH;
  const cache = path.join(process.env.LOCALAPPDATA || '', 'ms-playwright');
  if (!fs.existsSync(cache)) return undefined;
  for (const directory of fs.readdirSync(cache).filter(name => name.startsWith('chromium_headless_shell-')).sort().reverse()) {
    const executable = path.join(cache, directory, 'chrome-headless-shell-win64', 'chrome-headless-shell.exe');
    if (fs.existsSync(executable)) return executable;
  }
  return undefined;
}

async function differentPixels(firstPng, secondPng) {
  const first = await sharp(firstPng).removeAlpha().raw().toBuffer();
  const second = await sharp(secondPng).removeAlpha().raw().toBuffer();
  if (first.length !== second.length) throw new Error('Screenshot dimensions changed');
  let changed = 0;
  for (let i = 0; i < first.length; i += 3) {
    const distance = Math.abs(first[i] - second[i]) + Math.abs(first[i + 1] - second[i + 1]) + Math.abs(first[i + 2] - second[i + 2]);
    if (distance > 75) changed++;
  }
  return changed / (first.length / 3);
}

async function main() {
  if (selectedGames.length !== (requested.length || games.length)) throw new Error('Unknown or duplicate minigame ID');
  if (verifyFlow && (selectedGames.length !== 1 || selectedGames[0] !== 'solar_align')) {
    throw new Error('--flow requires solar_align as the only game');
  }
  if (!fs.existsSync(path.join(webRoot, 'index.html'))) throw new Error('Export Web to .godot/qa-web first');
  fs.mkdirSync(screenshotRoot, {recursive: true});
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, `http://127.0.0.1:${port}`);
    const file = path.resolve(webRoot, '.' + (url.pathname === '/' ? '/index.html' : decodeURIComponent(url.pathname)));
    if (!file.startsWith(webRoot + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
      res.writeHead(404); res.end(); return;
    }
    const types = {'.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm',
      '.png': 'image/png', '.pck': 'application/octet-stream'};
    res.writeHead(200, {'Content-Type': types[path.extname(file)] || 'application/octet-stream',
      'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp'});
    fs.createReadStream(file).pipe(res);
  });
  await new Promise(resolve => server.listen(port, '127.0.0.1', resolve));
  let browser;
  try {
    browser = await chromium.launch({headless: true, executablePath: chromiumExecutable(),
      args: ['--enable-unsafe-swiftshader', '--disable-background-timer-throttling', '--disable-renderer-backgrounding']});
    const context = await browser.newContext({viewport: viewportSize, deviceScaleFactor: 1});
    for (const id of selectedGames) {
      const page = await context.newPage();
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
      await page.goto(`http://127.0.0.1:${port}/?minigame=${id}`, {waitUntil: 'domcontentloaded'});
      await page.waitForFunction(() => !document.getElementById('loading'), null, {timeout: 90000});
      await page.waitForTimeout(350);
      const guide = await page.screenshot({path: path.join(screenshotRoot, `${id}-guide.png`)});
      await page.locator('#canvas').click({position: {x: Math.floor(viewportSize.width / 2), y: Math.floor(viewportSize.height / 2)}});
      await page.keyboard.press('Enter');
      await page.waitForTimeout(4800);
      const playing = await page.screenshot({path: path.join(screenshotRoot, `${id}-playing.png`)});
      const changed = await differentPixels(guide, playing);
      if (changed < 0.08) throw new Error(`${id}: guide did not transition into play (${(changed * 100).toFixed(1)}% pixels changed)`);
      await page.keyboard.down('KeyD');
      await page.waitForTimeout(450);
      await page.keyboard.up('KeyD');
      if (id === 'solar_align' || verifyFullResults) {
        await page.waitForTimeout(id === 'eco_commute' ? 65000 : 32000);
        const result = await page.screenshot({path: path.join(screenshotRoot, `${id}-result.png`)});
        const resultChanged = await differentPixels(playing, result);
        if (resultChanged < 0.15) throw new Error(`${id}: result screen did not appear (${(resultChanged * 100).toFixed(1)}% pixels changed)`);
        if (verifyFlow) {
          const bottomButtonY = viewportSize.height - 78;
          await page.locator('#canvas').click({position: {x: Math.floor(viewportSize.width / 2) - 120, y: bottomButtonY}});
          await page.waitForTimeout(650);
          const replayGuide = await page.screenshot({path: path.join(screenshotRoot, `${id}-replay-guide.png`)});
          if (await differentPixels(result, replayGuide) < 0.05) throw new Error('Replay did not reopen the guide');
          await page.keyboard.press('Enter');
          await page.waitForTimeout(4800);
          const replayPlaying = await page.screenshot({path: path.join(screenshotRoot, `${id}-replay-playing.png`)});
          if (await differentPixels(replayGuide, replayPlaying) < 0.08) throw new Error('Replayed game did not start');
          await page.waitForTimeout(32000);
          const replayResult = await page.screenshot({path: path.join(screenshotRoot, `${id}-replay-result.png`)});
          if (await differentPixels(replayPlaying, replayResult) < 0.15) throw new Error('Replayed game did not finish');
          await page.locator('#canvas').click({position: {x: Math.floor(viewportSize.width / 2) + 120, y: bottomButtonY}});
          await page.waitForTimeout(650);
          const menu = await page.screenshot({path: path.join(screenshotRoot, `${id}-menu.png`)});
          if (await differentPixels(replayResult, menu) < 0.15) throw new Error('Other minigames button did not open the menu');
          console.log('[BrowserSmoke] replay, second result, and menu navigation passed');
        }
      }
      if (errors.length) throw new Error(`${id}: ${errors.join(' | ')}`);
      console.log(`[BrowserSmoke] ${id} loaded, started, keyboard input · changed ${(changed * 100).toFixed(1)}%`);
      await page.close({runBeforeUnload: false});
    }
    await context.close();
    console.log(`[BrowserSmoke] PASS · ${selectedGames.length} direct links at ${viewportSize.width}×${viewportSize.height}`);
  } finally {
    if (browser) await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
