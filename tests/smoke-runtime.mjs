import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { EventEmitter, once } from 'node:events';
import fs from 'node:fs/promises';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(testDirectory, '..');
const entrypoint = path.join(
  repositoryRoot,
  'SillyTavernServer',
  'Resources',
  'nodejs-project',
  'main.js',
);
const dataDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'st-ios-smoke-'));
const events = new EventEmitter();
const recordedMarkers = new Map();
let partialOutput = '';
let allOutput = '';

const occupiedServer = http.createServer((_request, response) => response.end('occupied'));
occupiedServer.listen(18_123, '127.0.0.1');
await once(occupiedServer, 'listening');

const child = spawn(
  process.execPath,
  [
    '--jitless',
    entrypoint,
    '--preferred-port',
    '18123',
    '--data-directory',
    dataDirectory,
  ],
  { stdio: ['ignore', 'pipe', 'pipe'] },
);

function recordOutput(chunk) {
  allOutput += chunk;
  partialOutput += chunk;
  const lines = partialOutput.split(/\r?\n/);
  partialOutput = lines.pop() ?? '';

  for (const line of lines) {
    const match = line.match(/^\[([A-Z_]+)] (.+)$/);
    if (!match) continue;
    const [, name, payload] = match;
    const value = JSON.parse(payload);
    const values = recordedMarkers.get(name) ?? [];
    values.push(value);
    recordedMarkers.set(name, values);
    events.emit(name, value);
  }
}

child.stdout.setEncoding('utf8');
child.stdout.on('data', recordOutput);
child.stderr.setEncoding('utf8');
child.stderr.on('data', (chunk) => {
  allOutput += chunk;
  process.stderr.write(chunk);
});

async function marker(name, timeoutMilliseconds = 60_000) {
  const existing = recordedMarkers.get(name);
  if (existing?.length) return existing.at(-1);

  const timeout = AbortSignal.timeout(timeoutMilliseconds);
  try {
    const [value] = await once(events, name, { signal: timeout });
    return value;
  } catch (error) {
    throw new Error(`Timed out waiting for ${name}.\n${allOutput}`, { cause: error });
  }
}

async function command(baseURL, name, port) {
  const response = await fetch(`${baseURL}/${name}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ port }),
  });
  assert.equal(response.status, 200);
  return response.json();
}

try {
  const control = await marker('ST_CONTROL_READY');
  const initial = await marker('ST_SERVER_READY');
  assert.equal(initial.port, 18_124, 'occupied preferred port must be skipped');

  const controlURL = `http://127.0.0.1:${control.port}`;
  const healthResponse = await fetch(`${controlURL}/health`);
  const health = await healthResponse.json();
  assert.equal(health.ok, true);
  assert.equal(health.serverRunning, true);
  assert.equal(health.serverPort, 18_124);
  assert.match(health.runtimeVersion, /^v\d+\./);
  assert.equal(health.sillyTavernVersion, '1.18.0');

  const stopped = await command(controlURL, 'stop', 18_123);
  assert.equal(stopped.state, 'stopped');

  const started = await command(controlURL, 'start', 18_123);
  assert.equal(started.port, 18_124);

  const restarted = await command(controlURL, 'restart', 18_125);
  assert.equal(restarted.port, 18_125);

  const pageResponse = await fetch('http://127.0.0.1:18125/');
  const page = await pageResponse.text();
  assert.equal(pageResponse.status, 200);
  assert.match(page, /SillyTavern/i);

  const csrfResponse = await fetch('http://127.0.0.1:18125/csrf-token');
  const { token: csrfToken } = await csrfResponse.json();
  const setCookies = csrfResponse.headers.getSetCookie?.()
    ?? [csrfResponse.headers.get('set-cookie')].filter(Boolean);
  const sessionCookie = setCookies
    .map((cookie) => cookie.split(';', 1)[0])
    .join('; ');
  assert.match(csrfToken, /.+/);
  assert.match(sessionCookie, /.+/);

  const tokenizerResponse = await fetch('http://127.0.0.1:18125/api/tokenizers/gpt2/encode', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'cookie': sessionCookie,
      'x-csrf-token': csrfToken,
    },
    body: JSON.stringify({ text: 'SillyTavern iOS tokenizer smoke test' }),
  });
  const tokenizerResult = await tokenizerResponse.json();
  assert.equal(tokenizerResponse.status, 200);
  assert.ok(tokenizerResult.count > 0);
  assert.equal(tokenizerResult.ids.length, tokenizerResult.count);

  console.log(JSON.stringify({
    ok: true,
    runtime: health.runtimeVersion,
    sillyTavern: health.sillyTavernVersion,
    tokenizerTokens: tokenizerResult.count,
    controlPort: control.port,
    automaticPort: initial.port,
    restartedPort: restarted.port,
  }, null, 2));
} finally {
  if (child.exitCode === null) {
    child.kill('SIGTERM');
    await once(child, 'exit');
  }
  occupiedServer.close();
  await fs.rm(dataDirectory, { recursive: true, force: true });
}
