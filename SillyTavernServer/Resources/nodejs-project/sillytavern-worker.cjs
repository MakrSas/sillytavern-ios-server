const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const { pathToFileURL } = require('node:url');
const { parentPort, workerData } = require('node:worker_threads');

function report(type, value = {}) {
  parentPort.postMessage({ type, ...value });
}

function reportFatal(error) {
  report('error', { message: String(error?.stack ?? error) });
}

async function installPortableFetch(sillyTavernDirectory) {
  const http = require('node:http');
  for (const exportName of ['WebSocket', 'CloseEvent', 'MessageEvent']) {
    delete http[exportName];
  }

  const applicationRequire = createRequire(path.join(sillyTavernDirectory, 'package.json'));
  const nodeFetchEntrypoint = applicationRequire.resolve('node-fetch');
  const nodeFetch = await import(pathToFileURL(nodeFetchEntrypoint).href);

  for (const exportName of ['fetch', 'Headers', 'Request', 'Response', 'FormData', 'Blob', 'File']) {
    const value = exportName === 'fetch' ? nodeFetch.default : nodeFetch[exportName];
    if (value !== undefined) {
      Object.defineProperty(globalThis, exportName, {
        configurable: true,
        enumerable: true,
        writable: true,
        value,
      });
    }
  }
}

async function start() {
  const sillyTavernDirectory = path.resolve(workerData.sillyTavernDirectory);
  const dataDirectory = path.resolve(workerData.dataDirectory);
  const port = Number(workerData.port);
  const serverEntrypoint = path.join(sillyTavernDirectory, 'server.js');
  const packageFile = path.join(sillyTavernDirectory, 'package.json');
  const eventsEntrypoint = path.join(sillyTavernDirectory, 'src', 'server-events.js');

  if (!fs.existsSync(serverEntrypoint) || !fs.existsSync(packageFile)) {
    throw new Error(`SillyTavern payload is missing from ${sillyTavernDirectory}`);
  }

  const metadata = JSON.parse(fs.readFileSync(packageFile, 'utf8'));
  await installPortableFetch(sillyTavernDirectory);

  const { serverEvents, EVENT_NAMES } = await import(pathToFileURL(eventsEntrypoint).href);
  serverEvents.once(EVENT_NAMES.SERVER_STARTED, ({ url }) => {
    const listeningURL = new URL(url);
    report('ready', {
      port: Number(listeningURL.port) || port,
      version: String(metadata.version || 'unknown'),
    });
  });

  process.argv = [
    process.execPath,
    serverEntrypoint,
    '--port',
    String(port),
    '--listen',
    'false',
    '--enableIPv4',
    'true',
    '--enableIPv6',
    'false',
    '--browserLaunchEnabled',
    'false',
    '--heartbeatInterval',
    '0',
    '--dataRoot',
    dataDirectory,
  ];
  await import(pathToFileURL(serverEntrypoint).href);
}

process.once('uncaughtException', (error) => {
  reportFatal(error);
});
process.once('unhandledRejection', (error) => {
  reportFatal(error);
});

start().catch(reportFatal);
