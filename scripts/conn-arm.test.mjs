import assert from 'node:assert/strict';
import test from 'node:test';
import {
  monitorConnections,
  parseExternalConnections,
} from './conn-arm.mjs';

const chromeTarget = { id: 'chrome', pid: 100, port: 9222 };
const edgeTarget = { id: 'edge', pid: 200, port: 9333 };

function scriptedSnapshot(frames) {
  let index = 0;
  return () => frames[Math.min(index++, frames.length - 1)];
}

function fakeClock() {
  let value = 0;
  return {
    now: () => value,
    sleep: async (milliseconds) => {
      value += milliseconds;
    },
  };
}

test('只记录连向目标端口的外部客户端，不把浏览器自身或其他端口混入', () => {
  const lsof = [
    'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME',
    'Google 100 tester 10u IPv4 0x1 0t0 TCP 127.0.0.1:9222 (LISTEN)',
    'Google 100 tester 11u IPv4 0x2 0t0 TCP 127.0.0.1:9222->127.0.0.1:51000 (ESTABLISHED)',
    'node 301 tester 12u IPv4 0x3 0t0 TCP 127.0.0.1:51000->127.0.0.1:9222 (ESTABLISHED)',
    'python3 302 tester 13u IPv4 0x4 0t0 TCP 127.0.0.1:51001->127.0.0.1:9333 (ESTABLISHED)',
  ].join('\n');

  assert.deepEqual(parseExternalConnections(lsof, chromeTarget), [
    'chrome:100:9222:301:127.0.0.1:51000->127.0.0.1:9222',
  ]);
});

test('多浏览器基线互相隔离，新连接结束后停止续命', async () => {
  const existingChrome = 'chrome:100:9222:300:127.0.0.1:50000->127.0.0.1:9222';
  const existingEdge = 'edge:200:9333:400:127.0.0.1:50001->127.0.0.1:9333';
  const newEdge = 'edge:200:9333:401:127.0.0.1:50002->127.0.0.1:9333';
  const baseline = new Set([existingChrome, existingEdge]);
  const withNewEdge = new Set([...baseline, newEdge]);
  const frames = [
    { targets: [chromeTarget, edgeTarget], connections: baseline },
    { targets: [chromeTarget, edgeTarget], connections: baseline },
    { targets: [chromeTarget, edgeTarget], connections: withNewEdge },
    { targets: [chromeTarget, edgeTarget], connections: withNewEdge },
    { targets: [chromeTarget, edgeTarget], connections: baseline },
    { targets: [chromeTarget, edgeTarget], connections: baseline },
  ];
  const clock = fakeClock();
  let arms = 0;
  const hits = [];

  const result = await monitorConnections({
    snapshot: scriptedSnapshot(frames),
    arm: () => {
      arms += 1;
    },
    markReady: () => {},
    logProbe: () => {},
    logHit: (message) => hits.push(message),
    now: clock.now,
    sleep: clock.sleep,
    probeMs: 20_000,
    idleMs: 4_000,
    graceMs: 2_000,
    pollMs: 1_000,
  });

  assert.equal(result, 'connection-gone');
  assert.equal(arms, 2);
  assert.equal(hits.length, 1);
  assert.match(hits[0], /edge:200:9333/);
});

test('既有连接不算本次新增，缺少调试端口时也会快速结束', async () => {
  for (const frame of [
    {
      targets: [chromeTarget],
      connections: new Set([
        'chrome:100:9222:300:127.0.0.1:50000->127.0.0.1:9222',
      ]),
    },
    { targets: [], connections: new Set() },
  ]) {
    const clock = fakeClock();
    let arms = 0;
    const result = await monitorConnections({
      snapshot: () => frame,
      arm: () => {
        arms += 1;
      },
      markReady: () => {},
      logProbe: () => {},
      logHit: () => {},
      now: clock.now,
      sleep: clock.sleep,
      probeMs: 20_000,
      idleMs: 2_000,
      graceMs: 1_000,
      pollMs: 1_000,
    });
    assert.equal(result, 'idle');
    assert.equal(arms, 0);
  }
});
