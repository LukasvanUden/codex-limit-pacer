import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn, execFileSync } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
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
  return `<!doctype html><html lang="en"><head><style>
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
        sendMessageFromView(request) {
          queueMicrotask(() => window.postMessage({
            type: 'fetch-response',
            requestId: request.requestId,
            responseType: 'success',
            status: 200,
            bodyJsonString: ${JSON.stringify(JSON.stringify(payload))}
          }, '*'));
          return Promise.resolve();
        }
      };
    </script>
  </body></html>`;
}

async function waitForActive(client) {
  const deadline = Date.now() + 2_000;
  while (Date.now() < deadline) {
    const result = await client.send('Runtime.evaluate', {
      expression: 'globalThis.__codexLimitPacerMod?.getStatus?.() ?? null',
      returnByValue: true,
    });
    if (result.result.value?.state === 'active') return result.result.value;
    await sleep(25);
  }
  throw new Error('Injector did not become active');
}

test('ships the live injector instead of a copied test implementation', () => {
  const source = buildInjectorSource();
  assert.match(source, /version: '1\.0\.5'/);
  assert.match(source, /url: '\/wham\/usage'/);
  assert.match(source, /Math\.abs\(duration - WEEK_SECONDS\) <= WEEK_TOLERANCE_SECONDS/);
  assert.doesNotMatch(source, /Usage & billing/);
  assert.doesNotMatch(source, /localStorage/);
});

test('inserts weekly pace between Usage and Show pet without visiting settings', { timeout: 30_000 }, async (t) => {
  await withBrowser(t, async (client) => {
    const payload = usagePayload();
    await client.send('Runtime.evaluate', {
      expression: `document.open();document.write(${JSON.stringify(menuHtml(payload))});document.close();`,
      returnByValue: true,
    });
    await client.send('Runtime.evaluate', {
      expression: buildInjectorSource(),
      returnByValue: true,
      awaitPromise: true,
    });

    const status = await waitForActive(client);
    const view = await client.send('Runtime.evaluate', {
      expression: `({
        widget: !!document.querySelector('#codex-limit-pacer-widget'),
        previous: document.querySelector('#codex-limit-pacer-widget')?.previousElementSibling?.id,
        next: document.querySelector('#codex-limit-pacer-widget')?.nextElementSibling?.id,
        pagePanel: !!document.querySelector('#codex-limit-pacer-page-panel'),
        usedLabel: document.querySelector('#codex-limit-pacer-widget [data-cup-label="used"]')?.textContent,
        used: document.querySelector('#codex-limit-pacer-widget [data-cup-value="used"]')?.textContent,
        reset: document.querySelector('#codex-limit-pacer-widget-reset')?.textContent,
        dot: !!document.querySelector('#codex-limit-pacer-widget [data-cup-dot]')
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
    const expectedReset = new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'short' })
      .format(new Date(payload.rate_limit.secondary_window.reset_at * 1000));
    assert.equal(view.result.value.reset, ` (${expectedReset})`);
    assert.ok(Math.abs(status.elapsedPercent - 50) < 2);
    assert.equal(status.windowDurationMins, 10_080);
  });
});
