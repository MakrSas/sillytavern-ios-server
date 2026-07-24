import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const http = require('node:http');
const net = require('node:net');
const { Worker } = require('node:worker_threads');

const HOST = '127.0.0.1';
const resourceDirectory = path.dirname(fileURLToPath(import.meta.url));
const bundledSillyTavernDirectory = path.join(resourceDirectory, 'SillyTavern');
const sillyTavernDirectory = process.env.ST_IOS_PAYLOAD_DIR
  ? path.resolve(process.env.ST_IOS_PAYLOAD_DIR)
  : bundledSillyTavernDirectory;
const workerEntrypoint = path.join(resourceDirectory, 'sillytavern-worker.cjs');

function argument(name, fallback) {
  const index = process.argv.indexOf(name);
  return index >= 0 && process.argv[index + 1] ? process.argv[index + 1] : fallback;
}

const preferredPort = Number.parseInt(argument('--preferred-port', '8000'), 10);
const dataDirectory = argument('--data-directory', process.cwd());
fs.mkdirSync(dataDirectory, { recursive: true });

let contentWorker = null;
let activePort = null;
let activeVersion = null;
let operation = Promise.resolve();
const stoppingWorkers = new WeakSet();

function marker(name, value) {
  console.log(`[${name}] ${JSON.stringify(value)}`);
}

function validatePayload() {
  const requiredFiles = [
    path.join(sillyTavernDirectory, 'server.js'),
    path.join(sillyTavernDirectory, 'package.json'),
    path.join(sillyTavernDirectory, 'node_modules'),
  ];
  if (!process.env.ST_IOS_PAYLOAD_DIR) {
    requiredFiles.push(
      path.join(sillyTavernDirectory, 'ios-package-manifest.json'),
      path.join(sillyTavernDirectory, 'ios-runtime-capabilities.json'),
    );
  }
  const missing = requiredFiles.filter((entry) => !fs.existsSync(entry));
  if (missing.length > 0) {
    throw new Error(`SillyTavern payload is incomplete: ${missing.join(', ')}`);
  }
}

function canListen(port) {
  return new Promise((resolve) => {
    const probe = net.createServer();
    probe.unref();
    probe.once('error', () => resolve(false));
    probe.listen(port, HOST, () => {
      probe.close(() => resolve(true));
    });
  });
}

async function selectPort(port) {
  const firstPort = Number.isInteger(port) && port > 0 && port < 65536 ? port : 8000;
  for (let candidate = firstPort; candidate <= Math.min(firstPort + 100, 65535); candidate += 1) {
    if (await canListen(candidate)) return candidate;
  }
  throw new Error(`Нет свободного порта в диапазоне ${firstPort}…${firstPort + 100}`);
}

function launchSillyTavern(port) {
  return new Promise((resolve, reject) => {
    const worker = new Worker(workerEntrypoint, {
      workerData: {
        dataDirectory,
        port,
        sillyTavernDirectory,
      },
    });
    contentWorker = worker;
    let settled = false;

    const startupTimeout = setTimeout(() => {
      fail(new Error('SillyTavern did not finish starting within 120 seconds.'));
    }, 120_000);
    startupTimeout.unref();

    function finish(value) {
      if (settled) return;
      settled = true;
      clearTimeout(startupTimeout);
      resolve(value);
    }

    function fail(error) {
      if (settled) {
        if (contentWorker === worker) {
          contentWorker = null;
          activePort = null;
          activeVersion = null;
          stoppingWorkers.add(worker);
          void worker.terminate();
        }
        marker('ST_SERVER_ERROR', { message: String(error?.stack ?? error) });
        return;
      }
      settled = true;
      clearTimeout(startupTimeout);
      if (contentWorker === worker) contentWorker = null;
      activePort = null;
      activeVersion = null;
      stoppingWorkers.add(worker);
      void worker.terminate();
      reject(error);
    }

    worker.on('message', (message) => {
      if (!message || typeof message !== 'object') return;

      if (message.type === 'ready') {
        activePort = Number(message.port) || port;
        activeVersion = String(message.version || '1.18.0');
        const result = {
          ok: true,
          state: 'running',
          port: activePort,
          runtimeVersion: process.version,
          sillyTavernVersion: activeVersion,
        };
        marker('ST_SERVER_READY', result);
        finish(result);
        return;
      }

      if (message.type === 'error') {
        fail(new Error(String(message.message || 'Unknown SillyTavern worker error')));
      }
    });

    worker.once('error', fail);
    worker.once('exit', (code) => {
      const expected = stoppingWorkers.has(worker);
      if (contentWorker === worker) contentWorker = null;
      activePort = null;
      activeVersion = null;

      if (!expected) {
        fail(new Error(`SillyTavern worker exited with code ${code}.`));
      }
    });
  });
}

