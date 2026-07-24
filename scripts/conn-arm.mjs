#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync, spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { discoverBrowserTargets } from './browser-targets.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const probeLog = '/tmp/cdp-auto-allow.probe.log';
const hookLog = '/tmp/cdp-auto-allow.hook.log';

function appendLog(filePath, message) {
  try {
    fs.appendFileSync(
      filePath,
      `${new Date().toLocaleTimeString('en-GB', { hour12: false })} ${message}\n`,
    );
  } catch {
    // 日志失败不能影响 Agent 命令。
  }
}

export function parseExternalConnections(lsofText, target) {
  const destination = new RegExp(
    `->(?:127\\.0\\.0\\.1|\\[::1\\]):${target.port}$`,
  );
  const browserCommand = /^(?:Google|Chrome|Chromium|Microsoft|msedge|Edge)/i;
  const connections = [];

  for (const line of lsofText.split(/\r?\n/)) {
    if (!line.includes('(ESTABLISHED)')) continue;
    const fields = line.trim().split(/\s+/);
    if (fields.length < 3) continue;
    const command = fields[0];
    const pid = Number(fields[1]);
    const endpoint = fields.find((field) => field.includes('->'));
    if (!endpoint || !destination.test(endpoint)) continue;
    if (pid === target.pid || browserCommand.test(command)) continue;
    connections.push(
      `${target.id}:${target.pid}:${target.port}:${pid}:${endpoint}`,
    );
  }
  return connections;
}

function systemConnectionsForTarget(target) {
  try {
    const output = execFileSync(
      '/usr/sbin/lsof',
      ['-nP', `-iTCP:${target.port}`],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] },
    );
    return parseExternalConnections(output, target);
  } catch {
    return [];
  }
}

export function systemSnapshot() {
  const targets = discoverBrowserTargets();
  const connections = new Set();
  for (const target of targets) {
    for (const connection of systemConnectionsForTarget(target)) {
      connections.add(connection);
    }
  }
  return { targets, connections };
}

function describeTargets(targets) {
  if (!targets.length) return 'none';
  return targets
    .map((target) => `${target.id}:${target.pid}:${target.port}`)
    .join(',');
}

export async function monitorConnections({
  snapshot = systemSnapshot,
  arm = () => {
    const child = spawn(path.join(here, 'on-demand.sh'), ['watch', '20'], {
      detached: true,
      stdio: 'ignore',
    });
    child.unref();
  },
  markReady = () => {},
  logProbe = (message) => appendLog(probeLog, message),
  logHit = (message) => appendLog(hookLog, message),
  now = () => Date.now(),
  sleep = (milliseconds) =>
    new Promise((resolve) => setTimeout(resolve, milliseconds)),
  probeMs = 45_000,
  idleMs = 10_000,
  graceMs = 8_000,
  pollMs = 1_000,
} = {}) {
  let initial;
  try {
    initial = snapshot();
  } catch {
    initial = { targets: [], connections: new Set() };
  }
  const baseline = new Set(initial.connections);
  const loggedConnections = new Set();
  const startedAt = now();
  let seenNewConnection = false;
  let lastSeenAt;

  logProbe(`PROBE-START targets=${describeTargets(initial.targets)}`);
  markReady();

  while (now() - startedAt < probeMs) {
    await sleep(pollMs);
    let current;
    try {
      current = snapshot();
    } catch {
      current = { targets: [], connections: new Set() };
    }
    const newConnections = [...current.connections].filter(
      (connection) => !baseline.has(connection),
    );

    if (newConnections.length) {
      seenNewConnection = true;
      lastSeenAt = now();
      const firstSightings = newConnections.filter(
        (connection) => !loggedConnections.has(connection),
      );
      if (firstSightings.length) {
        firstSightings.forEach((connection) => loggedConnections.add(connection));
        logHit(
          `PROBE-HIT targets=${describeTargets(current.targets)} new=${firstSightings.join(',')}`,
        );
      }
      arm();
      continue;
    }

    if (seenNewConnection) {
      if (now() - lastSeenAt >= graceMs) return 'connection-gone';
    } else if (now() - startedAt >= idleMs) {
      return 'idle';
    }
  }
  return 'timeout';
}

function readyFileFromArgs(argv) {
  const index = argv.indexOf('--ready-file');
  return index >= 0 ? argv[index + 1] : undefined;
}

const invokedPath = process.argv[1] ? path.resolve(process.argv[1]) : '';
if (invokedPath === fileURLToPath(import.meta.url)) {
  const readyFile = readyFileFromArgs(process.argv.slice(2));
  try {
    await monitorConnections({
      markReady: () => {
        if (readyFile) fs.writeFileSync(readyFile, `${process.pid}\n`);
      },
    });
  } catch {
    // hook 后台探测绝不能阻塞或打断 Agent 命令。
  } finally {
    if (readyFile) {
      try {
        fs.rmSync(readyFile);
      } catch {
        // hook 进程通常已经先删掉 ready 文件。
      }
    }
  }
}
