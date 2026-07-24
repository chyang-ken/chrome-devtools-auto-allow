#!/usr/bin/env node
import assert from 'node:assert/strict';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ports = process.argv.slice(2).map(Number);
assert.ok(
  ports.length >= 2 &&
    ports.every((port) => Number.isInteger(port) && port >= 1 && port <= 65535),
  '需要至少两个有效端口',
);

const here = path.dirname(fileURLToPath(import.meta.url));
const client = path.join(here, 'hold-session.mjs');

await Promise.all(
  ports.map(
    (port) =>
      new Promise((resolve, reject) => {
        const child = spawn(process.execPath, [client, String(port), '4000'], {
          stdio: ['ignore', 'pipe', 'pipe'],
        });
        child.stdout.on('data', (chunk) => {
          process.stdout.write(`${port} ${chunk}`);
        });
        child.stderr.on('data', (chunk) => {
          process.stderr.write(`${port} ${chunk}`);
        });
        child.on('error', reject);
        child.on('exit', (code) => {
          if (code === 0) resolve();
          else reject(new Error(`端口 ${port} 的会话退出码为 ${code}`));
        });
      }),
  ),
);
