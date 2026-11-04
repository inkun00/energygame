// Isolated test project: the real project.godot / production entry point is never edited.
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const repo = path.resolve(__dirname, '../..');
const shadow = path.join(repo, '.godot/four-player-project');
const output = path.join(repo, '.godot/four-player-web');
fs.mkdirSync(path.join(shadow, '.godot'), { recursive: true });
fs.mkdirSync(output, { recursive: true });
for (const dir of ['assets', 'scenes', 'scripts', 'web', 'third_party']) {
  const link = path.join(shadow, dir);
  if (!fs.existsSync(link)) fs.symlinkSync(path.join(repo, dir), link, process.platform === 'win32' ? 'junction' : 'dir');
}
const imported = path.join(shadow, '.godot/imported');
if (!fs.existsSync(imported)) fs.symlinkSync(path.join(repo, '.godot/imported'), imported, process.platform === 'win32' ? 'junction' : 'dir');
for (const file of ['global_script_class_cache.cfg', 'uid_cache.bin']) {
  const source = path.join(repo, '.godot', file);
  if (fs.existsSync(source)) fs.copyFileSync(source, path.join(shadow, '.godot', file));
}
fs.writeFileSync(path.join(shadow, 'project.godot'), fs.readFileSync(path.join(repo, 'project.godot'), 'utf8')
  .replace('run/main_scene="res://scenes/Main.tscn"', 'run/main_scene="res://scripts/tests/FourPlayerWebHarness.tscn"'));
fs.writeFileSync(path.join(shadow, 'export_presets.cfg'), fs.readFileSync(path.join(repo, 'export_presets.cfg'), 'utf8')
  .replace(/exclude_filter="[^"]*"/, 'exclude_filter="build/*,build/**/*"'));
const godot = process.env.GODOT || (process.platform === 'win32' ? 'Godot_v4.7.2-stable_win64_console.exe' : 'godot');
for (const [name, args] of [
  ['import', ['--headless', '--editor', '--path', shadow, '--import']],
  ['export', ['--headless', '--path', shadow, '--export-release', 'Web', path.join(output, 'index.html')]],
]) {
  const result = spawnSync(godot, args, { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, timeout: 240000, windowsHide: true });
  const log = (result.stdout || '') + (result.stderr || '');
  fs.writeFileSync(path.join(output, `${name}.log`), log);
  if (result.status !== 0 || /SCRIPT ERROR|Parse Error|\[FAIL\]/.test(log)) {
    console.error(log.slice(-10000));
    throw result.error || new Error(`${name} failed: ${result.status}`);
  }
  console.log(`[PASS] Isolated four-browser ${name}`);
}
