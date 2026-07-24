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
child.stderr.on('data', (chunk) => process.stderr.write(chunk));

async function marker(name, timeoutMilliseconds = 10_000) {
  const existing = recordedMarkers.get(name);
  if (existing?.length) return existing.at(-1);

  const timeout = AbortSignal.timeout(timeoutMilliseconds);
  const [value] = await once(events, name, { signal: timeout });
  return value;
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

  const stopped = await command(controlURL, 'stop', 18_123);
  assert.equal(stopped.state, 'stopped');

  const started = await command(controlURL, 'start', 18_123);
  assert.equal(started.port, 18_124);

  const restarted = await command(controlURL, 'restart', 18_125);
  assert.equal(restarted.port, 18_125);

  const pageResponse = await fetch('http://127.0.0.1:18125/');
  const page = await pageResponse.text();
  assert.equal(pageResponse.status, 200);
  assert.match(page, /Локальный Node\.js-сервер работает/);

  console.log(JSON.stringify({
    ok: true,
    runtime: health.runtimeVersion,
    controlPort: control.port,
    automaticPort: initial.port,
    restartedPort: restarted.port,
  }, null, 2));
} finally {
  child.kill('SIGTERM');
  occupiedServer.close();
  await fs.rm(dataDirectory, { recursive: true, force: true });
}
