// Requires Node 22+ and Playwright. Uses only a local in-memory room service.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');
const { chromium } = require('playwright');
const { pathToFileURL } = require('node:url');

class SqliteD1 {
  constructor() { this.db = new DatabaseSync(':memory:'); this.db.exec('PRAGMA foreign_keys = ON'); }
  prepare(sql) {
    let args = {};
    const statement = {
      bind(...values) { args = Object.fromEntries(values.map((value, i) => [`p${i + 1}`, value])); return statement; },
      first: async () => this.db.prepare(sql.replace(/\?(\d+)/g, ':p$1')).get(args) || null,
      all: async () => ({results: this.db.prepare(sql.replace(/\?(\d+)/g, ':p$1')).all(args)}),
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

async function main() {
  const repo = path.resolve(__dirname, '../..');
  const webRoot = path.join(repo, '.godot/recovery-web');
  const { default: worker } = await import(pathToFileURL(path.join(repo, 'services/room-directory/src/index.js')));
  const env = {DB: new SqliteD1()};
  const server = http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url, 'http://127.0.0.1:19090');
      if (url.pathname.startsWith('/webrtc/')) {
        const chunks = [];
        for await (const chunk of req) chunks.push(chunk);
        const response = await worker.fetch(new Request(url, {
          method: req.method, headers: req.headers,
          body: ['GET', 'HEAD'].includes(req.method) ? undefined : Buffer.concat(chunks),
        }), env);
        res.writeHead(response.status, Object.fromEntries(response.headers));
        res.end(Buffer.from(await response.arrayBuffer()));
        return;
      }
      const file = path.resolve(webRoot, '.' + (url.pathname === '/' ? '/index.html' : decodeURIComponent(url.pathname)));
      if (!file.startsWith(webRoot + path.sep) || !fs.existsSync(file)) {res.writeHead(404); res.end(); return;}
      const types = {'.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png', '.pck': 'application/octet-stream'};
      res.writeHead(200, {'Content-Type': types[path.extname(file)] || 'application/octet-stream',
        'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp'});
      fs.createReadStream(file).pipe(res);
    } catch (error) {console.error(error); res.writeHead(500); res.end();}
  });
  await new Promise(resolve => server.listen(19090, '127.0.0.1', resolve));
  let browser;
  try {
    browser = await chromium.launch({headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH || undefined,
      args: ['--enable-unsafe-swiftshader', '--disable-background-timer-throttling', '--disable-renderer-backgrounding']});
    const context = await browser.newContext({viewport: {width: 1280, height: 720}});
    const host = await context.newPage();
    const guest = await context.newPage();
    const errors = [];
    for (const [role, page] of [['host', host], ['guest', guest]]) {
      page.on('console', msg => {
        if (msg.text().includes('[WEB TEST]')) console.log(role, msg.text());
        if (msg.type() === 'error') errors.push(`${role}: ${msg.text()}`);
      });
      page.on('pageerror', error => errors.push(`${role}: ${error.message}`));
    }
    await host.goto('http://127.0.0.1:19090/?role=host');
    await host.waitForFunction(() => ['ready', 'failed'].includes(window.recoveryTest?.status), null, {timeout: 60000});
    const initial = await host.evaluate(() => window.recoveryTest);
    if (initial.status !== 'ready') throw new Error(JSON.stringify(initial));
    await guest.goto(`http://127.0.0.1:19090/?role=client&code=${initial.code}`);
    await guest.waitForFunction(() => ['reconnecting', 'failed'].includes(window.recoveryTest?.status), null, {timeout: 60000});
    await guest.screenshot({path: path.join(webRoot, 'reconnecting.png')});
    await Promise.all([host, guest].map(async page => {
      await page.waitForFunction(() => ['passed', 'failed'].includes(window.recoveryTest?.status), null, {timeout: 60000});
      const state = await page.evaluate(() => window.recoveryTest);
      if (state.status === 'failed') throw new Error(JSON.stringify(state));
    }));
    const states = await Promise.all([host, guest].map(page => page.evaluate(() => window.recoveryTest)));
    if (states.some(state => state.status !== 'passed')) throw new Error(JSON.stringify(states));
    if (errors.length) throw new Error(errors.join('\n'));
    console.log('[PASS] Two-browser WebRTC disconnect/reconnect integration');
  } finally {
    if (browser) await browser.close();
    await new Promise(resolve => server.close(resolve));
    env.DB.db.close();
  }
}
main().catch(error => {console.error(error); process.exitCode = 1;});
