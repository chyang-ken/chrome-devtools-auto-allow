import assert from 'node:assert/strict';
import test from 'node:test';
import {
  decideHookAction,
  extractCommand,
  isDefinitelyNonConnecting,
} from './hook-decision.mjs';

test('读取 Claude Code 与 Codex 的命令字段', () => {
  assert.equal(
    extractCommand(
      JSON.stringify({ tool_name: 'Bash', tool_input: { command: 'node task.mjs' } }),
    ),
    'node task.mjs',
  );
  assert.equal(
    extractCommand(JSON.stringify({ cmd: ['node', 'task.mjs'] })),
    'node task.mjs',
  );
});

test('纯查看命令即使提到连接关键词也不会启动看守', () => {
  for (const command of [
    'echo web-access',
    'rg DevToolsActivePort scripts',
    'git grep remote-debugging | head',
    'ls -la',
  ]) {
    assert.equal(decideHookAction(command), 'skip', command);
    assert.equal(isDefinitelyNonConnecting(command), true, command);
  }
});

test('连接关键词只作为非查看命令的快速路径', () => {
  assert.equal(decideHookAction('node connect.mjs --endpoint=/devtools/browser/abc'), 'fast');
  assert.equal(decideHookAction('curl http://127.0.0.1:3456/json'), 'fast');
});

test('未知工具和无浏览器关键词的脚本仍会进入真实连接探测', () => {
  assert.equal(decideHookAction('mystery-browser-bridge --quiet'), 'probe');
  assert.equal(decideHookAction('/tmp/opaque-task.sh'), 'probe');
  assert.equal(decideHookAction('node harmless-name.mjs'), 'probe');
  assert.equal(decideHookAction('command mystery-browser-bridge'), 'probe');
  assert.equal(decideHookAction('find . -exec mystery-browser-bridge {} ;'), 'probe');
  assert.equal(decideHookAction('echo <(mystery-browser-bridge)'), 'probe');
});
