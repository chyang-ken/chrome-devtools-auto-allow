#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const browserDefinitions = [
  {
    id: 'chrome',
    label: 'Google Chrome',
    appName: 'Google Chrome',
    executableName: 'Google Chrome',
    dataDir: ['Library', 'Application Support', 'Google', 'Chrome'],
  },
  {
    id: 'chrome-beta',
    label: 'Google Chrome Beta',
    appName: 'Google Chrome Beta',
    executableName: 'Google Chrome Beta',
    dataDir: ['Library', 'Application Support', 'Google', 'Chrome Beta'],
  },
  {
    id: 'chrome-dev',
    label: 'Google Chrome Dev',
    appName: 'Google Chrome Dev',
    executableName: 'Google Chrome Dev',
    dataDir: ['Library', 'Application Support', 'Google', 'Chrome Dev'],
  },
  {
    id: 'chrome-canary',
    label: 'Google Chrome Canary',
    appName: 'Google Chrome Canary',
    executableName: 'Google Chrome Canary',
    dataDir: ['Library', 'Application Support', 'Google', 'Chrome Canary'],
  },
  {
    id: 'chromium',
    label: 'Chromium',
    appName: 'Chromium',
    executableName: 'Chromium',
    dataDir: ['Library', 'Application Support', 'Chromium'],
  },
  {
    id: 'edge',
    label: 'Microsoft Edge',
    appName: 'Microsoft Edge',
    executableName: 'Microsoft Edge',
    dataDir: ['Library', 'Application Support', 'Microsoft Edge'],
  },
  {
    id: 'edge-beta',
    label: 'Microsoft Edge Beta',
    appName: 'Microsoft Edge Beta',
    executableName: 'Microsoft Edge Beta',
    dataDir: ['Library', 'Application Support', 'Microsoft Edge Beta'],
  },
  {
    id: 'edge-dev',
    label: 'Microsoft Edge Dev',
    appName: 'Microsoft Edge Dev',
    executableName: 'Microsoft Edge Dev',
    dataDir: ['Library', 'Application Support', 'Microsoft Edge Dev'],
  },
  {
    id: 'edge-canary',
    label: 'Microsoft Edge Canary',
    appName: 'Microsoft Edge Canary',
    executableName: 'Microsoft Edge Canary',
    dataDir: ['Library', 'Application Support', 'Microsoft Edge Canary'],
  },
];

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function browserCommandMatch(command, definition) {
  const app = escapeRegExp(definition.appName);
  const executable = escapeRegExp(definition.executableName);
  const re = new RegExp(
    `^(.+?\\/${app}\\.app\\/Contents\\/MacOS\\/${executable})(?:\\s|$)`,
  );
  return command.match(re);
}

export function parseBrowserProcesses(processText) {
  const processes = [];
  for (const line of processText.split(/\r?\n/)) {
    const row = line.match(/^\s*(\d+)\s+(\d+)\s+(.+)$/);
    if (!row) continue;
    const [, pidText, parentPidText, command] = row;
    for (const definition of browserDefinitions) {
      const commandMatch = browserCommandMatch(command, definition);
      if (!commandMatch) continue;
      processes.push({
        ...definition,
        pid: Number(pidText),
        parentPid: Number(parentPidText),
        command,
        args: command.slice(commandMatch[0].length).trim(),
      });
      break;
    }
  }
  return processes;
}

export function readFlag(args, flagName) {
  const escaped = escapeRegExp(flagName);
  const match = args.match(
    new RegExp(
      `(?:^|\\s)--${escaped}(?:=|\\s+)(?:"([^"]*)"|'([^']*)'|(.+?))(?=\\s--[a-zA-Z0-9-]+(?:=|\\s|$)|$)`,
    ),
  );
  if (!match) return undefined;
  return (match[1] ?? match[2] ?? match[3] ?? '').trim();
}

function normalizeDataDir(value, home) {
  if (!value) return undefined;
  if (value === '~') return home;
  if (value.startsWith('~/')) return path.join(home, value.slice(2));
  return path.resolve(value);
}

function validPort(value) {
  if (!/^\d+$/.test(String(value ?? ''))) return undefined;
  const port = Number(value);
  return port >= 1 && port <= 65535 ? port : undefined;
}

function systemProcessText() {
  return execFileSync('/bin/ps', ['-axo', 'pid=,ppid=,command='], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
  });
}

function systemOwnedListener(pid, port) {
  try {
    execFileSync(
      '/usr/sbin/lsof',
      ['-nP', '-a', '-p', String(pid), `-iTCP:${port}`, '-sTCP:LISTEN'],
      { stdio: 'ignore' },
    );
    return true;
  } catch {
    return false;
  }
}

export function discoverBrowserTargets({
  processText = systemProcessText(),
  home = os.homedir(),
  readFile = (filePath) => fs.readFileSync(filePath, 'utf8'),
  isOwnedListener = systemOwnedListener,
  onlyPids,
} = {}) {
  const targets = [];
  for (const browser of parseBrowserProcesses(processText)) {
    if (onlyPids && !onlyPids.has(browser.pid)) continue;
    const customDataDir = normalizeDataDir(readFlag(browser.args, 'user-data-dir'), home);
    const dataDir = customDataDir ?? path.join(home, ...browser.dataDir);
    const candidates = new Set();

    try {
      const firstLine = readFile(path.join(dataDir, 'DevToolsActivePort'))
        .split(/\r?\n/, 1)[0]
        .trim();
      const port = validPort(firstLine);
      if (port) candidates.add(port);
    } catch {
      // 没有端口文件是正常状态：浏览器可能未开启远程调试。
    }

    const explicitPort = validPort(readFlag(browser.args, 'remote-debugging-port'));
    if (explicitPort) candidates.add(explicitPort);

    for (const port of candidates) {
      if (!isOwnedListener(browser.pid, port)) continue;
      targets.push({
        id: browser.id,
        label: browser.label,
        pid: browser.pid,
        port,
        dataDir,
      });
    }
  }

  return targets.sort(
    (left, right) => left.port - right.port || left.pid - right.pid || left.id.localeCompare(right.id),
  );
}

const invokedPath = process.argv[1] ? path.resolve(process.argv[1]) : '';
if (invokedPath === fileURLToPath(import.meta.url)) {
  try {
    const onlyPidIndex = process.argv.indexOf('--only-pid');
    const onlyPid =
      onlyPidIndex >= 0 ? Number(process.argv[onlyPidIndex + 1]) : undefined;
    const onlyPids = Number.isInteger(onlyPid) ? new Set([onlyPid]) : undefined;
    for (const target of discoverBrowserTargets({ onlyPids })) {
      process.stdout.write(`${JSON.stringify(target)}\n`);
    }
  } catch {
    // 探测器是 hook 的后台辅助，任何系统读取失败都必须静默快速退出。
  }
}
