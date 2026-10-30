// Test the default access policy on an isolated service and database.
const { spawn } = require('node:child_process');
const fs = require('node:fs'), path = require('node:path');
const http = require('node:http'), assert = require('node:assert/strict');
const { WebSocket } = require('../server/node_modules/ws');
const root = path.resolve(__dirname, '..'), port = 18781;
const env = { ...process.env, PORT: String(port), DATA_DIR: fs.mkdtempSync(path.join(root, '.runtime/access-test-')),
  WEB_ROOT: path.join(root, 'build/web'), TEST_URL: `ws://127.0.0.1:${port}/ws`, ACE_TEST_URL: `http://127.0.0.1:${port}` };
delete env.LAN_ONLY;
delete env.PUBLIC_URL;
const headers = { Host: 'games.company.example:8766', 'X-Forwarded-For': '203.0.113.2' };
function request(route) {
  return new Promise((resolve, reject) => {
    http.get({ hostname: '127.0.0.1', port, path: route, headers }, response => {
      let body = '';
      response.on('data', data => body += data);
      response.on('end', () => resolve({ status: response.statusCode, body }));
    }).on('error', reject);
  });
}
function run(file) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [file], { cwd: root, env, stdio: 'inherit', windowsHide: true });
    child.once('error', reject);
    child.once('exit', code => code === 0 ? resolve() : reject(Error(`${file}: ${code}`)));
  });
}
(async () => {
  const executable = process.env.ACE_TEST_SERVER_EXE;
  const service = spawn(executable || process.execPath, executable ? [] : ['server/server.js'], {
    cwd: root, env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'],
  });
  let socket;
  try {
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(Error('Server startup timeout')), 15000);
      service.once('error', error => { clearTimeout(timer); reject(error); });
      service.once('exit', code => { clearTimeout(timer); reject(Error(`Server exit ${code}`)); });
      service.stdout.on('data', data => {
        if (data.toString().includes(`localhost:${port}`)) { clearTimeout(timer); resolve(); }
      });
      service.stderr.on('data', data => process.stderr.write(data));
    });
    const health = await request('/health');
    assert.equal(health.status, 200);
    assert.equal(JSON.parse(health.body).lanOnly, false);
    assert.equal(JSON.parse(health.body).transport, 'websocket-relay');
    assert.equal((await request('/gm/api/players')).status, 403, 'GM remains local-only');
    await new Promise((resolve, reject) => {
      socket = new WebSocket(env.TEST_URL, { headers });
      const timer = setTimeout(() => reject(Error('WebSocket greeting timeout')), 5000);
      socket.once('error', error => { clearTimeout(timer); reject(error); });
      socket.once('message', data => {
        clearTimeout(timer);
        try {
          const message = JSON.parse(data);
          assert.equal(message.type, 'connection');
          assert.equal(message.lanOnly, false);
          resolve();
        } catch (error) { reject(error); }
      });
    });
    socket.close();
    await run('server/test-access.js');
    await run('server/test-relay.js');
    await run('server/test.js');
    await run('server/test-points.js');
    if (process.argv.includes('--browser')) await run('tools/online_check.cjs');
    console.log('PASS default server: HTTP/WebSocket accept routed host/proxy requests; accounts, rooms, signaling and points pass; GM stays restricted.');
  } finally {
    socket?.terminate();
    service.kill();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
