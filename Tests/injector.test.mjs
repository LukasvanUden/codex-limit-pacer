import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn, execFileSync } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer } from 'node:http';
import { CdpClient } from './cdp-client.mjs';
import { buildInjectorSource } from './injector-source.mjs';
import { fetchJson, pickUnusedLoopbackPort, waitForDebugEndpoint } from './app-control.mjs';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function findChromium() {
  for (const name of [
    'chromium',
    'chromium-browser',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ]) {
    try { return execFileSync('/usr/bin/env', ['which', name], { encoding: 'utf8' }).trim(); } catch {}
    try { execFileSync('/usr/bin/test', ['-x', name]); return name; } catch {}
  }
  return null;
}

async function withBrowser(t, callback) {
  const chromium = findChromium();
  if (!chromium) { t.skip('Chromium missing'); return; }

  const port = await pickUnusedLoopbackPort();
  const profile = await mkdtemp(join(tmpdir(), 'codex-limit-pacer-test-'));
  const args = [
    '--headless=new',
    '--disable-gpu',
    '--remote-debugging-address=127.0.0.1',
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${profile}`,
    'about:blank',
  ];
  if (process.platform === 'linux') args.unshift('--no-sandbox');
  const browser = spawn(chromium, args, { stdio: 'ignore' });
  t.after(async () => {
    if (browser.exitCode === null) browser.kill('SIGTERM');
    await sleep(150);
    await rm(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
  });

  await waitForDebugEndpoint(port, 15_000);
  const targets = await fetchJson(`http://127.0.0.1:${port}/json/list`);
  const page = targets.find((target) => target.type === 'page');
  const client = await CdpClient.connect(page.webSocketDebuggerUrl, 'test');
  t.after(() => client.close());
  await callback(client);
}

function usagePayload() {
  const resetAt = Math.floor((Date.now() + 3.5 * 24 * 60 * 60 * 1000) / 1000);
  return {
    rate_limit: {
      primary_window: {
        used_percent: 91,
        limit_window_seconds: 18_000,
        reset_at: resetAt,
      },
      secondary_window: {
        used_percent: 26,
        limit_window_seconds: 604_800,
        reset_at: resetAt,
      },
    },
  };
}

function menuHtml(payload = usagePayload()) {
  return `<!doctype html><html lang="en"><head><link rel="modulepreload" href="/assets/app-initial-test.js"><style>
    body{font-family:Arial;background:#151515;color:#eee}.menu{width:252px;background:#292929;padding:8px;border-radius:12px}.row{height:28px;display:flex;align-items:center;justify-content:space-between;padding:0 9px 0 30px}
  </style></head><body>
    <div class="menu">
      <div class="row"><span>Svenja Heutlebeck</span></div><hr>
      <div class="row" id="usage-row"><span id="usage-label">Usage</span><span id="remaining">74% left</span></div>
      <div class="row" id="pet-row"><span>Show pet</span></div>
      <div class="row"><span>Invite a friend</span></div>
    </div>
    <script>
      window.electronBridge = {
        sendMessageFromView() { throw new Error('HTTP requests must use the HTTP fetch service.'); }
      };
      window.testUsagePayload = ${JSON.stringify(payload)};
      window.usageRequests = 0;
    </script>
  </body></html>`;
}

async function loadMenu(t, client, payload = usagePayload(), { clientAvailable = true } = {}) {
  const server = createServer((request, response) => {
    if (request.url === '/assets/app-initial-test.js') {
      response.setHeader('Content-Type', 'text/javascript');
      response.end(clientAvailable ? `
        export const renamedClient = {
          async safeGet(url, { signal }) {
            if (url !== '/wham/usage' || !(signal instanceof AbortSignal)) throw new Error('Invalid usage request');
            signal.throwIfAborted();
            window.usageRequests += 1;
            return window.testUsagePayload;
          }
        };
      ` : 'export const unrelated = {};');
    } else {
      response.setHeader('Content-Type', 'text/html');
      response.end(menuHtml(payload));
    }
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise((resolve) => { server.close(resolve); server.closeAllConnections(); }));
  await client.send('Page.navigate', { url: `http://127.0.0.1:${server.address().port}` });
  const deadline = Date.now() + 2_000;
  while (Date.now() < deadline) {
    const result = await client.send('Runtime.evaluate', {
      expression: '!!document.getElementById("usage-row")', returnByValue: true,
    });
    if (result.result.value) return;
    await sleep(25);
  }
  throw new Error('Test menu did not load');
}

async function waitForStatus(client, state = 'active') {
  const deadline = Date.now() + 2_000;
  while (Date.now() < deadline) {
    const result = await client.send('Runtime.evaluate', {
      expression: 'globalThis.__codexLimitPacerMod?.getStatus?.() ?? null',
      returnByValue: true,
    });
    if (result.result.value?.state === state) return result.result.value;
    await sleep(25);
  }
  throw new Error(`Injector did not reach ${state}`);
}

test('ships the live injector instead of a copied test implementation', () => {
  const source = buildInjectorSource();
  assert.match(source, /version: '1\.0\.8'/);
  assert.match(source, /safeGet\('\/wham\/usage'/);
  assert.doesNotMatch(source, /sendMessageFromView/);
  assert.match(source, /Math\.abs\(duration - WEEK_SECONDS\) <= WEEK_TOLERANCE_SECONDS/);
  assert.doesNotMatch(source, /Usage & billing/);
  assert.doesNotMatch(source, /localStorage/);
});

test('inserts weekly pace between Usage and Show pet without visiting settings', { timeout: 30_000 }, async (t) => {
  await withBrowser(t, async (client) => {
    const payload = usagePayload();
    await loadMenu(t, client, payload);
    await client.send('Runtime.evaluate', {
      expression: buildInjectorSource(),
      returnByValue: true,
      awaitPromise: true,
    });

    const status = await waitForStatus(client);
    const view = await client.send('Runtime.evaluate', {
      expression: `({
        widget: !!document.querySelector('#codex-limit-pacer-widget'),
        previous: document.querySelector('#codex-limit-pacer-widget')?.previousElementSibling?.id,
        next: document.querySelector('#codex-limit-pacer-widget')?.nextElementSibling?.id,
        pagePanel: !!document.querySelector('#codex-limit-pacer-page-panel'),
        usedLabel: document.querySelector('#codex-limit-pacer-widget [data-cup-label="used"]')?.textContent,
        used: document.querySelector('#codex-limit-pacer-widget [data-cup-value="used"]')?.textContent,
        reset: document.querySelector('#codex-limit-pacer-widget-reset')?.textContent,
        dot: !!document.querySelector('#codex-limit-pacer-widget [data-cup-dot]'),
        requests: window.usageRequests,
        expectedReset: (() => {
          const parts = new Intl.DateTimeFormat(document.documentElement.lang, { day: 'numeric', month: 'short' })
            .formatToParts(new Date(window.testUsagePayload.rate_limit.secondary_window.reset_at * 1000));
          return ' (' + parts.find(p => p.type === 'day').value + ' ' + parts.find(p => p.type === 'month').value + ')';
        })()
      })`,
      returnByValue: true,
    });

    assert.equal(view.result.value.widget, true);
    assert.equal(view.result.value.previous, 'usage-row');
    assert.equal(view.result.value.next, 'pet-row');
    assert.equal(view.result.value.pagePanel, false);
    assert.equal(view.result.value.usedLabel, 'Quota used');
    assert.equal(view.result.value.used, '26%');
    assert.equal(view.result.value.dot, false);
    assert.equal(view.result.value.reset, view.result.value.expectedReset);
    assert.equal(view.result.value.requests, 1);
    assert.ok(Math.abs(status.elapsedPercent - 50) < 2);
    assert.equal(status.windowDurationMins, 10_080);
  });
});

test('reads the weekly primary window used by current Codex and removes the widget on destroy', { timeout: 30_000 }, async (t) => {
  await withBrowser(t, async (client) => {
    const payload = usagePayload();
    payload.rate_limit.primary_window = payload.rate_limit.secondary_window;
    payload.rate_limit.secondary_window = null;
    await loadMenu(t, client, payload);
    await client.send('Runtime.evaluate', { expression: buildInjectorSource(), returnByValue: true });
    const status = await waitForStatus(client);
    assert.equal(status.usedPercent, 26);
    assert.equal(status.windowDurationMins, 10_080);
    const result = await client.send('Runtime.evaluate', {
      expression: `globalThis.__codexLimitPacerMod.destroy(); ({
        widget: !!document.querySelector('#codex-limit-pacer-widget'),
        reset: !!document.querySelector('#codex-limit-pacer-widget-reset'),
        style: !!document.querySelector('#codex-limit-pacer-style')
      })`, returnByValue: true,
    });
    assert.deepEqual(result.result.value, { widget: false, reset: false, style: false });
  });
});

test('reports an unavailable HTTP client without using the removed bridge', { timeout: 30_000 }, async (t) => {
  await withBrowser(t, async (client) => {
    await loadMenu(t, client, usagePayload(), { clientAvailable: false });
    await client.send('Runtime.evaluate', { expression: buildInjectorSource(), returnByValue: true });
    const status = await waitForStatus(client, 'usage-unavailable');
    assert.equal(status.error, 'Codex desktop HTTP client is unavailable');
  });
});
