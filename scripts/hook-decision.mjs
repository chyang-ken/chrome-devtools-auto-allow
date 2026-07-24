#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const safeCommands = new Set([
  '[',
  'cat',
  'cd',
  'cut',
  'echo',
  'false',
  'git',
  'grep',
  'head',
  'ls',
  'pwd',
  'printf',
  'rg',
  'sed',
  'sort',
  'stat',
  'tail',
  'test',
  'tr',
  'true',
  'type',
  'uniq',
  'wc',
  'which',
]);

const fastMarkers =
  /cdp-proxy|web-access|:?3456|\/devtools\/browser|remote-debugging|DevToolsActivePort/i;

function findCommand(value, depth = 0) {
  if (depth > 4 || value == null) return undefined;
  if (typeof value === 'string') return value;
  if (Array.isArray(value)) {
    if (value.every((item) => typeof item === 'string')) return value.join(' ');
    for (const item of value) {
      const found = findCommand(item, depth + 1);
      if (found) return found;
    }
    return undefined;
  }
  if (typeof value !== 'object') return undefined;

  for (const key of ['command', 'cmd']) {
    const candidate = value[key];
    if (typeof candidate === 'string') return candidate;
    if (Array.isArray(candidate) && candidate.every((item) => typeof item === 'string')) {
      return candidate.join(' ');
    }
  }
  for (const key of ['tool_input', 'input', 'arguments', 'params']) {
    const found = findCommand(value[key], depth + 1);
    if (found) return found;
  }
  return undefined;
}

export function extractCommand(input) {
  const trimmed = input.trim();
  if (!trimmed) return '';
  try {
    return findCommand(JSON.parse(trimmed)) ?? trimmed;
  } catch {
    return trimmed;
  }
}

function firstCommandName(segment) {
  const tokens = segment
    .trim()
    .replace(/^[({]\s*/, '')
    .split(/\s+/)
    .filter(Boolean);
  while (tokens[0]?.match(/^[A-Za-z_][A-Za-z0-9_]*=/)) tokens.shift();
  return tokens[0] ? path.basename(tokens[0]) : '';
}

export function isDefinitelyNonConnecting(command) {
  if (!command.trim()) return true;
  if (
    command.includes('$(') ||
    command.includes('<(') ||
    command.includes('>(') ||
    command.includes('`')
  ) {
    return false;
  }
  const segments = command.split(/&&|\|\||[;|\n]/).filter((item) => item.trim());
  return (
    segments.length > 0 &&
    segments.every((segment) => safeCommands.has(firstCommandName(segment)))
  );
}

export function decideHookAction(input) {
  const command = extractCommand(input);
  if (isDefinitelyNonConnecting(command)) return 'skip';
  if (fastMarkers.test(command)) return 'fast';
  return command.trim() ? 'probe' : 'skip';
}

const invokedPath = process.argv[1] ? path.resolve(process.argv[1]) : '';
if (invokedPath === fileURLToPath(import.meta.url)) {
  const input = fs.readFileSync(0, 'utf8');
  process.stdout.write(`${decideHookAction(input)}\n`);
}
