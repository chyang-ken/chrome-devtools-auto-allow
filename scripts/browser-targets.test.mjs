import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import {
  discoverBrowserTargets,
  parseBrowserProcesses,
  readFlag,
} from './browser-targets.mjs';

test('识别 Chromium 家族主进程，不把 Helper 当成独立浏览器', () => {
  const processText = [
    '101 1 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '102 101 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper --type=renderer',
    '201 1 /Applications/Google Chrome Beta.app/Contents/MacOS/Google Chrome Beta',
    '202 1 /Applications/Google Chrome Dev.app/Contents/MacOS/Google Chrome Dev',
    '203 1 /Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary --user-data-dir=/tmp/canary',
    '301 1 /Applications/Chromium.app/Contents/MacOS/Chromium',
    '401 1 /Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
    '402 1 /Applications/Microsoft Edge Beta.app/Contents/MacOS/Microsoft Edge Beta',
    '403 1 /Applications/Microsoft Edge Dev.app/Contents/MacOS/Microsoft Edge Dev',
    '404 1 /Applications/Microsoft Edge Canary.app/Contents/MacOS/Microsoft Edge Canary',
  ].join('\n');

  assert.deepEqual(
    parseBrowserProcesses(processText).map(({ id, pid }) => ({ id, pid })),
    [
      { id: 'chrome', pid: 101 },
      { id: 'chrome-beta', pid: 201 },
      { id: 'chrome-dev', pid: 202 },
      { id: 'chrome-canary', pid: 203 },
      { id: 'chromium', pid: 301 },
      { id: 'edge', pid: 401 },
      { id: 'edge-beta', pid: 402 },
      { id: 'edge-dev', pid: 403 },
      { id: 'edge-canary', pid: 404 },
    ],
  );
});

test('发现默认目录、自定义 user-data-dir 和显式端口，并过滤过期与异常端口', () => {
  const home = '/Users/tester';
  const betaDir = '/tmp/Beta Profile';
  const processText = [
    '101 1 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    `201 1 /Applications/Google Chrome Beta.app/Contents/MacOS/Google Chrome Beta --user-data-dir=${betaDir} --remote-debugging-port=0`,
    '301 1 /Applications/Chromium.app/Contents/MacOS/Chromium --remote-debugging-port=9444',
    '401 1 /Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
    '501 1 /Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary --user-data-dir=/tmp/canary --remote-debugging-port=9555',
    '601 1 /Applications/Google Chrome Dev.app/Contents/MacOS/Google Chrome Dev',
  ].join('\n');
  const files = new Map([
    [path.join(home, 'Library/Application Support/Google/Chrome/DevToolsActivePort'), '9222\n/devtools/browser/chrome\n'],
    [path.join(betaDir, 'DevToolsActivePort'), '9333\n/devtools/browser/beta\n'],
    [path.join(home, 'Library/Application Support/Microsoft Edge/DevToolsActivePort'), 'not-a-port\n'],
    [path.join(home, 'Library/Application Support/Google/Chrome Dev/DevToolsActivePort'), '9666\n'],
  ]);
  const owned = new Set(['101:9222', '201:9333', '301:9444', '501:9555']);

  const targets = discoverBrowserTargets({
    processText,
    home,
    readFile: (filePath) => {
      if (!files.has(filePath)) throw new Error('missing');
      return files.get(filePath);
    },
    isOwnedListener: (pid, port) => owned.has(`${pid}:${port}`),
  });

  assert.deepEqual(
    targets.map(({ id, pid, port, dataDir }) => ({ id, pid, port, dataDir })),
    [
      {
        id: 'chrome',
        pid: 101,
        port: 9222,
        dataDir: path.join(home, 'Library/Application Support/Google/Chrome'),
      },
      { id: 'chrome-beta', pid: 201, port: 9333, dataDir: betaDir },
      {
        id: 'chromium',
        pid: 301,
        port: 9444,
        dataDir: path.join(home, 'Library/Application Support/Chromium'),
      },
      { id: 'chrome-canary', pid: 501, port: 9555, dataDir: '/tmp/canary' },
    ],
  );
});

test('诊断时可以只检查指定浏览器进程', () => {
  const home = '/Users/tester';
  const files = new Map([
    [path.join(home, 'Library/Application Support/Google/Chrome/DevToolsActivePort'), '9222\n'],
    [path.join(home, 'Library/Application Support/Chromium/DevToolsActivePort'), '9333\n'],
  ]);
  const targets = discoverBrowserTargets({
    processText: [
      '101 1 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      '202 1 /Applications/Chromium.app/Contents/MacOS/Chromium',
    ].join('\n'),
    home,
    onlyPids: new Set([202]),
    readFile: (filePath) => files.get(filePath),
    isOwnedListener: () => true,
  });

  assert.deepEqual(targets.map(({ id, pid, port }) => ({ id, pid, port })), [
    { id: 'chromium', pid: 202, port: 9333 },
  ]);
});

test('浏览器未运行时不采信残留端口文件', () => {
  let reads = 0;
  const targets = discoverBrowserTargets({
    processText: '',
    home: '/Users/tester',
    readFile: () => {
      reads += 1;
      return '9222\n';
    },
    isOwnedListener: () => true,
  });

  assert.deepEqual(targets, []);
  assert.equal(reads, 0);
});

test('参数解析保留带空格的自定义数据目录', () => {
  const args =
    '--user-data-dir=/tmp/My Browser Profile --remote-debugging-port=0 --no-first-run';
  assert.equal(readFlag(args, 'user-data-dir'), '/tmp/My Browser Profile');
  assert.equal(readFlag(args, 'remote-debugging-port'), '0');
});
