// Four native ENet processes against localhost; requires only Node and Godot.
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const godot = process.env.GODOT_BIN || 'Godot_v4.7.2-stable_win64_console.exe';
const logDir = path.join(root, '.godot/four-player-transport');
fs.mkdirSync(logDir, { recursive: true });
const children = [];
let failed = false;
const watchdog = setTimeout(() => {
  failed = true;
  console.error('[FAIL] Four-player transport exceeded 40 seconds');
  for (const child of children) child.kill();
}, 40_000);

Promise.all(['host', 'guest1', 'guest2', 'guest3'].map(role => new Promise(resolve => {
  const child = spawn(godot, ['--headless', '--path', root, '--script',
    'scripts/tests/FourPlayerTransportTest.gd', '--', `--role=${role}`],
  { cwd: root, windowsHide: true });
  children.push(child);
  let log = '';
  child.stdout.on('data', chunk => { log += chunk.toString(); });
  child.stderr.on('data', chunk => { log += chunk.toString(); });
  child.on('error', error => { failed = true; log += error.stack; });
  child.on('close', code => {
    fs.writeFileSync(path.join(logDir, `${role}.log`), log);
    const pass = code === 0 && log.includes(`[PASS] Four-player transport ${role}:`) &&
      !/SCRIPT ERROR|(?:^|\n)ERROR:|\[FAIL\]/.test(log);
    if (!pass) { failed = true; console.error(log); }
    else console.log(log.split(/\r?\n/).find(line => line.startsWith('[PASS]')));
    resolve();
  });
}))).then(() => {
  clearTimeout(watchdog);
  process.exitCode = failed ? 1 : 0;
});
