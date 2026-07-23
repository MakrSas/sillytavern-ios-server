import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const HOST = '127.0.0.1';

function argument(name, fallback) {
  const index = process.argv.indexOf(name);
  return index >= 0 && process.argv[index + 1] ? process.argv[index + 1] : fallback;
}

const preferredPort = Number.parseInt(argument('--preferred-port', '8000'), 10);
const dataDirectory = argument('--data-directory', process.cwd());
fs.mkdirSync(dataDirectory, { recursive: true });

let contentServer = null;
let activePort = null;
let operation = Promise.resolve();

function marker(name, value) {
  console.log(`[${name}] ${JSON.stringify(value)}`);
}

function page() {
  return `<!doctype html>
<html lang="ru">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>NodeMobile smoke test</title>
<style>
  :root { color-scheme: light dark; font: -apple-system-body; }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #11131a; color: #f6f7fb; }
  main { width: min(34rem, calc(100% - 2rem)); padding: 1.5rem; border-radius: 1.5rem; background: #20232d; box-sizing: border-box; }
  .ok { color: #55d98b; font-weight: 700; } code { color: #b8c7ff; overflow-wrap: anywhere; }
</style>
<main>
  <p class="ok">● Локальный Node.js-сервер работает</p>
  <h1>Технический прототип</h1>
  <p>Runtime: <code>${process.version}</code></p>
  <p>Адрес: <code>http://${HOST}:${activePort}</code></p>
  <p>Данные: <code>${dataDirectory}</code></p>
  <p>Это реальный HTTP-сервер NodeMobile, но ещё не SillyTavern.</p>
</main>
</html>`;
}

function createContentServer() {
  return http.createServer((request, response) => {
    if (request.url === '/health') {
      response.writeHead(200, { 'content-type': 'application/json; charset=utf-8' });
      response.end(JSON.stringify({ ok: true, runtime: process.version, port: activePort }));
      return;
    }
    response.writeHead(200, {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
      'content-security-policy': "default-src 'none'; style-src 'unsafe-inline'",
    });
    response.end(page());
  });
}

async function startContent(port = preferredPort) {
  if (contentServer) {
    return { ok: true, state: 'running', port: activePort };
  }

  const firstPort = Number.isInteger(port) && port > 0 && port < 65536 ? port : 8000;
  for (let candidate = firstPort; candidate <= Math.min(firstPort + 100, 65535); candidate += 1) {
    const server = createContentServer();
    const result = await new Promise((resolve) => {
      const onError = (error) => resolve({ error });
      server.once('error', onError);
      server.listen(candidate, HOST, () => {
        server.off('error', onError);
        resolve({ server });
      });
    });

    if (result.server) {
      contentServer = result.server;
      activePort = candidate;
      marker('ST_SERVER_READY', { port: activePort, runtimeVersion: process.version });
      return { ok: true, state: 'running', port: activePort };
    }
    if (result.error?.code !== 'EADDRINUSE') {
      throw result.error;
    }
  }
  throw new Error(`Нет свободного порта в диапазоне ${firstPort}…${firstPort + 100}`);
}

async function stopContent() {
  if (!contentServer) {
    return { ok: true, state: 'stopped', port: null };
  }
  const server = contentServer;
  contentServer = null;
  await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  const oldPort = activePort;
  activePort = null;
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
        serverRunning: Boolean(contentServer),
        serverPort: activePort,
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
    response.end(JSON.stringify({ ok: false, state: 'error', port: activePort, error: String(error.message ?? error) }));
  }
});

controlServer.listen(0, HOST, async () => {
  const address = controlServer.address();
  marker('ST_CONTROL_READY', { port: address.port, runtimeVersion: process.version });
  try {
    await startContent(preferredPort);
  } catch (error) {
    marker('ST_SERVER_ERROR', { message: String(error.message ?? error) });
  }
});

controlServer.on('error', (error) => {
  marker('ST_RUNTIME_ERROR', { message: String(error.message ?? error) });
});

process.on('uncaughtException', (error) => {
  marker('ST_RUNTIME_ERROR', { message: String(error.stack ?? error) });
});

process.on('unhandledRejection', (error) => {
  marker('ST_RUNTIME_ERROR', { message: String(error?.stack ?? error) });
});