async function startContent(port = preferredPort) {
  if (contentWorker && activePort) {
    return {
      ok: true,
      state: 'running',
      port: activePort,
      runtimeVersion: process.version,
      sillyTavernVersion: activeVersion,
    };
  }

  validatePayload();
  if (process.cwd() !== sillyTavernDirectory) {
    process.chdir(sillyTavernDirectory);
  }
  const selectedPort = await selectPort(port);
  return launchSillyTavern(selectedPort);
}

async function stopContent() {
  if (!contentWorker) {
    return { ok: true, state: 'stopped', port: null };
  }

  const worker = contentWorker;
  const oldPort = activePort;
  stoppingWorkers.add(worker);
  contentWorker = null;
  activePort = null;
  activeVersion = null;
  await worker.terminate();
  marker('ST_SERVER_STOPPED', { port: oldPort });
  return { ok: true, state: 'stopped', port: null };
}

async function restartContent(port) {
  await stopContent();
  return startContent(port);
}

function readJSON(request) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    request.on('data', (chunk) => {
      size += chunk.length;
      if (size > 16 * 1024) {
        reject(new Error('Слишком большой запрос'));
        request.destroy();
        return;
      }
      chunks.push(chunk);
    });
    request.on('end', () => {
      if (chunks.length === 0) return resolve({});
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch (error) {
        reject(error);
      }
    });
    request.on('error', reject);
  });
}

const controlServer = http.createServer(async (request, response) => {
  response.setHeader('content-type', 'application/json; charset=utf-8');
  response.setHeader('cache-control', 'no-store');

  try {
    if (request.method === 'GET' && request.url === '/health') {
      response.end(JSON.stringify({
        ok: true,
        runtime: 'NodeMobile',
        runtimeVersion: process.version,
        serverRunning: Boolean(contentWorker && activePort),
        serverPort: activePort,
        sillyTavernVersion: activeVersion,
        dataDirectory,
      }));
      return;
    }

    const command = request.url?.slice(1);
    if (request.method !== 'POST' || !['start', 'stop', 'restart'].includes(command)) {
      response.writeHead(404);
      response.end(JSON.stringify({ ok: false, error: 'Not found' }));
      return;
    }

    const body = await readJSON(request);
    operation = operation.then(() => {
      if (command === 'start') return startContent(Number(body.port));
      if (command === 'stop') return stopContent();
      return restartContent(Number(body.port));
    });
    const result = await operation;
    response.end(JSON.stringify(result));
  } catch (error) {
    console.error(error);
    response.writeHead(500);
    response.end(JSON.stringify({
      ok: false,
      state: 'error',
      port: activePort,
      error: String(error.message ?? error),
    }));
  }
});

controlServer.listen(0, HOST, async () => {
  const address = controlServer.address();
  marker('ST_CONTROL_READY', { port: address.port, runtimeVersion: process.version });
  try {
    await startContent(preferredPort);
  } catch (error) {
    marker('ST_SERVER_ERROR', { message: String(error.stack ?? error) });
  }
});

controlServer.on('error', (error) => {
  marker('ST_RUNTIME_ERROR', { message: String(error.stack ?? error) });
});

process.on('uncaughtException', (error) => {
  marker('ST_RUNTIME_ERROR', { message: String(error.stack ?? error) });
});

process.on('unhandledRejection', (error) => {
  marker('ST_RUNTIME_ERROR', { message: String(error?.stack ?? error) });
});
