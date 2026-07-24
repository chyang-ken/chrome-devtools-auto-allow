#!/usr/bin/env node
import assert from 'node:assert/strict';

const port = Number(process.argv[2]);
const holdMs = Number(process.argv[3] ?? 4_000);
assert.ok(Number.isInteger(port) && port >= 1 && port <= 65535, '需要有效端口');
assert.ok(Number.isFinite(holdMs) && holdMs >= 0, '需要有效保持时间');

const versionResponse = await fetch(`http://127.0.0.1:${port}/json/version`);
assert.equal(versionResponse.ok, true, `调试入口返回 ${versionResponse.status}`);
const version = await versionResponse.json();
assert.ok(version.webSocketDebuggerUrl, '缺少 webSocketDebuggerUrl');

await new Promise((resolve, reject) => {
  const socket = new WebSocket(version.webSocketDebuggerUrl);
  const timeout = setTimeout(() => {
    socket.close();
    reject(new Error('连接或授权等待超时'));
  }, 15_000);

  socket.addEventListener('open', () => {
    process.stdout.write('session-open\n');
    socket.send(JSON.stringify({ id: 1, method: 'Browser.getVersion' }));
  });
  socket.addEventListener('message', (event) => {
    const message = JSON.parse(String(event.data));
    if (message.id !== 1) return;
    process.stdout.write(`session-ready ${message.result.product}\n`);
    setTimeout(() => socket.close(), holdMs);
  });
  socket.addEventListener('close', () => {
    clearTimeout(timeout);
    process.stdout.write('session-closed\n');
    resolve();
  });
  socket.addEventListener('error', () => {
    clearTimeout(timeout);
    reject(new Error('WebSocket 连接失败'));
  });
});
