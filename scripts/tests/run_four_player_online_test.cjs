// Run four real native processes. No production build/debug hooks are exposed.
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const godot = process.env.GODOT_BIN || 'Godot_v4.7.2-stable_win64_console.exe';
const logDir = path.join(root, '.godot/four-player-online');
fs.mkdirSync(logDir, { recursive: true });
const roles = ['host', 'client1', 'client2', 'client3'];
const children = [];
let failed = false;
const watchdog = setTimeout(() => {
  failed = true;
  console.error('[FAIL] Four-player integration runner exceeded 240 seconds');
  for (const child of children) child.kill();
}, 240_000);
Promise.all(roles.map((role) => new Promise((resolve) => {
  const child = spawn(godot, ['--headless', '--path', root, '--script',
    'scripts/tests/FourPlayerOnlineRulesTest.gd', '--', `--role=${role}`],
  { cwd: root, windowsHide: true });
  children.push(child);
  let log = '';
  const logPath = path.join(logDir, `${role}.log`);
  fs.writeFileSync(logPath, '');
  const append = (chunk) => {
    const text = chunk.toString();
    log += text;
    fs.appendFileSync(logPath, text);
    if (role === 'host' && /\[TRACE\]/.test(text)) process.stdout.write(text);
  };
  child.stdout.on('data', append);
  child.stderr.on('data', append);
  child.on('error', (error) => { failed = true; append(String(error)); });
  child.on('close', (code) => {
    fs.writeFileSync(path.join(logDir, `${role}.log`), log);
    const passed = code === 0 && log.includes(`[PASS] Four-player online rules ${role}`)
      && !/SCRIPT ERROR|Parse Error|\[FAIL\]|^ERROR:/m.test(log);
    if (!passed) {
      failed = true;
      console.error(log);
      for (const other of children) if (other !== child) other.kill();
    }
    console.log(`${passed ? '[PASS]' : '[FAIL]'} ${role}: exit ${code}; ${path.join(logDir, `${role}.log`)}`);
    resolve();
  });
}))).then(() => {
  clearTimeout(watchdog);
  process.exitCode = failed ? 1 : 0;
});
