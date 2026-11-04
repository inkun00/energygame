// Real browser mouse/keyboard walkthrough; screenshots are development evidence,
// not player history. Run after exporting Web to .godot/qa-web.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const http = require('node:http');
const runtime = path.join(os.homedir(), '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules');
let chromium;
try { ({chromium} = require('playwright')); }
catch { ({chromium} = require(path.join(runtime, 'playwright'))); }
const root = path.resolve(__dirname, '../../.godot/qa-web');
const captures = path.join(root, 'tutorial-browser');
const remote = process.argv.find(arg => arg.startsWith('--url='))?.slice(6);
const server = http.createServer((req, res) => {
  const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  const file = path.resolve(root, '.' + (pathname === '/' ? '/index.html' : pathname));
  if (!file.startsWith(root + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
    res.writeHead(404); res.end(); return;
  }
  const types = {'.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm'};
  res.writeHead(200, {'Content-Type': types[path.extname(file)] || 'application/octet-stream',
    'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp'});
  fs.createReadStream(file).pipe(res);
});

(async () => {
  fs.mkdirSync(captures, {recursive: true});
  if (!remote) await new Promise(resolve => server.listen(19292, '127.0.0.1', resolve));
  let browser;
  try {
    const cache = path.join(process.env.LOCALAPPDATA || '', 'ms-playwright');
    const candidate = fs.readdirSync(cache).filter(name => name.startsWith('chromium_headless_shell-')).sort().reverse()[0];
    const executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH || path.join(cache, candidate, 'chrome-headless-shell-win64/chrome-headless-shell.exe');
    browser = await chromium.launch({headless: true, executablePath,
      args: ['--enable-unsafe-swiftshader', '--disable-background-timer-throttling', '--disable-renderer-backgrounding']});
    const page = await browser.newPage({viewport: {width: 1280, height: 720}});
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
    const url = new URL(remote || 'http://127.0.0.1:19292/');
    url.searchParams.set('tutorial', '1');
    await page.goto(url.href, {waitUntil: 'domcontentloaded'});
    await page.waitForFunction(() => !document.getElementById('loading'), null, {timeout: 90000});
    const capture = async name => {
      await page.waitForTimeout(300);
      await page.screenshot({path: path.join(captures, name + '.png')});
      console.log('[TutorialBrowser] captured ' + name);
    };
    // Keep keydown alive for several WebGL frames, as a human key press does.
    const enter = async () => { await page.keyboard.press('Enter', {delay: 160}); await page.waitForTimeout(750); };
    await capture('01-dice');
    await page.mouse.click(1107, 285);
    await page.waitForTimeout(4500);
    await page.mouse.click(1130, 670);
    await capture('02-catalog');
    await page.mouse.click(1032, 255);
    await page.waitForTimeout(200);
    await enter();
    await page.waitForTimeout(4500);
    await enter();
    await capture('03-quiz-explanation');
    await enter();
    await enter();
    await capture('04-arcade-guide');
    await enter();
    await page.waitForTimeout(3800);
    await page.keyboard.down('KeyW');
    await page.waitForTimeout(400);
    await page.keyboard.up('KeyW');
    await capture('05-arcade-playing');
    await page.waitForTimeout(31000);
    await capture('06-arcade-results');
    // The software WebGL renderer can deliver fewer active frames than a real
    // laptop; allow the noncompetitive eight-second results animation to drain.
    await page.waitForTimeout(15000);
    await capture('07-reward');
    await enter();
    await capture('08-construction');
    await enter();
    await capture('09-placement-pads');
    await enter();
    await capture('10-complete');
    await enter();
    await capture('11-fresh-adventure');
    if (errors.length) throw new Error(errors.join('\n'));
    console.log('[TutorialBrowser] No browser errors. Review captures 01–11 alongside GuidedTutorialTest assertions.');
    await page.close({runBeforeUnload: false});
  } finally {
    if (browser) await browser.close();
    if (server.listening) await new Promise(resolve => server.close(resolve));
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
