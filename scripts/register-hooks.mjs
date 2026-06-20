#!/usr/bin/env node
// 幂等注册 / 反注册 auto-allow 的 PreToolUse hook 到 Claude Code + Codex。
//
// 这是「自包含安装」的核心:把『要在 agent 配置里加一行 hook』这件事写进 repo,
// 让别人 clone 后跑 install.sh 就能自动完成,不必靠口口相传或翻别人机器的配置。
//
// 用法: node register-hooks.mjs <add|remove> <agent-hook.sh 绝对路径>
//
// 健壮性:对方配置千差万别 —— 文件不存在 / 无 hooks / 无 PreToolUse / 无对应 matcher
// 都会就地补齐;已注册则幂等跳过;改写前自动备份(.bak.auto-allow);JSON 解析失败则
// 不强改、退回打印「请手动加这一项」的明确指引。
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const [, , action, hookPath] = process.argv;
if (!['add', 'remove'].includes(action) || !hookPath) {
  console.error('用法: node register-hooks.mjs <add|remove> <agent-hook.sh 绝对路径>');
  process.exit(2);
}
const HOME = os.homedir();

// 两个 agent 的注册位。Codex 不同版本/表面展示过不同命令工具名,所以用兼容 matcher。
// Codex 的 hook 项还带 timeout / statusMessage。
const TARGETS = [
  { name: 'Claude Code', file: path.join(HOME, '.claude', 'settings.json'), matcher: 'Bash', extra: {} },
  { name: 'Codex', file: path.join(HOME, '.codex', 'hooks.json'), matcher: 'Bash|exec_command|functions\\.exec_command', extra: { timeout: 10, statusMessage: 'arm auto-allow watcher' } },
];

const isOurs = (cmd) => typeof cmd === 'string' && cmd.includes('agent-hook.sh');

function manualHint(t) {
  const item = { type: 'command', command: hookPath, ...t.extra };
  console.log(`  ⚠️ [${t.name}] 无法自动改 ${t.file}`);
  console.log(`     请手动把下面这项加进 hooks.PreToolUse 里 matcher="${t.matcher}" 的 hooks 数组:`);
  console.log('     ' + JSON.stringify(item));
}

for (const t of TARGETS) {
  let raw = null, cfg = null, existed = false;
  try { raw = fs.readFileSync(t.file, 'utf8'); existed = true; }
  catch (e) {
    if (e.code !== 'ENOENT') { console.log(`  ✗ [${t.name}] 读取失败: ${e.message}`); if (action === 'add') manualHint(t); continue; }
  }
  if (existed) {
    try { cfg = JSON.parse(raw); }
    catch { console.log(`  ✗ [${t.name}] ${t.file} 不是合法 JSON,跳过自动改`); if (action === 'add') manualHint(t); continue; }
  }

  if (action === 'add') {
    cfg ??= {};
    cfg.hooks ??= {};
    cfg.hooks.PreToolUse ??= [];
    for (const e of cfg.hooks.PreToolUse) {
      if (!e || e.matcher === t.matcher || !Array.isArray(e.hooks)) continue;
      e.hooks = e.hooks.filter((h) => !isOurs(h && h.command));
    }
    let entry = cfg.hooks.PreToolUse.find((e) => e && e.matcher === t.matcher);
    if (!entry) { entry = { matcher: t.matcher, hooks: [] }; cfg.hooks.PreToolUse.push(entry); }
    entry.hooks ??= [];
    if (entry.hooks.some((h) => isOurs(h && h.command))) { console.log(`  • [${t.name}] 已注册,跳过`); continue; }
    entry.hooks.push({ type: 'command', command: hookPath, ...t.extra });
    if (existed) fs.copyFileSync(t.file, t.file + '.bak.auto-allow');
    fs.mkdirSync(path.dirname(t.file), { recursive: true });
    fs.writeFileSync(t.file, JSON.stringify(cfg, null, 2) + '\n');
    console.log(`  ✓ [${t.name}] 已注册 → ${t.file}`);
  } else { // remove
    if (!cfg) { console.log(`  • [${t.name}] 无配置,跳过`); continue; }
    let changed = false;
    for (const e of (cfg.hooks && cfg.hooks.PreToolUse) || []) {
      if (e && Array.isArray(e.hooks)) {
        const before = e.hooks.length;
        e.hooks = e.hooks.filter((h) => !isOurs(h && h.command));
        if (e.hooks.length !== before) changed = true;
      }
    }
    if (changed) {
      fs.copyFileSync(t.file, t.file + '.bak.auto-allow');
      fs.writeFileSync(t.file, JSON.stringify(cfg, null, 2) + '\n');
      console.log(`  ✓ [${t.name}] 已移除`);
    } else console.log(`  • [${t.name}] 未发现本 hook,跳过`);
  }
}
