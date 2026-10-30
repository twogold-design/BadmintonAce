const { chromium } = require('playwright');
const { execFileSync } = require('node:child_process');
const { pathToFileURL } = require('node:url');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '..');

(async () => {
  const runtime = path.join(root, '.runtime');
  fs.mkdirSync(runtime, { recursive: true });
  const snapshot = fs.mkdtempSync(path.join(runtime, 'checkout-entry-'));
  // The Git index is the delivery boundary: ignored local exports cannot help.
  execFileSync('git', ['checkout-index', '--all', `--prefix=${snapshot.replaceAll('\\', '/')}/`], { cwd: root });
  const web = path.join(snapshot, 'build/web');
  for (const name of ['index.html', 'entry-ready.js', 'index.wasm', 'index.pck', 'local-data.js', 'local-loader.js']) {
    assert.ok(fs.statSync(path.join(web, name)).size > 0, `Missing committed Web asset: ${name}`);
  }
  const webBytes = fs.readdirSync(web).reduce((sum, name) => sum + fs.statSync(path.join(web, name)).size, 0);
  assert.ok(webBytes < 200000000, `Web export exceeds competition limit: ${webBytes}`);
  const context = await chromium.launchPersistentContext(path.join(snapshot, 'browser-profile'), {
    executablePath: process.env.ACE_BROWSER || 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    headless: true,
    viewport: { width: 1440, height: 900 },
    args: ['--enable-unsafe-swiftshader', '--disable-breakpad', '--disable-crash-reporter'],
  });
  try {
    const page = await context.newPage();
    const errors = [], connections = [], requests = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
    page.on('websocket', socket => connections.push(socket.url()));
    await context.route(/^https?:\/\//, route => {
      requests.push(route.request().url());
      return route.abort();
    });
    const wait = predicate => page.waitForFunction(predicate, null, { polling: 100, timeout: 60000 });
    await page.goto(pathToFileURL(path.join(snapshot, 'index.html')).href);
    await wait(() => window.badmintonState?.screen === 'login');
    assert.equal(page.url(), pathToFileURL(path.join(web, 'index.html')).href);
    await page.mouse.click(720, 629);
    await wait(() => window.badmintonState?.screen === 'menu' && window.badmintonState.offline);
    await page.mouse.click(200, 585);
    await wait(() => window.badmintonState.screen === 'challenges');
    await page.mouse.click(230, 575);
    await wait(() => window.badmintonState.screen === 'game');
    await page.waitForTimeout(400);
    await page.keyboard.press('l');
    await wait(() => window.badmintonState.hits >= 2);
    const state = await page.evaluate(() => window.badmintonState);
    assert.deepEqual(errors, [], 'No browser or game errors');
    assert.deepEqual(requests, [], 'Local play requires no HTTP assets');
    assert.deepEqual(connections, [], 'Local play requires no server');
    fs.mkdirSync(path.join(root, 'artifacts'), { recursive: true });
    await page.screenshot({ path: path.join(root, 'artifacts/checkout-entry.png') });
    fs.writeFileSync(path.join(root, 'artifacts/checkout-entry-test.json'), JSON.stringify({
      ok: true, entry: 'file: index.html (Git index snapshot)', web_bytes: webBytes,
      screen: state.screen, hits: state.hits, errors, http_requests: requests, websocket_connections: connections,
    }, null, 2) + '\n');
    console.log(`PASS fresh checkout: root index.html → offline challenge → AI rally; ${webBytes} bytes; no network dependencies.`);
  } finally {
    await context.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
