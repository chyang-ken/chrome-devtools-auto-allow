import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const scriptPath = fileURLToPath(new URL('./register-hooks.mjs', import.meta.url));
const hookPath = '/tmp/chrome-devtools-auto-allow/scripts/agent-hook.sh';
const codexMatcher = 'Bash|exec_command|functions\\.exec_command';

function makeHome() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'auto-allow-register-hooks-'));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const raw = `${JSON.stringify(value, null, 2)}\n`;
  fs.writeFileSync(filePath, raw);
  return raw;
}

function runRegister(home) {
  const result = spawnSync(process.execPath, [scriptPath, 'add', hookPath], {
    encoding: 'utf8',
    env: { ...process.env, HOME: home },
  });
  assert.equal(result.status, 0, result.stderr || result.stdout);
  return result.stdout;
}

function autoAllowHooks(config) {
  return (config.hooks?.PreToolUse ?? []).flatMap((entry) =>
    (entry.hooks ?? [])
      .filter((hook) => hook.command?.includes('agent-hook.sh'))
      .map((hook) => ({ matcher: entry.matcher, ...hook })),
  );
}

test('旧 matcher 会迁移，修改前会备份，重复运行不会重复登记', () => {
  const home = makeHome();
  const claudePath = path.join(home, '.claude', 'settings.json');
  const codexPath = path.join(home, '.codex', 'hooks.json');

  const claudeOriginal = writeJson(claudePath, {
    hooks: {
      PreToolUse: [
        {
          matcher: 'Bash',
          hooks: [{ type: 'command', command: '/tmp/keep-claude-hook.sh' }],
        },
      ],
    },
  });
  const codexOriginal = writeJson(codexPath, {
    hooks: {
      PreToolUse: [
        {
          matcher: 'exec_command',
          hooks: [
            { type: 'command', command: hookPath, timeout: 10 },
            { type: 'command', command: '/tmp/keep-codex-hook.sh' },
          ],
        },
      ],
    },
  });

  runRegister(home);

  const claudeAfterFirstRun = fs.readFileSync(claudePath, 'utf8');
  const codexAfterFirstRun = fs.readFileSync(codexPath, 'utf8');
  const claudeConfig = JSON.parse(claudeAfterFirstRun);
  const codexConfig = JSON.parse(codexAfterFirstRun);

  assert.equal(fs.readFileSync(`${claudePath}.bak.auto-allow`, 'utf8'), claudeOriginal);
  assert.equal(fs.readFileSync(`${codexPath}.bak.auto-allow`, 'utf8'), codexOriginal);
  assert.deepEqual(autoAllowHooks(claudeConfig), [
    { matcher: 'Bash', type: 'command', command: hookPath },
  ]);
  assert.deepEqual(autoAllowHooks(codexConfig), [
    {
      matcher: codexMatcher,
      type: 'command',
      command: hookPath,
      timeout: 10,
      statusMessage: 'arm auto-allow watcher',
    },
  ]);
  assert.ok(
    codexConfig.hooks.PreToolUse.some(
      (entry) =>
        entry.matcher === 'exec_command' &&
        entry.hooks.some((hook) => hook.command === '/tmp/keep-codex-hook.sh'),
    ),
    '迁移时必须保留同组里的其他 Codex hook',
  );

  runRegister(home);

  assert.equal(fs.readFileSync(claudePath, 'utf8'), claudeAfterFirstRun);
  assert.equal(fs.readFileSync(codexPath, 'utf8'), codexAfterFirstRun);
});

test('配置损坏时保持原文件不变并打印手工登记说明', () => {
  const home = makeHome();
  const codexPath = path.join(home, '.codex', 'hooks.json');
  fs.mkdirSync(path.dirname(codexPath), { recursive: true });
  fs.writeFileSync(codexPath, '{ invalid json\n');

  const output = runRegister(home);

  assert.equal(fs.readFileSync(codexPath, 'utf8'), '{ invalid json\n');
  assert.equal(fs.existsSync(`${codexPath}.bak.auto-allow`), false);
  assert.match(output, /不是合法 JSON,跳过自动改/);
  assert.match(output, /请手动把下面这项加进/);
  assert.ok(output.includes('Bash|exec_command|functions\\.exec_command'));
});
