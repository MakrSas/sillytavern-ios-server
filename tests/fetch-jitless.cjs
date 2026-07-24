const assert = require('node:assert/strict');
const http = require('node:http');
const path = require('node:path');
const { createRequire } = require('node:module');
const { pathToFileURL } = require('node:url');

for (const exportName of ['WebSocket', 'CloseEvent', 'MessageEvent']) {
  delete http[exportName];
}

async function run() {
  const sourceDirectory = path.resolve(process.argv[2] ?? '');
  const applicationRequire = createRequire(path.join(sourceDirectory, 'package.json'));
  const nodeFetch = await import(pathToFileURL(applicationRequire.resolve('node-fetch')).href);
  const server = http.createServer((_request, response) => {
    response.writeHead(200, { 'content-type': 'application/json' });
    response.end(JSON.stringify({ ok: true }));
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const { port } = server.address();
    const response = await nodeFetch.default(`http://127.0.0.1:${port}/`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { ok: true });
    console.log(JSON.stringify({ ok: true, implementation: 'node-fetch', port }));
  } finally {
    await new Promise((resolve, reject) => {
      server.close((error) => error ? reject(error) : resolve());
    });
  }
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
